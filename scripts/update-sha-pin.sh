#!/usr/bin/env bash
#
# update-sha-pin.sh — recompute and re-pin a manually-managed *_SHA512 pin.
#
# HEX_SHA512, REBAR_SHA512, and GODOT_SHA512 are pinned by hand because upstream
# does not publish sha512 checksums in a Renovate-readable form. When Renovate
# bumps the matching *_VERSION, the build fails at `sha512sum -c -` until the
# pin is recomputed. This helper removes the manual step: it reads the version
# args from the app's Dockerfile, downloads the exact artifact the build would
# fetch, computes its sha512, prints it, and patches the Dockerfile in place.
#
# Usage:
#   scripts/update-sha-pin.sh <app> <var>
#
#   <app>  one of: llmkube-coder, elixir-gate, godot-gate
#   <var>  one of: HEX, REBAR, GODOT
#
# Exit codes:
#   0 — pin recomputed and Dockerfile patched
#   1 — usage error (bad app/var, or var not present in that app)
#   2 — download or checksum computation failed
#
# The script is idempotent: if the computed SHA already matches the pin, it
# reports that and leaves the file untouched (no spurious diff).

set -euo pipefail

APP="${1:-}"
VAR="${2:-}"

usage() {
  echo "Usage: $(basename "$0") <app> <var>" >&2
  echo "  <app>  one of: llmkube-coder, elixir-gate, godot-gate" >&2
  echo "  <var>  one of: HEX, REBAR, GODOT" >&2
}

if [[ -z "$APP" || -z "$VAR" ]]; then
  usage
  exit 1
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOCKERFILE="$REPO_ROOT/apps/$APP/Dockerfile"

if [[ ! -f "$DOCKERFILE" ]]; then
  echo "ERROR: no Dockerfile at apps/$APP/Dockerfile" >&2
  exit 1
fi

# arg <name> — pull the value of `ARG <name>=<value>` from the Dockerfile.
arg() {
  sed -n "s/^ARG $1=\(.*\)$/\1/p" "$DOCKERFILE" | head -1
}

# Build the download URL for the requested artifact, reading every version
# component from the Dockerfile so the script never needs a version argument.
case "$APP" in
  llmkube-coder|elixir-gate)
    case "$VAR" in
      HEX)
        HEX_VERSION="$(arg HEX_VERSION)"
        HEX_INSTALLS="$(arg HEX_INSTALLS)"
        HEX_OTP="$(arg HEX_OTP)"
        [[ -n "$HEX_VERSION" && -n "$HEX_INSTALLS" && -n "$HEX_OTP" ]] || {
          echo "ERROR: could not read HEX_VERSION/HEX_INSTALLS/HEX_OTP from $DOCKERFILE" >&2
          exit 1
        }
        URL="https://builds.hex.pm/installs/${HEX_INSTALLS}/hex-${HEX_VERSION}-otp-${HEX_OTP}.ez"
        ;;
      REBAR)
        REBAR_VERSION="$(arg REBAR_VERSION)"
        [[ -n "$REBAR_VERSION" ]] || {
          echo "ERROR: could not read REBAR_VERSION from $DOCKERFILE" >&2
          exit 1
        }
        URL="https://github.com/erlang/rebar3/releases/download/${REBAR_VERSION}/rebar3"
        ;;
      GODOT)
        GODOT_VERSION="$(arg GODOT_VERSION)"
        GODOT_STATUS="$(arg GODOT_STATUS)"
        [[ -n "$GODOT_VERSION" && -n "$GODOT_STATUS" ]] || {
          echo "ERROR: could not read GODOT_VERSION/GODOT_STATUS from $DOCKERFILE" >&2
          exit 1
        }
        URL="https://github.com/godotengine/godot-builds/releases/download/${GODOT_VERSION}-${GODOT_STATUS}/Godot_v${GODOT_VERSION}-${GODOT_STATUS}_linux.x86_64.zip"
        ;;
      *)
        echo "ERROR: $APP does not pin a ${VAR}_SHA512 (expected HEX or REBAR)" >&2
        usage
        exit 1
        ;;
    esac
    ;;
  godot-gate)
    # godot-gate names the Godot version `VERSION`, not `GODOT_VERSION`.
    if [[ "$VAR" != "GODOT" ]]; then
      echo "ERROR: godot-gate only pins GODOT_SHA512" >&2
      usage
      exit 1
    fi
    GODOT_VERSION="$(arg VERSION)"
    GODOT_STATUS="$(arg GODOT_STATUS)"
    [[ -n "$GODOT_VERSION" && -n "$GODOT_STATUS" ]] || {
      echo "ERROR: could not read VERSION/GODOT_STATUS from $DOCKERFILE" >&2
      exit 1
    }
    URL="https://github.com/godotengine/godot-builds/releases/download/${GODOT_VERSION}-${GODOT_STATUS}/Godot_v${GODOT_VERSION}-${GODOT_STATUS}_linux.x86_64.zip"
    ;;
  *)
    echo "ERROR: unknown app '$APP'" >&2
    usage
    exit 1
    ;;
esac

PIN="${VAR}_SHA512"
OLD_SHA="$(arg "$PIN")"
if [[ -z "$OLD_SHA" ]]; then
  echo "ERROR: no ARG ${PIN} found in $DOCKERFILE" >&2
  exit 1
fi

TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

echo "Fetching: $URL" >&2
if ! curl -fsSL "$URL" -o "$TMP"; then
  echo "ERROR: download failed for $URL" >&2
  exit 2
fi

NEW_SHA="$(sha512sum "$TMP" | cut -d' ' -f1)"
echo "Computed ${PIN}=${NEW_SHA}"

if [[ "$NEW_SHA" == "$OLD_SHA" ]]; then
  echo "Pin already up to date; $DOCKERFILE left unchanged."
  exit 0
fi

# Patch the pin in place. The ARG line is `ARG <PIN>=<sha>`; replace only the
# value so the surrounding comment and formatting are preserved.
sed -i.bak "s/^ARG ${PIN}=.*/ARG ${PIN}=${NEW_SHA}/" "$DOCKERFILE"
rm -f "$DOCKERFILE.bak"

echo "Updated ${PIN} in $DOCKERFILE:"
echo "  old: $OLD_SHA"
echo "  new: $NEW_SHA"
echo
echo "Review the diff and commit it to the Renovate PR branch (or push a"
echo "follow-up commit before merge) so the build's sha512sum -c check passes."
