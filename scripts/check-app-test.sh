#!/usr/bin/env bash
# check-app-test.sh — Require an executable integration test for an app.
#
# Usage: check-app-test.sh <app-name> [repo-root]
#
# Fails (exit 1) with an actionable error when:
#   - apps/<app>/container_test.go is missing or empty, or
#   - go test discovers no Test* function in apps/<app>/...
#
# Every app must ship a non-empty container_test.go containing at least one
# discoverable Test* function (see AGENTS.md "Every app must ship a
# container_test.go"). A Go package with no tests exits 0 from `go test`,
# so this check makes the absence of an integration test a hard failure
# instead of a false-green signal.
set -euo pipefail

APP="${1:-}"
REPO_ROOT="${2:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

if [ -z "$APP" ]; then
  echo "ERROR: usage: check-app-test.sh <app-name> [repo-root]"
  exit 1
fi

APP_DIR="$REPO_ROOT/apps/$APP"
TEST_FILE="$APP_DIR/container_test.go"

if [ ! -d "$APP_DIR" ]; then
  echo "ERROR: app '$APP' has no directory at apps/$APP."
  echo "Add the app under apps/$APP with a non-empty container_test.go containing at least one Test* function."
  exit 1
fi

if [ ! -f "$TEST_FILE" ]; then
  echo "ERROR: app '$APP' is missing apps/$APP/container_test.go."
  echo "Every app must ship a non-empty container_test.go containing at least one Test* function (see AGENTS.md)."
  echo "Add apps/$APP/container_test.go with an integration test, e.g. testhelpers.TestHTTPEndpoint."
  exit 1
fi

if [ ! -s "$TEST_FILE" ]; then
  echo "ERROR: apps/$APP/container_test.go is empty."
  echo "Every app must ship a non-empty container_test.go containing at least one Test* function (see AGENTS.md)."
  exit 1
fi

# Verify go test discovers at least one Test* function in the app's package.
# `go test -list` compiles the test binary and prints each discovered test
# name; a package with no tests prints nothing and exits 0, which is exactly
# the false-green case this check exists to catch.
cd "$REPO_ROOT"
test_list="$(go test -list '.*' "./apps/$APP/..." 2>&1)" || {
  echo "ERROR: go test could not build the test package for app '$APP':"
  echo "$test_list"
  exit 1
}

# Filter out the per-package "no test files" / "no tests to run" markers.
discovered="$(echo "$test_list" | grep -vE '^(ok|---|\?|no test files|no tests to run)' | grep -E '^[A-Za-z_][A-Za-z0-9_]*$' || true)"

if [ -z "$discovered" ]; then
  echo "ERROR: app '$APP' has no discoverable Test* function in apps/$APP/..."
  echo "go test reported: $(echo "$test_list" | tr '\n' ' ')"
  echo "Add at least one Test* function to apps/$APP/container_test.go (see AGENTS.md)."
  exit 1
fi

echo "OK: app '$APP' has $(echo "$discovered" | wc -l | tr -d ' ') discoverable test(s) in apps/$APP/container_test.go"
exit 0
