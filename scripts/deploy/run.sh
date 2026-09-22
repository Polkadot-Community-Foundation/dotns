#!/usr/bin/env bash
#
# Runs the multi-stage DotNS deploy pipeline against a Foundry keystore
# wallet. `.env` is a one-off bootstrap file: it carries PRIVATE_KEY and
# ACCOUNT_PASSWORD only long enough to import the wallet into the
# Foundry keystore on the first run, after which the file is deleted so
# no plaintext secrets persist on disk. Subsequent runs prompt for the
# keystore password interactively and rely on sensible defaults for
# everything else; nothing sensitive ever sits in a file between
# deploys. A failed run leaves `.env` exactly as it was for correction
# and retry.
#
# Local usage:
#   1. cp .env.example .env
#   2. set PRIVATE_KEY and ACCOUNT_PASSWORD in .env (and adjust
#      ACCOUNT_NAME or RPC_URL if the defaults are
#      not what you want)
#   3. bun run deploy   (or ./scripts/deploy/run.sh)
#   4. on success, the script deletes .env automatically
#   5. for every subsequent run, just `bun run deploy`; you will be
#      prompted for the keystore password
#
# CI / scripted usage (no `.env`):
#   PRIVATE_KEY=0x... ACCOUNT_PASSWORD=... ./scripts/deploy/run.sh '--slow'
#
# Each stage runs as its own `forge script` invocation (therefore its
# own EVM simulation), so OpenZeppelin's upgrade-safety validator's
# cumulative memory gas cannot spill across stages.
#
# Env vars (read from `.env` if present, otherwise from the shell):
#   ACCOUNT_NAME       Foundry keystore account passed to forge as --account.
#                      Defaults to `dotns-deploy`.
#   ACCOUNT_PASSWORD   Password passed to cast/forge as --password. Prompted
#                      interactively when not set.
#   PRIVATE_KEY        Hex-encoded deployer private key, with or without 0x.
#                      Required only when ACCOUNT_NAME has not yet been
#                      imported into the Foundry keystore.
#   RPC_URL            Foundry rpc alias (see [rpc_endpoints] in foundry.toml)
#                      or full https/wss URL. Defaults to `paseo_local`.
#   ENV_FILE           Path to env file. Defaults to `.env`.
#   DOTNS_TLD          Bare TLD label the protocol registry initialises with.
#                      Required; no default (see below).
#   DOTNS_RELEASE_TAG  Release the final stage declares on chain, bare semver.
#                      Defaults to the tag the checkout sits exactly on;
#                      required otherwise (see below).
#   DEPLOY_STAGE_ATTEMPTS
#                      Attempts per stage (default 3, see _retry.sh). A failed
#                      attempt restores the manifest, waits for the RPC and
#                      re-runs the stage, which adopts what already landed.
#   DEPLOY_RESUME      1 resumes an interrupted deploy: a stage whose contracts
#                      are all on chain runs without --broadcast (BaseDeployer
#                      adopts each address after checking its code, the manifest
#                      is written, nothing is sent) as long as the only calls it
#                      would send are protocol-registry `set`s, which
#                      WireDeployments repeats; otherwise it broadcasts as usual
#                      and sends only what is missing. Needs CREATE3_FACTORY.
#
# Extra forge flags are forwarded verbatim to every stage, e.g.
#   ./scripts/deploy/run.sh '--slow --timeout 1000'

set -euo pipefail

# Resolve the deployer keystore account, RPC alias, broadcasting address, and
# chain id (importing from a one-off .env on first run). Shared with the factory
# deploy so both use identical account handling.
# shellcheck source=scripts/deploy/_account.sh
. "$(dirname "$0")/_account.sh"
# Stage-level retry (DEPLOY_STAGE_ATTEMPTS, default 3).
# shellcheck source=scripts/deploy/_retry.sh
. "$(dirname "$0")/_retry.sh"

# Pipeline-only default; .env has already been loaded by _account.sh.

# TLD the protocol registry initialises with. DeployCore reads it through
# vm.envString("DOTNS_TLD"), so it has to be exported: sourcing .env does not
# auto-export, matching DEPLOYMENT_NETWORK below. No default is applied; a
# missing TLD must abort in the Solidity stage rather than silently land the
# wrong one, which no setter can correct afterwards.
if [ -n "${DOTNS_TLD:-}" ]; then
  export DOTNS_TLD
fi

