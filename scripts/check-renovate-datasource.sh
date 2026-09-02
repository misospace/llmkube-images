#!/usr/bin/env bash
# check-renovate-datasource.sh — regression guard for issue #276.
#
# apps/godot-gate/Dockerfile once carried `# renovate: datasource=github-release
# depName=godotengine/godot-builds` above ARG GODOT_SHA512. The datasource name
# is wrong (Renovate's canonical name is `github-releases`, plural), so the
# custom regex manager in .renovaterc.json5 forwarded an unknown datasource and
# Renovate skipped the lookup. Worse, the hint was structurally misleading:
# Renovate tracks version strings, not sha512 checksums, so the line could
# never be auto-managed. The hint was deleted and the SHA documented as
# manually pinned; this check fails if a `datasource=github-release` (singular)
# hint is ever re-introduced.
#
# Usage: check-renovate-datasource.sh [path/to/Dockerfile]
# Defaults to apps/godot-gate/Dockerfile at the repo root.
set -euo pipefail

cd "$(dirname "$0")/.."

target="${1:-apps/godot-gate/Dockerfile}"

if [[ ! -f "$target" ]]; then
  echo "FAIL: $target not found" >&2
  exit 1
fi

# `github-release[^s]` matches the singular typo but not the canonical
# `github-releases` (the character class excludes the trailing 's').
if grep -nE 'datasource=github-release[^s]' "$target"; then
  echo "FAIL: $target contains a 'datasource=github-release' (singular) renovate hint." >&2
  echo "      Renovate's canonical datasource is 'github-releases' (plural), and" >&2
  echo "      GODOT_SHA512 is a manually pinned checksum that Renovate cannot" >&2
  echo "      update — see the comment above the ARG in apps/godot-gate/Dockerfile." >&2
  exit 1
fi

echo "OK: no 'datasource=github-release' (singular) renovate hint in $target"
