#!/usr/bin/env python3
"""Substrate-side reads for the production deploy scripts.

The eth view of a chopsticks fork serves stale balances, and the address
mapping only exists on the Substrate side, so these read storage directly.
Transport is `cast rpc`, so http(s) and ws(s) endpoints both work.

Usage:
  substrate.py account <H160|AccountId32> --rpc URL [--at HASH]   System.Account as JSON
  substrate.py mapped  <H160> --rpc URL               AccountId32 behind Revive.OriginalAccount, exit 1 if unmapped
  substrate.py fund    <H160> <planck> --rpc URL      chopsticks dev_setStorage of the H160's fallback account
  substrate.py locate  <H160> <nonce> --rpc URL [--from N] [--lookback N]
      The block where the sender's nonce passed <nonce> and the Revive.eth_transact
      extrinsic in it that carries the sender's transaction with that nonce, as JSON.
      Exit 2: the block was found but carries no such transaction (something else
      consumed the nonce). Exit 3: the nonce passed before the searched window
      (--from, else head - --lookback) or the state there is unavailable.
"""

import argparse
import hashlib
import json
import subprocess
import sys
import time

MASK64 = (1 << 64) - 1
P1, P2, P3, P4, P5 = (
    11400714785074694791,
    14029467366897019727,
    1609587929392839161,
    9650029242287828579,
    2870177450012600261,
)


def _rotl(x, r):
    return ((x << r) | (x >> (64 - r))) & MASK64


def _round(acc, lane):
    acc = (acc + lane * P2) & MASK64
    return (_rotl(acc, 31) * P1) & MASK64


def _merge(acc, val):
    acc ^= _round(0, val)
    return (acc * P1 + P4) & MASK64


def xxh64(data, seed):
    n = len(data)
    i = 0
    if n >= 32:
        v = [(seed + P1 + P2) & MASK64, (seed + P2) & MASK64, seed, (seed - P1) & MASK64]
        while i + 32 <= n:
            for j in range(4):
                v[j] = _round(v[j], int.from_bytes(data[i + 8 * j : i + 8 * j + 8], "little"))
            i += 32
        h = (_rotl(v[0], 1) + _rotl(v[1], 7) + _rotl(v[2], 12) + _rotl(v[3], 18)) & MASK64
        for x in v:
            h = _merge(h, x)
    else:
        h = (seed + P5) & MASK64
    h = (h + n) & MASK64
    while i + 8 <= n:
        h ^= _round(0, int.from_bytes(data[i : i + 8], "little"))
        h = (_rotl(h, 27) * P1 + P4) & MASK64
        i += 8
    if i + 4 <= n:
        h ^= (int.from_bytes(data[i : i + 4], "little") * P1) & MASK64
        h = (_rotl(h, 23) * P2 + P3) & MASK64
        i += 4
    while i < n:
        h ^= (data[i] * P5) & MASK64
        h = (_rotl(h, 11) * P1) & MASK64
        i += 1
    h ^= h >> 33
    h = (h * P2) & MASK64
    h ^= h >> 29
    h = (h * P3) & MASK64
    h ^= h >> 32
    return h


def twox128(name):
    b = name.encode()
    return (xxh64(b, 0).to_bytes(8, "little") + xxh64(b, 1).to_bytes(8, "little")).hex()


def account_id(addr):
    raw = bytes.fromhex(addr.removeprefix("0x"))
    if len(raw) == 20:
        return raw + b"\xee" * 12
    if len(raw) == 32:
        return raw
    sys.exit(f"not an H160 or AccountId32: {addr}")


def h160(addr):
    raw = bytes.fromhex(addr.removeprefix("0x"))
    if len(raw) != 20:
        sys.exit(f"not an H160: {addr}")
    return raw


def rpc(url, method, *params):
    out = subprocess.run(
        ["cast", "rpc", "--rpc-url", url, method, *params],
        check=True,
        capture_output=True,
        text=True,
    ).stdout.strip()
    return json.loads(out) if out else None


