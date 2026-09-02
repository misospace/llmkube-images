#!/usr/bin/env bash
# test-check-renovate-datasource.sh — Regression tests for
# scripts/check-renovate-datasource.sh (issue #276).
#
# Verifies the check rejects a `datasource=github-release` (singular) renovate
# hint while accepting the canonical `github-releases` (plural) form and files
# with no renovate hint at all.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$SCRIPT_DIR/check-renovate-datasource.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

pass=0
fail=0

expect_fail() {
  local file="$1"
  if bash "$CHECK" "$file" >"$TMP/out" 2>&1; then
    echo "FAIL: expected check-renovate-datasource.sh $file to fail"
    cat "$TMP/out"
    fail=$((fail + 1))
  else
    echo "PASS: check-renovate-datasource.sh $file fails as expected"
    pass=$((pass + 1))
  fi
}

expect_pass() {
  local file="$1"
  if bash "$CHECK" "$file" >"$TMP/out" 2>&1; then
    echo "PASS: check-renovate-datasource.sh $file passes as expected"
    pass=$((pass + 1))
  else
    echo "FAIL: expected check-renovate-datasource.sh $file to pass"
    cat "$TMP/out"
    fail=$((fail + 1))
  fi
}

# Fixture 1: the original typo from issue #276 — singular datasource.
cat > "$TMP/typo.Dockerfile" <<'EOF'
# renovate: datasource=github-release depName=godotengine/godot-builds
ARG GODOT_SHA512=9aa00f7a605200940bce3027a567b782f49bd8e940dd06ae9e987bd65aee1b1467edd56ed84fcdcbdd44354bf613bdbb4e5d2913e925850368e150c59ed54c65
EOF
expect_fail "$TMP/typo.Dockerfile"

# Fixture 2: canonical plural datasource — must not be flagged.
cat > "$TMP/plural.Dockerfile" <<'EOF'
# renovate: datasource=github-releases depName=godotengine/godot
ARG GODOT_VERSION=4.7.2
EOF
expect_pass "$TMP/plural.Dockerfile"

# Fixture 3: no renovate hint at all (the current godot-gate state).
cat > "$TMP/nohint.Dockerfile" <<'EOF'
# GODOT_SHA512 is manually pinned — do NOT add a renovate hint here.
ARG GODOT_SHA512=9aa00f7a605200940bce3027a567b782f49bd8e940dd06ae9e987bd65aee1b1467edd56ed84fcdcbdd44354bf613bdbb4e5d2913e925850368e150c59ed54c65
EOF
expect_pass "$TMP/nohint.Dockerfile"

# Fixture 4: missing file.
expect_fail "$TMP/does-not-exist.Dockerfile"

# The real file in the repo must pass.
expect_pass "apps/godot-gate/Dockerfile"

echo ""
echo "Results: $pass passed, $fail failed"
if [ "$fail" -gt 0 ]; then
  exit 1
fi
