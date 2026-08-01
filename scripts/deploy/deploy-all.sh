#!/usr/bin/env bash
#
# One-command deploy. Ensures the CREATE3 factory exists (deployed once from the
# dedicated factory key at nonce 0, a deterministic address), then runs the full
# pipeline reusing that factory. Because every DotNS address derives from the
# factory address, and the factory address is the same on every fresh chain,
# this reproduces the same address set across resets and networks.
#
# The two steps feed into each other: factory.sh prints the factory address,
# which this script passes to run.sh as CREATE3_FACTORY so DeployCore reuses it
# instead of minting a new one.
#
# Usage:
#   bun run deploy:all
#
# Keys (see _account.sh for the full env): factory.sh uses ACCOUNT_NAME
# (default dotns-factory), run.sh uses its own ACCOUNT_NAME (default
# dotns-deploy). Set FACTORY_ACCOUNT / ACCOUNT_NAME to override. Extra forge
# flags are forwarded to both steps.

set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"

# 1. Deploy or confirm the CREATE3 factory, capturing its address. The factory
#    key defaults to dotns-factory; keep it single-purpose so its nonce stays 0.
factory_out=$(mktemp "${TMPDIR:-/tmp}/dotns-factory.XXXXXX")
trap 'rm -f "$factory_out"' EXIT
ACCOUNT_NAME="${FACTORY_ACCOUNT:-dotns-factory}" "$here/factory.sh" "$@" | tee "$factory_out"

CREATE3_FACTORY=$(sed -n 's/^CREATE3_FACTORY=//p' "$factory_out" | tail -1)
if [ -z "${CREATE3_FACTORY:-}" ]; then
  echo "deploy-all: could not resolve the CREATE3 factory address from factory.sh output" >&2
  exit 1
fi
export CREATE3_FACTORY

# 2. Run the full pipeline reusing that factory (DeployCore adopts it instead of
#    minting a new one, so the pipeline key's nonce does not affect any address).
echo "=== Running pipeline reusing CREATE3 factory $CREATE3_FACTORY ==="
"$here/run.sh" "$@"
