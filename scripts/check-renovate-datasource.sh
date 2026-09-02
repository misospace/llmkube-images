#!/usr/bin/env bash
#
# check-renovate-datasource.sh — regression guard for the godot-gate
# GODOT_SHA512 renovate hint (issue #278).
#
# The old comment above ARG GODOT_SHA512 used `datasource=github-release`
# (singular), which is not a valid Renovate datasource (the canonical name is
# `github-releases`). The custom regex manager in .renovaterc.json5 captured
# the typo and forwarded it, so Renovate logged an "unknown datasource"
# warning and silently skipped the lookup. The SHA is a manually-pinned
# checksum (sha512 digests are not part of GitHub release metadata), so no
# renovate hint belongs there at all — see apps/godot-gate/Dockerfile.
#
# This check greps apps/godot-gate/Dockerfile for the singular form and fails
# if it is ever re-introduced.
#
# Usage:
#   scripts/check-renovate-datasource.sh [path-to-Dockerfile]
#
# Exit codes:
#   0 — no singular `datasource=github-release` hint found
#   1 — hint found (regression)
#   2 — usage / file error

set -euo pipefail

DOCKERFILE="${1:-apps/godot-gate/Dockerfile}"

if [[ ! -f "$DOCKERFILE" ]]; then
  echo "ERROR: Dockerfile not found: $DOCKERFILE" >&2
  exit 2
fi

# `datasource=github-release` not followed by `s` (i.e. not the valid
# `github-releases`). -E for ERE, -n for line numbers, -H to name the file.
matches="$(grep -En 'datasource=github-release[^s]' "$DOCKERFILE" || true)"

if [[ -n "$matches" ]]; then
  echo "FAIL: singular 'datasource=github-release' renovate hint found in $DOCKERFILE:" >&2
  echo "$matches" >&2
  echo "" >&2
  echo "Renovate's canonical datasource is 'github-releases' (plural), and a" >&2
  echo "sha512 checksum can never be auto-managed by Renovate anyway. Remove" >&2
  echo "the hint — see the comment above ARG GODOT_SHA512." >&2
  exit 1
fi

echo "OK: no singular 'datasource=github-release' renovate hint in $DOCKERFILE"
exit 0
