#!/usr/bin/env bash
#
# Runs the multi-stage DotNS deploy pipeline against a Foundry keystore
# wallet. `.env` is a one-off bootstrap file: it can provide PRIVATE_KEY
# once to import the wallet; later runs use the saved ACCOUNT_NAME and
# ACCOUNT_PASSWORD. A successful run deletes `.env`; a failed run leaves it
# in place for correction and retry.
#
# Local usage:
#   1. cp .env.example .env
#   2. set PRIVATE_KEY, ACCOUNT_NAME, ACCOUNT_PASSWORD, and WHITELIST_OPERATOR
#      in .env
#   3. bun run deploy   (or ./scripts/deploy/run.sh)
#   4. on success, the script deletes .env automatically
#
# CI / scripted usage (no `.env`):
#   PRIVATE_KEY=0x... ACCOUNT_NAME=dotns-deploy ACCOUNT_PASSWORD=... ./scripts/deploy/run.sh '--slow'
#
# Each stage runs as its own `forge script` invocation (therefore its
# own EVM simulation), so OpenZeppelin's upgrade-safety validator's
# cumulative memory gas cannot spill across stages.
#
# Required env (from `.env` or shell):
#   ACCOUNT_NAME   Foundry keystore account passed to forge as --account.
#   ACCOUNT_PASSWORD
#                  Password passed to cast/forge as --password.
#   WHITELIST_OPERATOR
#                  Address granted whitelist management permission.
#
# Optional env:
#   PRIVATE_KEY    Hex-encoded deployer private key, with or without 0x.
#                  Required only when ACCOUNT_NAME has not yet been imported.
#   RPC_URL        Foundry rpc alias (see [rpc_endpoints] in foundry.toml)
#                  or full https/wss URL. Defaults to `paseo_local`.
#   ENV_FILE       Path to env file. Defaults to `.env`.
#
# Extra forge flags are forwarded verbatim to every stage, e.g.
#   ./scripts/deploy/run.sh '--slow --timeout 1000'

set -euo pipefail

ENV_FILE="${ENV_FILE:-.env}"

if [ -f "$ENV_FILE" ]; then
  set -a
  # shellcheck source=/dev/null
  . "$ENV_FILE"
  set +a
fi

if [ -z "${ACCOUNT_NAME:-}" ]; then
  echo "ACCOUNT_NAME is required (set in $ENV_FILE or as env var)" >&2
  echo "see .env.example for the expected shape" >&2
  exit 1
fi

if [ -z "${ACCOUNT_PASSWORD:-}" ]; then
  echo "ACCOUNT_PASSWORD is required (set in $ENV_FILE or as env var)" >&2
  echo "see .env.example for the expected shape" >&2
  exit 1
fi

if [ -z "${WHITELIST_OPERATOR:-}" ]; then
  echo "WHITELIST_OPERATOR is required (set in $ENV_FILE or as env var)" >&2
  echo "see .env.example for the expected shape" >&2
  exit 1
fi

RPC_URL="${RPC_URL:-paseo_local}"
extra="${1:-}"

KEYSTORE_DIR="${FOUNDRY_KEYSTORES_DIR:-$HOME/.foundry/keystores}"
KEYSTORE_PATH="$KEYSTORE_DIR/$ACCOUNT_NAME"

if [ ! -f "$KEYSTORE_PATH" ]; then
  if [ -z "${PRIVATE_KEY:-}" ]; then
    echo "PRIVATE_KEY is required once to import missing account '$ACCOUNT_NAME'" >&2
    echo "after import, remove PRIVATE_KEY from $ENV_FILE and rerun with ACCOUNT_NAME/ACCOUNT_PASSWORD" >&2
    exit 1
  fi

  # Strip 0x prefix if present. `cast wallet import` accepts both, but one
  # normalised shell value keeps the command shape predictable.
  PK="${PRIVATE_KEY#0x}"

  cast wallet import "$ACCOUNT_NAME" \
    --private-key "$PK" \
    --unsafe-password "$ACCOUNT_PASSWORD" >/dev/null

  unset PK PRIVATE_KEY
fi

SENDER=$(cast wallet address --account "$ACCOUNT_NAME" --password "$ACCOUNT_PASSWORD")

common=(
  --rpc-url "$RPC_URL"
  --account "$ACCOUNT_NAME"
  --password "$ACCOUNT_PASSWORD"
  --sender "$SENDER"
  --broadcast
  --slow
  --legacy
  --gas-estimate-multiplier 10000
  -vvvvv
)

stages=(
  DeployCore
  DeployRecords
  DeployPolicy
  DeployPopSystem
  WireDeployments
)

for stage in "${stages[@]}"; do
  echo "=== Running $stage ==="
  # shellcheck disable=SC2086
  forge script "scripts/deploy/${stage}.s.sol:${stage}" "${common[@]}" $extra
done

echo "=== Pipeline complete ==="

if [ -f "$ENV_FILE" ]; then
  rm -f "$ENV_FILE"
  echo "Deleted one-off env file: $ENV_FILE"
fi
