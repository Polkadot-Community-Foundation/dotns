#!/usr/bin/env bash
#
# Runs the multi-stage DotNS deploy pipeline against an ephemeral
# Foundry keystore wallet built from `.env`, then deletes both the
# wallet and `.env` on exit so no key material persists on disk.
#
# Local usage:
#   1. cp .env.example .env
#   2. set PRIVATE_KEY (and optionally RPC_URL) in .env
#   3. bun run deploy   (or ./scripts/deploy/run.sh)
#
# CI / scripted usage (no `.env`):
#   PRIVATE_KEY=0x... ./scripts/deploy/run.sh '--slow'
#
# Each stage runs as its own `forge script` invocation (therefore its
# own EVM simulation), so OpenZeppelin's upgrade-safety validator's
# cumulative memory gas cannot spill across stages.
#
# Required env (from `.env` or shell):
#   PRIVATE_KEY    Hex-encoded deployer private key, with or without 0x.
#
# Optional env:
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

if [ -z "${PRIVATE_KEY:-}" ]; then
  echo "PRIVATE_KEY is required (set in $ENV_FILE or as env var)" >&2
  echo "see .env.example for the expected shape" >&2
  exit 1
fi

RPC_URL="${RPC_URL:-paseo_local}"
extra="${1:-}"

# Ephemeral keystore wallet. Name embeds the shell PID so concurrent
# runs cannot collide on the same keystore file. Password is a 32-char
# random string generated below; it lives only in this process's
# memory and the encrypted keystore on disk for the duration of the
# run.
WALLET_NAME="dotns-deploy-$$"
WALLET_PASSWORD=$(head -c 32 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 32)
KEYSTORE_DIR="${FOUNDRY_KEYSTORES_DIR:-$HOME/.foundry/keystores}"
KEYSTORE_PATH="$KEYSTORE_DIR/$WALLET_NAME"

cleanup() {
  # Always run, success or fail. Removes both the .env (if present) and
  # the ephemeral keystore so a deploy run leaves no key material on
  # disk. CI flows that pass PRIVATE_KEY via shell env (no .env) skip
  # the .env unlink because the conditional below short-circuits.
  if [ -f "$ENV_FILE" ]; then
    rm -f "$ENV_FILE"
  fi
  if [ -f "$KEYSTORE_PATH" ]; then
    rm -f "$KEYSTORE_PATH"
  fi
}
trap cleanup EXIT INT TERM

# Strip 0x prefix if present (cast accepts both, normalise to one shape).
PK="${PRIVATE_KEY#0x}"

cast wallet import "$WALLET_NAME" \
  --private-key "$PK" \
  --unsafe-password "$WALLET_PASSWORD" >/dev/null

SENDER=$(cast wallet address --account "$WALLET_NAME" --password "$WALLET_PASSWORD")

# Wipe the plaintext PK from this shell so a later `set | grep` or stack
# trace cannot surface it. The keystore is the canonical store now until
# cleanup deletes it.
unset PK PRIVATE_KEY

common=(
  --rpc-url "$RPC_URL"
  --account "$WALLET_NAME"
  --password "$WALLET_PASSWORD"
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