def account_info(url, addr, at=None):
    acc = account_id(addr)
    key = "0x" + twox128("System") + twox128("Account")
    key += hashlib.blake2b(acc, digest_size=16).hexdigest() + acc.hex()
    raw = rpc(url, "state_getStorage", key, *([at] if at else []))
    info = {"account_id": "0x" + acc.hex(), "nonce": 0, "free": 0, "reserved": 0, "frozen": 0}
    if raw:
        b = bytes.fromhex(raw[2:])
        info.update(
            nonce=int.from_bytes(b[0:4], "little"),
            free=int.from_bytes(b[16:32], "little"),
            reserved=int.from_bytes(b[32:48], "little"),
            frozen=int.from_bytes(b[48:64], "little"),
        )
    return info


def cmd_account(args):
    info = account_info(args.rpc, args.address, args.at)
    # Big integers as strings so jq does not round them.
    print(json.dumps({k: str(v) if isinstance(v, int) else v for k, v in info.items()}))


def compact_len(b, i):
    """SCALE compact integer at b[i:]: (value, bytes consumed)."""
    mode = b[i] & 3
    if mode == 0:
        return b[i] >> 2, 1
    if mode == 1:
        return int.from_bytes(b[i : i + 2], "little") >> 2, 2
    if mode == 2:
        return int.from_bytes(b[i : i + 4], "little") >> 2, 4
    n = (b[i] >> 2) + 4
    return int.from_bytes(b[i + 1 : i + 1 + n], "little"), 1 + n


def eth_transact_payload(extrinsic_hex):
    """The signed eth transaction inside a bare `Revive.eth_transact` extrinsic, else None.

    Bare extrinsic = compact length, version byte (bit 7 clear), pallet index, call index,
    then the call's one argument: a SCALE byte vector holding the RLP-encoded eth
    transaction, which must end exactly where the extrinsic ends.
    """
    b = bytes.fromhex(extrinsic_hex[2:])
    try:
        length, used = compact_len(b, 0)
        if length != len(b) - used or b[used] & 0x80:
            return None
        payload_len, n = compact_len(b, used + 3)
        start = used + 3 + n
        if start + payload_len != len(b) or payload_len < 2:
            return None
    except IndexError:
        return None
    payload = b[start:]
    # Legacy transactions are an RLP list; typed ones start with the type byte.
    if payload[0] < 0xC0 and payload[0] > 0x7F:
        return None
    return "0x" + payload.hex()


def decode_eth_transaction(payload):
    out = subprocess.run(
        ["cast", "decode-transaction", payload], capture_output=True, text=True, check=False
    ).stdout.strip()
    if not out:
        return None
    try:
        decoded = json.loads(out)
        if isinstance(decoded, str):
            decoded = json.loads(decoded)
    except json.JSONDecodeError:
        return None
    return decoded if isinstance(decoded, dict) else None


def cmd_locate(args):
    """Locate the sender's transaction with a given nonce from Substrate alone."""
    sender = "0x" + h160(args.address).hex()
    head = int(rpc(args.rpc, "chain_getHeader")["number"], 16)
    lo = args.from_block if args.from_block is not None else max(0, head - args.lookback)

    def nonce_at(n):
        try:
            return account_info(args.rpc, sender, rpc(args.rpc, "chain_getBlockHash", str(n)))["nonce"]
        except (subprocess.CalledProcessError, json.JSONDecodeError, TypeError):
            return None

    if nonce_at(head) is None or nonce_at(head) <= args.nonce:
        sys.exit(f"nonce {args.nonce} of {sender} is not consumed at block {head}")
    at_lo = nonce_at(lo)
    if at_lo is None:
        print(f"state at block {lo} unavailable; cannot locate nonce {args.nonce}", file=sys.stderr)
        sys.exit(3)
    if at_lo > args.nonce:
        print(f"nonce {args.nonce} of {sender} passed before block {lo}; not located", file=sys.stderr)
        sys.exit(3)
    # First block in (lo, head] whose nonce is above args.nonce.
    hi = head
    while lo < hi:
        mid = (lo + hi) // 2
        n = nonce_at(mid)
        if n is None:
            print(f"state at block {mid} unavailable; cannot locate nonce {args.nonce}", file=sys.stderr)
            sys.exit(3)
        if n > args.nonce:
            hi = mid
        else:
            lo = mid + 1
    block_hash = rpc(args.rpc, "chain_getBlockHash", str(hi))
    extrinsics = rpc(args.rpc, "chain_getBlock", block_hash)["block"]["extrinsics"]
    for index, extrinsic in enumerate(extrinsics):
        payload = eth_transact_payload(extrinsic)
        if payload is None:
            continue
        tx = decode_eth_transaction(payload)
        if not tx or tx.get("signer", "").lower() != sender or int(tx.get("nonce", "0x0"), 16) != args.nonce:
            continue
        print(
            json.dumps(
                {
                    "block": hi,
                    "block_hash": block_hash,
                    "extrinsic_index": index,
                    "extrinsic_hash": "0x" + hashlib.blake2b(bytes.fromhex(extrinsic[2:]), digest_size=32).hexdigest(),
                    "tx_hash": tx.get("hash", "").lower(),
                    "to": (tx.get("to") or "").lower(),
                    "value": tx.get("value", "0x0"),
                    "input": tx.get("input", "0x").lower(),
                }
            )
        )
        return
    print(
        f"block {hi} ({block_hash}) consumed nonce {args.nonce} of {sender} without a Revive.eth_transact from it",
        file=sys.stderr,
    )
    sys.exit(2)


