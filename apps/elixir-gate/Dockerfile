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
FROM node:24-bookworm-slim@sha256:3638d9a6fe4030bd716be989438248074489337ba3275657f93595428be4fc03 AS node

FROM hexpm/elixir:${VERSION}@sha256:dc0c79cbe0468a3df3b2cb7097d95b0d67a5a402ed9a2ad0a59741cd870adfdc

# The tag and the digest in the FROM above are independent inputs: the digest
# decides the contents, VERSION decides what the published image is called. So
# a mismatch between them ships silently and the tag lies about what is inside,
# which is what #178 was. Assert they agree at build time instead. ARG is
# re-declared because the global one is not in scope inside a stage.
ARG VERSION
RUN set -eu; \
    want="${VERSION%%-*}"; \
    got="$(elixir --version | sed -n 's/^Elixir \([0-9.]*\).*/\1/p')"; \
    if [ "$want" != "$got" ]; then \
        echo "elixir-gate: VERSION claims Elixir ${want} but the pinned digest ships ${got}." >&2; \
        echo "Update the FROM digest and VERSION together, or the published tag will misreport the image." >&2; \
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
ENV MIX_HOME=/opt/mix
RUN mkdir -p /opt/mix \
    && mix local.hex --force \
    && mix local.rebar --force \
    && chmod -R a+rX /opt/mix

# Writable state under /tmp so no write lands on a root-owned path: mix builds,
# hex's cache, and rebar all write during a gate run.
ENV HOME=/tmp \
    HEX_HOME=/tmp/.hex \
    XDG_CACHE_HOME=/tmp/.cache \
    XDG_CONFIG_HOME=/tmp/.config \
    XDG_DATA_HOME=/tmp/.local/share \
    ERL_CRASH_DUMP=/dev/null
RUN git config --system --add safe.directory '*'

# The gate clones the repo into /work and runs as this image's non-root user.
# World-writable + sticky (like /tmp) because the uid may be overridden by the
# pod: without it, `git clone … /work` fails with "Permission denied".
RUN mkdir -p /work && chmod 1777 /work

# No ENTRYPOINT: gate profiles supply shell command lines (`mix deps.get && mix
# test`), matching the stock language images the other profiles use.
USER 65534:65534
WORKDIR /work
CMD ["/bin/sh"]
