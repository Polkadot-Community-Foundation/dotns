#!/usr/bin/env python3
"""Checks occupied expected-set addresses against the code the pipeline deploys there.

Usage:
    expected-code.py --rpc <eth-rpc url> [--out <foundry out dir>] [--ignore-metadata] <expected-set json>

Reads the expected set (name -> address, the shape of expected-set.sh's output)
and, for every address, compares the runtime code on chain with the artefact
the deploy stage would put there: the CREATE3 factory, `ERC1967Proxy` for every
UUPS proxy, `UpgradeableBeacon` for the two store beacons, the contract's own
artefact otherwise. Bytes the compiler recorded as immutables are masked on
both sides (an immutable holding an address differs on every honest deploy);
everything else must match exactly. The stage that later adopts the address
re-checks it against this run's constructor arguments (BaseDeployer), so this
is the pre-screen and the stage is the authority.

`--ignore-metadata` also masks the CBOR metadata trailer (the compiler's
source and settings hash, which differs between build environments of the same
sources, e.g. in the remappings a checkout auto-detects). The standalone steps
use it to confirm a set is the pipeline's, where nothing adopts the code.

Prints one line per address: `empty`, `ok` or `MISMATCH`. Exits 1 when any
address holds code that is not the expected artefact.
"""

import argparse
import json
import sys
import urllib.request
from pathlib import Path

ARTEFACTS = {
    "Create3Factory": "Create3Factory.sol/Create3Factory",
    "LabelStoreBeacon": "UpgradeableBeacon.sol/UpgradeableBeacon",
    "UserStoreBeacon": "UpgradeableBeacon.sol/UpgradeableBeacon",
    "DotnsCostModelRegistry": "DotnsCostModelRegistry.sol/DotnsCostModelRegistry",
    "DotnsFlatPricing": "DotnsFlatPricing.sol/DotnsFlatPricing",
    "DotnsPopLens": "DotnsPopLens.sol/DotnsPopLens",
    "Multicall3": "Multicall3.sol/Multicall3",
}
PROXY_ARTEFACT = "ERC1967Proxy.sol/ERC1967Proxy"


def eth_get_code(rpc, address):
    body = json.dumps(
        {"jsonrpc": "2.0", "id": 1, "method": "eth_getCode", "params": [address, "latest"]}
    ).encode()
    # The public devnet ETH-RPC answers 403 to urllib's default user agent.
    req = urllib.request.Request(rpc, body, {"content-type": "application/json", "user-agent": "dotns-deploy"})
    with urllib.request.urlopen(req, timeout=60) as resp:
        reply = json.load(resp)
    if "error" in reply:
        raise SystemExit(f"eth_getCode {address}: {reply['error']}")
    return bytes.fromhex(reply["result"][2:])


def artefact_code(out_dir, artefact):
    """Runtime code with every immutable range zeroed, plus those ranges."""
    path = Path(out_dir) / f"{artefact}.json"
    if not path.exists():
        raise SystemExit(f"artefact missing: {path} (run `forge build` first)")
    deployed = json.loads(path.read_text())["deployedBytecode"]
    code = bytearray.fromhex(deployed["object"][2:])
    ranges = []
    for refs in (deployed.get("immutableReferences") or {}).values():
        for ref in refs:
            ranges.append((ref["start"], ref["length"]))
    for start, length in ranges:
        code[start : start + length] = bytes(length)
    return bytes(code), ranges


def masked(code, ranges):
    code = bytearray(code)
    for start, length in ranges:
        code[start : start + length] = bytes(length)
    return bytes(code)


def without_metadata(code):
    """Runtime code with the CBOR metadata trailer zeroed (its length is the last two bytes)."""
    length = int.from_bytes(code[-2:], "big") + 2
    if length > len(code):
        return code
    return code[:-length] + bytes(length)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--rpc", required=True)
    parser.add_argument("--out", default="out")
    parser.add_argument("--ignore-metadata", action="store_true")
    parser.add_argument("expected", help="expected-set JSON file, or - for stdin")
    args = parser.parse_args()

    source = sys.stdin if args.expected == "-" else open(args.expected)
    with source:
        expected = json.load(source)

    mismatches = 0
    occupied = 0
    for name, address in sorted(expected.items()):
        onchain = eth_get_code(args.rpc, address)
        if not onchain:
            print(f"empty     {name} {address}")
            continue
        occupied += 1
        artefact = ARTEFACTS.get(name, PROXY_ARTEFACT)
        reference, ranges = artefact_code(args.out, artefact)
        if len(onchain) == len(reference) and masked(onchain, ranges) == reference:
            print(f"ok        {name} {address} ({artefact})")
        elif (
            args.ignore_metadata
            and len(onchain) == len(reference)
            and without_metadata(masked(onchain, ranges)) == without_metadata(reference)
        ):
            print(f"ok        {name} {address} ({artefact}, metadata differs)")
        else:
            mismatches += 1
            print(
                f"MISMATCH  {name} {address}: code is not {artefact} "
                f"(on-chain {len(onchain)} bytes, expected {len(reference)})",
                file=sys.stderr,
            )
    print(f"occupied {occupied} of {len(expected)}, mismatches {mismatches}")
    return 1 if mismatches else 0


if __name__ == "__main__":
    sys.exit(main())
