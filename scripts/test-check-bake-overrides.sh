#!/usr/bin/env bash
# test-check-bake-overrides.sh — Regression tests for scripts/check-bake-overrides.sh.
#
# Guards the class of failure that turned the Release workflow's
# `Build (linux/arm64)` job red twice on the default branch (issue #402, and
# issue #396 before it): a `docker buildx bake --set` override using a
# `docker buildx build` flag name. Bake rejects unknown keys at parse time, so
# the whole run dies before any build step starts.
#
#   - `*.provenance=false` (a build flag) fails,
#   - `*.sbom=false` (a build flag) fails,
#   - `*.attest=type=provenance,disabled=true` (the bake-native spelling) passes,
#   - dotted sub-keys of a valid key (`*.labels.<name>`, `*.args.<name>`) pass,
#   - the repository's own workflows pass.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$SCRIPT_DIR/check-bake-overrides.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

pass=0
fail=0

# make_workflow <name> <set-block-body>
make_workflow() {
  local name="$1"
  local body="$2"
  local dir="$TMP/$name/.github/workflows"
  mkdir -p "$dir"
  {
    echo 'name: Test'
    echo 'on: push'
    echo 'jobs:'
    echo '  build:'
    echo '    runs-on: ubuntu-24.04'
    echo '    steps:'
    echo '      - uses: docker/bake-action@v7.3.0'
    echo '        with:'
    echo '          set: |'
    printf '%s\n' "$body"
  } > "$dir/test.yaml"
}

expect_fail() {
  local name="$1"
  local body="$2"
  make_workflow "$name" "$body"
  if bash "$CHECK" "$TMP/$name" >"$TMP/out" 2>&1; then
    echo "FAIL: expected check-bake-overrides.sh to reject $name"
    cat "$TMP/out"
    fail=$((fail + 1))
  else
    echo "PASS: check-bake-overrides.sh rejects $name"
    pass=$((pass + 1))
  fi
}

expect_pass() {
  local name="$1"
  local body="$2"
  make_workflow "$name" "$body"
  if bash "$CHECK" "$TMP/$name" >"$TMP/out" 2>&1; then
    echo "PASS: check-bake-overrides.sh accepts $name"
    pass=$((pass + 1))
  else
    echo "FAIL: expected check-bake-overrides.sh to accept $name"
    cat "$TMP/out"
    fail=$((fail + 1))
  fi
}

# The exact regression from issue #402, and the one from #396.
expect_fail provenance '            *.platform=linux/arm64
            *.provenance=false
            *.tags='
expect_fail sbom '            *.platform=linux/arm64
            *.sbom=false
            *.tags='

# The bake-native spelling of "no provenance attestation" must be accepted.
expect_pass attest_disabled '            *.platform=linux/arm64
            *.attest=type=provenance,disabled=true
            *.tags='

# Dotted sub-keys belong to their parent key.
expect_pass dotted_subkeys '            *.args.VENDOR=misospace
            *.labels.org.opencontainers.image.title=elixir-gate
            *.cache-from=type=registry,ref=example/cache:arm64,mode=max'

# Files that do not run bake are not scanned.
mkdir -p "$TMP/no_bake/.github/workflows"
printf 'name: No Bake\non: push\njobs:\n  x:\n    runs-on: ubuntu-24.04\n    steps:\n      - run: echo *.notabakekey=1\n' \
  > "$TMP/no_bake/.github/workflows/x.yaml"
if bash "$CHECK" "$TMP/no_bake" >"$TMP/out" 2>&1; then
  echo "PASS: check-bake-overrides.sh ignores workflows that do not run bake"
  pass=$((pass + 1))
else
  echo "FAIL: check-bake-overrides.sh scanned a workflow with no bake step"
  cat "$TMP/out"
  fail=$((fail + 1))
fi

# The real repository must be clean.
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
if bash "$CHECK" "$REPO_ROOT" >"$TMP/out" 2>&1; then
  echo "PASS: repository workflows use only valid bake override keys"
  pass=$((pass + 1))
else
  echo "FAIL: repository workflows use an invalid bake override key"
  cat "$TMP/out"
  fail=$((fail + 1))
fi

echo
echo "Results: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
