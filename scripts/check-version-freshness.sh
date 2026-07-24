#!/usr/bin/env bash
# check-version-freshness.sh — Compare docker-bake.hcl VERSION defaults against latest GitHub releases.
# Exit 0 if all versions are current; exit 1 if any are outdated (with details printed to stdout).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

OUTDATED=0
TOTAL=0

# Collect all docker-bake.hcl files under apps/*/
for bake_file in "$REPO_ROOT"/apps/*/docker-bake.hcl; do
  [ -f "$bake_file" ] || continue

  app_name="$(basename "$(dirname "$bake_file")")"

  # Extract the depName from the renovate comment preceding the VERSION variable's default.
  # Pattern: "// renovate: datasource=github-releases depName=<owner/repo>"
  dep_name=""
  current_version=""
  in_version_var=0

  while IFS= read -r line; do
    # Detect start of VERSION variable block
    if echo "$line" | grep -qE '^\s*variable\s+"VERSION"\s*\{'; then
      in_version_var=1
      continue
    fi

    # If we are inside the VERSION variable block
    if [ "$in_version_var" -eq 1 ]; then
      # Check for renovate comment with depName
      if echo "$line" | grep -qE '//\s*renovate:.*depName='; then
        dep_name="$(echo "$line" | sed -n 's/.*depName=\([^ ]*\).*/\1/p')"
      fi

      # Check for default value
      if echo "$line" | grep -qE '^\s*default\s*='; then
        current_version="$(echo "$line" | sed -n 's/.*default\s*=\s*"\([^"]*\)".*/\1/p')"
      fi

      # End of variable block
      if echo "$line" | grep -qE '^\s*\}'; then
        in_version_var=0
      fi
    fi
  done < "$bake_file"

  # Skip if we couldn't extract depName or version
  if [ -z "$dep_name" ] || [ -z "$current_version" ]; then
    echo "WARN: Could not parse VERSION/depName from $bake_file (depName='$dep_name', version='$current_version')"
    continue
  fi

  TOTAL=$((TOTAL + 1))

  # Fetch latest release tag from GitHub API
  latest_version=""
  if [ -n "${GITHUB_TOKEN:-}" ]; then
    latest_version="$(curl -sL \
      -H "Authorization: Bearer $GITHUB_TOKEN" \
      -H "Accept: application/vnd.github.v3+json" \
      "https://api.github.com/repos/$dep_name/releases/latest" \
      | grep '"tag_name"' | head -1 | sed -n 's/.*"tag_name"\s*:\s*"\([^"]*\)".*/\1/p')"
  else
    latest_version="$(curl -sL \
      -H "Accept: application/vnd.github.v3+json" \
      "https://api.github.com/repos/$dep_name/releases/latest" \
      | grep '"tag_name"' | head -1 | sed -n 's/.*"tag_name"\s*:\s*"\([^"]*\)".*/\1/p')"
  fi

  # Strip leading 'v' if present for comparison
  latest_clean="$(echo "$latest_version" | sed 's/^v//')"
  current_clean="$(echo "$current_version" | sed 's/^v//')"

  if [ -z "$latest_clean" ]; then
    echo "WARN: Could not fetch latest release for $dep_name (app: $app_name)"
    continue
  fi

  # Compare versions using sort -V (version sort)
  newer="$(printf '%s\n%s\n' "$current_clean" "$latest_clean" | sort -V | tail -1)"

  if [ "$newer" = "$latest_clean" ] && [ "$current_clean" != "$latest_clean" ]; then
    echo "OUTDATED: $app_name — $dep_name: current=$current_version, latest=$latest_version"
    OUTDATED=$((OUTDATED + 1))
  else
    echo "OK: $app_name — $dep_name: current=$current_version, latest=$latest_version"
  fi
done

echo ""
echo "Summary: checked $TOTAL apps, $OUTDATED outdated."

if [ "$OUTDATED" -gt 0 ]; then
  exit 1
fi
exit 0
