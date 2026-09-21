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
#   FACTORY_NONCE      When set, must equal the sender's nonce.
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

echo "=== Preflight ($DEPLOY_MODE, signer ${DEPLOY_SIGNER:-keystore}) ==="
echo "sender     $SENDER"
echo "new owner  $NEW_OWNER"

check_chain_id "$CHAIN_ID" || die "chain id $CHAIN_ID is not one mode=$DEPLOY_MODE accepts"
echo "ok  chain id $CHAIN_ID"

eth_nonce=$(cast nonce "$SENDER" --rpc-url "$RPC_URL")
account=$(substrate_account "$SENDER")
sub_nonce=$(jq -r .nonce <<<"$account")
[ "$eth_nonce" = "$sub_nonce" ] \
  || die "sender nonce differs between views (eth $eth_nonce, substrate $sub_nonce)"
if [ "$DEPLOY_MODE" = "live" ] && [ "$eth_nonce" != "0" ]; then
  die "sender nonce is $eth_nonce, not 0: on Polkadot Asset Hub the factory must be the key's first transaction"
fi
if [ -n "${FACTORY_NONCE:-}" ] && [ "$FACTORY_NONCE" != "$eth_nonce" ]; then
  die "FACTORY_NONCE=$FACTORY_NONCE but the sender nonce is $eth_nonce"
fi
FACTORY_NONCE="$eth_nonce"
echo "ok  sender nonce $eth_nonce (the factory lands at nonce $FACTORY_NONCE)"

free=$(jq -r .free <<<"$account")
unit=$(native_unit)
if [ "$CHAIN_ID" = "$DEVNET_AH_CHAIN_ID" ]; then min="${MIN_BALANCE_DOT:-50}"; else min="${MIN_BALANCE_DOT:-40}"; fi
min_planck=$(python3 -c "import sys; print(int(float(sys.argv[1]) * 10**10))" "$min")
python3 -c "import sys; sys.exit(int(sys.argv[1]) < int(sys.argv[2]))" "$free" "$min_planck" \
  || die "sender free balance $(planck_to_dot "$free") $unit < $min $unit"
echo "ok  sender free $(planck_to_dot "$free") $unit (fallback account $(jq -r .account_id <<<"$account"))"

! same_address "$NEW_OWNER" "$SENDER" || die "NEW_OWNER is the sender"
! has_code "$NEW_OWNER" || die "NEW_OWNER $NEW_OWNER has code; expected the dotns-owner pure's H160"
echo "ok  new owner has no code"

expected=$("$here/expected-set.sh" --nonce "$FACTORY_NONCE" "$SENDER")
if [ -n "${EXPECTED_SET_OUT:-}" ]; then
  printf '%s\n' "$expected" >"$EXPECTED_SET_OUT"
fi
occupied=0
while read -r name addr; do
  if has_code "$addr"; then
    echo "FAIL $name $addr already has code" >&2
    occupied=1
  fi
done < <(jq -r 'to_entries[] | "\(.key) \(.value)"' <<<"$expected")
[ "$occupied" = "0" ] || die "expected-set addresses are occupied"
echo "ok  $(jq length <<<"$expected") expected addresses are empty (factory $(jq -r .Create3Factory <<<"$expected"))"

echo "FACTORY_NONCE=$FACTORY_NONCE"
echo "=== Preflight passed ==="
