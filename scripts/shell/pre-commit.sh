#!/usr/bin/env bash
set -euo pipefail

# Augment PATH so this hook works under GUI git clients (GitHub Desktop and
# similar) that spawn shells with a minimal environment, and so a system
# `/usr/bin/python3` without `tomllib` never outranks the pyenv shims. The
# helper uses move-to-front semantics: any existing occurrence is stripped
# before prepending, guaranteeing the dir is at the head of PATH.
_prepend_path() {
  local dir="$1"
  [ -d "$dir" ] || return 0
  local cleaned=":${PATH:-}:"
  cleaned="${cleaned//:$dir:/:}"
  cleaned="${cleaned#:}"
  cleaned="${cleaned%:}"
  if [ -z "$cleaned" ]; then
    PATH="$dir"
  else
    PATH="$dir:$cleaned"
  fi
}

# Homebrew (Apple Silicon and Intel) and Foundry.
_prepend_path "/opt/homebrew/bin"
_prepend_path "/usr/local/bin"
_prepend_path "$HOME/.foundry/bin"

# Pyenv shims dispatch to the active Python version; TOML validation needs
# tomllib, which ships in Python 3.11+.
_prepend_path "$HOME/.pyenv/shims"

# Nvm: resolve the default alias to its installed version; fall back to the
# newest installed version when no default is pinned.
if [ -d "$HOME/.nvm/versions/node" ]; then
  _nvm_default=""
  if [ -r "$HOME/.nvm/alias/default" ]; then
    _nvm_default="$(tr -d '[:space:]' <"$HOME/.nvm/alias/default")"
  fi
  _nvm_bin=""
  if [ -n "$_nvm_default" ]; then
    for _candidate in "$HOME/.nvm/versions/node/v${_nvm_default}"*/bin; do
      [ -d "$_candidate" ] || continue
      _nvm_bin="$_candidate"
    done
  fi
  if [ -z "$_nvm_bin" ]; then
    for _candidate in "$HOME/.nvm/versions/node"/*/bin; do
      [ -d "$_candidate" ] || continue
      _nvm_bin="$_candidate"
    done
  fi
  [ -n "$_nvm_bin" ] && _prepend_path "$_nvm_bin"
  unset _nvm_default _nvm_bin _candidate
fi

export PATH
unset -f _prepend_path

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

validate_abi_contracts() {
  local file="$1"

  # Each line becomes part of an artifact path in the publish workflows, so a
  # carriage return from a CRLF save turns into out/Name\r.sol/Name\r.json and
  # aborts the release. Reject it here instead.
  run_validation "$file" "line-ending validation" awk '/\r/ { exit 1 }' "$file"
}

# Rejects decorative separator comments: a comment whose content is a run of
# rule characters, such as a line of dashes or equals under a heading. Prose
# and bullet lists are untouched because they carry words, not a bare run.
_reject_separator_comments() {
  if grep -nE '^[[:space:]]*(//+|/\*|\*|#)[[:space:]]*[-=*_~#]{6,}|^[[:space:]]*/{6,}[[:space:]]*$' "$1" >&2; then
    return 1
  fi
  return 0
}

validate_no_separator_comments() {
  local file="$1"

  run_validation "$file" "decorative-separator check" _reject_separator_comments "$file"
}

# Rejects trailing inline comments: a run of two or more slashes that follows code
# on the same line, including `///`. A comment belongs on its own line above the
# code it describes. Full-line and doc comments on their own line are fine, an
# inline tool directive such as solhint-disable-line is allowed because it only
# works on the line it annotates, and a `://` inside a URL is skipped. The check
# is a line regex, not a parser, so a `//` inside a string, template, or regex
# literal, or in a multi-line block-comment body, is a known false positive.
_reject_trailing_comments() {
  local hits
  hits="$(
    grep -nE '^[[:space:]]*[^/*[:space:]].*[^:/]/{2,}' "$1" 2>/dev/null \
      | grep -vE '//[[:space:]]*(solhint-disable(-next)?-line|eslint-disable(-next)?-line|prettier-ignore|slither-disable(-next)?-line|forge-lint:|@ts-(expect-error|ignore|nocheck))' 2>/dev/null \
      || true
  )"
  if [ -n "$hits" ]; then
    printf '%s\n' "$hits" >&2
    return 1
  fi
  return 0
}

validate_no_trailing_comments() {
  local file="$1"

  run_validation "$file" "trailing-comment check" _reject_trailing_comments "$file"
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
    .github/abi-contracts.txt)
      validate_abi_contracts "$file"
      ;;
  esac

  case "$file" in
    lib/*|node_modules/*)
      ;;
    *.sol|*.ts|*.tsx|*.mts|*.cts|*.js|*.jsx|*.cjs|*.mjs|*.sh|*.bash|*.py)
      validate_no_separator_comments "$file"
      ;;
  esac

  case "$file" in
    lib/*|node_modules/*)
      ;;
    *.sol|*.ts|*.tsx|*.mts|*.cts|*.js|*.jsx|*.cjs|*.mjs)
      validate_no_trailing_comments "$file"
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
