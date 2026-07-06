#!/usr/bin/env bash
#
# Runs the multi-stage DotNS deploy pipeline against a Foundry keystore
# wallet. `.env` is a one-off bootstrap file: it carries PRIVATE_KEY and
# ACCOUNT_PASSWORD only long enough to import the wallet into the
# Foundry keystore on the first run, after which the file is deleted so
# no plaintext secrets persist on disk. Subsequent runs prompt for the
# keystore password interactively and rely on sensible defaults for
# everything else; nothing sensitive ever sits in a file between
# deploys. A failed run leaves `.env` exactly as it was for correction
# and retry.
#
# Local usage:
#   1. cp .env.example .env
#   2. set PRIVATE_KEY and ACCOUNT_PASSWORD in .env (and adjust
#      ACCOUNT_NAME, WHITELIST_OPERATOR, or RPC_URL if the defaults are
#      not what you want)
#   3. bun run deploy   (or ./scripts/deploy/run.sh)
#   4. on success, the script deletes .env automatically
#   5. for every subsequent run, just `bun run deploy`; you will be
#      prompted for the keystore password
#
# CI / scripted usage (no `.env`):
#   PRIVATE_KEY=0x... ACCOUNT_PASSWORD=... ./scripts/deploy/run.sh '--slow'
#
# Each stage runs as its own `forge script` invocation (therefore its
# own EVM simulation), so OpenZeppelin's upgrade-safety validator's
# cumulative memory gas cannot spill across stages.
#
# Env vars (read from `.env` if present, otherwise from the shell):
#   ACCOUNT_NAME       Foundry keystore account passed to forge as --account.
#                      Defaults to `dotns-deploy`.
#   ACCOUNT_PASSWORD   Password passed to cast/forge as --password. Prompted
#                      interactively when not set.
#   WHITELIST_OPERATOR Address granted whitelist management permission.
#                      Defaults to the team-wide operator in .env.example.
#   PRIVATE_KEY        Hex-encoded deployer private key, with or without 0x.
#                      Required only when ACCOUNT_NAME has not yet been
#                      imported into the Foundry keystore.
#   RPC_URL            Foundry rpc alias (see [rpc_endpoints] in foundry.toml)
#                      or full https/wss URL. Defaults to `paseo_local`.
#   ENV_FILE           Path to env file. Defaults to `.env`.
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

# Defaults for the values that do not need to be re-entered between
# deploys. Override either via .env (during bootstrap) or via the shell
# environment.
: "${ACCOUNT_NAME:=dotns-deploy}"
: "${WHITELIST_OPERATOR:=0xd908e5a6c88e9263f8fd0756bd0b77916008bb72}"
: "${RPC_URL:=paseo_local}"
export ACCOUNT_NAME WHITELIST_OPERATOR

# Prompt for the keystore password when it has not been supplied by
# .env or the shell. Reading once into a bash variable keeps the prompt
# to a single keystroke per deploy even though every stage receives
# --password on its forge invocation.
if [ -z "${ACCOUNT_PASSWORD:-}" ]; then
  if [ ! -t 0 ]; then
    echo "ACCOUNT_PASSWORD is required (set in $ENV_FILE or as env var, or run from a terminal that can prompt)" >&2
    exit 1
  fi
  read -rsp "Password for Foundry keystore '$ACCOUNT_NAME': " ACCOUNT_PASSWORD
  echo
fi

extra="${1:-}"

KEYSTORE_DIR="${FOUNDRY_KEYSTORES_DIR:-$HOME/.foundry/keystores}"
KEYSTORE_PATH="$KEYSTORE_DIR/$ACCOUNT_NAME"

if [ ! -f "$KEYSTORE_PATH" ]; then
  if [ -z "${PRIVATE_KEY:-}" ]; then
    echo "PRIVATE_KEY is required once to import missing account '$ACCOUNT_NAME'" >&2
    echo "see .env.example for the expected shape" >&2
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
CHAIN_ID=$(cast chain-id --rpc-url "$RPC_URL")