def cmd_mapped(args):
    # Revive.OriginalAccount: StorageMap<Identity, H160, AccountId32>.
    key = "0x" + twox128("Revive") + twox128("OriginalAccount") + h160(args.address).hex()
    raw = rpc(args.rpc, "state_getStorage", key)
    if not raw:
        sys.exit(1)
    print(raw)


def cmd_fund(args):
    acc = "0x" + account_id(args.address).hex()
    storage = {"System": {"Account": [[[acc], {"providers": 1, "data": {"free": str(args.planck)}}]]}}
    rpc(args.rpc, "dev_setStorage", json.dumps(storage))


def _wait(what, fn, timeout=90):
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        v = fn()
        if v is not None:
            return v
        time.sleep(2)
    sys.exit(f"timed out waiting for {what}")


def cmd_same_chain(args):
    # The eth-rpc must serve the Substrate chain it is checked against: its block hash at a
    # height must equal Revive.BlockHash (StorageMap<Identity, u32, H256>) there. A fork behind
    # the eth-rpc never reaches a live chain's next block, and its hashes differ.
    head = lambda: int(rpc(args.rpc, "chain_getHeader")["number"], 16)
    start = head()
    target = start if args.fork else _wait(f"a new block on {args.rpc}", lambda: (lambda n: n if n > start else None)(head()))
    height = _wait(
        f"{args.eth} to reach block {target}",
        lambda: (lambda n: n if n >= target else None)(int(rpc(args.eth, "eth_blockNumber"), 16)),
    )
    if args.fork and height != target:
        sys.exit(f"{args.eth} is at block {height}, the fork {args.rpc} at {target}: not the fork")
    at = rpc(args.rpc, "chain_getBlockHash", str(target))
    key = "0x" + twox128("Revive") + twox128("BlockHash") + target.to_bytes(4, "little").hex()
    expected = rpc(args.rpc, "state_getStorage", key, at)
    block = rpc(args.eth, "eth_getBlockByNumber", hex(target), "false")
    got = block and block.get("hash")
    if not expected or not got or got.lower() != expected.lower():
        sys.exit(f"{args.eth} block {target} is {got}, {args.rpc} has {expected}: not the same chain")


def main():
    p = argparse.ArgumentParser()
    sub = p.add_subparsers(dest="cmd", required=True)
    for name, fn, extra in (
        ("account", cmd_account, ()),
        ("mapped", cmd_mapped, ()),
        ("fund", cmd_fund, ("planck",)),
    ):
        s = sub.add_parser(name)
        s.add_argument("address")
        for e in extra:
            s.add_argument(e, type=int)
        s.add_argument("--rpc", required=True)
        if name == "account":
            s.add_argument("--at", default=None, help="block hash")
        s.set_defaults(fn=fn)
    s = sub.add_parser("locate")
    s.add_argument("address")
    s.add_argument("nonce", type=int)
    s.add_argument("--rpc", required=True)
    s.add_argument("--from", dest="from_block", type=int, default=None, help="lowest block to search")
    s.add_argument("--lookback", type=int, default=100000, help="blocks below head to search when --from is unset")
    s.set_defaults(fn=cmd_locate)
    s = sub.add_parser("same-chain")
    s.add_argument("--rpc", required=True)
    s.add_argument("--eth", required=True)
    s.add_argument("--fork", action="store_true")
    s.set_defaults(fn=cmd_same_chain)
    args = p.parse_args()
    args.fn(args)


if __name__ == "__main__":
    main()
