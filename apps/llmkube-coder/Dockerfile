# syntax=docker/dockerfile:1

# Build stage: cross-compile the static foreman-agent from LLMKube source.
# CGO is disabled, so the binary runs on the Python/Node runtime below with no
# Go toolchain present. Pinned to $BUILDPLATFORM + GOOS/GOARCH so the compiler
# always runs natively (arm64 never pays QEMU's interpreted-compile cost).
FROM --platform=$BUILDPLATFORM golang:1.27-bookworm@sha256:ded31c68586d2e49e760acc2e65a884b23d032e9bbbed0ae0c55abd3fcaf4452 AS build
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
FROM node:24-bookworm-slim@sha256:a9f5f7c91a432850b2a8a7797adf5eadb6c733ceed61167806cee7ea7fbc29df AS node

# Upgrade npm to latest to patch CVEs in vendored deps (ip-address, brace-expansion, tar).
# See: https://github.com/misospace/llmkube-images/issues/126
RUN npm install -g npm@latest

# Go toolchain stage: deliberately NOT pinned to $BUILDPLATFORM so it resolves to
# the TARGET arch — the Go SDK copied into the runtime must match the image's
# platform (the build stage above is builder-arch and only cross-compiles the
# agent). Same digest as the build stage; the manifest resolves per-arch.
FROM golang:1.27-bookworm@sha256:ded31c68586d2e49e760acc2e65a884b23d032e9bbbed0ae0c55abd3fcaf4452 AS goruntime

# Elixir/OTP source stage: same Debian base as the runtime, so the copied
# trees are ABI-compatible. Erlang lives in /usr/local/lib/erlang and Elixir in
# /usr/local/lib/elixir; both relocate as whole directories.
FROM hexpm/elixir:1.20.3-erlang-27.0.1-debian-bookworm-20260803@sha256:ceaeabd3ca1cc4a0df72755ae431063a3f48dbeca32e17c7fec266d2c70c0550 AS elixir

# Runtime: Python 3.14 + Node + Go 1.26 + Godot headless + Elixir/OTP — one
# image for every coder self-gate. Rootless coders cannot install anything at
# run time, so every fleet runtime is baked here instead (the modern
# replacement for the old root-and-apt-get pods). amd64 only: Godot upstream
# ships a linux x86_64 headless binary and the fleet nodes are amd64.
FROM python:3.14-slim-bookworm@sha256:416f0db2a2b561945630cef9877a7ea0581b27449eb9fd9df42f03e1b74b5b63

LABEL org.opencontainers.image.title="llmkube-coder" \
      org.opencontainers.image.description="LLMKube foreman coder agent (built from source) with a Python + Node + Go + Godot + Elixir self-gate toolchain" \
      org.opencontainers.image.source="https://github.com/defilantech/LLMKube" \
      org.opencontainers.image.licenses="Apache-2.0"

# git for the coder workspace; libstdc++6 for Node and the BEAM; libtinfo6 for
# OTP; libfontconfig1 for Godot headless; build-essential because Elixir NIF
# deps (ecto_sqlite3 et al) compile C during mix deps.compile.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        git ca-certificates libstdc++6 libtinfo6 libfontconfig1 build-essential \
    && rm -rf /var/lib/apt/lists/*

# Godot headless. Fetched at build time (rootless coders cannot install at run
# time) and verified against the release's own SHA512-SUMS.txt — a stale digest
# fails the build loudly rather than installing an unverified engine.
# renovate: datasource=github-releases depName=godotengine/godot
ARG GODOT_VERSION=4.7.2
ARG GODOT_STATUS=stable
ARG GODOT_SHA512=9aa00f7a605200940bce3027a567b782f49bd8e940dd06ae9e987bd65aee1b1467edd56ed84fcdcbdd44354bf613bdbb4e5d2913e925850368e150c59ed54c65
RUN apt-get update \
    && apt-get install -y --no-install-recommends curl unzip \
    && curl -fsSL "https://github.com/godotengine/godot-builds/releases/download/${GODOT_VERSION}-${GODOT_STATUS}/Godot_v${GODOT_VERSION}-${GODOT_STATUS}_linux.x86_64.zip" -o /tmp/godot.zip \
    && echo "${GODOT_SHA512}  /tmp/godot.zip" | sha512sum -c - \
    && unzip -oq /tmp/godot.zip -d /tmp/godot \
    && mv "/tmp/godot/Godot_v${GODOT_VERSION}-${GODOT_STATUS}_linux.x86_64" /usr/local/bin/godot \
    && chmod 0755 /usr/local/bin/godot \
    && rm -rf /tmp/godot.zip /tmp/godot /var/lib/apt/lists/* \
    && apt-get purge -y --auto-remove curl unzip

# Elixir/OTP from the hexpm stage. Hex and rebar are installed into a
# world-READABLE shared MIX_HOME: the runtime uid is unknown at build time and
# $HOME is a scratch dir, so a HOME-local install would be invisible to the
# process that runs mix. HEX_HOME (hex's package CACHE, written during mix
# deps.get) points at /tmp below instead — putting it beside the read-only
# archives breaks the first real fetch.
COPY --from=elixir /usr/local/lib/erlang /usr/local/lib/erlang
COPY --from=elixir /usr/local/lib/elixir /usr/local/lib/elixir
ENV MIX_HOME=/opt/mix
RUN ln -sf /usr/local/lib/erlang/bin/erl /usr/local/bin/erl \
    && ln -sf /usr/local/lib/erlang/bin/erlc /usr/local/bin/erlc \
    && ln -sf /usr/local/lib/elixir/bin/elixir /usr/local/bin/elixir \
    && ln -sf /usr/local/lib/elixir/bin/elixirc /usr/local/bin/elixirc \
    && ln -sf /usr/local/lib/elixir/bin/mix /usr/local/bin/mix \
    && ln -sf /usr/local/lib/elixir/bin/iex /usr/local/bin/iex \
    && mkdir -p /opt/mix \
    && mix local.hex --force \
    && mix local.rebar --force \
    && chmod -R a+rX /opt/mix \
    && elixir --version

# Node 24 + npm from the official image.
COPY --from=node /usr/local/bin/node /usr/local/bin/node
COPY --from=node /usr/local/lib/node_modules /usr/local/lib/node_modules
RUN ln -sf /usr/local/lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm \
    && ln -sf /usr/local/lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx \
    && node --version && npm --version

# Python self-gate linters.
# renovate: datasource=pypi depName=ruff
ARG RUFF_VERSION=0.16.4
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
ARG TYPESCRIPT_VERSION=7.0.2
RUN npm install -g --no-fund --no-audit \
      "eslint@${ESLINT_VERSION}" "prisma@${PRISMA_VERSION}" "typescript@${TYPESCRIPT_VERSION}" \
    && rm -rf /root/.npm

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
