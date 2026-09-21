#!/usr/bin/env python3
"""Live progress for the deploy job log.

forge prints its receipts ("Hash: ... Contract Address: ... Block: ...") and the
per-stage "Total Paid" line through a progress bar that only draws on a
terminal, so a job log or a file gets neither. The full forge output goes to
the log file; this streams what an operator watches for.

Usage:
  progress.py filter
      Copies the stable lines of a deploy log from stdin to stdout as they
      arrive: stage headers and attempt lines, the estimates, ONCHAIN EXECUTION
      COMPLETE, the retry runner's messages, every Error line (and forge's
      receipt lines when a terminal drew them). Long lines are cut.
  progress.py watch --deployer H160 --substrate-rpc URL --eth-rpc URL \\
      --chain-id N [--unit DOT] [--interval 30] [--since EPOCH] [--broadcast DIR]
      Runs until killed. Every --interval seconds prints
      `progress: nonce N, balance X <unit>` (eth nonce, Substrate free balance);
      every few seconds reads the forge broadcast checkpoints
      (<DIR>/<Stage>.s.sol/<chain id>/run-latest.json, written after every
      send and every receipt) modified since --since and prints each new receipt
      once: stage, index, call, block, gas, status, hash.
"""

import argparse
import glob
import hashlib
import json
import os
import re
import sys
import time
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import substrate  # noqa: E402

FILTER = re.compile(
    "|".join(
        (
            r"^=== ",
            r"^Chain \d",
            r"^Estimated ",
            r"^Script ran successfully",
            r"ONCHAIN EXECUTION",
            r"^Transactions saved to",
            r"^Create3Factory already present",
            r"^CREATE3_FACTORY=",
            r"^Restored manifest",
            r"^Recovery:",
            r"^Stage failed",
            r"^Manifest ",
            r"^Could not ",
            r"^Deleted one-off",
            r"^(waiting for|RPC answered)",
            r"^\w+: (attempt \d+ of \d+ failed|retrying in|not retrying|giving up)",
            r"^\w+ broadcast \d+ transaction",
            # forge receipts, present only when a terminal drew the progress bars.
            r"^(✅|❌|⚠️)",
            r"^(Hash|Contract Address|Block|Paid|Gas used): ",
            r"Total Paid:",
            # Errors: forge's own, the scripts' die() lines, reverted broadcasts.
            r"^\s*(Error|error)\b",
            r"^(\S+\.sh|deployall): ",
            r"Transaction Failure",
            r"Failed to send",
        )
    )
)
MAX_LINE = 240


def cmd_filter(_args):
    for line in sys.stdin:
        line = line.rstrip("\n")
        if not FILTER.search(line):
            continue
        if len(line) > MAX_LINE:
            line = line[:MAX_LINE] + " ..."
        print(line, flush=True)


def eth_nonce(rpc, address):
    body = json.dumps(
        {"jsonrpc": "2.0", "id": 1, "method": "eth_getTransactionCount", "params": [address, "latest"]}
    ).encode()
    req = urllib.request.Request(rpc, body, {"content-type": "application/json", "user-agent": "dotns-deploy"})
    with urllib.request.urlopen(req, timeout=30) as resp:
        reply = json.load(resp)
    return int(reply["result"], 16)


def substrate_free(rpc, address):
    acc = substrate.account_id(address)
    key = "0x" + substrate.twox128("System") + substrate.twox128("Account")
    key += hashlib.blake2b(acc, digest_size=16).hexdigest() + acc.hex()
    raw = substrate.rpc(rpc, "state_getStorage", key)
    if not raw:
        return 0
    return int.from_bytes(bytes.fromhex(raw[2:])[16:32], "little")


def heartbeat(args):
    try:
        nonce = eth_nonce(args.eth_rpc, args.deployer)
        free = substrate_free(args.substrate_rpc, args.deployer)
    except Exception as err:  # noqa: BLE001  (a read failure is a log line, not a crash)
        print(f"progress: unavailable ({err})", flush=True)
        return
    print(f"progress: nonce {nonce}, balance {free / 1e10:.4f} {args.unit}", flush=True)


def describe(tx):
    """One label for a broadcast transaction: the deployed contract, else the call."""
    if tx.get("transactionType") == "CREATE":
        return f"create {tx.get('contractName') or '?'} at {tx.get('contractAddress')}"
    label = tx.get("function") or tx.get("contractName") or tx.get("transactionType", "?")
    created = [
        c["address"] for c in tx.get("additionalContracts") or [] if c.get("transactionType") == "CREATE"
    ]
    if created:
        label += " created " + ", ".join(created)
    else:
        label += f" -> {tx.get('contractAddress')}"
    return label


def scan_broadcasts(args, seen):
    pattern = os.path.join(args.broadcast, "*.s.sol", str(args.chain_id), "run-latest.json")
    for path in sorted(glob.glob(pattern)):
        try:
            if os.stat(path).st_mtime < args.since:
                continue
            with open(path) as f:
                run = json.load(f)
        except (OSError, ValueError):
            continue  # being written; next pass
        stage = os.path.basename(os.path.dirname(os.path.dirname(path))).removesuffix(".s.sol")
        txs = run.get("transactions") or []
        by_hash = {tx.get("hash"): (i, tx) for i, tx in enumerate(txs)}
        for receipt in run.get("receipts") or []:
            h = receipt.get("transactionHash")
            if not h or h in seen:
                continue
            seen.add(h)
            i, tx = by_hash.get(h, (None, {}))
            index = f"#{i + 1}/{len(txs)}" if i is not None else "#?"
            status = "ok" if receipt.get("status") == "0x1" else f"status {receipt.get('status')}"
            block = int(receipt.get("blockNumber", "0x0"), 16)
            gas = int(receipt.get("gasUsed", "0x0"), 16)
            print(
                f"landed  {stage} {index} {describe(tx)}  block {block} gas {gas} {status}  {h}",
                flush=True,
            )


def cmd_watch(args):
    seen = set()
    last_beat = 0.0
    while True:
        now = time.monotonic()
        if now - last_beat >= args.interval:
            heartbeat(args)
            last_beat = now
        scan_broadcasts(args, seen)
        time.sleep(args.scan_interval)


def main():
    p = argparse.ArgumentParser()
    sub = p.add_subparsers(dest="cmd", required=True)
    f = sub.add_parser("filter")
    f.set_defaults(fn=cmd_filter)
    w = sub.add_parser("watch")
    w.add_argument("--deployer", required=True)
    w.add_argument("--substrate-rpc", required=True)
    w.add_argument("--eth-rpc", required=True)
    w.add_argument("--chain-id", type=int, required=True)
    w.add_argument("--unit", default="DOT")
    w.add_argument("--interval", type=float, default=30)
    w.add_argument("--scan-interval", type=float, default=5)
    w.add_argument("--since", type=float, default=time.time())
    w.add_argument("--broadcast", default="broadcast")
    w.set_defaults(fn=cmd_watch)
    args = p.parse_args()
    args.fn(args)


if __name__ == "__main__":
    main()
