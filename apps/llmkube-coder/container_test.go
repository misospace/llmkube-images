package main

import (
	"bytes"
	"context"
	"testing"

	"github.com/misospace/llmkube-images/testhelpers"
	"github.com/stretchr/testify/require"
	"github.com/testcontainers/testcontainers-go"
	tcexec "github.com/testcontainers/testcontainers-go/exec"
	"github.com/testcontainers/testcontainers-go/wait"
)

func Test(t *testing.T) {
	// Default tag is the fallback used when $TEST_IMAGE is unset; CI sets
	// $TEST_IMAGE to the freshly built image. See AGENTS.md → Container Test Patterns.
	image := testhelpers.GetTestImage("ghcr.io/misospace/llmkube-coder:rolling")
	testhelpers.TestFileExists(t, image, "/foreman-agent", nil)
	// The agent binary and all three language toolchains the coder self-gate uses.
	testhelpers.TestCommandSucceeds(t, image, nil, "foreman-agent", "--version")
	testhelpers.TestCommandSucceeds(t, image, nil, "python3", "--version")
	testhelpers.TestCommandSucceeds(t, image, nil, "node", "--version")
	testhelpers.TestCommandSucceeds(t, image, nil, "npm", "--version")
	testhelpers.TestCommandSucceeds(t, image, nil, "go", "version")
	testhelpers.TestCommandSucceeds(t, image, nil, "git", "--version")
	// Representative Python + Node linters.
	testhelpers.TestCommandSucceeds(t, image, nil, "ruff", "--version")
	testhelpers.TestCommandSucceeds(t, image, nil, "eslint", "--version")
	// Godot + Elixir: the runtimes that used to need their own images.
	testhelpers.TestCommandSucceeds(t, image, nil, "godot", "--headless", "--version")
	testhelpers.TestCommandSucceeds(t, image, nil, "elixir", "--version")
	testhelpers.TestCommandSucceeds(t, image, nil, "sh", "-c",
		`ls "$MIX_HOME"/archives/hex-*.ez >/dev/null 2>&1 && `+
			`[ -x "$MIX_HOME/rebar3" ] && `+
			`[ -d "$MIX_HOME" ]`)
	// Run rebar3, do not just check the executable bit. rebar3 is an escript
	// and has to be compatible with the OTP this image ships; the bit being
	// set says nothing about that. This became load-bearing when the download
	// moved off builds.hex.pm — that URL selected an artifact per OTP release
	// (rebar3-$VERSION-otp-27), while the GitHub release asset is one generic
	// escript for every OTP. Nothing else here would notice a mismatch: the
	// mix smoke test below builds a bare project with no Erlang dependencies,
	// so it never invokes rebar3, and the failure would first appear when a
	// real Elixir gate compiled a dep.
	testhelpers.TestCommandSucceeds(t, image, nil, "sh", "-c", `"$MIX_HOME/rebar3" version`)

	// Presence and runnability are still not enough: Mix resolves rebar3 from a
	// version-scoped directory, $MIX_HOME/elixir/<elixir>-otp-<otp>/rebar3, and
	// ignores $MIX_HOME/rebar3 entirely. Unregistered, the first dep with a
	// rebar build makes `mix deps.get` install its own copy into root-owned
	// MIX_HOME, which fails as uid 65534. The bare `mix new` project below has
	// no Erlang dependencies, so nothing else in this file reaches that path.
	// Same defect, and same check, as apps/elixir-gate (#297).
	testhelpers.TestCommandSucceeds(t, image, nil, "sh", "-c",
		`ls "$MIX_HOME"/elixir/*/rebar3 >/dev/null 2>&1`)
}

// TestElixirProjectCompiles proves mix can create, compile, and test a project
// as the non-root uid — `elixir --version` exercises none of the MIX_HOME /
// HEX_HOME split this image depends on. This crashed under QEMU during
// development (BEAM JIT); on native amd64 it must pass.
func TestElixirProjectCompiles(t *testing.T) {
	image := testhelpers.GetTestImage("ghcr.io/misospace/llmkube-coder:rolling")
	testhelpers.TestCommandSucceeds(t, image, nil, "sh", "-c", `set -e
d=$(mktemp -d) && cd "$d"
mix new smoke --app smoke >/dev/null
cd smoke && mix test 2>&1 | grep -qE '[1-9][0-9]* (test|doctest)'`)
}

// TestGodotRunsAProject proves a project imports and a script executes headless
// — a GDScript parse error must fail loudly, which is what the per-repo coder
// exists to catch before a PR opens (windowstead#321).
func TestGodotRunsAProject(t *testing.T) {
	image := testhelpers.GetTestImage("ghcr.io/misospace/llmkube-coder:rolling")
	testhelpers.TestCommandSucceeds(t, image, nil, "sh", "-c", `set -e
d=$(mktemp -d) && cd "$d"
printf 'config_version=5\n[application]\nconfig/name="smoke"\n' > project.godot
printf 'extends SceneTree\nfunc _init():\n\tprint("POLYGLOT_OK")\n\tquit()\n' > s.gd
export HOME=/tmp
godot --headless --path . --script res://s.gd | grep -q POLYGLOT_OK
printf 'extends SceneTree\nfunc _init():\n\tnot valid(\n' > bad.gd
godot --headless --path . --script res://bad.gd 2>&1 | grep -qi "parse error"`)
}

