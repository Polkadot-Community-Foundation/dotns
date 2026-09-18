#!/usr/bin/env bash
#
# End-to-end production rehearsal on a local chopsticks fork of live Polkadot
# Asset Hub: preflight -> deployall -> handover -> verify -> sweep, with the
# cost read from the deployer's Substrate System.Account.
#
# Starts chopsticks and an eth-rpc container on the given ports, funds the
# deployer's fallback account through dev_setStorage, and tears both down on
# exit. Everything runs with DEPLOY_MODE=fork, so the D5 guard refuses any KMS
# key that is not a *-rehearsal key.
#
# Usage (from the repo root):
#   scripts/deploy/rehearse-fork.sh                      # fresh throwaway keystore key
#   DEPLOY_SIGNER=gcp GCP_KEY_NAME=contract-deployer-rehearsal ... scripts/deploy/rehearse-fork.sh
#
# Env vars:
#   CHOPSTICKS_PORT       Default 8110.
#   ETH_RPC_PORT          Default 8147.
#   ETH_RPC_CONTAINER     Default dotns-pipeline-ethrpc.
#   ETH_RPC_IMAGE         Default revive-eth-rpc:latest, built from ./dockerfile when absent.
#   CHOPSTICKS_VERSION    Default 1.5.1.
#   AH_ENDPOINTS          Space-separated wss endpoints of Polkadot Asset Hub.
#   FUND_DOT              Balance given to the deployer, default 40 (the production funding).
#   NEW_OWNER             Handover target, default a fixed dummy H160 with no code.
#   SWEEP_TO              Sweep target; default the first mapped H160 found on the fork.
#                         SKIP_SWEEP=1 skips the sweep.
#   WORK_DIR              Logs, config, cost summary, and (moved there on exit) the
#                         deployments/polkadot-rehearsal manifest and the broadcast
#                         files. Default a fresh temp dir.
#   ACCOUNT_NAME, ACCOUNT_PASSWORD, PRIVATE_KEY
#                         Keystore signer as in _account.sh. With none set, a fresh
#                         key is generated and its keystore removed on exit.

set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/../.." && pwd)"
cd "$repo"

export DEPLOY_MODE=fork
export DEPLOY_SIGNER="${DEPLOY_SIGNER:-keystore}"
# shellcheck source=scripts/deploy/_production.sh
. "$here/_production.sh"
guard_mode_key

CHOPSTICKS_PORT="${CHOPSTICKS_PORT:-8110}"
ETH_RPC_PORT="${ETH_RPC_PORT:-8147}"
ETH_RPC_CONTAINER="${ETH_RPC_CONTAINER:-dotns-pipeline-ethrpc}"
ETH_RPC_IMAGE="${ETH_RPC_IMAGE:-revive-eth-rpc:latest}"
CHOPSTICKS_VERSION="${CHOPSTICKS_VERSION:-1.5.1}"
AH_ENDPOINTS="${AH_ENDPOINTS:-wss://polkadot-asset-hub-rpc.polkadot.io wss://asset-hub-polkadot-rpc.n.dwellir.com}"
FUND_DOT="${FUND_DOT:-40}"
# keccak256("dotns-owner-rehearsal")[12..]: no key, no code.
NEW_OWNER="${NEW_OWNER:-0x$(cast keccak "dotns-owner-rehearsal" | cut -c27-66)}"
WORK_DIR="${WORK_DIR:-$(mktemp -d "${TMPDIR:-/tmp}/dotns-rehearsal.XXXXXX")}"
mkdir -p "$WORK_DIR"

for port in "$CHOPSTICKS_PORT" "$ETH_RPC_PORT"; do
  if (exec 3<>"/dev/tcp/127.0.0.1/$port") 2>/dev/null; then
    die "port $port is already in use"
  fi
done

export SUBSTRATE_RPC_URL="http://127.0.0.1:$CHOPSTICKS_PORT"
export RPC_URL="http://127.0.0.1:$ETH_RPC_PORT"
export ENV_FILE="$WORK_DIR/no.env"
# A fork manifest must never pass for the production one.
export DOTNS_TLD=dot DOTNS_RELEASE_TAG=0.8.0 DEPLOYMENT_NETWORK=polkadot-rehearsal
export NEW_OWNER

