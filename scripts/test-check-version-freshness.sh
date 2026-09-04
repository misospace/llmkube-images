#!/usr/bin/env bash
#
# test-check-version-freshness.sh — hermetic tests for check-version-freshness.sh.
#
# Stubs `curl` so no network calls are made. Verifies:
#   1. OK case: bake default matches the upstream latest.
#   2. SKIP case: docker-sourced deps are skipped.
#   3. Rollback case: current is AHEAD of latest (Renovate rolled back the
#      upstream recommendation) — must NOT be flagged OUTDATED.
#   4. Composite-tag case: the script picks the correct newer tag by
#      comparing the leading semver prefix, not by `sort -V | tail -1`.
#   5. Composite-tag drift: equal semver prefix, differing suffix —
#      reported as WARN, not OUTDATED.
#
# Run: bash scripts/test-check-version-freshness.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/check-version-freshness.sh"

PASS=0
FAIL=0

pass() { printf 'PASS: %s\n' "$1"; PASS=$((PASS + 1)); }
fail() { printf 'FAIL: %s\n' "$1"; FAIL=$((FAIL + 1)); }

# --- test 1: OK case -------------------------------------------------------
# Bake default matches upstream latest → no OUTDATED, exit 0.

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

mkdir -p "$tmpdir/bin" "$tmpdir/apps/test-app"

# Stub curl: return a fixed latest release for any github-releases URL.
cat > "$tmpdir/bin/curl" <<'STUB'
#!/usr/bin/env bash
# Stub: return a fake GitHub releases/latest JSON response.
for arg in "$@"; do
    case "$arg" in
        *hexpm/hex*)
            printf '{"tag_name":"v0.9.0"}\n'
            exit 0
            ;;
        *erlang/rebar3*)
            printf '{"tag_name":"v3.16.0"}\n'
            exit 0
            ;;
    esac
done
printf '{"tag_name":"v0.9.0"}\n'
STUB
chmod +x "$tmpdir/bin/curl"

cat > "$tmpdir/apps/test-app/docker-bake.hcl" <<'HCL'
variable "HEX_VERSION" {
  // renovate: datasource=github-releases depName=hexpm/hex
  default = "0.9.0"
}

variable "REBAR_VERSION" {
  // renovate: datasource=github-releases depName=erlang/rebar3
  default = "3.16.0"
}

variable "ELIXIR_VERSION" {
  // renovate: datasource=docker depName=hexpm/elixir
  default = "1.19.5"
}
HCL

exit_code=0
output="$(PATH="$tmpdir/bin:$PATH" REPO_ROOT="$tmpdir" DRY_RUN=true bash "$SCRIPT" 2>&1)" || exit_code=$?

if [ "$exit_code" -eq 0 ]; then
    pass "OK case: exit 0 when bake defaults match upstream"
else
    fail "OK case: expected exit 0, got $exit_code"
fi

if printf '%s' "$output" | grep -q 'OUTDATED'; then
    fail "OK case: no OUTDATED lines expected"
else
    pass "OK case: no OUTDATED lines"
fi

if printf '%s' "$output" | grep -q 'SKIP: test-app — hexpm/elixir'; then
    pass "SKIP case: docker-sourced dep is skipped"
else
    fail "SKIP case: docker-sourced dep should be skipped"
fi

# --- test 2: rollback case -------------------------------------------------
# current=0.9.0, latest=0.8.0 (Renovate rolled back the upstream
# recommendation). The bake default is AHEAD of upstream, so it must NOT be
# flagged OUTDATED.

tmpdir2="$(mktemp -d)"
mkdir -p "$tmpdir2/bin" "$tmpdir2/apps/rollback-app"

cat > "$tmpdir2/bin/curl" <<'STUB'
#!/usr/bin/env bash
for arg in "$@"; do
    case "$arg" in
        *hexpm/hex*)
            printf '{"tag_name":"v0.8.0"}\n'
            exit 0
            ;;
    esac
done
printf '{"tag_name":"v0.8.0"}\n'
STUB
chmod +x "$tmpdir2/bin/curl"

