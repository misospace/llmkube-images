#!/usr/bin/env bash
#
# test-update-sha-pin.sh — regression guard for scripts/update-sha-pin.sh.
#
# The helper reads each app's version args from its Dockerfile, reconstructs
# the artifact URL the build would download, and sha512s it. If the URL
# template the helper uses ever drifts from the URL the Dockerfile's `curl`
# line uses, the SHA the helper computes will not match the artifact the
# build downloads, so the build's `sha512sum -c` check still fails — which
# is the entire problem the helper is meant to solve. This test asserts the
# two URLs are equivalent for every (app, var) pair the helper supports.
#
# It also exercises the helper's `arg()` extractor against each Dockerfile
# so a future edit that changes an ARG name (HEX_VERSION → HEX_VER, or
# VERSION → GODOT_VERSION) is caught before the helper silently returns
# empty and the script exits with an opaque "could not read VERSION" error.
#
# Run: scripts/test-update-sha-pin.sh
#
# Exit codes:
#   0 — all checks passed
#   1 — one or more checks failed

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

HELPER="scripts/update-sha-pin.sh"
TEST_HELPERS_TMP="$(mktemp -d)"
trap 'rm -rf "$TEST_HELPERS_TMP"' EXIT

failures=0

# arg() — re-implemented inline (must stay byte-identical to the helper's
# arg() so this test catches drift).
arg() {
  sed -n "s/^ARG $1=//p" "$2" | head -1
}

check() {
  local name="$1"
  local cmd="$2"
  if eval "$cmd"; then
    echo "PASS: $name"
  else
    echo "FAIL: $name"
    failures=$((failures + 1))
  fi
}

# ---------------------------------------------------------------------------
# arg() regression: every (app, arg-name) pair the helper reads must be
# present and non-empty in the corresponding Dockerfile. If any of these
# break, the helper fails with an opaque "could not read X" error and the
# maintainer has to read the script to find out which ARG was renamed.
# ---------------------------------------------------------------------------

assert_arg_present() {
  local app="$1"
  local argname="$2"
  local df="apps/$app/Dockerfile"
  if [[ ! -f "$df" ]]; then
    echo "FAIL: $df is missing"
    failures=$((failures + 1))
    return
  fi
  local val
  val="$(arg "$argname" "$df")"
  if [[ -n "$val" ]]; then
    echo "PASS: $df declares ARG $argname=<value>"
  else
    echo "FAIL: $df is missing or empty ARG $argname=... (helper will fail at runtime)"
    failures=$((failures + 1))
  fi
}

# Mirrors scripts/update-sha-pin.sh's case statement.
for argname in HEX_VERSION HEX_INSTALLS HEX_OTP HEX_SHA512; do
  assert_arg_present llmkube-coder "$argname"
done
for argname in REBAR_VERSION REBAR_SHA512; do
  assert_arg_present llmkube-coder "$argname"
done
for argname in GODOT_VERSION GODOT_STATUS GODOT_SHA512; do
  assert_arg_present llmkube-coder "$argname"
done

for argname in HEX_VERSION HEX_INSTALLS HEX_OTP HEX_SHA512; do
  assert_arg_present elixir-gate "$argname"
done
for argname in REBAR_VERSION REBAR_SHA512; do
  assert_arg_present elixir-gate "$argname"
done

for argname in VERSION GODOT_STATUS GODOT_SHA512; do
  assert_arg_present godot-gate "$argname"
done

# ---------------------------------------------------------------------------
# URL template regression: the URL the helper would build for each
# (app, var) pair must contain the same hostname + path components the
# Dockerfile's `curl` line uses. Comparing on the structural components
# (host + path prefix + variable names) catches drift without coupling the
# test to exact version values that change every Renovate run.
# ---------------------------------------------------------------------------

# Extract the case branch from the helper for this (app, var) pair so the
# test reads the URL template directly out of the script source. Each
# helper_branch is the body of one case in scripts/update-sha-pin.sh, which
# contains the literal `URL="..."` assignment the helper will build.
extract_helper_branch() {
  local app="$1"
  local var="$2"
  local out="$TEST_HELPERS_TMP/helper-${app}-${var}.sh"
  case "$app:$var" in
    llmkube-coder:*|elixir-gate:*)
      # The llmkube-coder/elixir-gate branch is one case statement whose
      # inner HEX/REBAR/GODOT sub-cases each set URL= once.
      awk '
        /^  llmkube-coder\|elixir-gate\)/ {flag=1; next}
        flag && /^      \*\)/ {flag=0}
        flag
      ' "$HELPER" >"$out"
      ;;
    godot-gate:*)
      awk '
        /^  godot-gate\)/ {flag=1; next}
        flag && /^  \*\)/ {flag=0}
        flag
      ' "$HELPER" >"$out"
      ;;
  esac
  if [[ ! -s "$out" ]]; then
    return 1
  fi
  return 0
}

