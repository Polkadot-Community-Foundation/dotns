#!/usr/bin/env bash
#
# Read-only post-handover verification. Fails on any mismatch:
#   - the manifest equals the expected set derived from its own Create3Factory
#     entry (so the check does not depend on the deployer's nonce after the
#     run); with FACTORY_NONCE set, that factory is DEPLOYER's CREATE at it;
#   - every manifest address has code;
#   - the 14 owned contracts answer owner() == NEW_OWNER, none answers DEPLOYER;
#   - both store beacons are owned by StoreFactory;
#   - VerifyProduction.s.sol re-runs WireDeployments' checks (owners,
#     controllers, protocol-registry keys, declared codehashes, beacons and
#     store implementations) and asserts the release and the TLD.
#
# Usage:
#   DEPLOYER=0x... NEW_OWNER=0x... RPC_URL=... scripts/deploy/verify-production.sh
#
# Env vars:
#   MANIFEST            Default deployments/${DEPLOYMENT_NETWORK:-polkadot}/<chain id>.json.
#   FACTORY_NONCE       Optional; the nonce DEPLOYER deployed the factory at.
#   DOTNS_RELEASE_TAG   Default 0.8.0.
#   DOTNS_TLD           Bare TLD label, default dot.

set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/deploy/_production.sh
. "$here/_production.sh"

require_h160 DEPLOYER "${DEPLOYER:-}"
require_h160 NEW_OWNER "${NEW_OWNER:-}"
: "${RPC_URL:?RPC_URL is required}"
release="${DOTNS_RELEASE_TAG:-0.8.0}"
release="${release#v}"
tld="${DOTNS_TLD:-dot}"

chain_id=$(cast chain-id --rpc-url "$RPC_URL")
MANIFEST="${MANIFEST:-deployments/${DEPLOYMENT_NETWORK:-polkadot}/$chain_id.json}"
[ -f "$MANIFEST" ] || die "manifest not found: $MANIFEST"

failed=0
fail() {
  echo "FAIL $*" >&2
  failed=1
}

echo "=== Verify $MANIFEST (chain $chain_id) ==="

addresses() {
  jq -S 'with_entries(select(.key | startswith("_") | not))' "$1"
}
factory=$(jq -r '.Create3Factory // empty' "$MANIFEST")
[ -n "$factory" ] || die "manifest has no Create3Factory"
if [ -n "${FACTORY_NONCE:-}" ]; then
  from_deployer=$(cast compute-address --nonce "$FACTORY_NONCE" "$DEPLOYER" | awk '{print $NF}')
  same_address "$factory" "$from_deployer" \
    || fail "Create3Factory $factory is not $DEPLOYER's CREATE at nonce $FACTORY_NONCE ($from_deployer)"
fi
expected=$("$here/expected-set.sh" --factory "$factory")
if diff <(jq -S . <<<"$expected") <(addresses "$MANIFEST") >/dev/null; then
  echo "ok  manifest equals the expected set for factory $factory"
else
  fail "manifest differs from the expected set for factory $factory:"
  diff <(jq -S . <<<"$expected") <(addresses "$MANIFEST") >&2 || true
fi

while read -r name addr; do
  has_code "$addr" || fail "$name $addr has no code"
done < <(addresses "$MANIFEST" | jq -r 'to_entries[] | "\(.key) \(.value)"')
echo "ok  code checked at $(addresses "$MANIFEST" | jq length) addresses"

for name in "${OWNED_CONTRACTS[@]}"; do
  addr=$(jq -r --arg n "$name" '.[$n] // empty' "$MANIFEST")
  [ -n "$addr" ] || { fail "manifest has no $name"; continue; }
  owner=$(owner_of "$addr")
  same_address "$owner" "$NEW_OWNER" || fail "$name owner is $owner, expected $NEW_OWNER"
done
echo "ok  owner() checked on ${#OWNED_CONTRACTS[@]} contracts"

while read -r name addr; do
  owner=$(owner_of "$addr")
  ! same_address "$owner" "$DEPLOYER" || fail "$name is still owned by the deployer"
done < <(addresses "$MANIFEST" | jq -r 'to_entries[] | "\(.key) \(.value)"')

store_factory=$(jq -r .StoreFactory "$MANIFEST")
for beacon in LabelStoreBeacon UserStoreBeacon; do
  owner=$(owner_of "$(jq -r --arg n "$beacon" '.[$n]' "$MANIFEST")")
  same_address "$owner" "$store_factory" || fail "$beacon owner is $owner, expected StoreFactory $store_factory"
done
echo "ok  beacon owners checked"

# Same folder resolution as the deploy stages.
DEPLOYMENT_NETWORK="$(basename "$(dirname "$MANIFEST")")"
export DEPLOYMENT_NETWORK
if ! forge script scripts/deploy/VerifyProduction.s.sol:VerifyProduction \
  --sig 'verify(address,string,string)' "$NEW_OWNER" "$release" ".$tld" \
  --rpc-url "$RPC_URL" -vv; then
  fail "VerifyProduction.s.sol (WireDeployments checks, release $release, TLD .$tld)"
fi

[ "$failed" = "0" ] || die "verification failed"
echo "=== Verification passed ==="
