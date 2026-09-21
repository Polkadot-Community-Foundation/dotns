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
# The script asserts the deployer is at FACTORY_NONCE (default 0, so the key
# must be pristine). Devnet deploys from a used key set FACTORY_NONCE to the
# key's current nonce (preflight.sh prints it); the factory then lands at that
# nonce's CREATE address, which is stable only for that key at that nonce.
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
# shellcheck source=scripts/deploy/_retry.sh
. "$(dirname "$0")/_retry.sh"

# Forward every extra forge flag (word-split), not just the first token.
extra="$*"

# DeployCreate3Factory asserts the same nonce; exported so forge reads it
# (a value from .env is not exported by _account.sh).
: "${FACTORY_NONCE:=0}"
[[ "$FACTORY_NONCE" =~ ^[0-9]+$ ]] || { echo "FACTORY_NONCE must be a non-negative integer (got '$FACTORY_NONCE')" >&2; exit 1; }
export FACTORY_NONCE

# The factory address is the deterministic CREATE from this key at
# FACTORY_NONCE, so it is identical on every fresh chain (nonce 0).
FACTORY_ADDRESS=$(cast compute-address --nonce "$FACTORY_NONCE" "$SENDER" | awk '{print $NF}')

# Optional guard: when EXPECTED_CREATE3_FACTORY is pinned (per network), abort if
# the resolved address differs, so a wrong or rotated key cannot silently
# relocate the whole protocol.
if [ -n "${EXPECTED_CREATE3_FACTORY:-}" ] \
  && [ "$(printf '%s' "$FACTORY_ADDRESS" | tr 'A-F' 'a-f')" != "$(printf '%s' "$EXPECTED_CREATE3_FACTORY" | tr 'A-F' 'a-f')" ]; then
  echo "Factory address $FACTORY_ADDRESS does not match EXPECTED_CREATE3_FACTORY ($EXPECTED_CREATE3_FACTORY); wrong deployer key?" >&2
  exit 1
fi

# Skip the deploy when the factory is already present. Distinguish an RPC error
# (a failed attempt) from a genuinely empty account, so a network blip does not
# push a key at the wrong nonce into the deploy path and trip its assertion.
# The check is part of every attempt: a deploy whose transaction landed while
# the RPC was down is found present on the next attempt rather than resent
# (which the nonce assertion in DeployCreate3Factory would refuse anyway).
deploy_factory_once() {
  local existing_code
  if ! existing_code=$(cast code "$FACTORY_ADDRESS" --rpc-url "$RPC_URL" 2>/dev/null); then
    echo "Could not query code at $FACTORY_ADDRESS ($RPC_URL); not deploying blind." >&2
    return 1
  fi
  if [ "$existing_code" != "0x" ]; then
    echo "Create3Factory already present at $FACTORY_ADDRESS on chain $CHAIN_ID (skipping deploy)"
    return 0
  fi
  echo "=== Deploying Create3Factory from '$ACCOUNT_NAME' ($SENDER, nonce $FACTORY_NONCE) on chain $CHAIN_ID ==="
  # Broadcast flags shared with the pipeline (defined in _account.sh).
  # shellcheck disable=SC2086
  forge script scripts/deploy/DeployCreate3Factory.s.sol:DeployCreate3Factory \
    "${FORGE_DEPLOY_ARGS[@]}" \
    -vvvv $extra
}

run_with_attempts "Create3Factory" "" deploy_factory_once || exit 1

# Machine-parseable line consumed by deployall.sh.
echo "CREATE3_FACTORY=$FACTORY_ADDRESS"
