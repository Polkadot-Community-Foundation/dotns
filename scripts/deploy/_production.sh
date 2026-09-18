#!/usr/bin/env bash
#
# Shared helpers for the production scripts (preflight, handover, verify,
# sweep, rehearse-fork). SOURCED, not executed; the caller runs
# `set -euo pipefail` first.
#
# Env vars:
#   DEPLOY_MODE        fork, live or devnet. Required.
#   DEPLOY_SIGNER      keystore (default) or gcp; see _account.sh.
#   GCP_KEY_NAME       KMS key name, checked against DEPLOY_MODE and the chain.
#   RPC_URL            ETH-RPC endpoint.
#   SUBSTRATE_RPC_URL  Substrate endpoint of the same chain (http(s) or ws(s)).

export FOUNDRY_DISABLE_NIGHTLY_WARNING=1

# shellcheck disable=SC2034  # consumed by the sourcing scripts
POLKADOT_AH_CHAIN_ID=420420419
DEVNET_AH_CHAIN_ID=420420417
ZERO_ADDRESS=0x0000000000000000000000000000000000000000

# Manifest contracts whose owner() the deployer holds after WireDeployments.
# shellcheck disable=SC2034  # consumed by the sourcing scripts
OWNED_CONTRACTS=(
  DotnsContentResolver DotnsCostModelRegistry DotnsNameEscrow DotnsNameWhitelist
  DotnsPopController DotnsPopResolver DotnsRegistrar DotnsRegistrarController
  DotnsRegistry DotnsResolver DotnsReverseResolver PopRules StoreFactory
  DotnsProtocolRegistry
)

_deploy_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

die() {
  echo "$(basename "$0"): $*" >&2
  exit 1
}

lc() {
  printf '%s' "$1" | tr 'A-F' 'a-f'
}

same_address() {
  [ "$(lc "$1")" = "$(lc "$2")" ]
}

require_h160() {
  local name="$1" value="$2"
  [[ "$value" =~ ^0x[0-9a-fA-F]{40}$ ]] || die "$name is not an H160: '$value'"
  ! same_address "$value" "$ZERO_ADDRESS" || die "$name is the zero address"
}

# D5/D8: a fork keeps Polkadot's genesis and eth chain id, so a signature made
# there is valid on mainnet. Each KMS key class signs on one kind of chain only:
# *-rehearsal on forks, *-devnet on devnet Asset Hub, any other key on Polkadot
# Asset Hub. Keystore keys never sign live. Static part, no network.
guard_mode_key() {
  local signer="${DEPLOY_SIGNER:-keystore}" key="${GCP_KEY_NAME:-}"
  case "${DEPLOY_MODE:-}" in
    fork)
      if [ "$signer" = "gcp" ]; then
        [[ "$key" == *-rehearsal ]] \
          || die "mode=fork refuses KMS key '$key': only *-rehearsal keys sign on a fork"
      fi
      ;;
    devnet)
      if [ "$signer" = "gcp" ]; then
        [[ "$key" == *-devnet ]] \
          || die "mode=devnet refuses KMS key '$key': only *-devnet keys sign on devnet"
      fi
      ;;
    live)
      [ "$signer" = "gcp" ] || die "mode=live requires DEPLOY_SIGNER=gcp"
      [ -n "$key" ] || die "mode=live requires GCP_KEY_NAME"
      [[ "$key" != *-rehearsal && "$key" != *-devnet ]] || die "mode=live refuses key '$key'"
      ;;
    *) die "DEPLOY_MODE must be fork, live or devnet (got '${DEPLOY_MODE:-}')" ;;
  esac
}

expected_chain_id() {
  if [ "${DEPLOY_MODE:-}" = "devnet" ]; then echo "$DEVNET_AH_CHAIN_ID"; else echo "$POLKADOT_AH_CHAIN_ID"; fi
}

# chopsticks serves dev_newBlock; real nodes do not (they may serve other dev_*).
is_chopsticks() {
  local methods
  methods=$(cast rpc --rpc-url "$SUBSTRATE_RPC_URL" rpc_methods) \
    || die "could not read rpc_methods from $SUBSTRATE_RPC_URL"
  jq -e '.methods | index("dev_newBlock")' <<<"$methods" >/dev/null
}

# guard_mode_key, then the chain itself, before any KMS or signing call: fork
# mode needs a chopsticks fork; live needs Polkadot Asset Hub, devnet the
# devnet Asset Hub, neither a fork.
guard_chain_key() {
  guard_mode_key
  require_substrate_rpc
  : "${RPC_URL:?RPC_URL is required}"
  local chain_id fork=0
  chain_id=$(cast chain-id --rpc-url "$RPC_URL") || die "could not read the chain id from $RPC_URL"
  if is_chopsticks; then fork=1; fi
  case "$DEPLOY_MODE" in
    fork)
      [ "$fork" = "1" ] || die "mode=fork but $SUBSTRATE_RPC_URL is not a chopsticks fork"
      ;;
    live | devnet)
      [ "$fork" = "0" ] || die "mode=$DEPLOY_MODE but $SUBSTRATE_RPC_URL is a chopsticks fork"
      [ "$chain_id" = "$(expected_chain_id)" ] \
        || die "mode=$DEPLOY_MODE refuses chain id $chain_id (expected $(expected_chain_id))"
      ;;
  esac
  local same=(same-chain --rpc "$SUBSTRATE_RPC_URL" --eth "$RPC_URL")
  [ "$fork" = "1" ] && same+=(--fork)
  python3 "$_deploy_dir/substrate.py" "${same[@]}" || die "$RPC_URL does not serve the chain behind $SUBSTRATE_RPC_URL"
}

# Native token symbol for messages.
native_unit() {
  if [ "${DEPLOY_MODE:-}" = "devnet" ]; then echo PAS; else echo DOT; fi
}

require_substrate_rpc() {
  [ -n "${SUBSTRATE_RPC_URL:-}" ] || die "SUBSTRATE_RPC_URL is required"
}

# System.Account of an H160's fallback account (or an AccountId32), as JSON.
substrate_account() {
  python3 "$_deploy_dir/substrate.py" account "$1" --rpc "$SUBSTRATE_RPC_URL"
}

substrate_free() {
  substrate_account "$1" | jq -r .free
}

# AccountId32 the chain maps an H160 to, empty when unmapped.
substrate_mapped() {
  python3 "$_deploy_dir/substrate.py" mapped "$1" --rpc "$SUBSTRATE_RPC_URL" || true
}

planck_to_dot() {
  python3 -c "import sys; print(f'{int(sys.argv[1]) / 1e10:.4f}')" "$1"
}

has_code() {
  local code
  code=$(cast code "$1" --rpc-url "$RPC_URL") || die "could not read code at $1"
  [ "$code" != "0x" ]
}

owner_of() {
  cast call "$1" 'owner()(address)' --rpc-url "$RPC_URL" 2>/dev/null || echo none
}
