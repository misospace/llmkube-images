package main

import (
	"testing"

	"github.com/misospace/llmkube-images/testhelpers"
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