# Release tag WireDeployments declares on the protocol registry, as bare semver
# ("0.8.0", no leading v). Resolution order: explicit DOTNS_RELEASE_TAG, else
# the tag the checkout sits exactly on. Real deploys happen from release tags,
# so a checkout that is not on one aborts here rather than landing a network
# that cannot say what it runs; the CI reproduction workflow sets an explicit
# 0.0.0 placeholder. A leading v is stripped rather than rejected because the
# git tag itself carries one.
if [ -z "${DOTNS_RELEASE_TAG:-}" ]; then
  DOTNS_RELEASE_TAG="$(git describe --tags --exact-match 2>/dev/null || true)"
fi
DOTNS_RELEASE_TAG="${DOTNS_RELEASE_TAG#v}"
if [ -z "$DOTNS_RELEASE_TAG" ]; then
  echo "run.sh: DOTNS_RELEASE_TAG is not set and HEAD is not exactly on a tag." >&2
  echo "        Deploys happen from release tags; check one out, or set DOTNS_RELEASE_TAG." >&2
  exit 1
fi
# Semver core plus optional pre-release identifiers: deploys run from pre-release
# tags (see RELEASE_ARTIFACTS.md), so 0.8.0-rc.1 must pass. Build metadata does
# not: consumers parse and compare the declared value.
if ! printf '%s' "$DOTNS_RELEASE_TAG" \
  | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?$'; then
  echo "run.sh: DOTNS_RELEASE_TAG '$DOTNS_RELEASE_TAG' is not semver (expected e.g. 0.8.0 or 0.8.0-rc.1)." >&2
  exit 1
fi
export DOTNS_RELEASE_TAG

# Forward every extra forge flag (word-split), not just the first token.
extra="$*"

if [ "${DOTNS_DEPLOY_SKIP_CLEAN_BUILD:-0}" != "1" ]; then
  echo "=== Rebuilding full Foundry artifacts for OpenZeppelin validation ==="
  forge clean
  forge build
fi

# Manifest subdirectory. Two chains can present the same chain id (for example
# a previewnet and a next environment both reached through the local ETH-RPC
# adapter); chain id alone then aliases their manifests onto one file, so a
# later deploy silently overwrites an earlier one. DEPLOYMENT_NETWORK names the
# subdirectory explicitly so each upstream keeps its own manifest. When unset,
# fall back to the chain-id default, which must match DeploymentNetwork.folder
# on the Solidity side. The variable is exported (only when set) so every forge
# stage resolves the same folder through BaseDeployer.networkFolder.
# PCF fork: DOTNS_DEPLOYMENT_FOLDER predates upstream's DEPLOYMENT_NETWORK and
# names the same subdirectory. Honour it as an alias so existing devnet deploy
# invocations keep working; DEPLOYMENT_NETWORK wins when both are set.
if [ -z "${DEPLOYMENT_NETWORK:-}" ] && [ -n "${DOTNS_DEPLOYMENT_FOLDER:-}" ]; then
  DEPLOYMENT_NETWORK="$DOTNS_DEPLOYMENT_FOLDER"
fi

if [ -n "${DEPLOYMENT_NETWORK:-}" ]; then
  DEPLOYMENT_FOLDER="$DEPLOYMENT_NETWORK"
  export DEPLOYMENT_NETWORK
else
  unset DEPLOYMENT_NETWORK
  case "$CHAIN_ID" in
    420420422) DEPLOYMENT_FOLDER="passethub-testnet" ;;
    420420417) DEPLOYMENT_FOLDER="pcf-devnet" ;;
    420420420) DEPLOYMENT_FOLDER="paseo-local" ;;
    *) DEPLOYMENT_FOLDER="localhost" ;;
  esac
fi

# Reuse a pre-deployed CREATE3 factory when its address is supplied. Every DotNS
# address derives from the factory address, and the factory's own address is
# nonce-derived, so a key that also runs upgrades cannot keep it stable across
# chain resets. Deploy the factory once from a single-purpose key at nonce 0
# (scripts/deploy/DeployCreate3Factory.s.sol) and export its address as
# CREATE3_FACTORY; DeployCore then reuses it instead of minting a new one, so
# the pipeline key's nonce no longer affects any address. Exported (only when
# set) so every forge stage resolves it through BaseDeployer.
if [ -n "${CREATE3_FACTORY:-}" ]; then
  export CREATE3_FACTORY
else
  unset CREATE3_FACTORY
fi

