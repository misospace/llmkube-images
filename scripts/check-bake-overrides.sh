#!/usr/bin/env bash
# check-bake-overrides.sh — Validate `docker buildx bake --set` override keys.
#
# Usage: check-bake-overrides.sh [repo-root]
#
# Anything handed to `docker buildx bake --set` (including the `set:` list of
# docker/bake-action) is parsed by bake's override parser, NOT by
# `docker buildx build`. Bake only accepts the target keys listed in
# VALID_KEYS below; every other key aborts the whole run at parse time with
# `ERROR: unknown key: <key>` before a single build step starts.
#
# The trap: `--provenance` and `--sbom` are build flags, so they look like
# plausible bake overrides. `--set *.provenance=false` is what failed the
# Release workflow's `Build (linux/arm64)` job twice on the default branch
# (issue #402); the earlier `--set *.sbom=false` failure (issue #396) was the
# same mistake. To disable an attestation in bake, use the `attest` key:
#   *.attest=type=provenance,disabled=true
#
# Exit codes:
#   0 — every override key in every workflow is a valid bake key
#   1 — at least one invalid bake override key was found
set -euo pipefail

REPO_ROOT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

# The keys bake's Target.AddOverrides switch accepts (docker/buildx bake/bake.go).
VALID_KEYS="annotations args attest cache-from cache-to call context contexts dockerfile entitlements extra-hosts labels load network no-cache no-cache-filter output platform policy pull push secrets shm-size ssh tags target ulimits"

if [ ! -d "$REPO_ROOT/.github/workflows" ]; then
  echo "ERROR: $REPO_ROOT/.github/workflows not found"
  exit 1
fi

failures=0

# Composite actions live one level deeper (.github/actions/<name>/action.yaml),
# so walk both trees with find rather than a single glob.
while IFS= read -r file; do
  # Only scan files that actually invoke a bake step.
  grep -qE 'buildx bake|bake-action' "$file" || continue

  # A bake override line as it appears inside a bake-action `set: |` block:
  # leading whitespace, the `*` target glob, a dot, then the key. Only
  # `*`-globbed overrides are scanned, which is the spelling every bake
  # override in this repository uses.
  while IFS= read -r line; do
    key="${line#*.}"
    key="${key%%=*}"
    key="${key%%.*}"
    key="$(printf '%s' "$key" | tr -d '[:space:]')"
    [ -n "$key" ] || continue

    # Word splitting is intended: VALID_KEYS is a space-separated list.
    # shellcheck disable=SC2086
    if ! printf '%s\n' $VALID_KEYS | grep -qxF "$key"; then
      echo "FAIL: ${file#"$REPO_ROOT"/} uses invalid bake override key '$key'"
      echo "      Valid bake keys: $VALID_KEYS"
      echo "      --provenance/--sbom are build flags; in bake use"
      echo "      '*.attest=type=provenance,disabled=true' instead."
      failures=$((failures + 1))
    fi
  done < <(grep -nE '^[[:space:]]*\*\.[a-zA-Z0-9_-]' "$file" | sed 's/^[0-9]*://')
done < <(find "$REPO_ROOT/.github/workflows" "$REPO_ROOT/.github/actions" \
  -type f \( -name '*.yaml' -o -name '*.yml' \) 2>/dev/null | sort)

if [ "$failures" -ne 0 ]; then
  echo
  echo "Results: $failures invalid bake override key(s)"
  exit 1
fi

echo "All bake override keys are valid."
