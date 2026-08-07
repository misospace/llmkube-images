# syntax=docker/dockerfile:1

# Elixir/OTP toolchain for foreman verify gates (misospace/pinchflat et al).
# Everything the gate needs is baked at build time: the gate runs as a non-root
# uid with no network guarantees and cannot apt-install, so a stock elixir image
# plus runtime installs is not viable.
# renovate: datasource=docker depName=hexpm/elixir
ARG VERSION=1.20.3-erlang-29.0.5-ubuntu-resolute-20260724.1
FROM hexpm/elixir:${VERSION}@sha256:ceaeabd3ca1cc4a0df72755ae431063a3f48dbeca32e17c7fec266d2c70c0550

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
