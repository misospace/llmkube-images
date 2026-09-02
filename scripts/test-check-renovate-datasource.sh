#!/usr/bin/env bash
#
# test-check-renovate-datasource.sh — tests for scripts/check-renovate-datasource.sh
#
# Run: scripts/test-check-renovate-datasource.sh
#
# Exit codes:
#   0 — all tests passed
#   1 — one or more tests failed

set -uo pipefail

SCRIPT="$(cd "$(dirname "$0")" && pwd)/check-renovate-datasource.sh"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

PASS=0
FAIL=0

pass() {
  PASS=$((PASS + 1))
  echo "  PASS: $1"
}

fail() {
  FAIL=$((FAIL + 1))
  echo "  FAIL: $1"
}

# expect_ok <name> <dockerfile-content>
expect_ok() {
  local name="$1" content="$2"
  local f="$TMPDIR/$name.Dockerfile"
  printf '%s\n' "$content" > "$f"
  if "$SCRIPT" "$f" > /dev/null 2>&1; then
    pass "$name"
  else
    fail "$name (expected exit 0, got non-zero)"
  fi
}

# expect_fail <name> <dockerfile-content>
expect_fail() {
  local name="$1" content="$2"
  local f="$TMPDIR/$name.Dockerfile"
  printf '%s\n' "$content" > "$f"
  if "$SCRIPT" "$f" > /dev/null 2>&1; then
    fail "$name (expected exit 1, got 0)"
  else
    pass "$name"
  fi
}

echo "=== check-renovate-datasource.sh tests ==="

# 1. The real file must pass (the fix is in place).
if "$SCRIPT" > /dev/null 2>&1; then
  pass "real apps/godot-gate/Dockerfile passes"
else
  fail "real apps/godot-gate/Dockerfile passes"
fi

# 2. The original typo must be caught.
expect_fail "singular-typo" \
  "# renovate: datasource=github-release depName=godotengine/godot-builds
ARG GODOT_SHA512=abc123"

# 3. The valid plural datasource must NOT be flagged.
expect_ok "plural-valid" \
  "# renovate: datasource=github-releases depName=godotengine/godot
ARG GODOT_VERSION=4.7.2"

# 4. No renovate hint at all (the coder-image pattern) must pass.
expect_ok "no-hint" \
  "ARG GODOT_SHA512=abc123"

# 5. A comment mentioning the singular name without the `datasource=` prefix
#    must not be flagged (the guard is scoped to the hint form).
expect_ok "prose-mention" \
  "# the old singular github-release datasource hint was a typo
ARG GODOT_SHA512=abc123"

# 6. Missing file must exit 2.
"$SCRIPT" "$TMPDIR/does-not-exist.Dockerfile" > /dev/null 2>&1
rc=$?
if [[ "$rc" -eq 2 ]]; then
  pass "missing file exits 2"
else
  fail "missing file exits 2 (got $rc)"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"

if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
exit 0
