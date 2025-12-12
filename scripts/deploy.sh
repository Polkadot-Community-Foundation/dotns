#!/usr/bin/env bash
set -euo pipefail

RPC_URL="${RPC_URL:-https://testnet-passet-hub-eth-rpc.polkadot.io}"
ACCOUNT="${ACCOUNT:-revive}"
PASSWORD="${PASSWORD:-123456}"

CHAIN_ID=$(cast chain-id --rpc-url "$RPC_URL")
DEPLOY_DIR="deployments/${CHAIN_ID}"
CHAIN_FILE="${DEPLOY_DIR}/${CHAIN_ID}.json"
LOG_FILE="${DEPLOY_DIR}/deploy-$(date +'%Y%m%d-%H%M%S').log"
LAST_ADDR_FILE="${DEPLOY_DIR}/.last_address"

mkdir -p "$DEPLOY_DIR"
echo "{}" > "$CHAIN_FILE"
: > "$LAST_ADDR_FILE"

SENDER=$(cast wallet address --account "$ACCOUNT" --password "$PASSWORD")

log() { echo "[$(date +'%H:%M:%S')] $1" | tee -a "$LOG_FILE"; }

append_json() {
  local n=$1 a=$2
  local tmp
  tmp="$(mktemp)"
  jq --arg n "$n" --arg a "$a" '. + {($n): $a}' "$CHAIN_FILE" > "$tmp" && mv "$tmp" "$CHAIN_FILE"
}

to_lower() {
  echo "$1" | tr '[:upper:]' '[:lower:]'
}

