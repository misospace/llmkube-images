# syntax=docker/dockerfile:1

# Build stage: cross-compile the static foreman-agent from LLMKube source.
# CGO is disabled, so the binary runs on the Go runtime below. Pinned to
# $BUILDPLATFORM + GOOS/GOARCH so the compiler always runs natively.
FROM --platform=$BUILDPLATFORM golang:1.26-bookworm@sha256:349ad04971da5f200a537641ae2c70774a592ca21fad4b513b65f813f546781a AS build
ARG VERSION
ARG TARGETOS
ARG TARGETARCH
ENV CGO_ENABLED=0
WORKDIR /build
RUN mkdir -p /out /tmp/vresolve \
    && ( cd /tmp/vresolve && go mod init coderbuild >/dev/null 2>&1 \
         && go list -m -f '{{.Version}}' "github.com/defilantech/llmkube@v${VERSION}" > /out/llmkube.version ) \
    && LLMKUBE_VERSION="$(cat /out/llmkube.version)" \
    && GOOS="${TARGETOS:-linux}" GOARCH="${TARGETARCH}" go install -trimpath \
         -ldflags="-s -w -X main.Version=${LLMKUBE_VERSION} -X main.GitCommit=v${VERSION}" \
         "github.com/defilantech/llmkube/cmd/foreman-agent@v${VERSION}" \
    && cp "$(find "$(go env GOPATH)/bin" -name foreman-agent -type f | head -1)" /out/foreman-agent \
    && test -x /out/foreman-agent

# Runtime: the full Go toolchain — the coder self-gate runs `go build/test/vet`
# on Go repos, so unlike the python/node coders the language runtime IS the SDK.
FROM golang:1.26-bookworm@sha256:349ad04971da5f200a537641ae2c70774a592ca21fad4b513b65f813f546781a

LABEL org.opencontainers.image.title="llmkube-coder-go" \
      org.opencontainers.image.description="LLMKube foreman coder agent (built from source) with a Go self-gate toolchain" \
      org.opencontainers.image.source="https://github.com/defilantech/LLMKube" \
      org.opencontainers.image.licenses="Apache-2.0"

# git for the coder workspace.
RUN apt-get update \
    && apt-get install -y --no-install-recommends git ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Go self-gate linter.
# renovate: datasource=github-releases depName=golangci/golangci-lint
ARG GOLANGCI_LINT_VERSION=2.12.2
# golangci-lint v2+ carries the major version in its Go module path
# (github.com/golangci/golangci-lint/v2/...); v0/v1 do not. Derive it from the
# version so a future major bump doesn't re-break the install.
RUN set -eux; \
    major="${GOLANGCI_LINT_VERSION%%.*}"; \
    if [ "${major}" -ge 2 ]; then \
      modpath="github.com/golangci/golangci-lint/v${major}/cmd/golangci-lint"; \
    else \
      modpath="github.com/golangci/golangci-lint/cmd/golangci-lint"; \
    fi; \
    go install "${modpath}@v${GOLANGCI_LINT_VERSION}"; \
    mv "$(go env GOPATH)/bin/golangci-lint" /usr/local/bin/golangci-lint; \
    rm -rf /root/.cache/go-build

# Read-only-rootfs friendly: all writable Go state under /tmp, and git operates
# on the workspace regardless of the (possibly pod-overridden) uid.
ENV HOME=/tmp \
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
