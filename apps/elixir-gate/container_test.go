package main

import (
	"testing"

	"github.com/misospace/llmkube-images/testhelpers"
)

func Test(t *testing.T) {
	// Default tag is the fallback used when $TEST_IMAGE is unset; CI sets
	// $TEST_IMAGE to the freshly built image. See AGENTS.md → Container Test Patterns.
	image := testhelpers.GetTestImage("ghcr.io/misospace/elixir-gate:1.20.3-erlang-29.0.5-ubuntu-resolute-20260724.1")

	// The toolchain must run under the strictest sandbox — read-only rootfs with
	// only /tmp writable — since all mix/hex/erlang state is redirected there.
	roCfg := &testhelpers.ContainerConfig{ReadOnlyRootfs: true}
	testhelpers.TestCommandSucceeds(t, image, roCfg, "elixir", "--version")

	// Hex and rebar must be visible to the NON-ROOT uid that runs the gate. They
	// are installed into a shared MIX_HOME because a $HOME-local install would be
	// invisible here — this is the check that catches that regression. We verify
	// by file presence rather than invoking `mix hex.info`, because Mix's archive
	// auto-load in CLI mode is not stable across Mix/OTP versions (see #236).
	testhelpers.TestCommandSucceeds(t, image, roCfg, "sh", "-c",
		`ls "$MIX_HOME"/archives/hex-*.ez >/dev/null 2>&1 && `+
			`[ -x "$MIX_HOME/rebar3" ] && `+
			`[ -d "$MIX_HOME" ] && `+
			`mkdir -p "$HEX_HOME" && [ -d "$HEX_HOME" ]`)

	// Presence is not enough: Mix looks for rebar3 under a version-scoped
	// directory, $MIX_HOME/elixir/<elixir>-otp-<otp>/rebar3, not at
	// $MIX_HOME/rebar3. A binary at the latter is invisible to Mix, so the
	// first project with a rebar-built dependency makes `mix deps.get` install
	// its own copy — which fails, because MIX_HOME is root-owned and the gate
	// runs as nobody. That took out three pinchflat gate runs whose code had
	// already passed its own suite (#297). The check above is the same class of
	// mistake as asserting rebar3's executable bit and calling it verified.
	testhelpers.TestCommandSucceeds(t, image, roCfg, "sh", "-c",
		`ls "$MIX_HOME"/elixir/*/rebar3 >/dev/null 2>&1`)

	// A real project must COMPILE and its tests RUN as the non-root user. `elixir
	// --version` exercises none of that: it writes no _build, invokes no compiler,
	// and never touches the writable-path setup the gate depends on.
	testhelpers.TestCommandSucceeds(t, image, nil, "sh", "-c", `set -e
d=$(mktemp -d) && cd "$d"
mix new smoke --app smoke >/dev/null
cd smoke
mix test 2>&1 | grep -qE '[1-9][0-9]* (test|doctest)'
echo GATE_SMOKE_OK`)

	// The BEAM falls back to latin1 filename encoding without a UTF-8 locale,
	// which silently corrupts unicode filenames and string literals in gate
	// projects. The smoke project above is ASCII, so this is the check that
	// catches a missing LANG: the image must export LANG=C.UTF-8, and elixir
	// must round-trip a non-ASCII filename and string literal.
	testhelpers.TestCommandSucceeds(t, image, roCfg, "sh", "-c",
		`[ "$LANG" = "C.UTF-8" ]`)
	testhelpers.TestCommandSucceeds(t, image, roCfg, "sh", "-c", `set -e
d=$(mktemp -d) && cd "$d"
printf 'ok' > "ünicode.exs"
elixir -e 'IO.puts(File.read!("ünicode.exs"))' | grep -q ok
elixir -e 'IO.puts("héllo")' | grep -q 'héllo'
echo GATE_UNICODE_OK`)

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