if [ "${DOTNS_DEPLOY_SKIP_CLEAN_BUILD:-0}" != "1" ]; then
  echo "=== Rebuilding full Foundry artifacts for OpenZeppelin validation ==="
  forge clean
  forge build
fi

case "$CHAIN_ID" in
  420420422) DEPLOYMENT_FOLDER="passethub-testnet" ;;
  420420417) DEPLOYMENT_FOLDER="summit-asset-hub" ;;
  420420420) DEPLOYMENT_FOLDER="paseo-local" ;;
  *) DEPLOYMENT_FOLDER="localhost" ;;
esac

# Chains sharing an EVM chain id (paseo-next vs summit, both 420420417) are
# disambiguated with DOTNS_DEPLOYMENT_FOLDER; the Solidity stage scripts honor
# the same override (DeploymentNetwork.folder / _getDeploymentFolder).
DEPLOYMENT_FOLDER="${DOTNS_DEPLOYMENT_FOLDER:-$DEPLOYMENT_FOLDER}"

MANIFEST_PATH="deployments/$DEPLOYMENT_FOLDER/$CHAIN_ID.json"
mkdir -p "$(dirname "$MANIFEST_PATH")"

backup_manifest() {
  local backup
  backup=$(mktemp "${TMPDIR:-/tmp}/dotns-manifest.${CHAIN_ID}.XXXXXX")
  if [ -f "$MANIFEST_PATH" ]; then
    cp "$MANIFEST_PATH" "$backup"
    echo "$backup"
  else
    rm -f "$backup"
    echo ""
  fi
}

restore_manifest() {
  local backup="$1"
  if [ -n "$backup" ]; then
    cp "$backup" "$MANIFEST_PATH"
  else
    rm -f "$MANIFEST_PATH"
  fi
}

validate_manifest_contracts() {
  if [ ! -f "$MANIFEST_PATH" ]; then
    echo "Manifest missing after stage: $MANIFEST_PATH" >&2
    return 1
  fi

  local failed=0
  while read -r name addr; do
    [ -n "$name" ] || continue
    code=$(cast code "$addr" --rpc-url "$RPC_URL")
    if [ "$code" = "0x" ]; then
      echo "Manifest address has no code: $name=$addr" >&2
      failed=1
    fi
  done < <(
    jq -r '
      to_entries[]
      | select(.key != "_seed")
      | select(.value != "0x0000000000000000000000000000000000000000")
      | "\(.key) \(.value)"
    ' "$MANIFEST_PATH"
  )

  return "$failed"
}

if [ "${DOTNS_DEPLOY_KEEP_MANIFEST:-0}" != "1" ] && [ -f "$MANIFEST_PATH" ]; then
  ARCHIVE_PATH="${MANIFEST_PATH}.pre-fresh.$(date +%Y%m%d%H%M%S)"
  cp "$MANIFEST_PATH" "$ARCHIVE_PATH"
  rm -f "$MANIFEST_PATH"
  echo "Archived existing manifest for fresh deploy: $ARCHIVE_PATH"
fi

common=(
  --rpc-url "$RPC_URL"
  --account "$ACCOUNT_NAME"
  --password "$ACCOUNT_PASSWORD"
  --sender "$SENDER"
  --broadcast
  --slow
  --legacy
  --gas-limit 2000000000
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
  manifest_backup=$(backup_manifest)
  # shellcheck disable=SC2086
  if ! forge script "scripts/deploy/${stage}.s.sol:${stage}" "${common[@]}" $extra; then
    restore_manifest "$manifest_backup"
    echo "Restored manifest after failed stage: $stage" >&2
    exit 1
  fi
  if ! validate_manifest_contracts; then
    restore_manifest "$manifest_backup"
    echo "Restored manifest after invalid stage output: $stage" >&2
    exit 1
  fi
done

echo "=== Pipeline complete ==="

# Delete the bootstrap env file so plaintext secrets do not persist
# between deploys. Subsequent runs prompt for the password interactively
# and rely on the defaults declared above for everything else.
if [ -f "$ENV_FILE" ]; then
  rm -f "$ENV_FILE"
  echo "Deleted one-off env file: $ENV_FILE"
fi
