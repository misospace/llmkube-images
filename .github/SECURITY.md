# Security Policy

## Vulnerability Scanning

This repository uses [Grype](https://github.com/anchore/grype) via GitHub Actions to scan all published container images for known vulnerabilities on a daily schedule.

### Scan Configuration

- **Tool:** Grype (via `anchore/scan-action@v7.4.0`)
- **Schedule:** Daily at 01:30 UTC
- **Severity cutoff:** `high` — findings at High or Critical severity fail the build
- **Fail-build:** `true` — High/Critical vulnerabilities block the workflow run

### Gating Policy

High and Critical severity findings **fail both the pre-publish scan and the post-publish scan**. This ensures that:

1. No image with unmitigated High/Critical vulnerabilities is published as `:rolling` or a semver tag. The pre-publish Grype scan in `.github/workflows/app-builder.yaml` runs against every platform image digest built for the app and is a hard prerequisite of the `merge` job, so a High/Critical finding prevents the multi-platform `:rolling`/semver manifests from being created or pushed.
2. Findings are immediately visible to maintainers via the failed workflow run.
3. The scheduled `.github/workflows/vulnerability-scan.yaml` continues to run daily as defense in depth against newly disclosed vulnerabilities in already-published images.
4. Open alerts on GitHub Code Scanning are actively triaged and resolved.

### Acceptable Risk Exceptions

Some base OS packages (e.g., Debian bookworm) may carry known vulnerabilities that are tracked separately via distribution security advisories. These are patched when the base image (`node:24-bookworm-slim`) is updated, not at the application level. If such exceptions are needed, they may be added to `ignore-vulnerabilities` in `.github/workflows/vulnerability-scan.yaml` with a comment linking to the tracking issue.

### Application-Level Dependencies

Application-level dependencies (npm packages bundled by the Node.js base image) must be patched at build time. The standard approach is:

1. Bump the `node:24-bookworm-slim` base image digest when a new patch release is available.
2. If the base image does not yet carry the fix, run `npm install -g npm@latest` in the Dockerfile to upgrade npm and its vendored dependencies.

### Reporting Vulnerabilities

Report security vulnerabilities via [GitHub Security Advisories](https://github.com/misospace/llmkube-images/security/advisories/new).