cat > "$tmpdir2/apps/rollback-app/docker-bake.hcl" <<'HCL'
variable "HEX_VERSION" {
  // renovate: datasource=github-releases depName=hexpm/hex
  default = "0.9.0"
}
HCL

exit_code2=0
output2="$(PATH="$tmpdir2/bin:$PATH" REPO_ROOT="$tmpdir2" DRY_RUN=true bash "$SCRIPT" 2>&1)" || exit_code2=$?

if [ "$exit_code2" -eq 0 ]; then
    pass "rollback case: exit 0 when current is ahead of latest"
else
    fail "rollback case: expected exit 0, got $exit_code2"
fi

if printf '%s' "$output2" | grep -q 'OUTDATED'; then
    fail "rollback case: current=0.9.0 latest=0.8.0 must NOT be flagged OUTDATED"
else
    pass "rollback case: current=0.9.0 latest=0.8.0 not flagged OUTDATED"
fi

if printf '%s' "$output2" | grep -q 'OK: rollback-app — hexpm/hex is at 0.9.0 (upstream latest: v0.8.0)'; then
    pass "rollback case: reported as OK"
else
    fail "rollback case: expected OK line, got: $(printf '%s' "$output2" | grep 'rollback-app' || true)"
fi

# --- test 3: composite-tag case --------------------------------------------
# current=1.20.3-erlang-29.0.5-ubuntu-resolute-20260811.1,
# latest=1.20.4-erlang-29.0.5-ubuntu-resolute-20260824.1.
# The leading semver prefix (1.20.4 > 1.20.3) proves supersession → OUTDATED.

tmpdir3="$(mktemp -d)"
mkdir -p "$tmpdir3/bin" "$tmpdir3/apps/composite-app"

cat > "$tmpdir3/bin/curl" <<'STUB'
#!/usr/bin/env bash
for arg in "$@"; do
    case "$arg" in
        *example/composite*)
            printf '{"tag_name":"1.20.4-erlang-29.0.5-ubuntu-resolute-20260824.1"}\n'
            exit 0
            ;;
    esac
done
printf '{"tag_name":"1.20.4-erlang-29.0.5-ubuntu-resolute-20260824.1"}\n'
STUB
chmod +x "$tmpdir3/bin/curl"

cat > "$tmpdir3/apps/composite-app/docker-bake.hcl" <<'HCL'
variable "COMPOSITE_VERSION" {
  // renovate: datasource=github-releases depName=example/composite
  default = "1.20.3-erlang-29.0.5-ubuntu-resolute-20260811.1"
}
HCL

exit_code3=0
output3="$(PATH="$tmpdir3/bin:$PATH" REPO_ROOT="$tmpdir3" DRY_RUN=true bash "$SCRIPT" 2>&1)" || exit_code3=$?

if [ "$exit_code3" -eq 1 ]; then
    pass "composite case: exit 1 when upstream supersedes the bake default"
else
    fail "composite case: expected exit 1, got $exit_code3"
fi

if printf '%s' "$output3" | grep -q 'OUTDATED: composite-app — example/composite is at 1.20.3-erlang-29.0.5-ubuntu-resolute-20260811.1, upstream latest is 1.20.4-erlang-29.0.5-ubuntu-resolute-20260824.1'; then
    pass "composite case: correct newer tag picked (1.20.4 > 1.20.3)"
else
    fail "composite case: expected OUTDATED with correct newer tag, got: $(printf '%s' "$output3" | grep -E 'OUTDATED|composite-app' || true)"
fi

# --- test 4: composite-tag drift (equal prefix, differing suffix) ----------
# current and latest share the same semver prefix but differ in the suffix
# (e.g. upstream dropped the date component). Not a proven supersession →
# WARN, not OUTDATED.

tmpdir4="$(mktemp -d)"
mkdir -p "$tmpdir4/bin" "$tmpdir4/apps/drift-app"

cat > "$tmpdir4/bin/curl" <<'STUB'
#!/usr/bin/env bash
for arg in "$@"; do
    case "$arg" in
        *example/composite*)
            printf '{"tag_name":"1.20.3-erlang-29.0.5-ubuntu-resolute"}\n'
            exit 0
            ;;
    esac
