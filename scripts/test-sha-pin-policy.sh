#!/usr/bin/env bash
#
# test-sha-pin-policy.sh — regression guard for the SHA-pin policy in AGENTS.md
# (issue #283).
#
# HEX_SHA512, REBAR_SHA512, and GODOT_SHA512 are manual pins that must be
# recomputed whenever Renovate bumps the matching *_VERSION. The policy for
# doing that (and the scripts/update-sha-pin.sh helper) is documented in
# AGENTS.md. If a future edit drops that section, a maintainer discovering a
# red Renovate PR would have no idea what to do — so this test fails if the
# policy section disappears.
#
# It also asserts the helper script it references actually exists, so the docs
# cannot point at a script that was deleted.
#
# Run: scripts/test-sha-pin-policy.sh
#
# Exit codes:
#   0 — all checks passed
#   1 — one or more checks failed

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

AGENTS_MD="AGENTS.md"
HELPER="scripts/update-sha-pin.sh"

failures=0

check() {
  local name="$1"
  local pattern="$2"
  if grep -qF "$pattern" "$AGENTS_MD"; then
    echo "PASS: AGENTS.md documents: $name"
  else
    echo "FAIL: AGENTS.md is missing the SHA-pin policy marker: $name"
    failures=$((failures + 1))
  fi
}

if [[ ! -f "$AGENTS_MD" ]]; then
  echo "FAIL: $AGENTS_MD is missing"
  exit 1
fi

# The section heading that anchors the policy.
check "SHA-pin policy section heading" "SHA-Pinned Binary Downloads"

# The three manual pins must all be named so a maintainer knows the scope.
check "HEX_SHA512 named as manual" "HEX_SHA512"
check "REBAR_SHA512 named as manual" "REBAR_SHA512"
check "GODOT_SHA512 named as manual" "GODOT_SHA512"

# The reason the pins are manual (upstream does not publish checksums in a
# Renovate-readable form).
check "manual-pin rationale" "does not publish sha512 checksums"

# The helper the maintainer is told to run.
check "update-sha-pin.sh helper referenced" "scripts/update-sha-pin.sh"

# The manual fallback command, in case the helper is unavailable.
check "manual sha512 command" "curl -fsSL"
check "manual sha512 command (cut)" "cut -d' ' -f1"

# The helper the docs point at must actually exist and be executable, so the
# documentation cannot reference a deleted script.
if [[ -x "$HELPER" ]]; then
  echo "PASS: $HELPER exists and is executable"
else
  echo "FAIL: $HELPER is missing or not executable"
  failures=$((failures + 1))
fi

echo
if (( failures > 0 )); then
  echo "Results: $failures failed"
  exit 1
fi
echo "All tests passed!"
