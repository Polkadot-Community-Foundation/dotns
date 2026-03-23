#!/usr/bin/env bash
set -euo pipefail

# Usage: ./scripts/deploy-to-gh-pages.sh <source_dir> <destination_dir>

SOURCE_DIR="$1"
DESTINATION_DIR="$2"
MAX_RETRIES=5
RETRY_DELAY=3

git config user.name "github-actions[bot]"
git config user.email "github-actions[bot]@users.noreply.github.com"

for attempt in $(seq 1 $MAX_RETRIES); do
    rm -rf /tmp/gh-pages
    git clone --branch gh-pages --single-branch --depth 1 \
        "https://x-access-token:${GITHUB_TOKEN}@github.com/${GITHUB_REPOSITORY}.git" \
        /tmp/gh-pages 2>/dev/null || {
        git clone "https://x-access-token:${GITHUB_TOKEN}@github.com/${GITHUB_REPOSITORY}.git" /tmp/gh-pages
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

    REPORT_FILE=$(ls "${SOURCE_DIR}/"*.html 2>/dev/null | head -1 | xargs basename 2>/dev/null || echo "")
    if [ -n "$REPORT_FILE" ]; then
        cat > "/tmp/gh-pages/${DESTINATION_DIR}/index.html" << INDEXEOF
<!DOCTYPE html><html><head><meta http-equiv="refresh" content="0;url=${REPORT_FILE}"></head><body></body></html>
INDEXEOF
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
