#!/usr/bin/env bash
#
# check-version-freshness.sh — weekly freshness check for bake defaults.
#
# Scans apps/*/docker-bake.hcl for `// renovate:` comments, queries the
# upstream datasource for the latest release, and reports any bake default
# that is behind it. Designed to run in CI (GitHub Actions) and to open a
# GitHub issue when stale entries are found.
#
# Comparison policy (do not reintroduce a naive `sort -V | tail -1` pick):
#   OUTDATED is reported ONLY when the upstream release genuinely
#   supersedes the bake default, i.e. when the upstream version is
#   STRICTLY GREATER than the current one.
#
#   * Semver tags (major.minor.patch, optional leading v, optional
#     pre-release/build suffix) are compared numerically per component.
#     A Renovate-initiated rollback (latest < current) is therefore NOT
#     flagged: the bake default is ahead of the upstream recommendation,
#     which is a Renovate concern, not a freshness failure.
#   * Composite / non-semver tags (e.g.
#     1.20.3-erlang-29.0.5-ubuntu-resolute-20260811.1) are compared on
#     their leading semver prefix. When the prefixes are equal the
#     suffixes are compared lexicographically and the result is reported
#     as WARN (not OUTDATED), because a suffix-shape change upstream
#     (e.g. dropping the date component) is not a proven supersession.
#   * A `versioning=` hint in the renovate comment (Renovate's
#     `versioning` template: semver, semver-coerced, regex, loose) is
#     honoured: semver / semver-coerced route to the numeric comparator;
#     any other value routes to the composite fallback.
#
# Exit codes:
#   0 — all bake defaults are up to date (or skipped)
#   1 — one or more OUTDATED entries found (a GitHub issue is opened)
#   2 — usage / environment error

set -euo pipefail

# REPO_ROOT can be overridden (used by the hermetic test suite); by default
# it is the parent of this script's directory.
REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
GITHUB_REPO="${GITHUB_REPO:-misospace/llmkube-images}"
GITHUB_TOKEN="${GITHUB_TOKEN:-}"
DRY_RUN="${DRY_RUN:-false}"

# --- helpers ---------------------------------------------------------------

log()  { printf '%s\n' "$*"; }
warn() { printf 'WARN: %s\n' "$*" >&2; }

# curl with GitHub auth when a token is available.
gh_curl() {
    if [ -n "$GITHUB_TOKEN" ]; then
        curl -fsSL -H "Authorization: Bearer $GITHUB_TOKEN" "$@"
    else
        curl -fsSL "$@"
    fi
}

