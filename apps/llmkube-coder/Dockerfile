# syntax=docker/dockerfile:1

# Build stage: cross-compile the static foreman-agent from LLMKube source.
# CGO is disabled, so the binary runs on the Python/Node runtime below with no
# Go toolchain present. Pinned to $BUILDPLATFORM + GOOS/GOARCH so the compiler
# always runs natively (arm64 never pays QEMU's interpreted-compile cost).
FROM --platform=$BUILDPLATFORM golang:1.27-bookworm@sha256:648f440f42a0958804efb24df176f806f9d353b41f1c0627f666428e40310f6b AS build
ARG VERSION
ARG TARGETOS
ARG TARGETARCH
ENV CGO_ENABLED=0
WORKDIR /build
# Resolve VERSION to the module's version string so the stamped binary reports a
# real release (the FleetNode heartbeats main.Version; an empty stamp shows as
# "dev" in `kubectl get fleetnodes`). go list -m needs a module context.
RUN mkdir -p /out /tmp/vresolve \
    && ( cd /tmp/vresolve && go mod init coderbuild >/dev/null 2>&1 \
         && go list -m -f '{{.Version}}' "github.com/defilantech/llmkube@v${VERSION}" > /out/llmkube.version ) \
    && LLMKUBE_VERSION="$(cat /out/llmkube.version)" \
    && GOOS="${TARGETOS:-linux}" GOARCH="${TARGETARCH}" go install -trimpath \
         -ldflags="-s -w -X main.Version=${LLMKUBE_VERSION} -X main.GitCommit=v${VERSION}" \
         "github.com/defilantech/llmkube/cmd/foreman-agent@v${VERSION}" \
    && cp "$(find "$(go env GOPATH)/bin" -name foreman-agent -type f | head -1)" /out/foreman-agent \
    && test -x /out/foreman-agent

# Node source stage: the official Node 24 image on the same Debian base as the
# runtime, so the copied binary is ABI-compatible.
FROM node:24-trixie-slim@sha256:50c3b2f6988dfc307b86e5301d69611af31f4789bdf232863b07d3b02fe55ae0 AS node

# Pin npm to the patched 11.x line; npm 12's dependency tree still carries
# vulnerable versions of brace-expansion, ip-address, and tar.
# See: https://github.com/misospace/llmkube-images/issues/126
RUN npm install -g npm@11.19.1

# Go toolchain stage: deliberately NOT pinned to $BUILDPLATFORM so it resolves to
# the TARGET arch — the Go SDK copied into the runtime must match the image's
# platform (the build stage above is builder-arch and only cross-compiles the
# agent). Same digest as the build stage; the manifest resolves per-arch.
FROM golang:1.27-trixie@sha256:9baa6b4187bbb98d240372a8a235ac0bb6b5ddd52bba1431dc2f7c0705862728 AS goruntime

# Elixir/OTP source stage: same Debian base as the runtime, so the copied
# trees are ABI-compatible. Erlang lives in /usr/local/lib/erlang and Elixir in
# /usr/local/lib/elixir; both relocate as whole directories.
FROM hexpm/elixir:1.20.4-erlang-27.3.4.17-debian-trixie-20260824@sha256:3b050a8cadf59d0574849e1ed9056a3946b03c8206bb4678a78320c6453a5a53 AS elixir

# Runtime: Python 3.14 + Node + Go 1.26 + Godot headless + Elixir/OTP — one
# image for every coder self-gate. Rootless coders cannot install anything at
# run time, so every fleet runtime is baked here instead (the modern
# replacement for the old root-and-apt-get pods). amd64 only: Godot upstream
# ships a linux x86_64 headless binary and the fleet nodes are amd64.
FROM python:3.14-slim-trixie@sha256:cad9a2c871761c413caa6fdd6441c783451e740a48aaeba60ae62a8b53525ef6

LABEL org.opencontainers.image.title="llmkube-coder" \
      org.opencontainers.image.description="LLMKube foreman coder agent (built from source) with a Python + Node + Go + Godot + Elixir self-gate toolchain" \
      org.opencontainers.image.source="https://github.com/defilantech/LLMKube" \
      org.opencontainers.image.licenses="Apache-2.0"

