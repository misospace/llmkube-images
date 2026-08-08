package main

import (
	"testing"

	"github.com/misospace/llmkube-images/testhelpers"
)

func Test(t *testing.T) {
	// Default tag is the fallback used when $TEST_IMAGE is unset; CI sets
	// $TEST_IMAGE to the freshly built image. See AGENTS.md → Container Test Patterns.
	image := testhelpers.GetTestImage("ghcr.io/misospace/llmkube-coder-godot:rolling")
	testhelpers.TestFileExists(t, image, "/foreman-agent", nil)
	testhelpers.TestCommandSucceeds(t, image, nil, "foreman-agent", "--version")
	testhelpers.TestCommandSucceeds(t, image, nil, "godot", "--headless", "--version")
	testhelpers.TestCommandSucceeds(t, image, nil, "git", "--version")
}

func TestReadOnlyRootfs(t *testing.T) {
	image := testhelpers.GetTestImage("ghcr.io/misospace/llmkube-coder-godot:rolling")
	roCfg := &testhelpers.ContainerConfig{ReadOnlyRootfs: true}
	testhelpers.TestCommandSucceeds(t, image, roCfg, "foreman-agent", "--version")
	testhelpers.TestCommandSucceeds(t, image, roCfg, "godot", "--headless", "--version")
}

// TestRunsAProjectHeadless is the reason this image exists. `godot --version`
// proves the binary loads; it does not prove a project imports and a script
// runs, which is what a coder self-gate does. misospace/windowstead#321 shipped
// a test file that did not parse because the coder had no Godot at all and
// nothing executed it before the PR opened — a version check would not have
// caught that either.
func TestRunsAProjectHeadless(t *testing.T) {
	image := testhelpers.GetTestImage("ghcr.io/misospace/llmkube-coder-godot:rolling")
	testhelpers.TestCommandSucceeds(t, image, nil, "sh", "-c", `set -e
d=$(mktemp -d) && cd "$d"
printf 'config_version=5\n[application]\nconfig/name="smoke"\n' > project.godot
printf 'extends SceneTree\nfunc _init():\n\tprint("CODER_SMOKE_OK")\n\tquit()\n' > smoke.gd
export HOME=/tmp
godot --headless --path . --script res://smoke.gd | grep -q CODER_SMOKE_OK`)
}

// TestSurfacesAParseError is the specific failure this image is meant to catch
// locally instead of in CI: a GDScript file that does not compile must make the
// run fail, not pass quietly.
func TestSurfacesAParseError(t *testing.T) {
	image := testhelpers.GetTestImage("ghcr.io/misospace/llmkube-coder-godot:rolling")
	testhelpers.TestCommandSucceeds(t, image, nil, "sh", "-c", `set -e
d=$(mktemp -d) && cd "$d"
printf 'config_version=5\n[application]\nconfig/name="smoke"\n' > project.godot
printf 'extends SceneTree\nfunc _init():\n\tthis is not valid gdscript(\n' > bad.gd
export HOME=/tmp
godot --headless --path . --script res://bad.gd 2>&1 | grep -qi "parse error"`)
}
