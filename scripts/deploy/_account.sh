#!/usr/bin/env bash
#
# Shared deployer-account bootstrap for the deploy scripts. This file is
# SOURCED, not executed. It resolves the Foundry keystore account, RPC alias,
# broadcasting address, and chain id, importing the account from a one-off
# `.env` on first run.
#
# Callers set `ACCOUNT_NAME` (and optionally `RPC_URL`) before sourcing to pick
# which key and network to use; both default to the pipeline's values when
# unset. The parent script must already have run `set -euo pipefail`.
#
# On return the following are set and exported:
#   ACCOUNT_NAME, ACCOUNT_PASSWORD, RPC_URL, SENDER, CHAIN_ID
# plus FORGE_DEPLOY_ARGS (forge broadcast flags) and CAST_SIGNER_ARGS (cast send
# signer flags) for the resolved signer.
#
# Env vars honoured (read from `.env` if present, otherwise the shell):
#   DEPLOY_SIGNER      keystore (default) or gcp. gcp signs with a Cloud KMS
#                      key through forge/cast --gcp: no keystore, no password,
#                      and the sender is read from the key. Requires
#                      GCP_PROJECT_ID, GCP_LOCATION, GCP_KEY_RING, GCP_KEY_NAME;
#                      GCP_KEY_VERSION defaults to 1.
#   ACCOUNT_NAME       Foundry keystore account passed to forge as --account.
#   ACCOUNT_PASSWORD   Keystore password. Prompted interactively when unset.
#   PRIVATE_KEY        Deployer key, only needed to import a missing account.
#   RPC_URL            Foundry rpc alias or full URL. Defaults to paseo_local.
#   ENV_FILE           Path to the env file. Defaults to `.env`.

ENV_FILE="${ENV_FILE:-.env}"

# Source .env WITHOUT auto-export (no `set -a`), so secrets such as
# ACCOUNT_PASSWORD and PRIVATE_KEY stay as shell variables and are never
# exported into child processes (forge and cast receive them as explicit
# flags). The few variables forge scripts read from the environment
# (ACCOUNT_NAME here; DEPLOYMENT_NETWORK, CREATE3_FACTORY in
# run.sh) are exported explicitly.
# Preserve caller-provided account details (for example deployall.sh selecting
# the factory keystore with its own password and key) so sourcing .env cannot
# clobber them.
_caller_account_name="${ACCOUNT_NAME:-}"
_caller_account_password="${ACCOUNT_PASSWORD:-}"
_caller_private_key="${PRIVATE_KEY:-}"
if [ -f "$ENV_FILE" ]; then
  # shellcheck source=/dev/null
  . "$ENV_FILE"
fi
if [ -n "$_caller_account_name" ]; then
  ACCOUNT_NAME="$_caller_account_name"
fi
if [ -n "$_caller_account_password" ]; then
  ACCOUNT_PASSWORD="$_caller_account_password"
fi
if [ -n "$_caller_private_key" ]; then
  PRIVATE_KEY="$_caller_private_key"
fi

: "${ACCOUNT_NAME:=dotns-deploy}"
: "${RPC_URL:=paseo_local}"
export ACCOUNT_NAME

DEPLOY_SIGNER="${DEPLOY_SIGNER:-keystore}"

# Request-level RPC retries. forge retries a request only on HTTP 429/503 (alloy's
# retry policy; a 502 or a refused connection is never retried), and only the
# simulation provider honours these flags: the broadcast provider keeps forge's
# built-in 8 x 0.8 s. These widen the simulation's 503 tolerance to 8 x 3 s.
# Everything else (502, connection reset, adapter restart) is covered by the
# stage-level retry in run.sh and factory.sh (DEPLOY_STAGE_ATTEMPTS).
FORGE_RPC_RETRY_ARGS=(--fork-retries 8 --fork-retry-backoff 3000)

if [ "$DEPLOY_SIGNER" = "gcp" ]; then
  for _v in GCP_PROJECT_ID GCP_LOCATION GCP_KEY_RING GCP_KEY_NAME; do
    if [ -z "${!_v:-}" ]; then
      echo "DEPLOY_SIGNER=gcp requires $_v" >&2
      exit 1
    fi
  done
  # Every KMS path passes the mode/key/chain guard before touching the key.
  # shellcheck source=scripts/deploy/_production.sh
  . "$(dirname "${BASH_SOURCE[0]}")/_production.sh"
  guard_chain_key
  : "${GCP_KEY_VERSION:=1}"
  # forge and cast read the key coordinates from the environment.
  export GCP_PROJECT_ID GCP_LOCATION GCP_KEY_RING GCP_KEY_NAME GCP_KEY_VERSION
  SENDER=$(cast wallet address --gcp)
  # shellcheck disable=SC2034  # consumed by the sourcing scripts
  CHAIN_ID=$(cast chain-id --rpc-url "$RPC_URL")
  # shellcheck disable=SC2034  # consumed by the sourcing scripts
  CAST_SIGNER_ARGS=(--gcp)
  # shellcheck disable=SC2034  # consumed by the sourcing scripts (run.sh, factory.sh)
  FORGE_DEPLOY_ARGS=(
    --rpc-url "$RPC_URL"
    --gcp
    --sender "$SENDER"
    --broadcast
    --slow
    --legacy
    --gas-limit 1000000000
    "${FORGE_RPC_RETRY_ARGS[@]}"
  )
  return 0
elif [ "$DEPLOY_SIGNER" != "keystore" ]; then
  echo "DEPLOY_SIGNER must be keystore or gcp (got '$DEPLOY_SIGNER')" >&2
  exit 1
fi

# Prompt for the keystore password when it has not been supplied by `.env` or
# the shell. Reading once keeps the prompt to a single keystroke even though
# every forge invocation receives --password.
if [ -z "${ACCOUNT_PASSWORD:-}" ]; then
  if [ ! -t 0 ]; then
    echo "ACCOUNT_PASSWORD is required (set in $ENV_FILE or as env var, or run from a terminal that can prompt)" >&2
    exit 1
  fi
  read -rsp "Password for Foundry keystore '$ACCOUNT_NAME': " ACCOUNT_PASSWORD
  echo
fi

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

# Plain shell variables: the sourcing script reads them directly, and forge and
# cast receive them as explicit flags, so nothing needs the password in a child
# process's environment.
SENDER=$(cast wallet address --account "$ACCOUNT_NAME" --password "$ACCOUNT_PASSWORD")
# shellcheck disable=SC2034  # consumed by the sourcing script (run.sh)
CHAIN_ID=$(cast chain-id --rpc-url "$RPC_URL")

# Shared forge broadcast arguments for the resolved account, so run.sh and
# factory.sh invoke forge identically and the flags cannot drift apart.
# --legacy suits the eth-rpc adapter, --slow sequences one transaction at a time
# to keep nonces ordered, and --gas-limit matches block_gas_limit in foundry.toml
# (and the anvil --block-gas-limit used in CI). Callers append verbosity and any
# extra flags.
# shellcheck disable=SC2034  # consumed by the sourcing scripts (run.sh, factory.sh)
FORGE_DEPLOY_ARGS=(
  --rpc-url "$RPC_URL"
  --account "$ACCOUNT_NAME"
  --password "$ACCOUNT_PASSWORD"
  --sender "$SENDER"
  --broadcast
  --slow
  --legacy
  --gas-limit 1000000000
  "${FORGE_RPC_RETRY_ARGS[@]}"
)
# shellcheck disable=SC2034  # consumed by the sourcing scripts
CAST_SIGNER_ARGS=(--account "$ACCOUNT_NAME" --password "$ACCOUNT_PASSWORD")
