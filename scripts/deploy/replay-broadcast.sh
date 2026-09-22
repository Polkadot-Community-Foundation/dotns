#!/usr/bin/env bash
#
# Replays the unsent transactions of a forge broadcast file, one by one, with
# the nonce, target, value and calldata recorded there, and confirms each on
# Substrate. The gas limit is estimated at send time (eth_estimateGas times
# REPLAY_GAS_MULTIPLIER percent), as forge does for a transaction whose gas is
# not fixed: the file's `gas` is the EVM simulation's figure, and on revive the
# real limit (weight plus storage deposit) is several times larger. Recovery for a stage that died with transactions unsent
# (an ETH-RPC that returned null receipts, a job that was killed): forge's own
# `--resume` needs receipts the adapter may never serve for blocks before it
# started, this needs only the sender's nonce and the blocks.
#
# For every transaction of the file, in file order:
#   - with a receipt in the file: confirmed, skipped;
#   - recorded nonce below the sender's Substrate nonce: it must have landed as
#     ours. The block that consumed the nonce is searched for the sender's
#     Revive.eth_transact with that nonce (substrate.py locate): its hash must
#     be the recorded one, or, for a transaction forge never sent, its target,
#     value and calldata must be the recorded ones. A CREATE3 deploy call must
#     also have left code at its target (derived from the salt as in
#     expected-set.sh), a CREATE at its contract address. Anything else
#     consumed the nonce: refused;
#   - recorded nonce equal to the sender's nonce: sent with `cast send --async
#     --nonce N`, then the Substrate nonce is polled until it passes N
#     (REPLAY_INCLUSION_SECONDS). Success: the ETH-RPC receipt when it serves one
#     (REPLAY_RECEIPT_SECONDS), else the extrinsic located by nonce (hash must
#     match) plus code at the target for a deploy. A reverted transaction stops
#     the replay;
#   - recorded nonce above the sender's nonce: a gap, refused.
# A transaction is never sent twice: the nonce is pinned, and a nonce that
# moved on is verified, not resent.
#
# The mode/key/chain guard runs before the signer is touched (keystore in
# devnet and fork, KMS in devnet and live, as in _production.sh).
#
# Usage:
#   DEPLOY_MODE=... SUBSTRATE_RPC_URL=... RPC_URL=... [signer vars] \
#     scripts/deploy/replay-broadcast.sh broadcast/DeployCore.s.sol/<chain id>/run-latest.json
#
# Env vars:
#   REPLAY_DRY_RUN            1 prints the plan (landed / to send / refused) and sends nothing.
#   REPLAY_GAS_MULTIPLIER     Percent applied to the gas estimate, default 130 (forge's default).
#   REPLAY_INCLUSION_SECONDS  Longest wait for the nonce to pass after a send, default 180.
#   REPLAY_RECEIPT_SECONDS    Longest wait for the ETH-RPC receipt after inclusion, default 60.
#   REPLAY_LOOKBACK_BLOCKS    Blocks below head searched for a transaction that landed
#                             before this run, default 100000.
#   Signer vars as in _account.sh; DEPLOY_MODE, SUBSTRATE_RPC_URL, RPC_URL as in _production.sh.

set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/deploy/_production.sh
. "$here/_production.sh"