MANIFEST_PATH="deployments/$DEPLOYMENT_FOLDER/$CHAIN_ID.json"
mkdir -p "$(dirname "$MANIFEST_PATH")"

backup_manifest() {
  local backup
  backup=$(mktemp "${TMPDIR:-/tmp}/dotns-manifest.${CHAIN_ID}.XXXXXX")
  if [ -f "$MANIFEST_PATH" ]; then
    cp "$MANIFEST_PATH" "$backup"
    echo "$backup"
  else
    rm -f "$backup"
    echo ""
  fi
}

restore_manifest() {
  local backup="$1"
  if [ -n "$backup" ]; then
    cp "$backup" "$MANIFEST_PATH"
  else
    rm -f "$MANIFEST_PATH"
  fi
}

validate_manifest_contracts() {
  if [ ! -f "$MANIFEST_PATH" ]; then
    echo "Manifest missing after stage: $MANIFEST_PATH" >&2
    return 1
  fi

  local failed=0
  while read -r name addr; do
    [ -n "$name" ] || continue
    # A read that fails is a failed check, not an empty answer: this function
    # runs in an `if`, where errexit is off and an unchecked failure would leave
    # `code` empty and pass.
    if ! code=$(cast code "$addr" --rpc-url "$RPC_URL"); then
      echo "Could not read code for $name=$addr" >&2
      failed=1
    elif [ "$code" = "0x" ]; then
      echo "Manifest address has no code: $name=$addr" >&2
      failed=1
    fi
  done < <(
    jq -r '
      to_entries[]
      | select(.key != "_seed")
      | select(.value != "0x0000000000000000000000000000000000000000")
      | "\(.key) \(.value)"
    ' "$MANIFEST_PATH"
  )

  return "$failed"
}

if [ "${DOTNS_DEPLOY_KEEP_MANIFEST:-0}" != "1" ] && [ -f "$MANIFEST_PATH" ]; then
  ARCHIVE_PATH="${MANIFEST_PATH}.pre-fresh.$(date +%Y%m%d%H%M%S)"
  cp "$MANIFEST_PATH" "$ARCHIVE_PATH"
  rm -f "$MANIFEST_PATH"
  echo "Archived existing manifest for fresh deploy: $ARCHIVE_PATH"
fi

# Broadcast flags shared with factory.sh (defined in _account.sh); each stage
# also gets full verbosity.
common=("${FORGE_DEPLOY_ARGS[@]}" -vvvvv)

stages=(
  DeployCore
  DeployRecords
  DeployPolicy
  DeployPopSystem
  WireDeployments
)

# Resume: the manifest names each stage lands (WireDeployments lands none and
# always broadcasts). A stage with every one of them on chain is run without
# --broadcast first: the simulation adopts each address (BaseDeployer checks
# the code against this run's constructor arguments and the proxy's
# implementation slot), writes the manifest and sends nothing. Its dry-run
# broadcast then shows what a broadcast would have sent; only protocol-registry
# `set` calls are acceptable to skip (WireDeployments sets every key again),
# anything else (a cost-model registration, say) makes the stage broadcast
# after all, which adopts the same way and sends only that.
DEPLOY_RESUME="${DEPLOY_RESUME:-0}"
declare -A stage_contracts=(
  [DeployCore]="Create3Factory DotnsProtocolRegistry Multicall3 StoreFactory LabelStoreBeacon UserStoreBeacon DotnsRegistrar DotnsReverseResolver DotnsRegistry"
  [DeployRecords]="DotnsResolver DotnsContentResolver DotnsCostModelRegistry DotnsFlatPricing PopRules"
  [DeployPolicy]="DotnsNameEscrow DotnsNameWhitelist DotnsRegistrarController"
  [DeployPopSystem]="DotnsPopResolver DotnsPopController DotnsPopLens"
  [WireDeployments]=""
)
expected_set=""
if [ "$DEPLOY_RESUME" = "1" ]; then
  if [ -n "${CREATE3_FACTORY:-}" ]; then
    expected_set=$("$(dirname "$0")/expected-set.sh" --factory "$CREATE3_FACTORY")
  else
    echo "DEPLOY_RESUME=1 without CREATE3_FACTORY: every stage broadcasts" >&2
  fi
fi
REGISTRY_SET_SELECTOR=$(cast sig 'set(bytes32,address)')

