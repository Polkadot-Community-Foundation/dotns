#!/usr/bin/env bash
#
# Refuses a production deploy unless the chain, the key and the target
# addresses are exactly what a first deploy expects. Read-only.
#
# Checks: mode/key/chain guard (D5, D8); chain id 420420419 (420420417 for
# devnet); sender nonce 0 (eth and Substrate views); sender free balance >=
# MIN_BALANCE_DOT; NEW_OWNER set, not zero, not the sender, no code; no address
# of the expected set has code.
#
# Usage:
#   DEPLOY_MODE=fork|live|devnet NEW_OWNER=0x... SUBSTRATE_RPC_URL=... RPC_URL=... \
#     scripts/deploy/preflight.sh
#
# Env vars:
#   MIN_BALANCE_DOT    In the native token. Default 40 (33.3 spend + 2.64
#                      max-fee headroom at 8e11 wei + margin); devnet 50 (the
#                      same with every cost scaled to its 1e12 gas price).
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

[ "$CHAIN_ID" = "$(expected_chain_id)" ] \
  || die "chain id $CHAIN_ID, expected $(expected_chain_id) for mode=$DEPLOY_MODE"
echo "ok  chain id $CHAIN_ID"

eth_nonce=$(cast nonce "$SENDER" --rpc-url "$RPC_URL")
account=$(substrate_account "$SENDER")
sub_nonce=$(jq -r .nonce <<<"$account")
if [ "$eth_nonce" != "0" ] || [ "$sub_nonce" != "0" ]; then
  die "sender nonce is not 0 (eth $eth_nonce, substrate $sub_nonce): the factory must be its first transaction"
fi
echo "ok  sender nonce 0"

free=$(jq -r .free <<<"$account")
unit=$(native_unit)
if [ "$DEPLOY_MODE" = "devnet" ]; then min="${MIN_BALANCE_DOT:-50}"; else min="${MIN_BALANCE_DOT:-40}"; fi
min_planck=$(python3 -c "import sys; print(int(float(sys.argv[1]) * 10**10))" "$min")
python3 -c "import sys; sys.exit(int(sys.argv[1]) < int(sys.argv[2]))" "$free" "$min_planck" \
  || die "sender free balance $(planck_to_dot "$free") $unit < $min $unit"
echo "ok  sender free $(planck_to_dot "$free") $unit (fallback account $(jq -r .account_id <<<"$account"))"

! same_address "$NEW_OWNER" "$SENDER" || die "NEW_OWNER is the sender"
! has_code "$NEW_OWNER" || die "NEW_OWNER $NEW_OWNER has code; expected the dotns-owner pure's H160"
echo "ok  new owner has no code"

expected=$("$here/expected-set.sh" "$SENDER")
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

echo "=== Preflight passed ==="
