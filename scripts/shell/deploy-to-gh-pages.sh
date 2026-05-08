#!/usr/bin/env bash
set -euo pipefail

# Usage: ./scripts/deploy-to-gh-pages.sh <source_dir> <destination_dir>

SOURCE_DIR="$1"
DESTINATION_DIR="$2"
MAX_RETRIES=5
RETRY_DELAY=3

if [ -z "${GITHUB_TOKEN:-}" ]; then
    echo "GITHUB_TOKEN is required" >&2
    exit 1
fi

if [ -z "${GITHUB_REPOSITORY:-}" ]; then
    echo "GITHUB_REPOSITORY is required" >&2
    exit 1
fi

REPO_URL="https://github.com/${GITHUB_REPOSITORY}.git"

# Authenticate via GIT_ASKPASS instead of interpolating ${GITHUB_TOKEN}
# into the clone URL. URL interpolation leaks the token into process
# listings, error messages, the git remote config, and any `set -x`
# trace. GIT_ASKPASS keeps the token in an env var consumed by a
# short-lived helper script whose lifetime is tied to this run.
ASKPASS_DIR=$(mktemp -d)
trap 'rm -rf "$ASKPASS_DIR"' EXIT
cat > "$ASKPASS_DIR/askpass.sh" <<'ASKPASS_EOF'
#!/bin/sh
case "$1" in
    Username*) printf '%s' "x-access-token" ;;
    Password*) printf '%s' "$GH_PASS" ;;
esac
ASKPASS_EOF
chmod 700 "$ASKPASS_DIR/askpass.sh"
export GIT_ASKPASS="$ASKPASS_DIR/askpass.sh"
export GH_PASS="$GITHUB_TOKEN"

git config --global user.name "github-actions[bot]"
git config --global user.email "github-actions[bot]@users.noreply.github.com"

for attempt in $(seq 1 $MAX_RETRIES); do
    rm -rf /tmp/gh-pages
    git clone --branch gh-pages --single-branch --depth 1 \
        "$REPO_URL" /tmp/gh-pages 2>/dev/null || {
        git clone "$REPO_URL" /tmp/gh-pages
        cd /tmp/gh-pages
        git checkout --orphan gh-pages
        git rm -rf . 2>/dev/null || true
        touch .nojekyll
        git add .nojekyll
        git commit -m "Initialize gh-pages"
        cd -
    }

    rm -rf "/tmp/gh-pages/${DESTINATION_DIR}"
    mkdir -p "/tmp/gh-pages/${DESTINATION_DIR}"
    cp -r "${SOURCE_DIR}/"* "/tmp/gh-pages/${DESTINATION_DIR}/"
    touch "/tmp/gh-pages/.nojekyll"

    if [ -f "/tmp/gh-pages/404.html" ] && grep -q "mdbook" "/tmp/gh-pages/404.html" 2>/dev/null; then
        rm -f /tmp/gh-pages/404.html /tmp/gh-pages/searcher.js /tmp/gh-pages/searchindex.json /tmp/gh-pages/searchindex.js /tmp/gh-pages/print.html
        rm -rf /tmp/gh-pages/css /tmp/gh-pages/FontAwesome /tmp/gh-pages/fonts /tmp/gh-pages/theme /tmp/gh-pages/src /tmp/gh-pages/contracts
        echo '<!DOCTYPE html><html><head><meta http-equiv="refresh" content="0;url=docs/"></head></html>' > /tmp/gh-pages/index.html
    fi

    if [ ! -f "/tmp/gh-pages/${DESTINATION_DIR}/index.html" ]; then
        REPORT_FILE=$(ls "${SOURCE_DIR}/"*.html 2>/dev/null | head -1 | xargs basename 2>/dev/null || echo "")
        if [ -n "$REPORT_FILE" ]; then
            cat > "/tmp/gh-pages/${DESTINATION_DIR}/index.html" << INDEXEOF
<!DOCTYPE html><html><head><meta http-equiv="refresh" content="0;url=${REPORT_FILE}"></head><body></body></html>
INDEXEOF
        fi
    fi

    cd /tmp/gh-pages
    git add -A
    git diff --cached --quiet && { echo "No changes to deploy"; exit 0; }
    git commit -m "Deploy ${DESTINATION_DIR}"

    if git push origin gh-pages; then
        echo "Deployed to ${DESTINATION_DIR} (attempt ${attempt})"
        exit 0
    fi

    echo "Push failed (attempt ${attempt}/${MAX_RETRIES}), retrying in ${RETRY_DELAY}s..."
    sleep $RETRY_DELAY
    cd -
done

echo "Failed to deploy after ${MAX_RETRIES} attempts"
exit 1