stage_all_present() {
  local names="${stage_contracts[$stage]:-}" name addr code
  [ -n "$expected_set" ] && [ -n "$names" ] || return 1
  for name in $names; do
    addr=$(jq -r --arg n "$name" '.[$n] // empty' <<<"$expected_set")
    [ -n "$addr" ] || return 1
    code=$(cast code "$addr" --rpc-url "$RPC_URL") || return 1
    [ "$code" != "0x" ] || return 1
  done
}

# True when the stage's dry-run broadcast holds nothing but registry set calls.
dry_run_only_registry_sets() {
  local file="broadcast/${stage}.s.sol/${CHAIN_ID}/dry-run/run-latest.json"
  [ -f "$file" ] || return 0
  [ "$(stat -c %Y "$file")" -ge "$attempt_started" ] || return 0
  jq -e --arg sel "$REGISTRY_SET_SELECTOR" \
    '[.transactions[] | select(.transactionType != "CALL" or ((.transaction.input // "")[0:10] | ascii_downcase) != $sel)] | length == 0' \
    "$file" >/dev/null
}

# One attempt of the current stage: the forge run, then the manifest check.
attempt_started=0
run_stage_once() {
  attempt_started=$(date +%s)
  if [ "$DEPLOY_RESUME" = "1" ] && stage_all_present; then
    echo "=== $stage: every contract is on chain; adopting without broadcasting ==="
    local simulate=()
    local flag
    for flag in "${common[@]}"; do [ "$flag" = "--broadcast" ] || simulate+=("$flag"); done
    # shellcheck disable=SC2086
    forge script "scripts/deploy/${stage}.s.sol:${stage}" "${simulate[@]}" $extra || return 1
    if dry_run_only_registry_sets; then
      validate_manifest_contracts
      return
    fi
    echo "=== $stage: the simulation would send calls WireDeployments does not repeat; broadcasting ==="
    restore_manifest "$manifest_backup"
  fi
  # shellcheck disable=SC2086
  forge script "scripts/deploy/${stage}.s.sol:${stage}" "${common[@]}" $extra || return 1
  validate_manifest_contracts
}

# Between attempts the manifest goes back to what it was before the stage, so
# the next attempt starts from the same input. A re-run is safe only when the
# failed attempt broadcast nothing, or everything it broadcast was confirmed:
# the stage then re-reads the chain and adopts what is there. An attempt that
# died with transactions unconfirmed is not re-run: a UUPS implementation may
# have landed without its proxy, which BaseDeployer refuses to adopt
# (_broadcastDeployUups, "implementation address already occupied while its
# proxy is absent"), and a plain re-run would fail every attempt. The recovery
# there is `forge script --resume`, which sends the unsent transactions of the
# saved broadcast, followed by a plain re-run of the stage for the manifest.
rollback_stage() {
  restore_manifest "$manifest_backup"
  echo "Restored manifest after failed stage: $stage" >&2
  local file="broadcast/${stage}.s.sol/${CHAIN_ID}/run-latest.json" txs receipts
  [ -f "$file" ] || return 0
  # Only a file written by this attempt counts; an older run's file is not ours.
  [ "$(stat -c %Y "$file")" -ge "$attempt_started" ] || return 0
  txs=$(jq '.transactions | length' "$file")
  receipts=$(jq '.receipts | length' "$file")
  [ "$txs" -gt "$receipts" ] || return 0
  echo "$stage broadcast $txs transaction(s), $receipts confirmed; not re-running the stage." >&2
  echo "Recovery: send the rest with" >&2
  echo "  forge script scripts/deploy/${stage}.s.sol:${stage} <same flags> --resume" >&2
  echo "then re-run this script (the stage adopts what landed and rebuilds the manifest)." >&2
  return 1
}

for stage in "${stages[@]}"; do
  echo "=== Running $stage ==="
  manifest_backup=$(backup_manifest)
  if ! run_with_attempts "$stage" rollback_stage run_stage_once; then
    echo "Stage failed: $stage" >&2
    exit 1
  fi
  # Stage succeeded; drop its rollback backup so successful runs leave no temp files.
  [ -n "$manifest_backup" ] && rm -f "$manifest_backup"
done

echo "=== Pipeline complete ==="

# Delete the bootstrap env file so plaintext secrets do not persist
# between deploys. Subsequent runs prompt for the password interactively
# and rely on the defaults declared above for everything else.
if [ -f "$ENV_FILE" ]; then
  rm -f "$ENV_FILE"
  echo "Deleted one-off env file: $ENV_FILE"
fi
