# syntax=docker/dockerfile:1

# Download stage: fetch the Godot headless binary at build time (never at runtime
# — the foreman gate runs on a read-only rootfs where apt/curl/download fail,
# which is exactly why the previous apt-based gate could never run).
FROM debian:bookworm-slim@sha256:88200866dfff7ea7f5cbcb6ec7c8a701889efe6fe859fe64d6990e4b07ea4171 AS build
# renovate: datasource=github-releases depName=godotengine/godot
ARG VERSION=4.7.2
ARG GODOT_STATUS=stable
# GODOT_SHA512 is manually pinned: sha512 checksums are not part of GitHub
# release metadata, so Renovate's standard update flow cannot see them. When
# VERSION is bumped, re-pin this to the new binary's sha512 (see
# apps/llmkube-coder/Dockerfile, which pins the same value the same way).
# Do not add a renovate hint here — scripts/check-renovate-datasources.sh
# fails the lint job if one reappears.
ARG GODOT_SHA512=9aa00f7a605200940bce3027a567b782f49bd8e940dd06ae9e987bd65aee1b1467edd56ed84fcdcbdd44354bf613bdbb4e5d2913e925850368e150c59ed54c65
RUN apt-get update \
    && apt-get install -y --no-install-recommends curl unzip ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && curl -fsSL "https://github.com/godotengine/godot-builds/releases/download/${VERSION}-${GODOT_STATUS}/Godot_v${VERSION}-${GODOT_STATUS}_linux.x86_64.zip" -o /tmp/godot.zip \
    && echo "${GODOT_SHA512}  /tmp/godot.zip" | sha512sum -c - \
    && unzip -oq /tmp/godot.zip -d /tmp/godot \
    && mv "/tmp/godot/Godot_v${VERSION}-${GODOT_STATUS}_linux.x86_64" /usr/local/bin/godot \
    && chmod 0755 /usr/local/bin/godot

# Runtime: Godot 4.7.2 headless gate for foreman verify gates (windowstead et al).
# amd64 only — Godot upstream ships a linux x86_64 headless binary and the fleet
# nodes are amd64 (the bake `image-all` pins linux/amd64).
FROM debian:bookworm-slim@sha256:88200866dfff7ea7f5cbcb6ec7c8a701889efe6fe859fe64d6990e4b07ea4171
ARG VERSION=4.7.2

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
