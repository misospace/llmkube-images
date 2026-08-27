#!/usr/bin/env bash
# test-check-app-test.sh — Regression tests for scripts/check-app-test.sh.
#
# Verifies the app-tests gate rejects apps that lack an executable
# integration test (issue #235):
#   - an app directory with no container_test.go fails,
#   - an app whose container_test.go is empty fails,
#   - an app whose container_test.go contains only non-test Go code fails,
#   - an app with a real Test* function passes.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$SCRIPT_DIR/check-app-test.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

pass=0
fail=0

expect_fail() {
  local app="$1"
  if bash "$CHECK" "$app" "$TMP" >"$TMP/out" 2>&1; then
    echo "FAIL: expected check-app-test.sh $app to fail"
    cat "$TMP/out"
    fail=$((fail + 1))
  else
    echo "PASS: check-app-test.sh $app fails as expected"
    pass=$((pass + 1))
  fi
}

expect_pass() {
  local app="$1"
  if bash "$CHECK" "$app" "$TMP" >"$TMP/out" 2>&1; then
    echo "PASS: check-app-test.sh $app passes as expected"
    pass=$((pass + 1))
  else
    echo "FAIL: expected check-app-test.sh $app to pass"
    cat "$TMP/out"
    fail=$((fail + 1))
  fi
}

# The check runs `go test` from the repo root, so the fixture needs a module.
cat > "$TMP/go.mod" <<'EOF'
module example.com/fixture

go 1.24
EOF

# Fixture 1: empty app directory (no container_test.go at all).
mkdir -p "$TMP/apps/empty-app"
expect_fail "empty-app"

# Fixture 2: container_test.go exists but is empty.
mkdir -p "$TMP/apps/empty-file-app"
: > "$TMP/apps/empty-file-app/container_test.go"
expect_fail "empty-file-app"

# Fixture 3: container_test.go contains only non-test Go code.
mkdir -p "$TMP/apps/no-test-app"
cat > "$TMP/apps/no-test-app/container_test.go" <<'EOF'
package noapp

func helper() int {
	return 42
}
EOF
expect_fail "no-test-app"

# Fixture 4: container_test.go with a real Test* function.
mkdir -p "$TMP/apps/good-app"
cat > "$TMP/apps/good-app/container_test.go" <<'EOF'
package goodapp

import "testing"

func TestGoodApp(t *testing.T) {
	t.Log("integration test")
}
EOF
expect_pass "good-app"

# Fixture 5: app directory does not exist at all.
expect_fail "missing-app"

echo ""
echo "Results: $pass passed, $fail failed"
if [ "$fail" -gt 0 ]; then
  exit 1
fi
