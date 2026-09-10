#!/usr/bin/env bash
# Regression test for issue #389: the Build job in app-builder.yaml must not
# pass buildx *flags* through the bake-action's `set:` block.
#
# `provenance` and `sbom` are buildx flags (shorthands for
# `--set=*.attest=type=provenance` / `type=sbom`), not bake target keys.
# Putting `*.provenance=false` in the `set:` block makes `docker buildx bake`
# reject the whole definition at parse time with
#   ERROR: unknown key: provenance
# before any build starts, so the release never rebuilds the image and the
# scheduled Vulnerability Scan keeps failing on the stale :rolling digest.
#
# The correct mechanism is the bake-action's top-level `provenance` / `sbom`
# inputs, which map to the `--provenance` / `--sbom` buildx flags.
#
# This test extracts the `set:` block of the bake-action invocation and fails
# if it reintroduces a `*.provenance=` or `*.sbom=` override.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

WORKFLOW=".github/workflows/app-builder.yaml"

failures=0

if [[ ! -f "$WORKFLOW" ]]; then
  echo "FAIL: $WORKFLOW is missing"
  exit 1
fi

# Collect the body of the `set: |` block: the lines that follow it at a deeper
# indentation than the `set:` key itself.
set_block="$(awk '
  /^[ \t]*set: *\|/ {
    collecting = 1
    match($0, /^[ \t]*/)
    base_indent = RLENGTH
    next
  }
  collecting {
    if ($0 ~ /^[ \t]*$/) { next }
    match($0, /^[ \t]*/)
    if (RLENGTH <= base_indent) {
      collecting = 0
    } else {
      sub(/^[ \t]+/, "")
      print
    }
  }
' "$WORKFLOW")"

if [[ -z "$set_block" ]]; then
  echo "FAIL: could not find a 'set: |' block in $WORKFLOW"
  exit 1
fi

# The buildx flags that must not appear as bake target keys in the set block.
for key in provenance sbom; do
  if printf '%s\n' "$set_block" | grep -qE "^\*\.${key}="; then
    echo "FAIL: $WORKFLOW set: block passes buildx flag '*.${key}=' as a bake key"
    printf '%s\n' "$set_block" | grep -nE "^\*\.${key}=" | sed 's/^/  /'
    failures=$((failures + 1))
  else
    echo "PASS: $WORKFLOW set: block has no '*.${key}=' override"
  fi
done

if (( failures > 0 )); then
  echo
  echo "Results: $failures failed"
  exit 1
fi

echo
echo "All tests passed!"
