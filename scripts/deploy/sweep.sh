#!/usr/bin/env bash
#
# Sends the deployer's leftover balance to SWEEP_TO, keeping the existential
# deposit plus the transfer's maximum fee.
#
# An eth transfer credits pallet-revive's to_account_id(SWEEP_TO): the
# AccountId32 in Revive.OriginalAccount when the H160 is mapped, otherwise the
# 0xEE-suffixed fallback account. The H160 of a Substrate account (a pure
# proxy, a multisig) is a hash, so its fallback account belongs to nobody. The
# sweep therefore refuses an unmapped SWEEP_TO, and SWEEP_TO_ACCOUNT_ID, when
# set, must equal the mapped AccountId32.
#
# Runs last: refuses while the sender still owns any of the manifest's owned
# contracts (hand over first).
#
# Usage:
#   DEPLOY_MODE=devnet|live|fork SWEEP_TO=0x... SUBSTRATE_RPC_URL=... RPC_URL=... \
#     scripts/deploy/sweep.sh
#
# Env vars:
#   MANIFEST              Default deployments/${DEPLOYMENT_NETWORK:-polkadot}/<chain id>.json.
#   SWEEP_TO_ACCOUNT_ID   Optional 0x AccountId32 the mapping must resolve to.
#   SWEEP_KEEP_PLANCK     Left on the deployer on top of the max fee. Default
#                         100000000 (0.01 DOT, the Asset Hub existential deposit;
#                         the transfer preserves the sender).
#   Signer vars as in _account.sh.

set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/deploy/_production.sh
. "$here/_production.sh"

guard_chain_key
require_h160 SWEEP_TO "${SWEEP_TO:-}"

# shellcheck source=scripts/deploy/_account.sh
. "$here/_account.sh"

! same_address "$SWEEP_TO" "$SENDER" || die "SWEEP_TO is the sender"

# The sweep is the last step: the sender must not own the set any more.
MANIFEST="${MANIFEST:-deployments/${DEPLOYMENT_NETWORK:-polkadot}/$CHAIN_ID.json}"
[ -f "$MANIFEST" ] || die "manifest not found: $MANIFEST (needed to check the set was handed over)"
still_owned=0
for name in "${OWNED_CONTRACTS[@]}"; do
  addr=$(jq -r --arg n "$name" '.[$n] // empty' "$MANIFEST")
  [ -n "$addr" ] || die "manifest has no $name"
  if same_address "$(owner_of "$addr")" "$SENDER"; then
    echo "FAIL $name $addr is still owned by the sender" >&2
    still_owned=$((still_owned + 1))
  fi
done
[ "$still_owned" = "0" ] \
  || die "the sender still owns $still_owned of ${#OWNED_CONTRACTS[@]} contracts: hand over first (handover.sh)"
echo "ok  the sender owns none of the ${#OWNED_CONTRACTS[@]} owned contracts ($MANIFEST)"

target_account=$(substrate_mapped "$SWEEP_TO")
[ -n "$target_account" ] \
  || die "SWEEP_TO $SWEEP_TO is not mapped (no Revive.OriginalAccount entry); the DOT would land on its unowned fallback account"
if [ -n "${SWEEP_TO_ACCOUNT_ID:-}" ] && [ "$(lc "$target_account")" != "$(lc "$SWEEP_TO_ACCOUNT_ID")" ]; then
  die "SWEEP_TO maps to $target_account, expected $SWEEP_TO_ACCOUNT_ID"
fi
echo "ok  $SWEEP_TO maps to $target_account"

free=$(substrate_free "$SENDER")
target_before=$(substrate_free "$target_account")

# 1 planck = 1e8 wei in the eth view.
gas_price=$(cast gas-price --rpc-url "$RPC_URL")
gas=$(cast estimate "$SWEEP_TO" --value "$((free / 2))00000000" --from "$SENDER" --rpc-url "$RPC_URL")
amount=$(python3 -c '
import sys
free, gas, price, keep = map(int, sys.argv[1:])
max_fee = -(-gas * 2 * price // 10**8)
print(max(free - keep - max_fee, 0))
' "$free" "$gas" "$gas_price" "${SWEEP_KEEP_PLANCK:-100000000}")
unit=$(native_unit)
[ "$amount" != "0" ] || die "nothing to sweep (free $(planck_to_dot "$free") $unit)"

echo "=== Sweep $(planck_to_dot "$amount") $unit: $SENDER -> $SWEEP_TO ==="
receipt=$(cast send "$SWEEP_TO" --value "${amount}00000000" --gas-limit "$((gas * 2))" \
  "${CAST_SIGNER_ARGS[@]}" --rpc-url "$RPC_URL" --legacy --json)
[ "$(jq -r .status <<<"$receipt")" = "0x1" ] || die "sweep failed: $receipt"

target_after=$(substrate_free "$target_account")
received=$((target_after - target_before))
[ "$received" = "$amount" ] || die "target received $received planck, expected $amount"
echo "ok  target $target_account +$(planck_to_dot "$received") $unit; deployer left $(planck_to_dot "$(substrate_free "$SENDER")") $unit"
echo "SWEPT_PLANCK=$amount"