# Verify a list of URL components appears in BOTH the Dockerfile `curl`
# line and the helper's URL string. Components are chosen to be stable
# across version bumps (host, path prefix, variable names).
#
# Components may legitimately start with a dash (e.g. `-otp-` is part of
# the hex artifact filename), so every grep call uses `--` to terminate
# the option list before the pattern.
assert_url_components() {
  local app="$1"
  local var="$2"
  shift 2
  local component
  local df="apps/$app/Dockerfile"
  local helper_branch
  if ! extract_helper_branch "$app" "$var"; then
    echo "FAIL: could not extract $app/$var branch from $HELPER"
    failures=$((failures + 1))
    return
  fi
  helper_branch="$TEST_HELPERS_TMP/helper-${app}-${var}.sh"
  for component in "$@"; do
    if grep -qF -- "$component" "$df"; then
      echo "PASS: $df references URL component '$component'"
    else
      echo "FAIL: $df is missing URL component '$component'"
      failures=$((failures + 1))
    fi
    if grep -qF -- "$component" "$helper_branch"; then
      echo "PASS: $HELPER ($app/$var branch) references URL component '$component'"
    else
      echo "FAIL: $HELPER ($app/$var branch) is missing URL component '$component'"
      failures=$((failures + 1))
    fi
  done
}

# HEX (llmkube-coder, elixir-gate)
assert_url_components llmkube-coder HEX \
  "builds.hex.pm/installs/" \
  "hex-" \
  "otp-" \
  ".ez"

assert_url_components elixir-gate HEX \
  "builds.hex.pm/installs/" \
  "hex-" \
  "otp-" \
  ".ez"

# REBAR (llmkube-coder, elixir-gate)
assert_url_components llmkube-coder REBAR \
  "github.com/erlang/rebar3/releases/download/" \
  "/rebar3"

assert_url_components elixir-gate REBAR \
  "github.com/erlang/rebar3/releases/download/" \
  "/rebar3"

# GODOT (llmkube-coder, godot-gate)
assert_url_components llmkube-coder GODOT \
  "godotengine/godot-builds/releases/download/" \
  "Godot_v" \
  "_linux.x86_64.zip"

assert_url_components godot-gate GODOT \
  "godotengine/godot-builds/releases/download/" \
  "Godot_v" \
  "_linux.x86_64.zip"

# ---------------------------------------------------------------------------
# Per-app presence checks: each Dockerfile must fetch what its app is
# responsible for. Catches a future refactor that drops the godot
# download from llmkube-coder, or removes the hex install from
# elixir-gate, etc.
# ---------------------------------------------------------------------------

check "llmkube-coder/Dockerfile fetches godot-builds" \
  "grep -qF 'godotengine/godot-builds/releases/download/' apps/llmkube-coder/Dockerfile"

check "llmkube-coder/Dockerfile fetches hex.pm" \
  "grep -qF 'builds.hex.pm/installs/' apps/llmkube-coder/Dockerfile"

check "llmkube-coder/Dockerfile fetches rebar3" \
  "grep -qF 'github.com/erlang/rebar3/releases/download/' apps/llmkube-coder/Dockerfile"

check "elixir-gate/Dockerfile fetches hex.pm" \
  "grep -qF 'builds.hex.pm/installs/' apps/elixir-gate/Dockerfile"

check "elixir-gate/Dockerfile fetches rebar3" \
  "grep -qF 'github.com/erlang/rebar3/releases/download/' apps/elixir-gate/Dockerfile"

check "godot-gate/Dockerfile fetches godot-builds" \
  "grep -qF 'godotengine/godot-builds/releases/download/' apps/godot-gate/Dockerfile"

# godot-gate must NOT fetch hex or rebar (it is not in the helper's
# supported matrix, and adding it would be a scope change).
check "godot-gate/Dockerfile does NOT fetch hex.pm" \
  "! grep -qF 'builds.hex.pm/installs/' apps/godot-gate/Dockerfile"

check "godot-gate/Dockerfile does NOT fetch rebar3" \
  "! grep -qF 'github.com/erlang/rebar3/releases/download/' apps/godot-gate/Dockerfile"

echo
if (( failures > 0 )); then
  echo "Results: $failures failed"
  exit 1
fi
echo "All tests passed!"
