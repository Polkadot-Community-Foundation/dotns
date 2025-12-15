#!/bin/bash
set -euo pipefail

RELEASE_REPO="paritytech/hardhat-polkadot"
BIN_DIR="$(pwd)/bin"
REVIVE_PK="5fb92d6e98884f76de468fa3f6278f8807c48bebc13595d45af5bdc4da702133"
REVIVE_ADDRESS="0xf24FF3a9CF04c71Dbc94D0b566f7A27B94566cac"
ANVIL="0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"
ANVIL_ADDRESS="0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"
WALLET_PASSWORD="123456"

REQUIRED_SUBMODULES=(
  "lib/openzeppelin-foundry-upgrades"
  "lib/openzeppelin-contracts-upgradeable"
  "lib/openzeppelin-contracts"
  "lib/forge-std"
)

msg(){ printf "%s\n" "$*"; }

init_submodules(){
  echo "Initializing git submodules..."
  if [ ! -d ".git" ]; then
    echo "  ⚠ Not a git repository, skipping submodules"
    return 0
  fi
  if ! command -v git >/dev/null 2>&1; then
    echo "  ⚠ Git not installed, skipping submodules"
    return 0
  fi
  echo "Syncing submodule configuration..."
  git submodule sync 2>/dev/null || true
  echo "Initializing required submodules..."
  for path in "${REQUIRED_SUBMODULES[@]}"; do
    if [ ! -d "$path" ]; then
      echo "  - Initializing $path"
      git submodule update --init "$path" || {
        echo "  ✗ Failed to initialize $path"
        exit 1
      }
    else
      echo "  ✓ $path already present"
    fi
  done
  echo "Initializing nested submodules..."
  git submodule update --init --recursive
  echo "Forcing OpenZeppelin v4.9.3..."
  if [ -d "lib/openzeppelin-contracts-upgradeable" ]; then
    echo "  - Fetching openzeppelin-contracts-upgradeable tags..."
    (cd lib/openzeppelin-contracts-upgradeable && git fetch --tags origin 2>/dev/null)
    echo "  - Checking out v4.9.3..."
    (cd lib/openzeppelin-contracts-upgradeable && git checkout -f v4.9.3 2>/dev/null) && \
      echo "  ✓ openzeppelin-contracts-upgradeable@v4.9.3" || \
      echo "  ⚠ Failed to checkout openzeppelin-contracts-upgradeable@v4.9.3"
  else
    echo "  ⚠ lib/openzeppelin-contracts-upgradeable not found"
  fi
  if [ -d "lib/openzeppelin-contracts" ]; then
    echo "  - Fetching openzeppelin-contracts tags..."
    (cd lib/openzeppelin-contracts && git fetch --tags origin 2>/dev/null)
    echo "  - Checking out v4.9.3..."
    (cd lib/openzeppelin-contracts && git checkout -f v4.9.3 2>/dev/null) && \
      echo "  ✓ openzeppelin-contracts@v4.9.3" || \
      echo "  ⚠ Failed to checkout openzeppelin-contracts@v4.9.3"
  else
    echo "  ⚠ lib/openzeppelin-contracts not found"
  fi
}

patch_openzeppelin_upgrades(){
  echo "Patching OpenZeppelin upgrades library..."
  local upgrades_file="lib/openzeppelin-foundry-upgrades/src/Upgrades.sol"
  local patch_file="$(pwd)/Upgrades.p.sol"
  if [ ! -f "$patch_file" ]; then
    echo "  ⚠ Patch file 'Upgrades.p.sol' not found, skipping patch"
    return 0
  fi
  if [ ! -f "$upgrades_file" ]; then
    echo "  ⚠ OpenZeppelin upgrades file not found, skipping patch"
    return 0
  fi
  if cmp -s "$patch_file" "$upgrades_file"; then
    echo "  ✓ OpenZeppelin upgrades already patched, skipping"
    return 0
  fi
  cp "$upgrades_file" "${upgrades_file}.backup"
  cp "$patch_file" "$upgrades_file"
  echo "  ✓ OpenZeppelin upgrades replaced with patched version"
}

check_binary_exists(){
  local link_name="$1"
  local binary_path="$BIN_DIR/$link_name"
  if [ -f "$binary_path" ] && [ -x "$binary_path" ]; then
    echo "  ✓ $link_name already installed, skipping download"
    return 0
  fi
  return 1
}

resolve_asset_url(){
  local want="$1"
  curl -fsSL "https://api.github.com/repos/${RELEASE_REPO}/releases?per_page=30" \
  | node -e '
    const fs=require("fs");
    const rels=JSON.parse(fs.readFileSync(0,"utf8"));
    const want=process.argv[1];
    for(const r of rels){
      const tag=(r.tag_name||"").toLowerCase();
      const name=(r.name||"").toLowerCase();
      if(tag.startsWith("nodes-")||name.includes("nodes build")){
        for(const a of r.assets||[]){
          if(a.name===want){ console.log(a.browser_download_url); process.exit(0); }
        }
      }
    }
    process.exit(1);
  ' "$want"
}

download_bin(){
  local asset="$1" link_name="$2"
  if check_binary_exists "$link_name"; then
    return 0
  fi
  local url out
  if ! url="$(resolve_asset_url "$asset")"; then
    msg "$asset not found in latest nodes-* releases"
    return 1
  fi
  out="$BIN_DIR/$asset"
  curl -fsSL --retry 3 --retry-delay 1 -o "$out" "$url"
  chmod +x "$out"
  ln -sfn "$out" "$BIN_DIR/$link_name"
  msg "  ✓ $link_name installed from $(basename "$url")"
}

setup_foundry_wallet(){
  echo "Setting up Foundry wallets..."
  if ! command -v cast >/dev/null 2>&1; then
    echo "WARNING: 'cast' command not found. Install Foundry: https://getfoundry.sh"
    return 0
  fi
  if cast wallet list 2>/dev/null | grep -q "revive"; then
    echo "  ✓ Wallet 'revive' already exists, skipping creation"
  else
    cast wallet import revive --private-key "$REVIVE_PK" --unsafe-password "$WALLET_PASSWORD" 2>/dev/null || true
    echo "  ✓ Wallet 'revive' created (address: $REVIVE_ADDRESS)"
  fi
  if cast wallet list 2>/dev/null | grep -q "anvil-polkadot"; then
    echo "  ✓ Wallet 'anvil-polkadot' already exists, skipping creation"
  else
    cast wallet import anvil-polkadot --private-key "$ANVIL" --unsafe-password "$WALLET_PASSWORD" 2>/dev/null || true
    echo "  ✓ Wallet 'anvil-polkadot' created (address: $ANVIL_ADDRESS)"
  fi
}

init_submodules
patch_openzeppelin_upgrades
setup_foundry_wallet
echo "Setup complete!"
