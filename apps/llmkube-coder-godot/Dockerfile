# syntax=docker/dockerfile:1

# Build stage: cross-compile the static foreman-agent from LLMKube source.
# CGO is disabled, so the binary runs on the Debian runtime below with no
# Go toolchain present. Pinned to $BUILDPLATFORM + GOOS/GOARCH so the compiler
# always runs natively (arm64 never pays QEMU's interpreted-compile cost).
FROM --platform=$BUILDPLATFORM golang:1.26-bookworm@sha256:6c5605ab3a9a9fb3c4eafe5b3d63cdbf3881caf113262b67862547b54a9db599 AS build
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

# Runtime: Godot headless, matching the toolchain the target repo declares.
# misospace/windowstead pins 4.2.2 in godot-toolchain.json, and both its CI and
# its verify gate run that version; a coder on a different engine would report
# results CI does not reproduce.
FROM debian:bookworm-slim@sha256:abd67ffcfa541b485a3dff59865ab629aa048a6c613e639d36e7456b0b229241
# renovate: datasource=github-releases depName=godotengine/godot
ARG GODOT_VERSION=4.2.2
ARG GODOT_STATUS=stable
# SHA512 from the release's own SHA512-SUMS.txt. Must be updated alongside
# GODOT_VERSION — a stale digest fails the build loudly rather than installing
# an unverified engine.
ARG GODOT_SHA512=4c0294f437b97cf14f848d921ed028cb6e100ebbfcf6480f2d50292d001221cf29cda73f0a96a8c0e80b145b65cdbf7e422252dbbe17e79d883753e500306276

LABEL org.opencontainers.image.title="llmkube-coder-godot" \
      org.opencontainers.image.description="LLMKube foreman coder agent (built from source) with a Godot headless self-gate toolchain" \
      org.opencontainers.image.source="https://github.com/defilantech/LLMKube" \
      org.opencontainers.image.licenses="Apache-2.0"

# libfontconfig1 is Godot headless's one runtime lib dep. curl/unzip fetch the
# engine at BUILD time — the coder pod cannot install anything at run time.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates curl git libfontconfig1 unzip \
    && curl -fsSL "https://github.com/godotengine/godot-builds/releases/download/${GODOT_VERSION}-${GODOT_STATUS}/Godot_v${GODOT_VERSION}-${GODOT_STATUS}_linux.x86_64.zip" -o /tmp/godot.zip \
    && echo "${GODOT_SHA512}  /tmp/godot.zip" | sha512sum -c - \
    && unzip -oq /tmp/godot.zip -d /tmp/godot \
    && mv "/tmp/godot/Godot_v${GODOT_VERSION}-${GODOT_STATUS}_linux.x86_64" /usr/local/bin/godot \
    && chmod 0755 /usr/local/bin/godot \
    && rm -rf /tmp/godot.zip /tmp/godot /var/lib/apt/lists/* \
    && apt-get purge -y --auto-remove curl unzip

# Read-only-rootfs friendly: Godot, git and the import cache all write under
# /tmp, so the image works whatever uid the pod runs as.
ENV HOME=/tmp \
    XDG_CACHE_HOME=/tmp/.cache \
    XDG_CONFIG_HOME=/tmp/.config \
    XDG_DATA_HOME=/tmp/.local/share
RUN git config --system --add safe.directory '*'

COPY --from=build /out/foreman-agent /foreman-agent
RUN chmod 0755 /foreman-agent \
    && ln -sf /foreman-agent /usr/local/bin/foreman-agent

# nobody:nogroup (repo default). The foreman pod may override the uid; the image
# is uid-agnostic — writable state lives in /tmp and the tools are
# world-executable.
USER 65534:65534
ENTRYPOINT ["/foreman-agent"]
