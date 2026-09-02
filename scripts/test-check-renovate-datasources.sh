#!/usr/bin/env bash
# test-check-renovate-datasources.sh — Regression tests for
# scripts/check-renovate-datasources.sh (issue #277).
#
# Verifies the lint gate rejects a renovate hint that uses the singular
# datasource `github-release` (Renovate's canonical name is `github-releases`):
#   - a Dockerfile with `datasource=github-release depName=...` fails,
#   - a Dockerfile with the correct `datasource=github-releases` passes,
#   - a Dockerfile with no renovate hint at all passes,
#   - the real repo (apps/godot-gate/Dockerfile) passes.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$SCRIPT_DIR/check-renovate-datasources.sh"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

pass=0
fail=0

expect_fail() {
  local root="$1"
  if bash "$CHECK" "$root" >"$TMP/out" 2>&1; then
    echo "FAIL: expected check-renovate-datasources.sh $root to fail"
    cat "$TMP/out"
    fail=$((fail + 1))
  else
    echo "PASS: check-renovate-datasources.sh $root fails as expected"
    pass=$((pass + 1))
  fi
}

expect_pass() {
  local root="$1"
  if bash "$CHECK" "$root" >"$TMP/out" 2>&1; then
    echo "PASS: check-renovate-datasources.sh $root passes as expected"
    pass=$((pass + 1))
  else
    echo "FAIL: expected check-renovate-datasources.sh $root to pass"
    cat "$TMP/out"
    fail=$((fail + 1))
  fi
}

# Fixture 1: singular typo — must fail.
mkdir -p "$TMP/bad/apps/godot-gate"
cat > "$TMP/bad/apps/godot-gate/Dockerfile" <<'EOF'
FROM alpine:3.20
# renovate: datasource=github-release depName=godotengine/godot-builds
ARG GODOT_SHA512=deadbeef
EOF
expect_fail "$TMP/bad"

# Fixture 2: correct plural datasource — must pass.
mkdir -p "$TMP/good-plural/apps/godot-gate"
cat > "$TMP/good-plural/apps/godot-gate/Dockerfile" <<'EOF'
FROM alpine:3.20
# renovate: datasource=github-releases depName=godotengine/godot
ARG GODOT_VERSION=4.7.2
EOF
expect_pass "$TMP/good-plural"

# Fixture 3: no renovate hint at all (the coder image's pattern) — must pass.
mkdir -p "$TMP/good-none/apps/llmkube-coder"
cat > "$TMP/good-none/apps/llmkube-coder/Dockerfile" <<'EOF'
FROM alpine:3.20
ARG GODOT_SHA512=deadbeef
EOF
expect_pass "$TMP/good-none"

# Fixture 4: the real repo — must pass (the typo was removed in issue #277).
expect_pass "$REPO_ROOT"

echo ""
echo "Results: $pass passed, $fail failed"
if [ "$fail" -gt 0 ]; then
  exit 1
fi
