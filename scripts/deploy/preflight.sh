#!/usr/bin/env bash
#
# Refuses a deploy unless the chain, the key and the target addresses are
# exactly what a first deploy expects. Read-only.
#
# Checks: mode/key/chain guard; chain id 420420419 (420420417 for devnet);
# sender nonce (eth and Substrate views agree; exactly 0 in live, any value in
# devnet and fork, where the factory lands at the key's current nonce); sender
# free balance >= MIN_BALANCE_DOT; NEW_OWNER set, not zero, not the sender, no
# code; no address of the expected set has code.
#
# DEPLOY_RESUME=1 accepts a run that stopped part way instead: the key is past
# the factory nonce, so the factory is taken from the chain (FACTORY_NONCE when
# set, else the highest nonce below the current one whose CREATE address holds
# the Create3Factory code; live keeps nonce 0), and an occupied expected
# address passes only when its runtime code is the artefact the pipeline
# deploys there (expected-code.py; a squat with other code is refused) and,
# for the owned contracts, its owner() is still the sender. The minimum balance
# scales with what is left to deploy. Every stage re-checks an adopted address
# against this run's constructor arguments (BaseDeployer), so this pre-screen
# is not the last line.
#
# Prints `FACTORY_NONCE=<nonce>` for the deploy step (deployall.sh reads it
# from the environment).
#
# Usage:
#   DEPLOY_MODE=devnet|live|fork NEW_OWNER=0x... SUBSTRATE_RPC_URL=... RPC_URL=... \
#     scripts/deploy/preflight.sh
#
# Env vars:
#   MIN_BALANCE_DOT    In the native token. Default 40 (33.3 spend + 2.64
#                      max-fee headroom at 8e11 wei + margin); 50 on devnet
#                      Asset Hub (the same with every cost scaled to its 1e12
#                      gas price).
#   FACTORY_NONCE      When set, must equal the sender's nonce (with
#                      DEPLOY_RESUME=1: the nonce the factory was deployed at).
#   DEPLOY_RESUME      1 to accept a partially deployed set (see above).
#   EXPECTED_SET_OUT   When set, the expected set is also written there.
#   Signer vars as in _account.sh.

set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/deploy/_production.sh
. "$here/_production.sh"

guard_chain_key
require_h160 NEW_OWNER "${NEW_OWNER:-}"

# shellcheck source=scripts/deploy/_account.sh
. "$here/_account.sh"

DEPLOY_RESUME="${DEPLOY_RESUME:-0}"
case "$DEPLOY_RESUME" in 0 | 1) ;; *) die "DEPLOY_RESUME must be 0 or 1 (got '$DEPLOY_RESUME')" ;; esac

echo "=== Preflight ($DEPLOY_MODE, signer ${DEPLOY_SIGNER:-keystore}$([ "$DEPLOY_RESUME" = "1" ] && echo ", resume")) ==="
echo "sender     $SENDER"
echo "new owner  $NEW_OWNER"

check_chain_id "$CHAIN_ID" || die "chain id $CHAIN_ID is not one mode=$DEPLOY_MODE accepts"
echo "ok  chain id $CHAIN_ID"

eth_nonce=$(cast nonce "$SENDER" --rpc-url "$RPC_URL")
account=$(substrate_account "$SENDER")
sub_nonce=$(jq -r .nonce <<<"$account")
[ "$eth_nonce" = "$sub_nonce" ] \
  || die "sender nonce differs between views (eth $eth_nonce, substrate $sub_nonce)"
# Runtime code of the Create3Factory artefact (no immutables, so it compares exactly).
factory_artefact=out/Create3Factory.sol/Create3Factory.json
holds_factory_code() {
  local code
  code=$(cast code "$1" --rpc-url "$RPC_URL") || die "could not read code at $1"
  [ "$code" = "$(jq -r .deployedBytecode.object "$factory_artefact")" ]
}

if [ "$DEPLOY_RESUME" = "1" ]; then
  # The artefacts are the reference for every code comparison below.
  [ -f "$factory_artefact" ] || forge build >/dev/null
  if [ "$DEPLOY_MODE" = "live" ]; then
    [ "${FACTORY_NONCE:-0}" = "0" ] \
      || die "FACTORY_NONCE=$FACTORY_NONCE but on Polkadot Asset Hub the factory is the key's nonce-0 transaction"
    FACTORY_NONCE=0
  fi
  if [ -n "${FACTORY_NONCE:-}" ]; then
    [ "$FACTORY_NONCE" -lt "$eth_nonce" ] \
      || die "FACTORY_NONCE=$FACTORY_NONCE is not below the sender nonce $eth_nonce: nothing to resume"
    factory_addr=$(cast compute-address --nonce "$FACTORY_NONCE" "$SENDER" | awk '{print $NF}')
    holds_factory_code "$factory_addr" \
      || die "no Create3Factory at $factory_addr, the sender's CREATE at nonce $FACTORY_NONCE: nothing to resume"
  else
    # The interrupted run began with its factory, and every later transaction of the key
    # belonged to that run, so the factory with the highest nonce is the one to resume.
    factory_addr=""
    for ((n = eth_nonce - 1; n >= 0 && n >= eth_nonce - 500; n--)); do
      candidate=$(cast compute-address --nonce "$n" "$SENDER" | awk '{print $NF}')
      if holds_factory_code "$candidate"; then
        FACTORY_NONCE="$n"
        factory_addr="$candidate"
        break
      fi
    done
    [ -n "$factory_addr" ] \
      || die "no Create3Factory found among the sender's CREATE addresses below nonce $eth_nonce: nothing to resume (run without DEPLOY_RESUME)"
  fi
  echo "ok  sender nonce $eth_nonce, resuming the factory at nonce $FACTORY_NONCE ($factory_addr)"