chopsticks_pid=""
created_keystore=""
cleanup() {
  # npx forks the chopsticks node process; stop the whole session.
  if [ -n "$chopsticks_pid" ]; then kill -- "-$chopsticks_pid" 2>/dev/null || true; fi
  docker rm -f "$ETH_RPC_CONTAINER" >/dev/null 2>&1 || true
  if [ -n "$created_keystore" ]; then rm -f "$created_keystore"; fi
  if [ -d "deployments/$DEPLOYMENT_NETWORK" ]; then
    rm -rf "$WORK_DIR/deployments"
    mv "deployments/$DEPLOYMENT_NETWORK" "$WORK_DIR/deployments"
  fi
  for d in broadcast/*/"$POLKADOT_AH_CHAIN_ID"; do
    [ -d "$d" ] || continue
    mkdir -p "$WORK_DIR/broadcast/$(basename "$(dirname "$d")")"
    mv "$d" "$WORK_DIR/broadcast/$(basename "$(dirname "$d")")/"
  done
  echo "Rehearsal artefacts: $WORK_DIR"
}
trap cleanup EXIT

# Fresh throwaway key for keystore rehearsals.
if [ "$DEPLOY_SIGNER" = "keystore" ] && [ -z "${ACCOUNT_NAME:-}" ]; then
  export ACCOUNT_NAME
  ACCOUNT_NAME="dotns-rehearsal-$(date +%s)"
  export ACCOUNT_PASSWORD="rehearsal"
  export PRIVATE_KEY
  PRIVATE_KEY=$(cast wallet new --json | jq -r '.[0].private_key')
  cast wallet import "$ACCOUNT_NAME" --private-key "$PRIVATE_KEY" \
    --unsafe-password "$ACCOUNT_PASSWORD" >/dev/null
  created_keystore="$HOME/.foundry/keystores/$ACCOUNT_NAME"
  unset PRIVATE_KEY
fi
if [ "$DEPLOY_SIGNER" = "gcp" ]; then
  : "${GCP_KEY_VERSION:=1}"
  export GCP_KEY_VERSION
  deployer=$(cast wallet address --gcp)
else
  deployer=$(cast wallet address --account "$ACCOUNT_NAME" --password "$ACCOUNT_PASSWORD")
fi
export DEPLOYER="$deployer"
# Factory and pipeline share the one key.
export FACTORY_ACCOUNT="${ACCOUNT_NAME:-}" FACTORY_PASSWORD="${ACCOUNT_PASSWORD:-}"
echo "deployer $DEPLOYER, new owner $NEW_OWNER, work dir $WORK_DIR"

# Earlier broadcasts for this chain id would pollute the tx count.
for d in broadcast/*/"$POLKADOT_AH_CHAIN_ID"; do
  [ -d "$d" ] || continue
  mkdir -p "$WORK_DIR/broadcast-earlier/$(basename "$(dirname "$d")")"
  mv "$d" "$WORK_DIR/broadcast-earlier/$(basename "$(dirname "$d")")/"
done
[ ! -e "deployments/$DEPLOYMENT_NETWORK" ] || die "deployments/$DEPLOYMENT_NETWORK exists; move it away first"

# --- chopsticks fork of live Polkadot Asset Hub ---
{
  echo "endpoint:"
  for e in $AH_ENDPOINTS; do echo "  - $e"; done
  echo "port: $CHOPSTICKS_PORT"
  echo "build-block-mode: Instant"
  echo "mock-signature-host: true"
  echo "runtime-log-level: 0"
} >"$WORK_DIR/chopsticks.yml"
setsid npx --yes "@acala-network/chopsticks@$CHOPSTICKS_VERSION" -c "$WORK_DIR/chopsticks.yml" \
  >"$WORK_DIR/chopsticks.log" 2>&1 &
chopsticks_pid=$!
for _ in $(seq 1 120); do
  if cast rpc --rpc-url "$SUBSTRATE_RPC_URL" chain_getHeader >/dev/null 2>&1; then break; fi
  kill -0 "$chopsticks_pid" 2>/dev/null || die "chopsticks exited, see $WORK_DIR/chopsticks.log"
  sleep 2
done
fork_head=$(cast rpc --rpc-url "$SUBSTRATE_RPC_URL" chain_getHeader | jq -r .number)
echo "chopsticks up on $CHOPSTICKS_PORT, fork head $((fork_head))"

# --- fund the deployer's fallback account ---
fund_planck=$(python3 -c "import sys; print(int(float(sys.argv[1]) * 10**10))" "$FUND_DOT")
python3 "$here/substrate.py" fund "$DEPLOYER" "$fund_planck" --rpc "$SUBSTRATE_RPC_URL"
# A new block so the eth view picks up the balance.
cast rpc --rpc-url "$SUBSTRATE_RPC_URL" dev_newBlock >/dev/null

# --- eth-rpc ---
if ! docker image inspect "$ETH_RPC_IMAGE" >/dev/null 2>&1; then
  if [ "$ETH_RPC_IMAGE" = "revive-eth-rpc:latest" ]; then
    docker build -t "$ETH_RPC_IMAGE" -f dockerfile . >"$WORK_DIR/eth-rpc-build.log" 2>&1
  else
    docker pull "$ETH_RPC_IMAGE" >/dev/null
  fi
fi
docker rm -f "$ETH_RPC_CONTAINER" >/dev/null 2>&1 || true
docker run -d --name "$ETH_RPC_CONTAINER" --network host "$ETH_RPC_IMAGE" \
  --node-rpc-url "ws://127.0.0.1:$CHOPSTICKS_PORT" --rpc-port "$ETH_RPC_PORT" --eth-pruning 1 >/dev/null
for _ in $(seq 1 60); do
  if cast chain-id --rpc-url "$RPC_URL" >/dev/null 2>&1; then break; fi
  sleep 2
done
echo "eth-rpc up on $ETH_RPC_PORT, chain id $(cast chain-id --rpc-url "$RPC_URL")"


balance() { substrate_free "$DEPLOYER"; }
b0=$(balance)
echo "funded $(planck_to_dot "$b0") DOT"

# --- 3. preflight ---
"$here/preflight.sh" 2>&1 | tee "$WORK_DIR/preflight.log"

# --- 4. deploy ---
"$here/deployall.sh" >"$WORK_DIR/deploy.log" 2>&1 || {
  tail -40 "$WORK_DIR/deploy.log" >&2
  die "deployall failed, see $WORK_DIR/deploy.log"
}
b1=$(balance)
deploy_txs=$(cat broadcast/*/"$POLKADOT_AH_CHAIN_ID"/run-latest.json | jq -s '[.[].receipts | length] | add')
echo "deploy: $deploy_txs txs, $(planck_to_dot "$((b0 - b1))") DOT"

# --- 5. handover ---
"$here/handover.sh" 2>&1 | tee "$WORK_DIR/handover.log"
b2=$(balance)
handover_txs=$(grep -c '^ok    ' "$WORK_DIR/handover.log" || true)

# --- 6. verify ---
"$here/verify-production.sh" >"$WORK_DIR/verify.log" 2>&1 || {
  tail -40 "$WORK_DIR/verify.log" >&2
  die "verification failed, see $WORK_DIR/verify.log"
}
tail -1 "$WORK_DIR/verify.log"

# --- 7. sweep ---
swept=0
b3=$b2
if [ "${SKIP_SWEEP:-0}" != "1" ]; then
  if [ -z "${SWEEP_TO:-}" ]; then
    # Revive.OriginalAccount prefix; the key suffix is the H160 (Identity hasher).
    prefix=0x735f040a5d490f1107ad9c56f5ca00d2c56ab6c1f203b345fe5879f819627723
    key=$(cast rpc --rpc-url "$SUBSTRATE_RPC_URL" state_getKeysPaged "$prefix" 1 | jq -r '.[0] // empty')
    [ -n "$key" ] || die "no mapped account found on the fork to sweep to"
    SWEEP_TO="0x${key:66:40}"
  fi
  export SWEEP_TO
  "$here/sweep.sh" 2>&1 | tee "$WORK_DIR/sweep.log"
  swept=$(sed -n 's/^SWEPT_PLANCK=//p' "$WORK_DIR/sweep.log")
  b3=$(balance)
fi

{
  echo "| Step | txs | DOT |"
  echo "|---|---:|---:|"
  echo "| Deploy (factory + 5 stages) | $deploy_txs | $(planck_to_dot "$((b0 - b1))") |"
  echo "| Handover | $handover_txs | $(planck_to_dot "$((b1 - b2))") |"
  echo "| Deploy + handover | $((deploy_txs + handover_txs)) | $(planck_to_dot "$((b0 - b2))") |"
  echo "| Sweep fee | $([ "$swept" = 0 ] && echo 0 || echo 1) | $(planck_to_dot "$((b2 - b3 - swept))") |"
  echo ""
  echo "Funded $(planck_to_dot "$b0") DOT, swept $(planck_to_dot "$swept") DOT, left $(planck_to_dot "$b3") DOT."
  echo "Fork head $((fork_head)), deployer $DEPLOYER, new owner $NEW_OWNER."
} | tee "$WORK_DIR/cost.md"
echo "=== Rehearsal passed ==="
