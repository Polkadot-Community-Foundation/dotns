#!/usr/bin/env python3
"""Substrate-side reads for the production deploy scripts.

The eth view of a chopsticks fork serves stale balances, and the address
mapping only exists on the Substrate side, so these read storage directly.
Transport is `cast rpc`, so http(s) and ws(s) endpoints both work.

Usage:
  substrate.py account <H160|AccountId32> --rpc URL   System.Account as JSON
  substrate.py mapped  <H160> --rpc URL               AccountId32 behind Revive.OriginalAccount, exit 1 if unmapped
  substrate.py fund    <H160> <planck> --rpc URL      chopsticks dev_setStorage of the H160's fallback account
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


def cmd_account(args):
    acc = account_id(args.address)
    key = "0x" + twox128("System") + twox128("Account")
    key += hashlib.blake2b(acc, digest_size=16).hexdigest() + acc.hex()
    raw = rpc(args.rpc, "state_getStorage", key)
    info = {"account_id": "0x" + acc.hex(), "nonce": 0, "free": 0, "reserved": 0, "frozen": 0}
    if raw:
        b = bytes.fromhex(raw[2:])
        info.update(
            nonce=int.from_bytes(b[0:4], "little"),
            free=int.from_bytes(b[16:32], "little"),
            reserved=int.from_bytes(b[32:48], "little"),
            frozen=int.from_bytes(b[48:64], "little"),
        )
    # Big integers as strings so jq does not round them.
    print(json.dumps({k: str(v) if isinstance(v, int) else v for k, v in info.items()}))


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
        s.set_defaults(fn=fn)
    s = sub.add_parser("same-chain")
    s.add_argument("--rpc", required=True)
    s.add_argument("--eth", required=True)
    s.add_argument("--fork", action="store_true")
    s.set_defaults(fn=cmd_same_chain)
    args = p.parse_args()
    args.fn(args)


if __name__ == "__main__":
    main()
