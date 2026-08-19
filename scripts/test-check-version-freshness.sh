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

# Test 4: docker-registry datasources are skipped (no GitHub API call), github-releases still checked.
# Regression for issue #192: elixir-gate's `datasource=docker depName=hexpm/elixir` made the
# script curl api.github.com/repos/hexpm%2Felixir, get a 404, and fail the whole gate.
echo "--- Test: docker-registry datasource is skipped ---"
tmp_repo=$(mktemp -d)
trap 'rm -rf "$tmp_repo"' EXIT
mkdir -p "$tmp_repo/scripts" "$tmp_repo/apps/elixir-gate" "$tmp_repo/apps/ollama"
cp "$CHECK_SCRIPT" "$tmp_repo/scripts/check-version-freshness.sh"

cat > "$tmp_repo/apps/elixir-gate/docker-bake.hcl" <<'EOF'
variable "VERSION" {
  type    = string
  default = "1.18.4"
  // renovate: datasource=docker depName=hexpm/elixir
}
EOF

cat > "$tmp_repo/apps/ollama/docker-bake.hcl" <<'EOF'
variable "VERSION" {
  type    = string
  default = "0.9.0"
  // renovate: datasource=github-releases depName=ollama/ollama
}
EOF

# Stub curl so the test is hermetic: report HTTP 200 with a fake latest release.
mkdir -p "$tmp_repo/bin"
cat > "$tmp_repo/bin/curl" <<'EOF'
#!/usr/bin/env bash
# Minimal curl stub honoring -o <file> and -w "%{http_code}":
# writes the JSON body to the -o file and prints the status code to stdout.
out_file=""
while [ $# -gt 0 ]; do
  case "$1" in
    -o) out_file="$2"; shift 2 ;;
    *) shift ;;
  esac
done
if [ -n "$out_file" ]; then
  printf '%s' '{"tag_name":"v0.9.0"}' > "$out_file"
fi
printf '%s' '200'
EOF
chmod +x "$tmp_repo/bin/curl"

set +e
output=$(PATH="$tmp_repo/bin:$PATH" GITHUB_TOKEN="dummy" bash "$tmp_repo/scripts/check-version-freshness.sh" 2>&1)
exit_code=$?
set -e

assert_exit_code "docker-sourced dep does not fail the gate" "0" "$exit_code"
assert_output_contains "docker-sourced dep is skipped" "SKIP: elixir-gate" "$output"
assert_output_contains "github-releases dep is still checked" "OK: ollama" "$output"
assert_output_contains "summary counts only checked apps" "checked 1 apps" "$output"

# Summary
echo ""
echo "Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
echo "All tests passed!"
