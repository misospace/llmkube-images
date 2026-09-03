# syntax=docker/dockerfile:1

# Elixir/OTP toolchain for foreman verify gates (misospace/pinchflat et al).
# Everything the gate needs is baked at build time: the gate runs as a non-root
# uid with no network guarantees and cannot apt-install, so a stock elixir image
# plus runtime installs is not viable.
# Declared before any FROM so it stays a global ARG usable by the elixir stage
# below — an ARG after the first FROM is scoped to that stage only.
#
# Deliberately NOT Renovate-managed. docker-bake.hcl's VERSION is the single
# managed declaration, because that is what .github/actions/app-options reads
# (via `buildx bake --list`) to tag the published image, and bake passes it in
# as a build arg that overrides this default. A second marker here is what let
# the two drift apart in #156: Renovate matched a different "latest" for each
# and the tag ended up describing an image the digest did not ship (#178).
# This default exists only so a bare `docker build` works locally.
ARG VERSION=1.20.3-erlang-29.0.5-ubuntu-resolute-20260724.1

# Node source stage: pinchflat's `mix check` includes a prettier_formatting
# tool (`yarn run lint:check`, see its tooling/.check.exs), so the gate needs a
# JS toolchain to reach parity with the repo's CI. Copied from the official
# image rather than apt-installed so the version is pinned. Note this is a
# Debian-built binary landing on the Ubuntu base below — that direction works
# because the target's glibc is newer, and the version check after the copy
# fails the build if it ever stops holding.
FROM node:24-bookworm-slim@sha256:ba849c60be29959425b8734d57b8b4b7d56f98edd9504c9af091d5281095a71e AS node

FROM hexpm/elixir:${VERSION}@sha256:dc0c79cbe0468a3df3b2cb7097d95b0d67a5a402ed9a2ad0a59741cd870adfdc

# base-pin.json is the checked-in manifest-digest table the build-time
# assertion below consults as the source of truth for which hexpm/elixir tag
# each ubuntu-<flavor>-YYYYMMDD[.N] VERSION suffix resolves to (see #267). It
# must live in this stage: a COPY in the node stage above is dropped when the
# second FROM starts a fresh filesystem, and the assertion would then fail
# with "missing from base-pin.json" instead of catching a real drift.
COPY base-pin.json /tmp/base-pin.json

# The tag and the digest in the FROM above are independent inputs: the digest
# decides the contents, VERSION decides what the published image is called. So
# a mismatch between them ships silently and the tag lies about what is inside,
# which is what #178 was. Assert they agree at build time instead. ARG is
# re-declared because the global one is not in scope inside a stage.
# Both components of the tag are checked. Elixir comes from `elixir --version`;
# OTP comes from the releases/*/OTP_VERSION file rather than
# erlang:system_info(otp_release), because the latter reports only the major
# ("29") and would not catch a 29.0.5 -> 29.0.6 drift. An OTP-less VERSION
# skips that half rather than failing.
# The Ubuntu-base half compares VERSION's trailing 'ubuntu-<flavor>-YYYYMMDD[.N]'
# segment to a checked-in manifest digest in base-pin.json (the digest Docker
# Hub reports for hexpm/elixir:<VERSION>). This is the source of truth the
# issue called for — the previous dpkg-query -W Install-Date proxy is the same
# class of weakly-correlated timestamp #178/#267 both regressed on, so it is
# not used here.
ARG VERSION
RUN set -eu; \
    want_elixir="${VERSION%%-*}"; \
    got_elixir="$(elixir --version | sed -n 's/^Elixir \([0-9.]*\).*/\1/p')"; \
    want_otp="$(printf '%s' "$VERSION" | sed -n 's/.*erlang-\([0-9][0-9.]*\).*/\1/p')"; \
    got_otp="$(cat /usr/local/lib/erlang/releases/*/OTP_VERSION)"; \
    want_pin_key="$(printf '%s' "$VERSION" | sed -n 's/.*\(ubuntu-[a-z]*-[0-9]\{8\}\(\.[0-9]\+\)\?\)$/\1/p')"; \
    want_pin_digest="$(python3 -c "import json,sys; m=json.load(open('/tmp/base-pin.json')); sys.stdout.write(m.get('$want_pin_key',''))")"; \
    from_digest="$(awk '/^FROM /{sub(/.*@sha256:/,""); sub(/[^a-f0-9].*/,""); print; exit}' /Dockerfile)"; \
    bad=""; \
    [ "$want_elixir" = "$got_elixir" ] || bad="Elixir: tag says ${want_elixir}, image ships ${got_elixir}"; \
    if [ -n "$want_otp" ] && [ "$want_otp" != "$got_otp" ]; then \
        bad="${bad:+${bad}\n}OTP: tag says ${want_otp}, image ships ${got_otp}"; \
    fi; \
    if [ -n "$want_pin_key" ]; then \
        if [ -z "$want_pin_digest" ]; then \
            bad="${bad:+${bad}\n}Ubuntu base: ${want_pin_key} is missing from base-pin.json (update the pin file when bumping VERSION)"; \
        elif [ "$want_pin_digest" != "$from_digest" ]; then \
            bad="${bad:+${bad}\n}Ubuntu base: VERSION ${want_pin_key} expects sha256:${want_pin_digest} but FROM pins sha256:${from_digest}"; \
        fi; \
    fi; \
    if [ -n "$bad" ]; then \
        echo "elixir-gate: VERSION disagrees with the pinned digest." >&2; \
        printf '%b\n' "$bad" >&2; \
        echo "Update the FROM digest, VERSION, and apps/elixir-gate/base-pin.json together, or the published tag will misreport the image." >&2; \
        exit 1; \
    fi