[ $# -eq 1 ] || die "usage: $0 <run-latest.json>"
file="$1"
[ -f "$file" ] || die "no such file: $file"
jq -e '.transactions | type == "array"' "$file" >/dev/null 2>&1 || die "$file is not a forge broadcast file"

guard_chain_key
# shellcheck source=scripts/deploy/_account.sh
. "$here/_account.sh"

REPLAY_DRY_RUN="${REPLAY_DRY_RUN:-0}"
REPLAY_INCLUSION_SECONDS="${REPLAY_INCLUSION_SECONDS:-180}"
REPLAY_RECEIPT_SECONDS="${REPLAY_RECEIPT_SECONDS:-60}"
REPLAY_LOOKBACK_BLOCKS="${REPLAY_LOOKBACK_BLOCKS:-100000}"
REPLAY_GAS_MULTIPLIER="${REPLAY_GAS_MULTIPLIER:-130}"

file_chain=$(jq -r '.chain' "$file")
[ "$file_chain" = "$CHAIN_ID" ] || die "$file is for chain $file_chain, the RPC serves $CHAIN_ID"

# Solady CREATE3 (lib/solady/src/utils/CREATE3.sol), as in expected-set.sh.
PROXY_INITCODE_HASH=0x21c35dbe1b344a2488cf3321d6ce542f8e9f305544ff09e4993a62319a497c1f
DEPLOY_SELECTOR=$(cast sig 'deploy(bytes32,bytes)')

# The contract a transaction leaves behind: a CREATE's contract address, or the
# CREATE3 target of a factory deploy(bytes32,bytes) call (salt = first argument).
# Empty for every other call.
target_of() {
  local type="$1" to="$2" input="$3" contract="$4" salt proxy
  if [ "$type" = "CREATE" ]; then
    printf '%s' "$contract"
    return
  fi
  [ "${input:0:10}" = "$DEPLOY_SELECTOR" ] && [ "${#input}" -ge 74 ] || return 0
  salt="0x${input:10:64}"
  proxy=$(cast create2 --deployer "$to" --salt "$salt" --init-code-hash "$PROXY_INITCODE_HASH" | awk '{print $NF}')
  cast compute-address --nonce 1 "$proxy" | awk '{print $NF}'
}

sub_nonce() {
  substrate_account "$SENDER" | jq -r .nonce
}

sub_head() {
  cast rpc --rpc-url "$SUBSTRATE_RPC_URL" chain_getHeader | jq -r '.number' | xargs printf '%d\n'
}

# substrate.py locate; prints the JSON on success. Return 2: the nonce was
# consumed by something that is not the sender's eth transaction. Return 3: not
# locatable (too old, or state unavailable).
locate() {
  local nonce="$1" from="${2:-}"
  local args=(locate "$SENDER" "$nonce" --rpc "$SUBSTRATE_RPC_URL")
  if [ -n "$from" ]; then args+=(--from "$from"); else args+=(--lookback "$REPLAY_LOOKBACK_BLOCKS"); fi
  python3 "$here/substrate.py" "${args[@]}"
}

# eth_getTransactionReceipt status ("0x1"/"0x0"), empty when the adapter has none.
receipt_status() {
  cast rpc --rpc-url "$RPC_URL" eth_getTransactionReceipt "$1" 2>/dev/null | jq -r '.status // empty' || true
}

# Checks a located extrinsic against the record: the hash when forge recorded
# one, else target, value and calldata.
located_matches() {
  local located="$1" hash="$2" to="$3" value="$4" input="$5" l_hash l_to l_value l_input
  l_hash=$(jq -r .tx_hash <<<"$located")
  if [ -n "$hash" ]; then
    [ "$l_hash" = "$(lc "$hash")" ]
    return
  fi
  l_to=$(jq -r .to <<<"$located")
  l_value=$(jq -r .value <<<"$located")
  l_input=$(jq -r .input <<<"$located")
  [ "$l_to" = "$(lc "$to")" ] && [ "$((l_value))" = "$((value))" ] && [ "$l_input" = "$(lc "$input")" ]
}

# Landed-as-ours verification for a consumed nonce. Prints the verdict line.
# Dies on anything that is not the recorded transaction.
verify_landed() {
  local i="$1" nonce="$2" hash="$3" to="$4" value="$5" input="$6" target="$7" from_block="${8:-}"
  local located rc=0 block="" where="" code
  located=$(locate "$nonce" "$from_block") || rc=$?
  case "$rc" in
    0)
      located_matches "$located" "$hash" "$to" "$value" "$input" \
        || die "tx[$i] nonce $nonce: block $(jq -r .block <<<"$located") carries $(jq -r .tx_hash <<<"$located") from the sender at that nonce, not the recorded transaction; refusing"
      block=$(jq -r .block <<<"$located")
      where="block $block, extrinsic $(jq -r .extrinsic_index <<<"$located"), tx $(jq -r .tx_hash <<<"$located")"
      ;;
    2) die "tx[$i] nonce $nonce was consumed by something that is not the sender's eth transaction; refusing" ;;
    *)
      # Too old to locate: only a contract left at the target can prove the transaction.
      [ -n "$target" ] \
        || die "tx[$i] nonce $nonce is consumed but could not be located on $SUBSTRATE_RPC_URL (REPLAY_LOOKBACK_BLOCKS=$REPLAY_LOOKBACK_BLOCKS) and leaves no contract to check; refusing"
      where="not located (before the search window)"
      ;;
  esac
  if [ -n "$target" ]; then
    code=$(cast code "$target" --rpc-url "$RPC_URL") || die "could not read code at $target"
    [ "$code" != "0x" ] \
      || die "tx[$i] nonce $nonce is consumed ($where) but its target $target holds no code: the deploy reverted or is not ours; refusing"
    echo "landed   tx[$i] nonce $nonce -> $target has code ($where)"
  else
    # A plain call that landed: its success is not provable from the code alone; the
    # stage re-run repeats every such call (they are idempotent), so it is not resent.
    echo "landed   tx[$i] nonce $nonce call to $to ($where)"
  fi
}

