# Containers — AI Review Standards

You review pull requests for a rootless, semantically versioned, multi-architecture container image collection.

## What This Repo Is

- A Go module building and testing container Dockerfiles
- Individual container images under `apps/`
- Test helpers in `testhelpers/`
- A `docker-bake.hcl` build orchestration file
- Go module with `testcontainers-go` for integration testing

## Review Standards

### Container Image Requirements

Every container MUST:

1. **Rootless by default**
    - Run as `nobody:nogroup` / `65534:65534`
    - No `USER root` unless absolutely required for a specific capability
    - If root is temporarily required, switch back to `nobody` before `CMD`/`ENTRYPOINT`

2. **Immutable via digest**
    - Use `@sha256:...` digest pinning for runtime images
    - Do not use mutable tags like `:latest`
    - The action will flag any image reference that lacks a digest

3. **One process per container**
    - Single `CMD` or `ENTRYPOINT`
    - No `s6-overlay`, supervisord, or similar process managers
    - Log to stdout/stderr (no log files unless mounted)

4. **Multi-architecture support**
    - Must build for `linux/amd64` and `linux/arm64`
    - Use `ARG TARGETARCH` for architecture-specific logic
    - Test with `docker/bake-action` or equivalent in CI

5. **Read-only root filesystem compatible**
    - Write persistent data to mounted volumes only
    - Use `/tmp` as a tmpfs when `read_only: true` is needed
    - No state written to image layers at runtime

6. **No secrets baked into images**
    - No API keys, tokens, or credentials in Dockerfiles
    - Use environment variables passed at runtime
    - Use `--build-arg` for sensitive build-time values, not hardcoded defaults

### Dockerfile Quality

Good patterns:

```dockerfile
FROM python:3.13-alpine3.23
ARG TARGETARCH
USER nobody:nogroup
COPY --chown=nobody:nogroup . /app
CMD ["/app/entrypoint.sh"]
```

Bad patterns to flag:

- `USER root` without justification
- `curl | sh` or unguarded external scripts
- Missing `--no-cache` on `apk`/`apt`
- Hardcoded version numbers without `ARG`
- Writing to image filesystem at runtime
- Missing shellcheck/hadolint violations for shell scripts

### Version Pinning

- Base images: pin to a specific tag or digest, not `:latest`
- Build tools: use `ARG VERSION` and pass it at build time
- Renovate-managed dependencies: `@version` format in comments
- `docker-bake.hcl` `VERSION` defaults are the single managed declaration for an app.
  Renovate updates them in place via the "Process Annotations in Docker Bake" custom
  manager in `.renovaterc.json5`, keyed off the `// renovate:` comment above each default.
  `.github/actions/app-options` reads the same value back with `docker buildx bake --list`
  to tag the published image, so the default is what the release is named after. Do not
  treat it as a placeholder or edit it to something the digest below it does not ship.
- Third-party binary downloads: verify checksums when possible

### Security

- No exposed secrets in entrypoint.sh or defaults/\*
- Container capability drops: CAP_SYS_ADMIN requires explicit justification
- Network access: flag containers that bind to all interfaces unnecessarily

### Go Code Standards

- Follow standard Go project layout
- go.mod must be clean (go mod tidy)
- Tests: use testcontainers-go for integration tests
- No hardcoded credentials in test helpers

### Commit and PR Standards

- Commit messages: conventional commits (fix:, feat:, chore:, docs:)
- PR titles: descriptive, matching commit style
- PR description: explain why, not just what
- Breaking changes: must be called out explicitly

## What to Flag

- Any USER root in a Dockerfile without a comment explaining why
- Image references without @sha256: digests
- latest tags in Dockerfile FROM or ARG defaults
- Shell scripts that curl | bash or download from untrusted sources
- Missing architecture handling (TARGETARCH)
- Files written to image filesystem at runtime
- Overly broad ARG defaults that mask version drift

## What to Approve

- Rootless containers with correct USER directives
- Digest-pinned image references
- Clean go.mod with no // indirect drift unless justified
- Well-structured docker-bake.hcl targets
- Proper use of COPY --chown
- Minimal, single-purpose entrypoint scripts
- Multi-architecture builds using TARGETARCH

## Skip Review For

- CI-only changes to GitHub Actions workflow files (workflow changes are reviewed separately)
- Dependency bot updates (renovate/) when they only update version comments in Go files or container versions
- Documentation-only PRs
- Auto-generated files from go generate or similar tooling

## Zizmor Suppressions

The following `# zizmor: ignore[...]` suppressions are intentional and reviewed:

| File | Line | Rule | Justification |
|------|------|------|---------------|
| `.github/workflows/mise-lock.yaml` | 28 | `bot-conditions` | Workflow intentionally only runs when triggered by `renovate[bot]`. The filter prevents manual or unrelated pushes from running the mise lock update. Revisit if non-bot triggers are needed. |

## Container Test Patterns

All container test files (e.g. `apps/llmkube-coder/container_test.go`, `apps/godot-gate/container_test.go`) resolve the image under test through `testhelpers.GetTestImage()`, which reads the `$TEST_IMAGE` environment variable first and falls back to a hardcoded default tag when the variable is unset.

- **CI** sets `TEST_IMAGE` to the freshly built image reference (digest or `:rolling` tag) before invoking `go test`. This is the value actually exercised in CI.
- **Local development** can set `TEST_IMAGE` to test a specific image, or leave it unset to rely on the hardcoded fallback in each test file.
- **The hardcoded default in each test file is the fallback**, not the CI-set value. Treat it as a last-resort value: keep it pointing at a stable, immutable tag (e.g. `:rolling` for the coder images, an explicit version such as `:4.7.1` for godot-gate) and never use a mutable tag such as `:latest` here — the rest of this repository emphasises digest-immutability for the same reason.

Example call site:

```go
image := testhelpers.GetTestImage("ghcr.io/misospace/llmkube-coder:rolling")
```

## Known Gaps & Technical Debt

- **No automated integration tests**: The CI pipeline only runs `docker buildx bake` for syntax validation. There are no end-to-end tests that start containers and verify LLM endpoints respond correctly.

## Filing issues for the autonomous loop

Issues here are picked up by an autonomous coding loop (dispatch → foreman), and two
parts of the body feed deterministic reviewer rails. Agents filing issues in this repo
must include both.

**1. State the ask in one imperative sentence.** The reviewer quotes it verbatim to
prove it actually read the issue. If it can only paraphrase, its GO is demoted to NO-GO
unless the rail below vouches — costing a revision cycle and an escalation review.

**2. Name the concrete file paths the fix is expected to touch** (backticks are fine).
The scope-overlap rail vouches for a diff that touches a named file, and that vouch is
what survives a paraphrased ask.

Name only paths you are confident about. An issue that names files the diff does *not*
touch is read as scope drift and also gets the change rejected — so when unsure, name
none rather than guessing.