// TestDeepmergeTsAllCopiesPatched asserts that every copy of deepmerge-ts in
// the image's node_modules tree has major version >= 8 (GHSA-ggr8-5vv4-36mx,
// fixed in 8.0.0). The Dockerfile override fans out to all copies, but a
// future Prisma layout change could reintroduce a vulnerable nested copy that
// the build-time assertion misses. This test catches that at image-test time.
func TestDeepmergeTsAllCopiesPatched(t *testing.T) {
	image := testhelpers.GetTestImage("ghcr.io/misospace/llmkube-coder:rolling")
	testhelpers.TestCommandSucceeds(t, image, nil, "sh", "-c", `set -e
found=0
for d in $(find /usr/local/lib/node_modules -type d -name deepmerge-ts -path '*/node_modules/*'); do
  found=1
  major=$(node -p "require('$d/package.json').version" | cut -d. -f1)
  if [ "$major" -lt 8 ]; then
    echo "FAIL: $d reports major $major (< 8)" >&2
    exit 1
  fi
done
if [ "$found" -eq 0 ]; then
  echo "FAIL: no deepmerge-ts found under /usr/local/lib/node_modules" >&2
  exit 1
fi`)
}

// TestMysql2AllCopiesPatched asserts that every resolvable copy of mysql2 in
// the image's node_modules tree is at or past 3.22.0 (GHSA-3f6p-5ww8-9rcr).
// prisma pulls it transitively, so a future Prisma bump can reintroduce a
// vulnerable nested copy the Dockerfile's fan-out did not reach.
//
// Directories with no package.json are skipped deliberately: prisma ships a
// BUNDLED mysql2 at @prisma/studio-core/dist/data/mysql2 which is a build
// artifact rather than a package. Nothing resolves it as a module and the SBOM
// does not report it, so asserting a version there would fail on a copy that
// carries no version and is not the finding.
func TestMysql2AllCopiesPatched(t *testing.T) {
	image := testhelpers.GetTestImage("ghcr.io/misospace/llmkube-coder:rolling")
	testhelpers.TestCommandSucceeds(t, image, nil, "sh", "-c", `set -e
found=0
for d in $(find /usr/local/lib/node_modules -type d -name mysql2 -path '*/node_modules/*'); do
  [ -f "$d/package.json" ] || continue
  found=1
  v=$(node -p "require('$d/package.json').version")
  major=$(echo "$v" | cut -d. -f1)
  minor=$(echo "$v" | cut -d. -f2)
  if [ "$major" -lt 3 ] || { [ "$major" -eq 3 ] && [ "$minor" -lt 22 ]; }; then
    echo "FAIL: $d reports $v (< 3.22.0)" >&2
    exit 1
  fi
done
if [ "$found" -eq 0 ]; then
  echo "FAIL: no resolvable mysql2 found under /usr/local/lib/node_modules" >&2
  exit 1
fi`)
}

// TestRepoFetchToolsPresent pins the tools a repo's own test command shells
// out to. Gates are not dispatched, so this image runs those commands itself,
// and the image it replaced on that path (elixir-gate) shipped curl and unzip.
// Purging them here turned a pinchflat run into
// "tooling/fetch-sqlean.sh: line 51: curl: command not found" AFTER the coder
// had already done the work -- a failure with no signal in this repo at all.
func TestRepoFetchToolsPresent(t *testing.T) {
	image := testhelpers.GetTestImage("ghcr.io/misospace/llmkube-coder:rolling")
	for _, tool := range []string{"curl", "unzip"} {
		testhelpers.TestCommandSucceeds(t, image, nil, "sh", "-c",
			`command -v `+tool+` >/dev/null 2>&1 || { echo "FAIL: `+tool+` missing" >&2; exit 1; }`)
	}
	// Reachable as the non-root runtime uid, not merely present on disk.
	testhelpers.TestCommandSucceeds(t, image, nil, "curl", "--version")
}

func TestReadOnlyRootfs(t *testing.T) {
	// Default tag is the fallback used when $TEST_IMAGE is unset; CI sets
	// $TEST_IMAGE to the freshly built image. See AGENTS.md → Container Test Patterns.
	image := testhelpers.GetTestImage("ghcr.io/misospace/llmkube-coder:rolling")
	roCfg := &testhelpers.ContainerConfig{ReadOnlyRootfs: true}
	testhelpers.TestCommandSucceeds(t, image, roCfg, "foreman-agent", "--version")
	testhelpers.TestCommandSucceeds(t, image, roCfg, "python3", "--version")
	testhelpers.TestCommandSucceeds(t, image, roCfg, "node", "--version")
	testhelpers.TestCommandSucceeds(t, image, roCfg, "go", "version")
	testhelpers.TestCommandSucceeds(t, image, roCfg, "godot", "--headless", "--version")
	testhelpers.TestCommandSucceeds(t, image, roCfg, "elixir", "--version")
}

