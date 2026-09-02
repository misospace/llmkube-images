#!/usr/bin/env bash
# check-renovate-datasources.sh — Regression check for issue #277.
#
# apps/godot-gate/Dockerfile once carried a renovate hint above GODOT_SHA512
# with the typo'd datasource `github-release` (singular). Renovate's canonical
# name is `github-releases` (plural), so the hint was dead weight — and the
# hint was structurally misleading anyway, because sha512 checksums are not
# part of GitHub release metadata and Renovate cannot auto-update them.
#
# This check fails if any Dockerfile under apps/ carries a renovate hint with
# the singular `github-release` datasource, so the typo cannot silently come
# back. GODOT_SHA512 must stay a manually-pinned checksum (see the comment in
# apps/godot-gate/Dockerfile and the matching pin in apps/llmkube-coder/Dockerfile).
#
# Usage: check-renovate-datasources.sh [ROOT]
#   ROOT defaults to the repository root (parent of this script's directory).
set -euo pipefail

ROOT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

if [ ! -d "$ROOT/apps" ]; then
  echo "ERROR: no apps/ directory under $ROOT" >&2
  exit 1
fi

fail=0

# `datasource=github-release` not followed by `s` — i.e. the singular typo.
# POSIX ERE has no lookahead, so match the singular form explicitly:
# `github-release` followed by a non-`s` character or end-of-line.
while IFS= read -r -d '' file; do
  if grep -nE 'datasource=github-release([^s]|$)' "$file"; then
    echo "ERROR: $file: renovate hint uses the singular datasource 'github-release' (issue #277)." >&2
    echo "       Renovate's canonical name is 'github-releases' (plural), and sha512" >&2
    echo "       checksums cannot be auto-updated by Renovate at all — keep" >&2
    echo "       GODOT_SHA512 manually pinned and drop the renovate hint." >&2
    fail=1
  fi
done < <(find "$ROOT/apps" -name Dockerfile -print0)

if [ "$fail" -ne 0 ]; then
  exit 1
fi

echo "check-renovate-datasources: OK (no singular 'github-release' datasource hints)"
