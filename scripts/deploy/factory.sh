#!/usr/bin/env bash
#
# Deploys the CREATE3 factory on its own, from a dedicated single-purpose key,
# so its address stays reproducible across chain resets. Every other DotNS
# address derives from the factory address, and the factory's own address is
# nonce-derived, so a key that also runs the pipeline or upgrades cannot keep it
# stable. Deploy it here from a key that does nothing else, then pass the printed
# address to the pipeline as CREATE3_FACTORY (see the "Keeping the factory
# address stable across chain resets" section in DEPLOYMENTS.md).
#
# The script asserts the deployer is at nonce 0, so this key must be pristine.
#
# Usage:
#   bun run deploy:factory
#   ACCOUNT_NAME=dotns-factory RPC_URL=paseo bun run deploy:factory
#
# Env vars are the same as the main deploy runner (see _account.sh); ACCOUNT_NAME
# defaults to a factory-only key so it is never the pipeline/upgrade key. Extra
# forge flags are forwarded verbatim, e.g. ./scripts/deploy/factory.sh '--timeout 1000'.

set -euo pipefail

# Default to a factory-only key so it is never reused for the pipeline or
# upgrades, which is what keeps its nonce (and therefore the factory address)
# reproducible.
: "${ACCOUNT_NAME:=dotns-factory}"

# shellcheck source=scripts/deploy/_account.sh
. "$(dirname "$0")/_account.sh"

extra="${1:-}"

echo "=== Deploying Create3Factory from '$ACCOUNT_NAME' ($SENDER) on chain $CHAIN_ID ==="

# shellcheck disable=SC2086
forge script scripts/deploy/DeployCreate3Factory.s.sol:DeployCreate3Factory \
  --rpc-url "$RPC_URL" \
  --account "$ACCOUNT_NAME" \
  --password "$ACCOUNT_PASSWORD" \
  --sender "$SENDER" \
  --broadcast \
  --slow \
  --legacy \
  --gas-limit 1000000000 \
  -vvvv $extra
