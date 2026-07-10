# syntax=docker/dockerfile:1

# Download stage: fetch the Godot headless binary at build time (never at runtime
# — the foreman gate runs on a read-only rootfs where apt/curl/download fail,
# which is exactly why the previous apt-based gate could never run).
FROM debian:bookworm-slim@sha256:60eac759739651111db372c07be67863818726f754804b8707c90979bda511df AS build
# renovate: datasource=github-releases depName=godotengine/godot
ARG VERSION=4.2.2
ARG GODOT_STATUS=stable
RUN apt-get update \
    && apt-get install -y --no-install-recommends curl unzip ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && curl -fsSL "https://github.com/godotengine/godot-builds/releases/download/${VERSION}-${GODOT_STATUS}/Godot_v${VERSION}-${GODOT_STATUS}_linux.x86_64.zip" -o /tmp/godot.zip \
    && unzip -oq /tmp/godot.zip -d /tmp/godot \
    && mv "/tmp/godot/Godot_v${VERSION}-${GODOT_STATUS}_linux.x86_64" /usr/local/bin/godot \
    && chmod 0755 /usr/local/bin/godot

# Runtime: Godot 4.2.2 headless gate for foreman verify gates (windowstead et al).
# amd64 only — Godot upstream ships a linux x86_64 headless binary and the fleet
# nodes are amd64 (the bake `image-all` pins linux/amd64).
FROM debian:bookworm-slim@sha256:60eac759739651111db372c07be67863818726f754804b8707c90979bda511df
ARG VERSION=4.2.2

LABEL org.opencontainers.image.title="godot-gate" \
      org.opencontainers.image.description="Godot ${VERSION} headless runtime for foreman verify gates (read-only-rootfs safe)" \
      org.opencontainers.image.source="https://github.com/misospace/llmkube-images" \
      org.opencontainers.image.licenses="MIT"

# libfontconfig1 is Godot headless's one runtime lib dep; git + ca-certificates
# for the gate's checkout/fetch.
RUN apt-get update \
    && apt-get install -y --no-install-recommends libfontconfig1 ca-certificates git \
    && rm -rf /var/lib/apt/lists/*

COPY --from=build /usr/local/bin/godot /usr/local/bin/godot

# The gate runs as a non-root user; point all Godot/font/git state at world-
# writable /tmp so no write lands on a root-owned path.
ENV HOME=/tmp \
    XDG_CACHE_HOME=/tmp/.cache \
    XDG_CONFIG_HOME=/tmp/.config \
    XDG_DATA_HOME=/tmp/.local/share
RUN git config --system --add safe.directory '*'

# The foreman verify gate clones the target repo into /work and runs as this
# image's non-root user. Create it world-writable (sticky, like /tmp) so the
# clone — and Godot's in-project .godot import cache under `--path .` — can write
# regardless of the (possibly pod-overridden) uid. Without this, `git clone …
# /work` fails with "could not create work tree dir '/work': Permission denied"
# because a non-root uid cannot mkdir under root-owned /.
RUN mkdir -p /work && chmod 1777 /work

USER 65534:65534
ENTRYPOINT ["godot"]