else
  if [ "$DEPLOY_MODE" = "live" ] && [ "$eth_nonce" != "0" ]; then
    die "sender nonce is $eth_nonce, not 0: on Polkadot Asset Hub the factory must be the key's first transaction"
  fi
  if [ -n "${FACTORY_NONCE:-}" ] && [ "$FACTORY_NONCE" != "$eth_nonce" ]; then
    die "FACTORY_NONCE=$FACTORY_NONCE but the sender nonce is $eth_nonce"
  fi
  FACTORY_NONCE="$eth_nonce"
  echo "ok  sender nonce $eth_nonce (the factory lands at nonce $FACTORY_NONCE)"
fi

! same_address "$NEW_OWNER" "$SENDER" || die "NEW_OWNER is the sender"
! has_code "$NEW_OWNER" || die "NEW_OWNER $NEW_OWNER has code; expected the dotns-owner pure's H160"
echo "ok  new owner has no code"

expected=$("$here/expected-set.sh" --nonce "$FACTORY_NONCE" "$SENDER")
if [ -n "${EXPECTED_SET_OUT:-}" ]; then
  printf '%s\n' "$expected" >"$EXPECTED_SET_OUT"
fi
total=$(jq length <<<"$expected")
occupied=0
if [ "$DEPLOY_RESUME" = "1" ]; then
  # Occupied addresses must hold the pipeline's own artefacts (immutables masked);
  # anything else at an expected address is a squat.
  report=$(python3 "$here/expected-code.py" --rpc "$RPC_URL" - <<<"$expected") \
    || die "an expected-set address holds code the pipeline would not deploy there (squat?)"
  occupied=$(sed -n 's/^occupied \([0-9]*\) of.*/\1/p' <<<"$report")
  # An adopted proxy must still answer to the deployer, or the wiring and the handover cannot
  # run from this key (a set already handed over is not resumable through the deploy step).
  for name in "${OWNED_CONTRACTS[@]}"; do
    addr=$(jq -r --arg n "$name" '.[$n]' <<<"$expected")
    has_code "$addr" || continue
    owner=$(owner_of "$addr")
    same_address "$owner" "$SENDER" || die "$name $addr is owned by $owner, not the sender: cannot resume"
  done
  echo "ok  $occupied of $total expected addresses hold the expected code, $((total - occupied)) empty (factory $(jq -r .Create3Factory <<<"$expected"))"
else
  while read -r name addr; do
    if has_code "$addr"; then
      echo "FAIL $name $addr already has code" >&2
      occupied=1
    fi
  done < <(jq -r 'to_entries[] | "\(.key) \(.value)"' <<<"$expected")
  [ "$occupied" = "0" ] || die "expected-set addresses are occupied"
  occupied=0
  echo "ok  $total expected addresses are empty (factory $(jq -r .Create3Factory <<<"$expected"))"
fi

free=$(jq -r .free <<<"$account")
unit=$(native_unit)
if [ "$CHAIN_ID" = "$DEVNET_AH_CHAIN_ID" ]; then min="${MIN_BALANCE_DOT:-50}"; else min="${MIN_BALANCE_DOT:-40}"; fi
if [ "$DEPLOY_RESUME" = "1" ]; then
  # Scaled by the addresses still to deploy, with a floor for the wiring stage, the handover
  # and the fee headroom (RESUME_MIN_FLOOR_DOT, default 8).
  min=$(python3 -c "import sys; m, t, o, f = map(float, sys.argv[1:]); print(max(m * (t - o) / t, f))" \
    "$min" "$total" "$occupied" "${RESUME_MIN_FLOOR_DOT:-8}")
fi
min_planck=$(python3 -c "import sys; print(int(float(sys.argv[1]) * 10**10))" "$min")
python3 -c "import sys; sys.exit(int(sys.argv[1]) < int(sys.argv[2]))" "$free" "$min_planck" \
  || die "sender free balance $(planck_to_dot "$free") $unit < $min $unit"
echo "ok  sender free $(planck_to_dot "$free") $unit (fallback account $(jq -r .account_id <<<"$account"))"

echo "FACTORY_NONCE=$FACTORY_NONCE"
echo "=== Preflight passed ==="
