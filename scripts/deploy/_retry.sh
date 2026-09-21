#!/usr/bin/env bash
#
# Stage-level retry for the deploy scripts. SOURCED, not executed; the caller
# runs `set -euo pipefail` first and has RPC_URL set.
#
# forge retries a single request only on HTTP 429/503, so one 502 or a
# restarting adapter aborts a whole `forge script` stage. Every stage is
# idempotent (an occupied CREATE3 address is adopted when its code matches,
# the wiring setters return early or overwrite with the same value), so the
# recovery is to re-run the stage once the RPC answers again.
#
# Env vars:
#   DEPLOY_STAGE_ATTEMPTS      Attempts per stage, default 3.
#   DEPLOY_RPC_WAIT_SECONDS    Longest wait for the RPC to answer eth_chainId
#                              again before an attempt, default 600.
#   DEPLOY_STAGE_SETTLE_SECONDS  Extra wait once the RPC answers, default 12
#                              (two Asset Hub blocks), so a transaction that was
#                              in flight when the stage died has landed and the
#                              next attempt adopts it instead of resending it.

DEPLOY_STAGE_ATTEMPTS="${DEPLOY_STAGE_ATTEMPTS:-3}"
DEPLOY_RPC_WAIT_SECONDS="${DEPLOY_RPC_WAIT_SECONDS:-600}"
DEPLOY_STAGE_SETTLE_SECONDS="${DEPLOY_STAGE_SETTLE_SECONDS:-12}"
[[ "$DEPLOY_STAGE_ATTEMPTS" =~ ^[1-9][0-9]*$ ]] \
  || { echo "DEPLOY_STAGE_ATTEMPTS must be a positive integer (got '$DEPLOY_STAGE_ATTEMPTS')" >&2; exit 1; }

# Backoff before attempt N+1: 10 s after the first failure, 30 s after every later one.
stage_backoff_seconds() {
  if [ "$1" -le 1 ]; then echo 10; else echo 30; fi
}

# Polls eth_chainId until the RPC answers, bounded by DEPLOY_RPC_WAIT_SECONDS.
wait_for_rpc() {
  local waited=0
  until cast chain-id --rpc-url "$RPC_URL" >/dev/null 2>&1; do
    if [ "$waited" -ge "$DEPLOY_RPC_WAIT_SECONDS" ]; then
      echo "RPC $RPC_URL still not answering eth_chainId after ${waited}s" >&2
      return 1
    fi
    if [ "$waited" = "0" ]; then echo "waiting for $RPC_URL to answer eth_chainId ..." >&2; fi
    sleep 5
    waited=$((waited + 5))
  done
  [ "$waited" = "0" ] || echo "RPC answered again after ${waited}s" >&2
  sleep "$DEPLOY_STAGE_SETTLE_SECONDS"
}

# run_with_attempts <label> <on-failure command or ""> <command...>
# Runs <command> up to DEPLOY_STAGE_ATTEMPTS times. After a failed attempt the
# on-failure command runs (run.sh restores the manifest and decides whether a
# re-run is safe: a non-zero return stops the retries), then the backoff, then
# the RPC wait. Returns non-zero only after the last attempt failed.
run_with_attempts() {
  local label="$1" on_failure="$2" attempt delay made=0
  shift 2
  for ((attempt = 1; attempt <= DEPLOY_STAGE_ATTEMPTS; attempt++)); do
    made=$attempt
    echo "=== $label: attempt $attempt of $DEPLOY_STAGE_ATTEMPTS ==="
    if "$@"; then
      return 0
    fi
    echo "$label: attempt $attempt of $DEPLOY_STAGE_ATTEMPTS failed" >&2
    if [ -n "$on_failure" ] && ! "$on_failure"; then
      echo "$label: not retrying" >&2
      return 1
    fi
    if [ "$attempt" -lt "$DEPLOY_STAGE_ATTEMPTS" ]; then
      delay=$(stage_backoff_seconds "$attempt")
      echo "$label: retrying in ${delay}s" >&2
      sleep "$delay"
      wait_for_rpc || break
    fi
  done
  echo "$label: giving up after $made attempt(s)" >&2
  return 1
}