# renovate: datasource=github-releases depName=godotengine/godot
ARG GODOT_VERSION=4.7.2
ARG GODOT_STATUS=stable
ARG GODOT_SHA512=9aa00f7a605200940bce3027a567b782f49bd8e940dd06ae9e987bd65aee1b1467edd56ed84fcdcbdd44354bf613bdbb4e5d2913e925850368e150c59ed54c65
# renovate: datasource=github-releases depName=hexpm/hex
ARG HEX_VERSION=2.5.1
ARG HEX_SHA512=ad624850969eaeb8a994bfc9c199554269648d23598da4231ab5e1a7c81cc58f5356425022ca8f20d3c3efc4e4625ac32d608b58fa1c6159fe6a3e2ed224c2fa
ARG HEX_INSTALLS=1.20.0
ARG HEX_OTP=27
# renovate: datasource=github-releases depName=erlang/rebar3
ARG REBAR_VERSION=3.27.0
ARG REBAR_SHA512=0d00494d849fdc521a55142278d1f6ba552954fbd65b80d40df8022f594f05d6c99ed1d731bc263691a04176e11d4c6e126c56ba20dca19c5e42d4ffab2e7e36

# Elixir/OTP from the hexpm stage. Copied before the consolidated apt-get RUN
# below so the hex/rebar substep can run `mix local.rebar` and `elixir
# --version` in the same layer. Hex and rebar are installed into a
# world-READABLE shared MIX_HOME: the runtime uid is unknown at build time and
# $HOME is a scratch dir, so a HOME-local install would be invisible to the
# process that runs mix. HEX_HOME (hex's package CACHE, written during mix
# deps.get) points at /tmp below instead — putting it beside the read-only
# archives breaks the first real fetch. Versions AND sha512 checksums are
# pinned so a build cannot silently pick up a different executable than the
# one recorded here. The build fails (set -eux + sha512sum -c) on any drift,
# including a compromised or typo'd upstream. Checksums are pinned for the
# exact artifacts downloaded below. Hex comes from builds.hex.pm; rebar3 comes
# from its upstream GitHub release asset, because 3.27.0 is not yet available
# in Hex's installer index.
COPY --from=elixir /usr/local/lib/erlang /usr/local/lib/erlang
COPY --from=elixir /usr/local/lib/elixir /usr/local/lib/elixir
ENV MIX_HOME=/opt/mix