# Gas limit for a transaction: the RPC's estimate times the multiplier. An
# estimate that fails means the call would revert: nothing is sent.
gas_limit_for() {
  local type="$1" to="$2" value="$3" input="$4" estimate
  local args=(estimate --rpc-url "$RPC_URL" --from "$SENDER")
  [ "$value" = "0" ] || args+=(--value "$value")
  if [ "$type" = "CREATE" ]; then args+=(--create "$input"); else args+=("$to" "$input"); fi
  estimate=$(cast "${args[@]}") || return 1
  [[ "$estimate" =~ ^[0-9]+$ ]] || return 1
  echo $((estimate * REPLAY_GAS_MULTIPLIER / 100))
}

# Sends tx[i] at its recorded nonce and confirms it. Dies on revert or timeout.
send_and_confirm() {
  local i="$1" nonce="$2" type="$3" to="$4" value="$5" input="$6" target="$7"
  local head_before out hash waited=0 delay=2 now status located gas
  gas=$(gas_limit_for "$type" "$to" "$value" "$input") \
    || die "tx[$i] nonce $nonce: gas estimate failed (the call reverts in simulation); nothing sent"
  head_before=$(sub_head)
  local args=(send --rpc-url "$RPC_URL" --async --legacy --nonce "$nonce" --gas-limit "$gas" "${CAST_SIGNER_ARGS[@]}")
  [ "$value" = "0" ] || args+=(--value "$value")
  if [ "$type" = "CREATE" ]; then
    args+=(--create "$input")
  else
    args+=("$to" --data "$input")
  fi
  out=$(cast "${args[@]}") || die "tx[$i] nonce $nonce: cast send failed"
  hash=$(grep -oE '0x[0-9a-fA-F]{64}' <<<"$out" | head -1 | tr 'A-F' 'a-f')
  [ -n "$hash" ] || die "tx[$i] nonce $nonce: cast send printed no transaction hash: $out"
  echo "sent     tx[$i] nonce $nonce tx $hash (gas $gas); waiting for the Substrate nonce to pass $nonce"
  # Inclusion: the Substrate nonce, never the receipt (the adapter may have none).
  while [ "$(sub_nonce)" -le "$nonce" ]; do
    [ "$waited" -lt "$REPLAY_INCLUSION_SECONDS" ] \
      || die "tx[$i] nonce $nonce ($hash) not included within ${REPLAY_INCLUSION_SECONDS}s; it may still be in the pool: check the nonce before running again"
    sleep "$delay"
    waited=$((waited + delay))
    [ "$delay" -ge 10 ] || delay=$((delay + 2))
  done
  # Success: the receipt when the adapter serves one.
  waited=0
  status=""
  while status=$(receipt_status "$hash") && [ -z "$status" ] && [ "$waited" -lt "$REPLAY_RECEIPT_SECONDS" ]; do
    sleep 3
    waited=$((waited + 3))
  done
  case "$status" in
    0x1) ;;
    0x0) die "tx[$i] nonce $nonce ($hash) REVERTED (receipt status 0); stopping the replay" ;;
    "") echo "         no receipt from $RPC_URL after ${waited}s; confirming on Substrate" ;;
    *) die "tx[$i] nonce $nonce ($hash): unexpected receipt status $status" ;;
  esac
  located=$(locate "$nonce" "$head_before") || die "tx[$i] nonce $nonce ($hash): the nonce passed but the transaction was not found in the blocks since $head_before"
  [ "$(jq -r .tx_hash <<<"$located")" = "$hash" ] \
    || die "tx[$i] nonce $nonce: block $(jq -r .block <<<"$located") carries $(jq -r .tx_hash <<<"$located") at that nonce, not $hash"
  if [ -n "$target" ]; then
    now=$(cast code "$target" --rpc-url "$RPC_URL") || die "could not read code at $target"
    [ "$now" != "0x" ] || die "tx[$i] nonce $nonce ($hash) landed in block $(jq -r .block <<<"$located") but left no code at $target: reverted; stopping the replay"
  elif [ -z "$status" ]; then
    echo "         success not provable without a receipt; the stage re-run repeats this call"
  fi
  echo "ok       tx[$i] nonce $nonce block $(jq -r .block <<<"$located")${status:+ status $status}${target:+ -> $target}"
}

