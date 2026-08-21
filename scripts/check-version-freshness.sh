#!/usr/bin/env bash
# check-version-freshness.sh — Compare docker-bake.hcl VERSION defaults against latest GitHub releases.
# Exit 0 if all versions are current; exit 1 if any are outdated (with details printed to stdout).
#
# NOTE: GITHUB_TOKEN is required for authenticated GitHub API access. Without it, unauthenticated
# requests are subject to a strict rate limit (~60 requests/hour), which will cause this script
# to fail with a non-zero exit code. Set GITHUB_TOKEN to a personal access token (no scopes needed)
# or use the CI-provided token. Example:
#   export GITHUB_TOKEN="ghp_..."
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Require GITHUB_TOKEN to avoid silent failures on rate-limited unauthenticated requests.
if [ -z "${GITHUB_TOKEN:-}" ]; then
  echo "ERROR: GITHUB_TOKEN is required for GitHub API access."
  echo "Unauthenticated requests are rate-limited (~60/hour) and will fail."
  echo "Set GITHUB_TOKEN to a personal access token (no scopes needed):"
  echo "  export GITHUB_TOKEN=\"ghp_...\""
  exit 1
fi

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
  renovate_line=""
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
        renovate_line="$line"
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

  # Extract the datasource from the renovate annotation (defaults to github-releases).
  # Only GitHub-releases datasources are in scope for this check: the script queries
  # api.github.com/repos/<depName>/releases/latest, which 404s for non-GitHub deps
  # such as docker-registry images (e.g. hexpm/elixir).
  datasource="$(echo "$renovate_line" | sed -n 's/.*datasource=\([^ ]*\).*/\1/p')"
  if [ -z "$datasource" ]; then
    datasource="github-releases"
  fi
  if [ "$datasource" != "github-releases" ] && [ "$datasource" != "github" ]; then
    echo "SKIP: $app_name — $dep_name (datasource='$datasource' is not a GitHub repo)"
    continue
  fi

  TOTAL=$((TOTAL + 1))

  # Fetch latest release tag from GitHub API
  latest_version=""
  # Fetch latest release with retry logic for rate limits (429) and transient errors.
  max_retries=3
  retry_delay=5
  response=""
  http_code=""
  body_file="$(mktemp)"
  for attempt in $(seq 1 $max_retries); do
    # Write the JSON body to a file and the status code to stdout so the two
    # are never mixed: `read` on "body<code>" breaks because the body has no
    # spaces, so the code never lands in its own variable.
    http_code="$(curl -sL -o "$body_file" -w "%{http_code}" \
      -H "Authorization: Bearer $GITHUB_TOKEN" \
      -H "Accept: application/vnd.github.v3+json" \
      "https://api.github.com/repos/$dep_name/releases/latest" 2>/dev/null)"
    # On rate limit (429), wait before retrying.
    if [ "$http_code" = "429" ]; then
      echo "WARN: Rate limited for $dep_name. Waiting ${retry_delay}s before retry (attempt $attempt/$max_retries)..."
      sleep "$retry_delay"
      continue
    fi
    # On other 4xx/5xx errors, don't retry — fail immediately.
    if [ "$http_code" = "403" ]; then
      echo "ERROR: GitHub API returned 403 (forbidden) for $dep_name."
      echo "Check that GITHUB_TOKEN is valid and has appropriate permissions."
      exit 1
    fi
    if [ "$http_code" = "404" ]; then
      echo "ERROR: GitHub API returned 404 (not found) for $dep_name."
      echo "Check that the depName in the renovate annotation is a valid GitHub repo."
      exit 1
    fi
    if [ "$http_code" -ge 500 ] 2>/dev/null; then
      echo "WARN: GitHub API returned HTTP $http_code for $dep_name (attempt $attempt/$max_retries)."
      sleep "$retry_delay"
      continue
    fi
    response="$(cat "$body_file")"
    break
  done
  rm -f "$body_file"

  if [ -z "$response" ]; then
    echo "ERROR: Failed to fetch latest release for $dep_name after $max_retries attempts."
    exit 1
  fi

  # Validate that the response contains tag_name before parsing.
  if ! echo "$response" | grep -q '"tag_name"'; then
    echo "ERROR: Unexpected GitHub API response for $dep_name (HTTP $http_code):"
    echo "$response" | head -5
    exit 1
  fi

  latest_version="$(echo "$response" | grep tag_name | head -1 | sed -n 's/.*"tag_name"\s*:\s*"\([^"]*\)".*/\1/p')"

  # Strip leading 'v' if present for comparison
  latest_clean="${latest_version#v}"
  current_clean="${current_version#v}"

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
