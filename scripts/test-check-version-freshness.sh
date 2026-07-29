#!/usr/bin/env bash
# test-check-version-freshness.sh — Regression tests for check-version-freshness.sh error handling.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK_SCRIPT="$SCRIPT_DIR/check-version-freshness.sh"

PASS=0
FAIL=0

assert_exit_code() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "PASS: $desc (exit code $actual)"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $desc — expected exit $expected, got $actual"
    FAIL=$((FAIL + 1))
  fi
}

assert_output_contains() {
  local desc="$1" expected="$2" output="$3"
  if echo "$output" | grep -qF "$expected"; then
    echo "PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $desc — expected output to contain '$expected'"
    echo "  Actual output: $(echo "$output" | head -5)"
    FAIL=$((FAIL + 1))
  fi
}

# Test 1: Missing GITHUB_TOKEN should exit non-zero
echo "--- Test: Missing GITHUB_TOKEN ---"
unset GITHUB_TOKEN
output=$(bash "$CHECK_SCRIPT" 2>&1) || true
exit_code=$?
# Re-run to capture actual exit code
set +e
bash "$CHECK_SCRIPT" > /dev/null 2>&1
exit_code=$?
set -e
assert_exit_code "Missing GITHUB_TOKEN exits non-zero" "1" "$exit_code"
assert_output_contains "Error message mentions GITHUB_TOKEN" "GITHUB_TOKEN" "$output"
assert_output_contains "Error message is actionable" "export GITHUB_TOKEN" "$output"

# Test 2: Empty GITHUB_TOKEN should exit non-zero
echo "--- Test: Empty GITHUB_TOKEN ---"
set +e
GITHUB_TOKEN="" bash "$CHECK_SCRIPT" > /dev/null 2>&1
exit_code=$?
set -e
assert_exit_code "Empty GITHUB_TOKEN exits non-zero" "1" "$exit_code"

# Test 3: Script header documents GITHUB_TOKEN requirement
echo "--- Test: Script header documentation ---"
header=$(head -15 "$CHECK_SCRIPT")
assert_output_contains "Header mentions GITHUB_TOKEN" "GITHUB_TOKEN" "$header"
assert_output_contains "Header mentions rate limit" "rate limit" "$header"

# Summary
echo ""
echo "Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
echo "All tests passed!"