echo "=== Replay $file ($DEPLOY_MODE, signer ${DEPLOY_SIGNER:-keystore}$([ "$REPLAY_DRY_RUN" = "1" ] && echo ", dry run")) ==="
echo "sender  $SENDER, chain $CHAIN_ID"
total=$(jq '.transactions | length' "$file")
with_receipt=$(jq '.receipts | length' "$file")
echo "file    $total transaction(s), $with_receipt with a receipt"

sent=0 landed=0 confirmed=0 pending=0
while IFS=$'\t' read -r i hash nonce_hex from to value_hex type contract has_receipt; do
  # "-" stands for an absent field (tabs around an empty field collapse in read).
  [ "$hash" != "-" ] || hash=""
  [ "$to" != "-" ] || to=""
  [ "$contract" != "-" ] || contract=""
  for v in "$nonce_hex" "$value_hex"; do
    [[ "$v" =~ ^0x[0-9a-fA-F]+$ ]] || die "tx[$i]: nonce and value must be hex quantities in the file (got '$v')"
  done
  nonce=$((nonce_hex))
  value=$((value_hex))
  input=$(jq -r --argjson i "$i" '.transactions[$i].transaction.input // ""' "$file")
  same_address "$from" "$SENDER" || die "tx[$i] nonce $nonce is from $from, the signer is $SENDER; refusing"
  [ -n "$input" ] || die "tx[$i] nonce $nonce has no input"
  if [ "$type" != "CREATE" ] && [ -z "$to" ]; then die "tx[$i] nonce $nonce is a $type without a target"; fi
  target=$(target_of "$type" "$to" "$input" "$contract")
  if [ "$has_receipt" = "true" ]; then
    echo "confirmed tx[$i] nonce $nonce (receipt in file)${target:+ -> $target}"
    confirmed=$((confirmed + 1))
    continue
  fi
  chain_nonce=$(sub_nonce)
  # A dry run counts the sends it would have made.
  [ "$REPLAY_DRY_RUN" != "1" ] || chain_nonce=$((chain_nonce + pending))
  if [ "$chain_nonce" -gt "$nonce" ]; then
    verify_landed "$i" "$nonce" "$hash" "$to" "$value" "$input" "$target"
    landed=$((landed + 1))
  elif [ "$chain_nonce" -eq "$nonce" ]; then
    [ -z "$hash" ] || echo "         tx[$i] nonce $nonce was sent as $hash but never included; sending again at the same nonce"
    if [ "$REPLAY_DRY_RUN" = "1" ]; then
      echo "to send  tx[$i] nonce $nonce -> $([ "$type" = "CREATE" ] && echo "CREATE" || echo "$to") value $value${target:+ (target $target)}"
      pending=$((pending + 1))
      continue
    fi
    send_and_confirm "$i" "$nonce" "$type" "$to" "$value" "$input" "$target"
    sent=$((sent + 1))
  else
    die "tx[$i] nonce $nonce is above the sender's nonce $chain_nonce: a transaction before it is missing; refusing"
  fi
done < <(
  jq -r '
    (.receipts // [] | map(.transactionHash | ascii_downcase)) as $r
    | .transactions | to_entries[]
    | [
        .key,
        (.value.hash // "-"),
        (.value.transaction.nonce // "-"),
        (.value.transaction.from // "-"),
        (.value.transaction.to // "-"),
        (.value.transaction.value // "0x0"),
        (.value.transactionType // "-"),
        (.value.contractAddress // "-"),
        ((.value.hash // "" | ascii_downcase) as $h | ($h != "" and ($r | index($h)) != null))
      ] | @tsv
  ' "$file"
)

if [ "$REPLAY_DRY_RUN" = "1" ]; then
  echo "=== Replay plan: $confirmed confirmed in file, $landed landed, $pending to send (nothing sent) ==="
else
  echo "=== Replay done: $confirmed confirmed in file, $landed landed before, $sent sent now (sender nonce $(sub_nonce)) ==="
fi