# --- version comparison ----------------------------------------------------
#
# is_semver TAG
#   True when TAG is a plain semver version: optional leading v,
#   MAJOR.MINOR.PATCH, optional -prerelease / +build suffix.
#   The pre-release portion must be hyphen-free (alphanumeric + dots,
#   e.g. rc.1, 0.3.7, alpha.2). This is the documented heuristic that
#   keeps composite tags like
#   1.20.3-erlang-29.0.5-ubuntu-resolute-20260811.1 (whose pre-release
#   embeds a hyphenated word-version) out of the semver path and into
#   the composite fallback.
is_semver() {
    [[ "$1" =~ ^v?([0-9]+)\.([0-9]+)\.([0-9]+)(-([0-9A-Za-z.]+))?(\\+([0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*))?$ ]]
}

# semver_gt A B
#   True when semver A is strictly greater than semver B.
#   Numeric per-component comparison of major/minor/patch; a pre-release
#   tag sorts below its release (1.0.0-rc.1 < 1.0.0), and two pre-releases
#   on the same core are compared by their pre-release identifiers.
semver_gt() {
    local a="${1#v}" b="${2#v}"
    local a_pre="" b_pre=""
    [[ "$a" == *-* ]] && a_pre="${a#*-}"
    [[ "$b" == *-* ]] && b_pre="${b#*-}"
    a="${a%%[-+]*}"; b="${b%%[-+]*}"
    local a_maj a_min a_pat b_maj b_min b_pat
    IFS='.' read -r a_maj a_min a_pat _ <<< "$a"
    IFS='.' read -r b_maj b_min b_pat _ <<< "$b"
    if [ "$a_maj" -ne "$b_maj" ]; then [ "$a_maj" -gt "$b_maj" ]; return; fi
    if [ "$a_min" -ne "$b_min" ]; then [ "$a_min" -gt "$b_min" ]; return; fi
    if [ "$a_pat" -ne "$b_pat" ]; then [ "$a_pat" -gt "$b_pat" ]; return; fi
    # Equal core: a pre-release sorts below the plain release.
    if [ -n "$a_pre" ] && [ -z "$b_pre" ]; then return 1; fi
    if [ -z "$a_pre" ] && [ -n "$b_pre" ]; then return 0; fi
    # Both pre-releases (or neither): compare the identifiers.
    [ "$a_pre" != "$b_pre" ] && [ "$a_pre" > "$b_pre" ]
}

# semver_core_numeric TAG
#   True when the leading MAJOR.MINOR.PATCH of TAG is all-numeric. Guards
#   semver_gt against non-semver input (which would otherwise abort the
#   script under set -e in the arithmetic comparisons).
semver_core_numeric() {
    local p
    p="$(semver_prefix "$1")"
    [ -n "$p" ]
}

# semver_prefix TAG
#   Leading MAJOR.MINOR.PATCH of a composite tag, or empty when the tag
#   does not start with a semver core (e.g. "ubuntu-resolute-20260811.1").
semver_prefix() {
    local p=""
    [[ "$1" =~ ^v?([0-9]+\.[0-9]+\.[0-9]+) ]] && p="${BASH_REMATCH[1]}"
    printf '%s' "$p"
}

# compare_versions CURRENT LATEST
#   Prints exactly one of:
#     OUTDATED  — upstream strictly supersedes the bake default
#     WARN      — composite-tag drift that is not a proven supersession
#     OK        — bake default is current, ahead (rollback), or equal
compare_versions() {
    local current="$1" latest="$2"
    if is_semver "$current" && is_semver "$latest"; then
        if semver_gt "$latest" "$current"; then
            printf 'OUTDATED'
        else
            printf 'OK'
        fi
        return
    fi
    # Composite / non-semver fallback: compare the leading semver prefix
    # numerically; equal prefixes fall back to a lexicographic suffix
    # compare reported as WARN (see the policy note in the header).
    local cp lp
    cp="$(semver_prefix "$current")"
    lp="$(semver_prefix "$latest")"
    if [ -n "$cp" ] && [ -n "$lp" ]; then
        if [ "$cp" != "$lp" ] && semver_gt "$lp" "$cp"; then
            printf 'OUTDATED'
            return
        fi
    fi
    if [ "$current" != "$latest" ]; then
        printf 'WARN'
    else
        printf 'OK'
    fi
}

# --- main ------------------------------------------------------------------

outdated_count=0
warn_count=0
checked_count=0
skipped_count=0
outdated_lines=""

log "Scanning $REPO_ROOT/apps/*/docker-bake.hcl for renovate-managed bake defaults..."
log ""

for bake_file in "$REPO_ROOT"/apps/*/docker-bake.hcl; do
    [ -f "$bake_file" ] || continue
    app="$(basename "$(dirname "$bake_file")")"

    # Extract renovate comments and the bake default that follows them.
    # Format: // renovate: datasource=... depName=... [versioning=...]
    #          default = "..."
    while IFS= read -r renovate_line; do
        # Normalise leading whitespace so the awk match below works.
        renovate_line="$(printf '%s' "$renovate_line" | sed 's/^[[:space:]]*//')"
        # Pull out the fields.
        datasource="$(printf '%s' "$renovate_line" | sed -n 's/.*datasource=\([^ ]*\).*/\1/p')"
        dep_name="$(printf '%s' "$renovate_line" | sed -n 's/.*depName=\([^ ]*\).*/\1/p')"
        versioning="$(printf '%s' "$renovate_line" | sed -n 's/.*versioning=\([^ ]*\).*/\1/p')"

        # The bake default is the next `default = "..."` line after the comment.
        # grep -n prefixes the line number, so match on the comment text
        # itself (whitespace-tolerant) rather than the whole prefixed line.
        current="$(awk -v line="$renovate_line" '
            { sub(/^[[:space:]]+/, "") }
            index($0, line) { found = 1; next }
            found && /default[[:space:]]*=[[:space:]]*"/ {
                gsub(/.*default[[:space:]]*=[[:space:]]*"/, "")
                gsub(/".*/, "")
                print
                exit
            }
        ' "$bake_file")"

        if [ -z "$current" ]; then
            warn "$app: no bake default found after renovate comment for $dep_name"
            continue
        fi

        # Skip docker-sourced deps: their "latest" is a moving tag, not a
        # release, so a freshness comparison is meaningless.
        if [ "$datasource" = "docker" ]; then
            log "SKIP: $app — $dep_name (docker-sourced dep, no release comparison)"
            skipped_count=$((skipped_count + 1))
            continue
        fi

        # Only github-releases is supported for now.
        if [ "$datasource" != "github-releases" ]; then
            log "SKIP: $app — $dep_name (unsupported datasource: $datasource)"
            skipped_count=$((skipped_count + 1))
            continue
        fi

        # Query the upstream for the latest release tag.
        latest="$(gh_curl "https://api.github.com/repos/${dep_name}/releases/latest" 2>/dev/null \
            | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)" || latest=""

        if [ -z "$latest" ]; then
            warn "$app: could not determine latest release for $dep_name (skipping)"
            skipped_count=$((skipped_count + 1))
            continue
        fi

        # Strip a leading v for comparison.
        current_clean="${current#v}"
        latest_clean="${latest#v}"

        checked_count=$((checked_count + 1))

        # Honour the optional versioning= hint: semver / semver-coerced
        # force the numeric comparator; anything else (regex, loose, or
        # absent) lets compare_versions decide from the tag shapes.
        if [ "$versioning" = "semver" ] || [ "$versioning" = "semver-coerced" ]; then
            if semver_core_numeric "$current_clean" && semver_core_numeric "$latest_clean"; then
                if [ "$current_clean" != "$latest_clean" ] && semver_gt "$latest_clean" "$current_clean"; then
                    verdict="OUTDATED"
                else
                    verdict="OK"
                fi
            else
                # Hint says semver but the tag has no numeric core —
                # fall back to the shape-based comparison.
                verdict="$(compare_versions "$current_clean" "$latest_clean")"
            fi
        else
            verdict="$(compare_versions "$current_clean" "$latest_clean")"
        fi

        case "$verdict" in
            OUTDATED)
                log "OUTDATED: $app — $dep_name is at $current, upstream latest is $latest"
                outdated_count=$((outdated_count + 1))
                outdated_lines="${outdated_lines}OUTDATED: $app — $dep_name is at $current, upstream latest is $latest"$'\n'
                ;;
            WARN)
                log "WARN: $app — $dep_name is at $current, upstream latest is $latest (composite-tag drift, not a proven supersession)"
                warn_count=$((warn_count + 1))
                ;;
            *)
                log "OK: $app — $dep_name is at $current (upstream latest: $latest)"
                ;;
        esac
    done < <(grep -n 'renovate:' "$bake_file" | cut -d: -f2- || true)
done

log ""
log "Summary: $checked_count checked, $outdated_count outdated, $warn_count warnings, $skipped_count skipped"

# Open a GitHub issue if any OUTDATED entries were found.
if [ "$outdated_count" -gt 0 ]; then
    if [ "$DRY_RUN" = "true" ]; then
        log "DRY_RUN: would open a GitHub issue for $outdated_count outdated entries"
    elif [ -n "$GITHUB_TOKEN" ]; then
        log "Opening GitHub issue for $outdated_count outdated entries..."
        issue_body="$outdated_lines"
        if [ -n "$issue_body" ]; then
            gh_curl -X POST \
                -H "Accept: application/vnd.github+json" \
                "https://api.github.com/repos/$GITHUB_REPO/issues" \
                -d "$(printf '{"title":"[freshness] %d bake default(s) are outdated","body":"%s"}' \
                    "$outdated_count" \
                    "$(printf '%s' "$issue_body" | sed 's/"/\\"/g' | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
                )" >/dev/null 2>&1 || warn "failed to open GitHub issue"
        fi
    else
        warn "GITHUB_TOKEN not set; cannot open issue for $outdated_count outdated entries"
    fi
    exit 1
fi

exit 0
