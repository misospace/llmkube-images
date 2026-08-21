package main

import (
	"testing"

	"github.com/misospace/llmkube-images/testhelpers"
)

func Test(t *testing.T) {
	// Default tag is the fallback used when $TEST_IMAGE is unset; CI sets
	// $TEST_IMAGE to the freshly built image. See AGENTS.md → Container Test Patterns.
	image := testhelpers.GetTestImage("ghcr.io/misospace/elixir-gate:1.20.3-erlang-29.0.5-ubuntu-resolute-20260811.1")

	// The toolchain must run under the strictest sandbox — read-only rootfs with
	// only /tmp writable — since all mix/hex/erlang state is redirected there.
	roCfg := &testhelpers.ContainerConfig{ReadOnlyRootfs: true}
	testhelpers.TestCommandSucceeds(t, image, roCfg, "elixir", "--version")

	// Hex and rebar must be visible to the NON-ROOT uid that runs the gate. They
	// are installed into a shared MIX_HOME because a $HOME-local install would be
	// invisible here — this is the check that catches that regression.
	testhelpers.TestCommandSucceeds(t, image, roCfg, "sh", "-c",
		`mix hex.info >/dev/null && test -d "$MIX_HOME" && test -d "$HEX_HOME"`)

	// A real project must COMPILE and its tests RUN as the non-root user. `elixir
	// --version` exercises none of that: it writes no _build, invokes no compiler,
	// and never touches the writable-path setup the gate depends on.
	testhelpers.TestCommandSucceeds(t, image, nil, "sh", "-c", `set -e
d=$(mktemp -d) && cd "$d"
mix new smoke --app smoke >/dev/null
cd smoke
mix test 2>&1 | grep -qE '[1-9][0-9]* (test|doctest)'
echo GATE_SMOKE_OK`)

	// Native SQLite extensions are fetched during project setup — pinchflat's
	// tooling/fetch-sqlean.sh curls a zip and unzips it, and its Repo loads that
	// extension outside the prod guard, so `mix test` fails without it. bash too:
	// the script uses [[ ]].
	testhelpers.TestCommandSucceeds(t, image, roCfg, "sh", "-c",
		`command -v curl && command -v unzip && command -v bash`)

	// The gate clones into /work as a possibly-overridden uid; that must not fail
	// on a permission error the way an unprepared root-owned /work does.
	testhelpers.TestCommandSucceeds(t, image, nil, "sh", "-c",
		`git init -q /work/probe && cd /work/probe && git config user.email a@b && git config user.name a &&
		 echo x > f && git add f && git -c commit.gpgsign=false commit -qm x`)
}
