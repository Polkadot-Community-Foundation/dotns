#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

format_before="$(mktemp)"
format_after="$(mktemp)"
build_log="$(mktemp)"
project_warnings="$(mktemp)"
validation_errors="$(mktemp)"
validation_detail="$(mktemp)"
cleanup() {
  rm -f "$format_before" "$format_after" "$build_log" "$project_warnings" "$validation_errors" "$validation_detail"
}
trap cleanup EXIT

record_validation_failure() {
  local file="$1"
  local check="$2"

  {
    echo "$file: failed $check"
    sed 's/^/  /' "$validation_detail"
  } >>"$validation_errors"
}

run_validation() {
  local file="$1"
  local check="$2"
  shift 2

  : >"$validation_detail"
  if ! "$@" > /dev/null 2>"$validation_detail"; then
    record_validation_failure "$file" "$check"
  fi
}

validate_toml() {
  local file="$1"

  run_validation "$file" "TOML validation" python3 -c 'import pathlib, sys, tomllib; tomllib.loads(pathlib.Path(sys.argv[1]).read_text())' "$file"
}

validate_env_file() {
  local file="$1"

  run_validation "$file" "environment-file validation" ruby -e '
    file = ARGV.fetch(0)
    ARGF.each_line.with_index(1) do |line, number|
      next if line.match?(/\A\s*(#.*)?\s*\z/)
      next if line.match?(/\A[A-Za-z_][A-Za-z0-9_]*=.*\s*\z/)
      raise "#{file}:#{number}: expected KEY=value, blank line, or comment"
    end
  ' "$file"
}

validate_git_config_file() {
  local file="$1"

  run_validation "$file" "git-config validation" git config --file "$file" --list
}

echo "pre-commit: validating repository files"
while IFS= read -r -d '' file; do
  [ -f "$file" ] || continue

  case "$file" in
    lib/*|node_modules/*)
      continue
      ;;
    *.bash|*.sh|setup.bash|.githooks/*)
      run_validation "$file" "shell validation" bash -n "$file"
      ;;
    *.cjs|*.js|*.mjs)
      run_validation "$file" "JavaScript validation" node --check "$file"
      ;;
    *.json)
      run_validation "$file" "JSON validation" jq -e . "$file"
      ;;
    *.py)
      run_validation "$file" "Python validation" python3 -c 'import ast, pathlib, sys; ast.parse(pathlib.Path(sys.argv[1]).read_text(), filename=sys.argv[1])' "$file"
      ;;
    *.toml)
      validate_toml "$file"
      ;;
    *.yaml|*.yml)
      run_validation "$file" "YAML validation" ruby -e 'require "yaml"; YAML.load_file(ARGV.fetch(0))' "$file"
      ;;
    .env.example)
      validate_env_file "$file"
      ;;
    .gitmodules)
      validate_git_config_file "$file"
      ;;
  esac
done < <(git ls-files -z)

if command -v actionlint > /dev/null 2>&1; then
  run_validation ".github/workflows" "GitHub Actions validation" actionlint
fi

if [ -s "$validation_errors" ]; then
  echo "pre-commit: repository file validation failed:" >&2
  cat "$validation_errors" >&2
  exit 1
fi

echo "pre-commit: running forge fmt"

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
