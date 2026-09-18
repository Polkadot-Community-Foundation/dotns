#!/usr/bin/env bash
#
# Prints the address set a fresh deploy lands for a given deployer, without a
# chain. The factory is the deployer's nonce-0 CREATE; every CREATE3 address is
# Solady's (CREATE2 proxy from the factory, then that proxy's nonce-1 CREATE)
# over the BaseDeployer salt; the beacons are CREATEs of the StoreFactory proxy
# at nonces 2 and 4 (StoreFactory.initialize deploys LabelStore, its beacon,
# UserStore, its beacon, in that order).
#
# Usage:
#   scripts/deploy/expected-set.sh <deployer H160>
#   scripts/deploy/expected-set.sh --factory <factory H160>
#
# Honours DOTNS_SALT_VERSION like BaseDeployer._create3Salt. Output has the
# shape of deployments/expected.json (sorted keys, checksummed addresses).

set -euo pipefail
export FOUNDRY_DISABLE_NIGHTLY_WARNING=1

usage() {
  echo "usage: $0 <deployer H160> | --factory <factory H160>" >&2
  exit 2
}

[ $# -ge 1 ] || usage
if [ "$1" = "--factory" ]; then
  [ $# -eq 2 ] || usage
  factory=$(cast to-check-sum-address "$2")
else
  [ $# -eq 1 ] || usage
  factory=$(cast compute-address --nonce 0 "$1" | awk '{print $NF}')
fi

# Solady CREATE3 proxy init code hash (lib/solady/src/utils/CREATE3.sol).
PROXY_INITCODE_HASH=0x21c35dbe1b344a2488cf3321d6ce542f8e9f305544ff09e4993a62319a497c1f
NAMESPACE="dotns.create3.v1"
version="${DOTNS_SALT_VERSION:-1}"

create3() {
  local preimage="$NAMESPACE:$1:$2" salt proxy
  if [ "$version" != "1" ]; then
    preimage="$preimage:$version"
  fi
  salt=$(cast keccak "$preimage")
  proxy=$(cast create2 --deployer "$factory" --salt "$salt" \
    --init-code-hash "$PROXY_INITCODE_HASH" | awk '{print $NF}')
  cast compute-address --nonce 1 "$proxy" | awk '{print $NF}'
}

proxies=(
  DotnsContentResolver DotnsNameEscrow DotnsNameWhitelist DotnsPopController
  DotnsPopResolver DotnsProtocolRegistry DotnsRegistrar DotnsRegistrarController
  DotnsRegistry DotnsResolver DotnsReverseResolver PopRules StoreFactory
)
contracts=(DotnsCostModelRegistry DotnsFlatPricing DotnsPopLens Multicall3)

{
  echo "Create3Factory $factory"
  for n in "${proxies[@]}"; do echo "$n $(create3 "$n" proxy)"; done
  for n in "${contracts[@]}"; do echo "$n $(create3 "$n" contract)"; done
  store_factory=$(create3 StoreFactory proxy)
  echo "LabelStoreBeacon $(cast compute-address --nonce 2 "$store_factory" | awk '{print $NF}')"
  echo "UserStoreBeacon $(cast compute-address --nonce 4 "$store_factory" | awk '{print $NF}')"
} | jq -R -n -S '[inputs | split(" ") | {(.[0]): .[1]}] | add'