# Consolidated apt-get for the whole runtime stage: ONE `apt-get update` (one
# Debian index download) instead of three. Split inside this single RUN:
#   1. apt-get update
#   2. install runtime deps (git, ca-certificates, libstdc++6, libtinfo6,
#      libfontconfig1, build-essential)
#   3. rm -rf /var/lib/apt/lists/*
# Do not re-split into per-tool `apt-get update` calls — each one re-downloads
# the full Debian index and bloats the layer.
#
# curl and unzip are installed once and KEPT. They were previously installed
# and purged per substep, on the reasoning that they were build-only. They are
# not: gates are not dispatched, so this image runs each repo's own test
# command and those shell out — pinchflat's tooling/fetch-sqlean.sh curls a
# release asset before `mix ecto.create`. elixir-gate, the image the coder
# replaced on that path, ships both; purging them here silently narrowed what
# a repo may do, and surfaced only as `curl: command not found` in a coder
# transcript in another repo.
#
# git for the coder workspace; libstdc++6 for Node and the BEAM; libtinfo6 for
# OTP; libfontconfig1 for Godot headless; build-essential because Elixir NIF
# deps (ecto_sqlite3 et al) compile C during mix deps.compile.
#
# Godot headless. Fetched at build time (rootless coders cannot install at run
# time) and verified against the release's own SHA512-SUMS.txt — a stale digest
# fails the build loudly rather than installing an unverified engine.
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        git ca-certificates libstdc++6 libtinfo6 libfontconfig1 build-essential \
        curl unzip; \
    curl -fsSL "https://github.com/godotengine/godot-builds/releases/download/${GODOT_VERSION}-${GODOT_STATUS}/Godot_v${GODOT_VERSION}-${GODOT_STATUS}_linux.x86_64.zip" -o /tmp/godot.zip; \
    echo "${GODOT_SHA512}  /tmp/godot.zip" | sha512sum -c -; \
    unzip -oq /tmp/godot.zip -d /tmp/godot; \
    mv "/tmp/godot/Godot_v${GODOT_VERSION}-${GODOT_STATUS}_linux.x86_64" /usr/local/bin/godot; \
    chmod 0755 /usr/local/bin/godot; \
    rm -rf /tmp/godot.zip /tmp/godot; \
    ln -sf /usr/local/lib/erlang/bin/erl /usr/local/bin/erl; \
    ln -sf /usr/local/lib/erlang/bin/erlc /usr/local/bin/erlc; \
    ln -sf /usr/local/lib/erlang/bin/escript /usr/local/bin/escript; \
    ln -sf /usr/local/lib/elixir/bin/elixir /usr/local/bin/elixir; \
    ln -sf /usr/local/lib/elixir/bin/elixirc /usr/local/bin/elixirc; \
    ln -sf /usr/local/lib/elixir/bin/mix /usr/local/bin/mix; \
    ln -sf /usr/local/lib/elixir/bin/iex /usr/local/bin/iex; \
    mkdir -p /opt/mix/archives; \
    curl -fsSL -o /opt/mix/archives/hex-${HEX_VERSION}.ez \
      "https://builds.hex.pm/installs/${HEX_INSTALLS}/hex-${HEX_VERSION}-otp-${HEX_OTP}.ez"; \
    echo "${HEX_SHA512}  /opt/mix/archives/hex-${HEX_VERSION}.ez" | sha512sum -c -; \
    curl -fsSL -o /opt/mix/rebar3 \
      "https://github.com/erlang/rebar3/releases/download/${REBAR_VERSION}/rebar3"; \
    echo "${REBAR_SHA512}  /opt/mix/rebar3" | sha512sum -c -; \
    chmod +x /opt/mix/rebar3; \
    mix local.rebar rebar3 /opt/mix/rebar3 --force; \
    chmod -R a+rX /opt/mix; \
    elixir --version; \
    rm -rf /var/lib/apt/lists/*

# Node 24 + npm from the official image.
COPY --from=node /usr/local/bin/node /usr/local/bin/node
COPY --from=node /usr/local/lib/node_modules /usr/local/lib/node_modules
RUN ln -sf /usr/local/lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm \
    && ln -sf /usr/local/lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx \
    && node --version && npm --version

# Python self-gate linters.
# renovate: datasource=pypi depName=ruff
ARG RUFF_VERSION=0.16.6
# renovate: datasource=pypi depName=black
ARG BLACK_VERSION=26.5.1
# renovate: datasource=pypi depName=flake8
ARG FLAKE8_VERSION=7.3.0
# renovate: datasource=pypi depName=yamllint
ARG YAMLLINT_VERSION=1.38.0
RUN pip install --no-cache-dir \
      "ruff==${RUFF_VERSION}" "black==${BLACK_VERSION}" \
      "flake8==${FLAKE8_VERSION}" "yamllint==${YAMLLINT_VERSION}"

# Node self-gate linters.
# renovate: datasource=npm depName=eslint
ARG ESLINT_VERSION=10.9.1
# renovate: datasource=npm depName=prisma
ARG PRISMA_VERSION=7.10.0
# renovate: datasource=npm depName=typescript
ARG TYPESCRIPT_VERSION=6.0.3
# Vulnerable transitives bundled under prisma, replaced after install below.
# renovate: datasource=npm depName=deepmerge-ts
ARG DEEPMERGE_TS_VERSION=8.0.2
# renovate: datasource=npm depName=mysql2
ARG MYSQL2_VERSION=3.22.0
# Override the vulnerable transitives Prisma bundles: deepmerge-ts
# (GHSA-ggr8-5vv4-36mx, High, fixed in 8.0.0) and mysql2 (GHSA-3f6p-5ww8-9rcr,
# High, fixed in 3.22.0). prisma@7.10.0 pulls deepmerge-ts@7.1.5 and
# mysql2@3.15.3. The override fans out to ALL copies of each package
# under /usr/local/lib/node_modules, not just the top-level
# prisma/node_modules/deepmerge-ts path, because npm's hoisting or a future Prisma
# minor may nest the vulnerable copy under e.g. prisma/node_modules/@prisma/config/
# node_modules/deepmerge-ts. A single-path rm -rf + cp -a would silently no-op on
# a layout change (the rm succeeds on a missing path, the cp writes to a path
# nothing resolves, and the assertion reads from the same empty path).
#
# Only directories carrying a package.json are replaced. prisma also ships a
# BUNDLED copy at @prisma/studio-core/dist/data/mysql2, which is a build
# artifact rather than a package: it has no package.json, nothing resolves it as
# a module, and the SBOM does not report it, so overwriting it with a real
# package would risk breaking studio-core to fix a finding that is not there.
# Fallback if Prisma's layout changes again: switch to `npm install --prefix
# /tmp/override && npm dedupe` or pin Prisma to a known layout-compatible minor.
RUN npm install -g --no-fund --no-audit \
      "eslint@${ESLINT_VERSION}" "prisma@${PRISMA_VERSION}" "typescript@${TYPESCRIPT_VERSION}" \
    && mkdir -p /tmp/npm-overrides \
    && printf '%s\n' \
       "{\"private\":true,\"dependencies\":{\"deepmerge-ts\":\"${DEEPMERGE_TS_VERSION}\",\"mysql2\":\"${MYSQL2_VERSION}\"}}" \
       > /tmp/npm-overrides/package.json \
    && npm install --prefix /tmp/npm-overrides --no-save --no-package-lock --ignore-scripts \
    && for pkg in deepmerge-ts mysql2; do \
         for d in $(find /usr/local/lib/node_modules -type d -name "$pkg" -path '*/node_modules/*'); do \
           [ -f "$d/package.json" ] || continue; \
           rm -rf "$d" && cp -a "/tmp/npm-overrides/node_modules/$pkg" "$d"; \
         done; \
       done \
    && rm -rf /tmp/npm-overrides /root/.npm \
    && for pkg in deepmerge-ts mysql2; do \
         case "$pkg" in \
           deepmerge-ts) want="${DEEPMERGE_TS_VERSION}" ;; \
           mysql2)       want="${MYSQL2_VERSION}" ;; \
         esac; \
         for d in $(find /usr/local/lib/node_modules -type d -name "$pkg" -path '*/node_modules/*'); do \
           [ -f "$d/package.json" ] || continue; \
           got=$(node -p "require('$d/package.json').version"); \
           test "$got" = "$want" || { echo "FAIL: $d reports $got, want $want"; exit 1; }; \
         done; \
       done \
    && prisma --version \
    && tsc --version

# Go 1.26 toolchain (target-arch) for the Go self-gate: go build/test/vet/gofmt.
COPY --from=goruntime /usr/local/go /usr/local/go
ENV PATH="/usr/local/go/bin:${PATH}"

# Read-only-rootfs friendly: all writable state under /tmp, and git operates on
# the workspace regardless of the (possibly pod-overridden) uid.
# LANG: the BEAM falls back to latin1 filename encoding without a UTF-8
# locale, which breaks Elixir apps handling unicode (hexpm images set this).
ENV LANG=C.UTF-8 \
    HOME=/tmp \
    npm_config_cache=/tmp/.npm \
    PIP_CACHE_DIR=/tmp/.pip \
    HEX_HOME=/tmp/.hex \
    XDG_CACHE_HOME=/tmp/.cache \
    XDG_CONFIG_HOME=/tmp/.config \
    XDG_DATA_HOME=/tmp/.local/share \
    GOCACHE=/tmp/.gocache \
    GOMODCACHE=/tmp/.gomodcache \
    GOPATH=/tmp/go
RUN git config --system --add safe.directory '*'

COPY --from=build /out/foreman-agent /foreman-agent
RUN chmod 0755 /foreman-agent \
    && ln -sf /foreman-agent /usr/local/bin/foreman-agent

# nobody:nogroup (repo default). The foreman pod may override the uid; the image
# is uid-agnostic — all writable state lives in /tmp and the tools are
# world-executable.
USER 65534:65534
ENTRYPOINT ["/foreman-agent"]
