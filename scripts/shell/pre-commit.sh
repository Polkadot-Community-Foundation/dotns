#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

echo "pre-commit: running forge fmt"
format_before="$(mktemp)"
format_after="$(mktemp)"
build_log="$(mktemp)"
project_warnings="$(mktemp)"
cleanup() {
  rm -f "$format_before" "$format_after" "$build_log" "$project_warnings"
}
trap cleanup EXIT

git diff --binary -- . ':!lib/**' ':!node_modules/**' >"$format_before"

forge fmt
git diff --binary -- . ':!lib/**' ':!node_modules/**' >"$format_after"

if ! cmp -s "$format_before" "$format_after"; then
  echo "pre-commit: forge fmt changed files. Review and stage the formatting changes." >&2
  git diff --name-only -- . ':!lib/**' ':!node_modules/**' >&2
  exit 1
fi

echo "pre-commit: running forge build"
if ! forge build >"$build_log" 2>&1; then
  cat "$build_log" >&2
  exit 1
fi

awk '
  function flush() {
    if (!in_warning) {
      return
    }

    if (project_warning) {
      printf "%s", block
    }

    block = ""
    in_warning = 0
    has_path = 0
    project_warning = 0
  }

  /^Warning / {
    flush()
    in_warning = 1
  }

  in_warning {
    block = block $0 "\n"
    if ($0 ~ /^[[:space:]]*-->[[:space:]]+[^:]+:/) {
      path = $0
      sub(/^[[:space:]]*-->[[:space:]]+/, "", path)
      sub(/:.*/, "", path)
      has_path = 1
      if (path !~ /(^|\/)(lib|node_modules)\//) {
        project_warning = 1
      }
    }
  }

  END {
    flush()
  }
' "$build_log" >"$project_warnings"

if [ -s "$project_warnings" ]; then
  echo "pre-commit: forge build emitted warnings from project code:" >&2
  cat "$project_warnings" >&2
  echo "pre-commit: address these warnings before committing." >&2
  exit 1
fi

echo "pre-commit: ok"
