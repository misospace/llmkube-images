# llmkube-images

`llmkube-images` builds and publishes the rootless, digest-immutable, multi-architecture
container images that power the LLMKube **foreman** fleet. It is a Go module that drives
`docker buildx` builds (orchestrated through `docker-bake.hcl` per app), runs
`testcontainers-go` integration tests against each image, and gates publication on
scanning. Each image is a single-purpose, read-only-rootfs-safe toolchain — no `root`,
no mutable `:latest` tags, no process managers — sized so the foreman can run verify
gates and the coder on a read-only, non-privileged workload.

## Published images

| Image | ghcr tag | Intended foreman profile |
|-------|----------|--------------------------|
| [`llmkube-coder`](apps/llmkube-coder/) | `ghcr.io/misospace/llmkube-coder` (`:rolling`, `:sandbox`, semver) | The LLMKube **coder** — the foreman-agent (cross-compiled from LLMKube source) plus a Python + Node + Go + Godot + Elixir self-gate toolchain. Entry point: `/foreman-agent`. |
| [`elixir-gate`](apps/elixir-gate/) | `ghcr.io/misospace/elixir-gate` (e.g. `1.20.4`) | **Verify gate** toolchain for Elixir/OTP repos (e.g. `misospace/pinchflat`). Bakes the Hex/Rebar + `mix`/`yarn` toolchain at build time since the gate runs non-root with no install at runtime. |
| [`godot-gate`](apps/godot-gate/) | `ghcr.io/misospace/godot-gate` (e.g. `4.7.2`) | **Verify gate** runtime for Godot repos (e.g. `windowstead`). Ships the Godot headless binary (SHA-512 pinned, download at build time, never at runtime) on a read-only rootfs. `amd64` only. |

`llmkube-coder` and `godot-gate` are `amd64`-only (Godot upstream ships only a
`linux x86_64` headless binary and the fleet nodes are `amd64`); `elixir-gate` builds
`linux/amd64` and `linux/arm64`.

## Usage

Images are pulled from GHCR by tag or by digest. In the foreman fleet, a verify gate
clones the target repo into `/work` and runs as the image's non-root user against a
read-only rootfs, e.g.:

```sh
docker run --rm --read-only --tmpfs /tmp --workdir /work \
  -v /path/to/repo:/work \
  ghcr.io/misospace/godot-gate:4.7.2
```

In CI and tests the image under test is selected with the `TEST_IMAGE` environment
variable (see `testhelpers.GetTestImage`), falling back to a stable, immutable tag
(`:rolling` for the coder, an explicit version for the gates).

## Review standards

The full container standards — rootless-by-default, digest-immutable, one process per
container, multi-arch, read-only-rootfs-safe, no baked-in secrets — plus the SHA-pinned
binary-download policy and version-pinning rules live in
[`AGENTS.md`](AGENTS.md). This README deliberately defers to it rather than duplicating
those rules.

## Renovate & the scan gate

- **Renovate** manages image and toolchain versions in place (the `VERSION` defaults in
  each `docker-bake.hcl` and the annotated `ARG`s in the Dockerfiles), opening one PR
  per app and auto-merging once the build + test CI is green. See `.renovaterc.json5`.
- **Scheduled vulnerability scan**: a nightly workflow
  (`.github/workflows/vulnerability-scan.yaml`) re-scans each published image with
  **Grype** (`--fail-on high --only-fixed`), gating both the `:rolling` tag and the
  highest semver-pinned tag (resolved via the `:rolling` image's
  `org.opencontainers.image.version` label). Downstream foreman pods pin the semver
  tag rather than `:rolling`, so the gate covers the tag they actually pull.
  Unfixable base-OS advisories still print and upload to the security tab; they
  still do not block.

> Note: the GitHub repo **Description** field (the sidebar header) is currently empty.
> Filling it is a one-line `gh repo edit --description` on the GitHub settings page and
> is outside this repo's automation; it is flagged here for whoever owns the repo
> settings.