deploy() {
  local path=$1 name=$2
  shift 2
  local args=("$@")
  echo "--------------------------------------------" | tee -a "$LOG_FILE"
  log "[⏳] Deploying ${name}..."
  [[ ${#args[@]} -gt 0 ]] && log "Args: ${args[*]}" || log "No args"

  local cmd=("forge" "create" "${path}:${name}" "--account" "$ACCOUNT" "--password" "$PASSWORD" "--rpc-url" "$RPC_URL" "--broadcast")
  if [[ ${#args[@]} -gt 0 ]]; then
    cmd+=("--constructor-args")
    cmd+=("${args[@]}")
  fi
  log "[⚙️] ${cmd[*]}"

  if ! "${cmd[@]}" 2>&1 | tee -a "$LOG_FILE"; then
    log "[❌] ${name} failed"
    exit 1
  fi

  local addr
  addr=$(grep -oE 'Deployed to: 0x[a-fA-F0-9]{40}' "$LOG_FILE" | tail -1 | awk '{print $3}')
  if [[ -z "$addr" ]]; then
    log "[❌] ${name} produced no address"
    exit 1
  fi

  echo "$addr" > "$LAST_ADDR_FILE"
  append_json "$name" "$addr"
  log "[✅] ${name} at ${addr}"
}

tx() {
  local target=$1 func=$2
  shift 2
  local args=("$@")
  log "[🔗] TX: $target :: $func(${args[*]})"
  if ! cast send "$target" "$func" "${args[@]}" --account "$ACCOUNT" --password "$PASSWORD" --rpc-url "$RPC_URL" 2>&1 | tee -a "$LOG_FILE"; then
    log "[❌] TX failed: $func"
    exit 1
  fi
}

namehash() {
  local parent=$1 label=$2
  local encoded
  encoded=$(cast abi-encode "f(bytes32,bytes32)" "$parent" "$label")
  cast keccak "$encoded"
}

log "[🔨] Building contracts..."
forge build | tee -a "$LOG_FILE"
log "[✅] Build done."

ZERO_HASH="0x0000000000000000000000000000000000000000000000000000000000000000"
REV_LABEL=$(cast keccak "reverse")
ADDR_LABEL=$(cast keccak "addr")
DOT_LABEL=$(cast keccak "dot")

REV_NODE=$(namehash "$ZERO_HASH" "$REV_LABEL")
DOT_NODE=$(namehash "$ZERO_HASH" "$DOT_LABEL")

log "[📋] Labels and nodes:"
log "  reverse label: $REV_LABEL"
log "  reverse node:  $REV_NODE"
log "  addr label:    $ADDR_LABEL"
log "  dot label:     $DOT_LABEL"
log "  dot node:      $DOT_NODE"

echo "============================================" | tee -a "$LOG_FILE"
log "[🏗️] Deploying core ENS infrastructure..."

deploy "contracts/registry/ENSRegistry.sol" "ENSRegistry"
ENSRegistry=$(cat "$LAST_ADDR_FILE")

deploy "contracts/root/Root.sol" "Root" "$ENSRegistry"
Root=$(cat "$LAST_ADDR_FILE")

tx "$ENSRegistry" "setOwner(bytes32,address)" "$ZERO_HASH" "$Root"
tx "$Root" "setController(address,bool)" "$SENDER" true

deploy "contracts/reverseRegistrar/ReverseRegistrar.sol" "ReverseRegistrar" "$ENSRegistry"
ReverseRegistrar=$(cat "$LAST_ADDR_FILE")

tx "$Root" "setSubnodeOwner(bytes32,address)" "$REV_LABEL" "$SENDER"
tx "$ENSRegistry" "setSubnodeOwner(bytes32,bytes32,address)" "$REV_NODE" "$ADDR_LABEL" "$ReverseRegistrar"

deploy "contracts/ethregistrar/BaseRegistrarImplementation.sol" "BaseRegistrarImplementation" \
  "$ENSRegistry" "$DOT_NODE"
BaseRegistrarImplementation=$(cat "$LAST_ADDR_FILE")

tx "$Root" "setSubnodeOwner(bytes32,address)" "$DOT_LABEL" "$BaseRegistrarImplementation"

OWNER_OF_DOT=$(cast call "$ENSRegistry" "owner(bytes32)(address)" "$DOT_NODE" --rpc-url "$RPC_URL")
log "[🔎] Owner of .dot node: $OWNER_OF_DOT"

LOWER_DOT=$(to_lower "$OWNER_OF_DOT")
LOWER_BASE=$(to_lower "$BaseRegistrarImplementation")

if [ "$LOWER_DOT" != "$LOWER_BASE" ]; then
  log "[❌] CRITICAL: .dot not owned by BaseRegistrar"
  log "    Expected: $BaseRegistrarImplementation"
  log "    Got:      $OWNER_OF_DOT"
  exit 1
fi
log "[✅] .dot ownership verified"

echo "============================================" | tee -a "$LOG_FILE"
log "[💰] Deploying pricing and metadata..."

deploy "contracts/ethregistrar/DummyOracle.sol" "DummyOracle" 160000000000
DummyOracle=$(cat "$LAST_ADDR_FILE")

deploy "contracts/ethregistrar/StableOracle.sol" "StableOracle" \
  "$DummyOracle" "[0, 0, 3170979200, 1585489600, 317097920]"
StableOracle=$(cat "$LAST_ADDR_FILE")

deploy "contracts/wrapper/StaticMetadataService.sol" "StaticMetadataService" "http://localhost:8080/name/0x{id}"
StaticMetadataService=$(cat "$LAST_ADDR_FILE")

echo "============================================" | tee -a "$LOG_FILE"
log "[📦] Deploying NameWrapper and controllers..."

deploy "contracts/wrapper/NameWrapper.sol" "NameWrapper" "$ENSRegistry" "$BaseRegistrarImplementation" "$StaticMetadataService"
NameWrapper=$(cat "$LAST_ADDR_FILE")

tx "$BaseRegistrarImplementation" "addController(address)" "$NameWrapper"

deploy "contracts/reverseRegistrar/DefaultReverseRegistrar.sol" "DefaultReverseRegistrar"
DefaultReverseRegistrar=$(cat "$LAST_ADDR_FILE")

deploy "contracts/ethregistrar/ETHRegistrarController.sol" "ETHRegistrarController" \
  "$BaseRegistrarImplementation" "$StableOracle" 6 86400 "$ReverseRegistrar" "$DefaultReverseRegistrar" "$ENSRegistry"
ETHRegistrarController=$(cat "$LAST_ADDR_FILE")

tx "$StableOracle" "updateEthRegistry(address)" "$ETHRegistrarController"
tx "$BaseRegistrarImplementation" "addController(address)" "$ETHRegistrarController"
tx "$NameWrapper" "setController(address,bool)" "$ETHRegistrarController" true
tx "$ReverseRegistrar" "setController(address,bool)" "$ETHRegistrarController" true

echo "============================================" | tee -a "$LOG_FILE"
log "[🔧] Deploying additional contracts..."

deploy "contracts/ethregistrar/StaticBulkRenewal.sol" "StaticBulkRenewal" "$ETHRegistrarController"
StaticBulkRenewal=$(cat "$LAST_ADDR_FILE")

deploy "contracts/resolvers/PublicResolver.sol" "PublicResolver" "$ENSRegistry" "$NameWrapper" "$ETHRegistrarController" "$ReverseRegistrar"
PublicResolver=$(cat "$LAST_ADDR_FILE")

tx "$ReverseRegistrar" "setDefaultResolver(address)" "$PublicResolver"

deploy "contracts/ccipRead/GatewayProvider.sol" "GatewayProvider" "$SENDER" '["http://universal-offchain-resolver.local/"]'
GatewayProvider=$(cat "$LAST_ADDR_FILE")

deploy "contracts/universalResolver/UniversalResolver.sol" "UniversalResolver" "$SENDER" "$ENSRegistry" "$GatewayProvider"
UniversalResolver=$(cat "$LAST_ADDR_FILE")

tx "$ENSRegistry" "setApprovalForAll(address,bool)" "$ETHRegistrarController" true
tx "$BaseRegistrarImplementation" "setResolver(address)" "$PublicResolver"

echo "============================================" | tee -a "$LOG_FILE"
log "[🛠️] Deploying utilities..."

deploy "contracts/utils/StoreFactory.sol" "StoreFactory"
StoreFactory=$(cat "$LAST_ADDR_FILE")

deploy "contracts/utils/DotnsRegistrar.sol" "DotnsRegistrar" "$ETHRegistrarController" "$ENSRegistry" "$StoreFactory"
DotnsRegistrar=$(cat "$LAST_ADDR_FILE")

deploy "contracts/utils/Multicall3.sol" "Multicall3"
Multicall3=$(cat "$LAST_ADDR_FILE")

echo "============================================" | tee -a "$LOG_FILE"
log "[🔍] Running final verification..."

FINAL_DOT_OWNER=$(cast call "$ENSRegistry" "owner(bytes32)(address)" "$DOT_NODE" --rpc-url "$RPC_URL")
LOWER_FINAL=$(to_lower "$FINAL_DOT_OWNER")

if [ "$LOWER_FINAL" != "$LOWER_BASE" ]; then
  log "[❌] VERIFICATION FAILED: .dot TLD not owned by registrar"
  exit 1
fi

log "[✅] Verification passed: .dot TLD owned by BaseRegistrar"

echo "============================================" | tee -a "$LOG_FILE"
log "[🏁] Deployment script completed successfully."
exit 0