done
printf '{"tag_name":"1.20.3-erlang-29.0.5-ubuntu-resolute"}\n'
STUB
chmod +x "$tmpdir4/bin/curl"

cat > "$tmpdir4/apps/drift-app/docker-bake.hcl" <<'HCL'
variable "COMPOSITE_VERSION" {
  // renovate: datasource=github-releases depName=example/composite
  default = "1.20.3-erlang-29.0.5-ubuntu-resolute-20260811.1"
}
HCL

exit_code4=0
output4="$(PATH="$tmpdir4/bin:$PATH" REPO_ROOT="$tmpdir4" DRY_RUN=true bash "$SCRIPT" 2>&1)" || exit_code4=$?

if [ "$exit_code4" -eq 0 ]; then
    pass "drift case: exit 0 (WARN is not a freshness failure)"
else
    fail "drift case: expected exit 0, got $exit_code4"
fi

if printf '%s' "$output4" | grep -q 'OUTDATED'; then
    fail "drift case: equal-prefix composite drift must NOT be flagged OUTDATED"
else
    pass "drift case: equal-prefix composite drift not flagged OUTDATED"
fi

if printf '%s' "$output4" | grep -q 'WARN: drift-app — example/composite is at 1.20.3-erlang-29.0.5-ubuntu-resolute-20260811.1, upstream latest is 1.20.3-erlang-29.0.5-ubuntu-resolute (composite-tag drift'; then
    pass "drift case: reported as WARN"
else
    fail "drift case: expected WARN line, got: $(printf '%s' "$output4" | grep 'drift-app' || true)"
fi

# --- test 5: depName injection guard ---------------------------------------
# A malicious or malformed renovate comment could set depName to a value
# that begins with `-` (e.g. `-K @/etc/passwd`), which curl would interpret
# as a flag rather than a URL path component. The script must reject such
# depName values without invoking curl, and the bake default must be
# skipped (not flagged OUTDATED, not crashed).

tmpdir5="$(mktemp -d)"
mkdir -p "$tmpdir5/bin" "$tmpdir5/apps/inject-app"

cat > "$tmpdir5/bin/curl" <<'STUB'
#!/usr/bin/env bash
# If the script reaches curl with a malicious depName, fail loudly so the
# regression test fails rather than silently passing.
printf 'CURL-INVOKED-WITH-ARGS: %s\n' "$*" >&2
exit 99
STUB
chmod +x "$tmpdir5/bin/curl"

cat > "$tmpdir5/apps/inject-app/docker-bake.hcl" <<'HCL'
variable "EVIL_VERSION" {
  // renovate: datasource=github-releases depName=-K@/etc/passwd
  default = "1.0.0"
}
HCL

exit_code5=0
output5="$(PATH="$tmpdir5/bin:$PATH" REPO_ROOT="$tmpdir5" DRY_RUN=true bash "$SCRIPT" 2>&1)" || exit_code5=$?

if [ "$exit_code5" -eq 0 ]; then
    pass "inject case: exit 0 (invalid depName is skipped, not crashed)"
else
    fail "inject case: expected exit 0, got $exit_code5"
fi

if printf '%s' "$output5" | grep -q 'CURL-INVOKED-WITH-ARGS'; then
    fail "inject case: curl must NOT be invoked with a malicious depName (got: $(printf '%s' "$output5" | grep CURL-INVOKED-WITH-ARGS))"
else
    pass "inject case: curl not invoked for invalid depName"
fi

if printf '%s' "$output5" | grep -q 'OUTDATED'; then
    fail "inject case: invalid depName must not be flagged OUTDATED"
else
    pass "inject case: invalid depName skipped, no OUTDATED line"
fi

if printf '%s' "$output5" | grep -q 'invalid depName'; then
    pass "inject case: invalid depName warning emitted"
else
    fail "inject case: expected invalid depName warning, got: $(printf '%s' "$output5" | grep -E 'inject-app|warn|WARN' || true)"
fi

# --- summary ---------------------------------------------------------------
echo ""
echo "Results: $PASS passed, $FAIL failed"

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
