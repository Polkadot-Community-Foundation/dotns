#!/usr/bin/env bash
#
# Hands every deployer-owned manifest contract to NEW_OWNER with a single-step
# transferOwnership, DotnsProtocolRegistry last, asserting owner() after each
# call. Never calls renounceOwnership.
#
# Plans before sending: a contract already owned by NEW_OWNER counts as done
# (so a re-run resumes), one owned by the sender is transferred, anything else
# is skipped. The run refuses unless done + to-transfer equals
# EXPECTED_HANDOVER_COUNT (default 14).
#
# Usage:
#   DEPLOY_MODE=fork|live|devnet NEW_OWNER=0x... RPC_URL=... scripts/deploy/handover.sh
#
# Env vars:
#   MANIFEST                  Default deployments/${DEPLOYMENT_NETWORK:-polkadot}/<chain id>.json.
#   EXPECTED_HANDOVER_COUNT   Default 14.
#   Signer vars as in _account.sh.

set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/deploy/_production.sh
. "$here/_production.sh"

guard_chain_key
require_h160 NEW_OWNER "${NEW_OWNER:-}"

# shellcheck source=scripts/deploy/_account.sh
. "$here/_account.sh"

MANIFEST="${MANIFEST:-deployments/${DEPLOYMENT_NETWORK:-polkadot}/$CHAIN_ID.json}"
[ -f "$MANIFEST" ] || die "manifest not found: $MANIFEST"
expected_count="${EXPECTED_HANDOVER_COUNT:-14}"

! same_address "$NEW_OWNER" "$SENDER" || die "NEW_OWNER is the sender"
! has_code "$NEW_OWNER" || die "NEW_OWNER $NEW_OWNER has code; refusing to hand ownership to a contract"

echo "=== Handover plan: $SENDER -> $NEW_OWNER ($MANIFEST) ==="
names=$(jq -r 'to_entries[] | select(.key | startswith("_") | not) | .key' "$MANIFEST" \
  | grep -vx DotnsProtocolRegistry || true)
names="$names DotnsProtocolRegistry"

todo=()
done_count=0
for name in $names; do
  addr=$(jq -r --arg n "$name" '.[$n] // empty' "$MANIFEST")
  [ -n "$addr" ] || die "manifest has no $name"
  owner=$(owner_of "$addr")
  if same_address "$owner" "$NEW_OWNER"; then
    echo "done  $name $addr"
    done_count=$((done_count + 1))
  elif same_address "$owner" "$SENDER"; then
    echo "todo  $name $addr"
    todo+=("$name")
  else
    echo "skip  $name $addr owner=$owner"
  fi
done

total=$((done_count + ${#todo[@]}))
[ "$total" = "$expected_count" ] \
  || die "plan covers $total owned contracts ($done_count done, ${#todo[@]} to transfer), expected $expected_count; refusing"

for name in "${todo[@]}"; do
  addr=$(jq -r --arg n "$name" '.[$n]' "$MANIFEST")
  receipt=$(cast send "$addr" 'transferOwnership(address)' "$NEW_OWNER" \
    "${CAST_SIGNER_ARGS[@]}" --rpc-url "$RPC_URL" --legacy --json)
  [ "$(jq -r .status <<<"$receipt")" = "0x1" ] || die "$name transferOwnership failed: $receipt"
  after=$(owner_of "$addr")
  same_address "$after" "$NEW_OWNER" || die "$name owner is $after after transferOwnership"
  echo "ok    $name gasUsed=$(jq -r .gasUsed <<<"$receipt") tx=$(jq -r .transactionHash <<<"$receipt")"
done

echo "=== Handover complete: ${#todo[@]} transferred, $done_count already done ==="
