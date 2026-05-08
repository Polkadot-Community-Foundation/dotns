#!/bin/bash
set -euo pipefail

BIN_DIR="$(pwd)/bin"

# Local-development test keys. NEITHER OF THESE IS A REAL CREDENTIAL.
# Both are checked into source so a fresh clone can run `forge test` and
# `bun run deploy:anvil` / `bun run deploy:testnet` (paseo testnet only)
# without any out-of-band setup. They MUST NOT be used on any production
# chain or hold funds beyond throwaway testnet balances.
#
# REVIVE_PK / REVIVE_ADDRESS — deterministic test wallet for the revive
# eth-rpc adapter pointed at paseo-assethub. Address is referenced in
# `package.json` as the deployer for `deploy:testnet`. Anyone with this
# private key can sign as that address on paseo, which is fine for
# testnet ergonomics but means the address must never be granted any
# privileged role (mainnet owner, governance signer, multisig member).
REVIVE_PK="5fb92d6e98884f76de468fa3f6278f8807c48bebc13595d45af5bdc4da702133"
REVIVE_ADDRESS="0xf24FF3a9CF04c71Dbc94D0b566f7A27B94566cac"

# ANVIL — well-known anvil-default account #0; same value foundry's
# `anvil` ships with by default. Used by `bun run deploy:anvil`.
ANVIL="0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"
ANVIL_ADDRESS="0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"

# Foundry keystore password for the dev wallets imported below. Local
# keystores on the dev machine; never reused for any non-test wallet.
WALLET_PASSWORD="123456"

# External Solidity dependencies pinned by commit SHA. Tags can be
# moved on the upstream repo; commit SHAs cannot. The `tag` column is
# advisory (used in install logs) and the `sha` column is what the
# checkout actually lands on. Refresh by running `git ls-remote <url>`
# and pasting the dereferenced commit (use the `^{}` line for annotated
# tags so we record the underlying commit, not the tag object).
# Format: name|tag|sha|url
SUBMODULES=(
  "forge-std|v1.12.0|7117c90c8cf6c68e5acce4f09a6b24715cea4de6|https://github.com/foundry-rs/forge-std.git"
  "openzeppelin-contracts|v5.5.0|fcbae5394ae8ad52d8e580a3477db99814b9d565|https://github.com/OpenZeppelin/openzeppelin-contracts.git"
  "openzeppelin-contracts-upgradeable|v5.5.0|aa677e9d28ed78fc427ec47ba2baef2030c58e7c|https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable.git"
  "openzeppelin-foundry-upgrades|v0.4.0|cbce1e00305e943aa1661d43f41e5ac72c662b07|https://github.com/OpenZeppelin/openzeppelin-foundry-upgrades.git"
  "halmos-cheatcodes|main|6da4e692c357ba6d641a2e677a28298cac9f76ab|https://github.com/a16z/halmos-cheatcodes.git"
)

msg(){ printf "%s\n" "$*"; }

remove_dir_cross_platform() {
  local dir="$1"
  if [ -d "$dir" ]; then
    if command -v rm >/dev/null 2>&1; then
      rm -rf "$dir"
    else
      find "$dir" -delete 2>/dev/null || rmdir /s /q "$dir" 2>/dev/null || true
    fi
  fi
}

clone_and_checkout() {
  local name="$1"
  local tag="$2"
  local sha="$3"
  local url="$4"
  local target="lib/$name"

  echo "  → Processing $name..."

  remove_dir_cross_platform "$target"

  # Full clone + checkout-by-SHA. We cannot use `git clone --depth 1
  # --branch` here because the supply-chain pin is the commit hash, not
  # the tag name; a moved tag would silently land on a different
  # commit. Fetch everything once, hard-checkout the recorded SHA, then
  # verify HEAD matches before declaring success.
  git clone "$url" "$target"
  (
    cd "$target" || exit 1
    git fetch --tags origin
    if ! git cat-file -e "${sha}^{commit}" 2>/dev/null; then
      echo "  ✗ $name: pinned commit $sha not present in $url" >&2
      exit 1
    fi
    git checkout -f "$sha"
    git reset --hard "$sha"
    local actual
    actual=$(git rev-parse HEAD)
    if [ "$actual" != "$sha" ]; then
      echo "  ✗ $name: HEAD $actual does not match pinned $sha" >&2
      exit 1
    fi
  )

  echo "  ✓ $name@$tag installed (sha=$sha)"
}

init_submodules(){
  echo "Installing dependencies (forced clean install)..."

  mkdir -p lib

  local processed=""
  
  for entry in "${SUBMODULES[@]}"; do
    IFS='|' read -r name tag sha url <<< "$entry"

    if echo "$processed" | grep -q "^${name}\$"; then
      echo "  ⊘ Skipping duplicate: $name"
      continue
    fi

    clone_and_checkout "$name" "$tag" "$sha" "$url"
    processed="${processed}${name}"$'\n'
  done
}

apply_dependency_patches(){
  echo "Applying dependency patches..."
  bash scripts/shell/apply-oz-patches.sh
}

setup_wallet() {
  local wallet_name="$1"
  local private_key="$2"
  local address="$3"
  local keystore_dir="${FOUNDRY_KEYSTORES_DIR:-$HOME/.foundry/keystores}"
  local keystore_path="$keystore_dir/$wallet_name"

  if [ -f "$keystore_path" ]; then
    echo "  ℹ Wallet '$wallet_name' already exists (address: $address)"
    return 0
  fi

  cast wallet import "$wallet_name" --private-key "$private_key" --unsafe-password "$WALLET_PASSWORD"
  echo "  ✓ Wallet '$wallet_name' created (address: $address)"
}

setup_foundry_wallet(){
  echo "Setting up Foundry wallets..."

  if ! command -v cast >/dev/null 2>&1; then
    echo "WARNING: 'cast' command not found. Install Foundry: https://getfoundry.sh"
    return 0
  fi

  setup_wallet "revive" "$REVIVE_PK" "$REVIVE_ADDRESS"
  setup_wallet "anvil-polkadot" "$ANVIL" "$ANVIL_ADDRESS"
}

check_missing_files(){
  echo "Checking for missing source files..."
  
  if [ ! -f "contracts/utils/StringUtils.sol" ]; then
    echo "  ⚠ Missing: contracts/utils/StringUtils.sol"
    echo "  → You need to create this file or restore it from your repository"
  fi
}

init_submodules
apply_dependency_patches
setup_foundry_wallet
check_missing_files
echo "Setup complete!"