// TestGitSafeDirectoryScopedToWork proves the safe.directory exemption is
// scoped to /work, not global (the '*' that #430 retires).
//
// The dubious-ownership guard (git >= 2.35.2) fires whenever git reads a
// repository owned by a uid different from the uid that process runs as. So
// the probe repos are ROOT-owned (seeded with docker exec -u 0) while every
// probe git runs as the image's own nobody (65534) — the uid the foreman pod
// runs the coder as. Both repos live in one persistent container so the
// seeded state is visible to every probe, and the only thing that differs
// between the two clones is the SOURCE repo's path:
//
//   - clone a root-owned repo UNDER /work → must SUCCEED. This is the
//     production case: the foreman clones into /work as a (possibly
//     pod-overridden) uid, and only 'safe.directory /work' keeps git from
//     refusing it.
//   - clone a root-owned repo OUTSIDE /work → must FAIL with "detected
//     dubious ownership", proving the guard is still armed for everything
//     that is not the workspace.
//
// Both regressions are covered: with the old 'safe.directory *' the outside
// clone succeeds (guard off for every path); with a scoping narrower than
// /work (or none) the under /work clone fails. The "detected dubious
// ownership" wording is stable across git 2.35..2.5x, so the assertion does
// not rot on a git bump.
func TestGitSafeDirectoryScopedToWork(t *testing.T) {
	image := testhelpers.GetTestImage("ghcr.io/misospace/llmkube-coder:rolling")

	// One long-lived container; the entrypoint (sleep infinity) is replaced.
	c, err := testcontainers.Run(t.Context(), image,
		testcontainers.WithEntrypoint("sleep"),
		testcontainers.WithEntrypointArgs("infinity"),
		testcontainers.WithWaitStrategy(wait.ForNop(func(context.Context, wait.StrategyTarget) error { return nil })),
	)
	testcontainers.CleanupContainer(t, c)
	require.NoError(t, err, "start persistent container")

	// Seed two root-owned repos. Root is required only for the OWNERSHIP (the
	// guard compares the repo's st_uid against the git process uid); the coder
	// runtime itself runs as 65534 and never as root.
	seed := `set -e
seed_repo() {
  d=$1
  rm -rf "$d"
  mkdir -p "$d"
  git init -q -C "$d"
  git -C "$d" config user.email a@b
  git -C "$d" config user.name a
  echo x > "$d/f"
  git -C "$d" add f
  git -C "$d" -c commit.gpgsign=false commit -qm seed
}
seed_repo /work/origin
seed_repo /tmp/origin`
	code, out, err := execInContainer(t, c, []string{"sh", "-c", seed}, tcexec.WithUser("0"))
	require.NoError(t, err)
	require.Equal(t, 0, code, "seeding root-owned repos failed: %s", out)

	// 1) clone of a root-owned repo that lives UNDER /work: the exemption
	//    must cover it, so this succeeds.
	code, out, err = execInContainer(t, c, []string{"git", "clone", "-q", "/work/origin", "/tmp/dw"})
	require.NoError(t, err)
	require.Equal(t, 0, code,
		"cloning a root-owned repo from under /work must succeed (it is the exemption's purpose): %s", out)

	// 2) a clone into a non-/work path whose source is a root-owned repo OUTSIDE
	//    /work: the guard must refuse it with its own message and a non-zero
	//    exit. This is the regression #430 fixes — the old 'safe.directory *'
	//    made this clone succeed, so the test would fail on that image.
	code, out, err = execInContainer(t, c, []string{"git", "clone", "-q", "/tmp/origin", "/tmp/do"})
	require.NoError(t, err)
	require.NotEqual(t, 0, code,
		"cloning a root-owned repo from outside /work must fail — 'safe.directory' is not scoped to /work: %s", out)
	require.Contains(t, out, "detected dubious ownership",
		"the refusal must be git's dubious-ownership guard, not an unrelated error: %s", out)
}

// execInContainer runs one command inside an already-running container via
// docker exec and returns its exit code plus the combined stdout+stderr. The
// container's configured user is the image's own non-root uid (65534); the
// extra ProcessOptions (e.g. tcexec.WithUser) override it for that single
// exec. The testhelpers package only ships TestCommandSucceeds, which asserts
// a specific outcome up front, so this local exec mirror is the minimal way to
// observe raw results for BOTH a success case and a failure case.
func execInContainer(t *testing.T, c testcontainers.Container, args []string, opts ...tcexec.ProcessOption) (int, string, error) {
	t.Helper()
	require.NotEmpty(t, args, "execInContainer: no command given")

	code, reader, err := c.Exec(t.Context(), args, opts...)
	require.NoError(t, err, "exec %v", args)
	buf := new(bytes.Buffer)
	_, _ = buf.ReadFrom(reader)
	return code, buf.String(), nil
}
