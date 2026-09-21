#!/usr/bin/env bash
#
# Rebuilds the manifest of a deployed set for the standalone handover, verify
# and sweep steps, which run as separate dispatches without the deploy run's
# manifest (that one is only a workflow artifact). Read-only.
#
# The set is expected-set.sh's for DEPLOYER's CREATE at FACTORY_NONCE
# (CREATE3_FACTORY names the factory directly instead). Before anything else
# runs against it: every address must hold code, and that code must be the
# artefact the pipeline deploys there (expected-code.py, immutables and the
# compiler metadata masked).
# A manifest already at the manifest path (committed after the deploy run)
# must equal the rebuilt set; otherwise the rebuilt set is written there, so
# handover.sh, verify-production.sh and sweep.sh read it as they would the
# deploy run's.
#
# Usage:
#   DEPLOY_MODE=devnet|live|fork DEPLOYER=0x... FACTORY_NONCE=N \
#     SUBSTRATE_RPC_URL=... RPC_URL=... scripts/deploy/rebuild-manifest.sh
#
# Env vars:
#   DEPLOYER         The deploy key's H160.
#   FACTORY_NONCE    Nonce the factory was deployed at. Default 0; live accepts only 0.
#   CREATE3_FACTORY  Optional factory address; FACTORY_NONCE must then produce it.
#   MANIFEST         Default deployments/${DEPLOYMENT_NETWORK:-polkadot}/<chain id>.json.
#   Mode/key/chain guard vars as in _production.sh.

set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/deploy/_production.sh
. "$here/_production.sh"

require_h160 DEPLOYER "${DEPLOYER:-}"
FACTORY_NONCE="${FACTORY_NONCE:-0}"
[[ "$FACTORY_NONCE" =~ ^[0-9]+$ ]] || die "FACTORY_NONCE must be a non-negative integer (got '$FACTORY_NONCE')"
if [ "${DEPLOY_MODE:-}" = "live" ] && [ "$FACTORY_NONCE" != "0" ]; then
  die "FACTORY_NONCE=$FACTORY_NONCE but on Polkadot Asset Hub the factory is the key's nonce-0 transaction"
fi
guard_chain_key

chain_id=$(cast chain-id --rpc-url "$RPC_URL")
MANIFEST="${MANIFEST:-deployments/${DEPLOYMENT_NETWORK:-polkadot}/$chain_id.json}"

echo "=== Rebuild manifest: $DEPLOYER, factory nonce $FACTORY_NONCE (chain $chain_id) ==="

factory=$(cast compute-address --nonce "$FACTORY_NONCE" "$DEPLOYER" | awk '{print $NF}')
if [ -n "${CREATE3_FACTORY:-}" ]; then
  same_address "$factory" "$CREATE3_FACTORY" \
    || die "CREATE3_FACTORY $CREATE3_FACTORY is not $DEPLOYER's CREATE at nonce $FACTORY_NONCE ($factory)"
fi
expected=$("$here/expected-set.sh" --factory "$factory")
total=$(jq length <<<"$expected")

# The artefacts are the reference for the code comparison.
[ -f out/Create3Factory.sol/Create3Factory.json ] || forge build >/dev/null
# Metadata ignored: the hash covers the build environment (auto-detected remappings
# included), and nothing here adopts the code; the contract itself must match.
report=$(python3 "$here/expected-code.py" --rpc "$RPC_URL" --ignore-metadata - <<<"$expected") \
  || die "an address of the set holds code that is not the pipeline's artefact (see above)"
occupied=$(sed -n 's/^occupied \([0-9]*\) of.*/\1/p' <<<"$report")
if [ "$occupied" != "$total" ]; then
  sed -n 's/^empty     /  empty /p' <<<"$report" >&2
  die "only $occupied of $total addresses hold code: no complete set from $DEPLOYER at factory nonce $FACTORY_NONCE (factory $factory)"
fi
echo "ok  $total addresses hold the expected code (factory $factory)"

addresses() {
  jq -S 'with_entries(select(.key | startswith("_") | not))' "$1"
}
if [ -f "$MANIFEST" ]; then
  if diff <(jq -S . <<<"$expected") <(addresses "$MANIFEST") >/dev/null; then
    echo "ok  $MANIFEST equals the rebuilt set"
  else
    diff <(jq -S . <<<"$expected") <(addresses "$MANIFEST") >&2 || true
    die "$MANIFEST differs from the set rebuilt for $DEPLOYER at factory nonce $FACTORY_NONCE; refusing"
  fi
else
  mkdir -p "$(dirname "$MANIFEST")"
  jq -S . <<<"$expected" >"$MANIFEST"
  echo "ok  wrote $MANIFEST"
fi
echo "=== Manifest ready: $MANIFEST ==="