LABEL org.opencontainers.image.title="elixir-gate" \
      org.opencontainers.image.description="Elixir/OTP toolchain for foreman verify gates (rootless, read-only-rootfs safe)" \
      org.opencontainers.image.source="https://github.com/misospace/llmkube-images" \
      org.opencontainers.image.licenses="MIT"

# build-essential: ecto_sqlite3 (and other NIF deps) compile C at `mix deps.compile`.
# git + ca-certificates: the gate clones the target repo and mix fetches over https.
# curl + unzip: projects fetch native SQLite extensions during setup — pinchflat's
# tooling/fetch-sqlean.sh downloads and unzips sqlean, and its Repo loads that
# extension OUTSIDE the prod guard, so `mix test` needs it too.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        build-essential ca-certificates curl git unzip \
    && rm -rf /var/lib/apt/lists/*

# Node + Yarn for `mix check`'s prettier_formatting tool. Everything is made
# world-readable for the same reason MIX_HOME is: the gate's uid is not known
# at build time, so anything only root can read is invisible to the process
# that runs the check. The version calls are a build-time smoke test of the
# Debian-binary-on-Ubuntu copy above.
COPY --from=node /usr/local/bin/node /usr/local/bin/node
COPY --from=node /usr/local/lib/node_modules /usr/local/lib/node_modules
RUN ln -sf /usr/local/lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm \
    && ln -sf /usr/local/lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx \
    && npm install -g yarn \
    && chmod -R a+rX /usr/local/lib/node_modules \
    && node --version && npm --version && yarn --version

# Hex and rebar archives go into a world-READABLE shared MIX_HOME rather than
# into $HOME. The gate's uid is not known at build time and $HOME is a scratch
# dir, so a HOME-local install would be invisible to the process that runs mix.
#
# rebar3 must also be registered where Mix looks for it, not merely present:
# Mix consults $MIX_HOME/elixir/<elixir>-otp-<otp>/rebar3, so a binary sitting
# at $MIX_HOME/rebar3 is invisible and `mix deps.get` tries to install its own
# copy — which fails, because MIX_HOME is root-owned and the gate runs as
# nobody. `mix local.rebar <path>` installs the already-verified binary into
# that version-scoped directory and lets Mix compute the version itself, so
# this does not rot on an Elixir or OTP bump. MIX_HOME stays read-only for the
# gate: writes belong under /tmp (see below).
# Versions AND sha512 checksums are pinned so a build cannot silently pick up a
# different executable than the one recorded here. The build fails (set -eu +
# sha512sum -c) on any drift, including a compromised or typo'd upstream.
# Checksums are pinned for the exact artifacts downloaded below. Hex comes
# from builds.hex.pm; rebar3 comes from its upstream GitHub release asset,
# because 3.27.0 is not yet available in Hex's installer index.
# renovate: datasource=github-releases depName=hexpm/hex
ARG HEX_VERSION=2.5.1
ARG HEX_SHA512=6629f4b4bb2e040326151ebb853aad065e342c65ad3a0f2a2674dcf7164eb4328d6c929513d7230309ad75042024e72bef0e0a51ebff373b4173d2746b1772b7
ARG HEX_INSTALLS=1.20.0
ARG HEX_OTP=29
# renovate: datasource=github-releases depName=erlang/rebar3
ARG REBAR_VERSION=3.27.0
ARG REBAR_SHA512=0d00494d849fdc521a55142278d1f6ba552954fbd65b80d40df8022f594f05d6c99ed1d731bc263691a04176e11d4c6e126c56ba20dca19c5e42d4ffab2e7e36
ENV MIX_HOME=/opt/mix
RUN set -eux; \
    mkdir -p /opt/mix/archives; \
    curl -fsSL -o /opt/mix/archives/hex-${HEX_VERSION}.ez \
      "https://builds.hex.pm/installs/${HEX_INSTALLS}/hex-${HEX_VERSION}-otp-${HEX_OTP}.ez"; \
    echo "${HEX_SHA512}  /opt/mix/archives/hex-${HEX_VERSION}.ez" | sha512sum -c -; \
    curl -fsSL -o /opt/mix/rebar3 \
      "https://github.com/erlang/rebar3/releases/download/${REBAR_VERSION}/rebar3"; \
    echo "${REBAR_SHA512}  /opt/mix/rebar3" | sha512sum -c -; \
    chmod +x /opt/mix/rebar3; \
    mix local.rebar rebar3 /opt/mix/rebar3 --force; \
    chmod -R a+rX /opt/mix

# Writable state under /tmp so no write lands on a root-owned path: mix builds,
# hex's cache, and rebar all write during a gate run.
ENV HOME=/tmp \
    HEX_HOME=/tmp/.hex \
    XDG_CACHE_HOME=/tmp/.cache \
    XDG_CONFIG_HOME=/tmp/.config \
    XDG_DATA_HOME=/tmp/.local/share \
    ERL_CRASH_DUMP=/dev/null
# Scope the safe-directory exemption to the gate's only mount point (/work):
# the repo is cloned there by a possibly pod-overridden uid, so git would
# otherwise refuse it as "dubious ownership". '*' would disable the check for
# every path in the container, which is wider than the gate needs.
RUN git config --system --add safe.directory /work

# The gate clones the repo into /work and runs as this image's non-root user.
# World-writable + sticky (like /tmp) because the uid may be overridden by the
# pod: without it, `git clone … /work` fails with "Permission denied".
RUN mkdir -p /work && chmod 1777 /work

# No ENTRYPOINT: gate profiles supply shell command lines (`mix deps.get && mix
# test`), matching the stock language images the other profiles use.
USER 65534:65534
WORKDIR /work
CMD ["/bin/sh"]
