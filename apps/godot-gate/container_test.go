package main

import (
	"testing"

	"github.com/misospace/llmkube-images/testhelpers"
)

func Test(t *testing.T) {
	image := testhelpers.GetTestImage("ghcr.io/misospace/godot-gate:4.2.2")

	// Godot headless must run even under the strictest sandbox — read-only rootfs
	// with only /tmp writable — since all its state is redirected to /tmp. The
	// previous apt-based gate died here.
	roCfg := &testhelpers.ContainerConfig{ReadOnlyRootfs: true}
	testhelpers.TestCommandSucceeds(t, image, roCfg, "godot", "--headless", "--version")

	// A real project must LOAD and a script must actually RUN headless — the gate
	// runs `godot --headless --path . --script …`, which `godot --version` never
	// exercises (it inits no user:// data dir and loads no project). This is the
	// smoke that would have caught the earlier in-cluster-only failures. Runs as
	// the image's non-root user, writing project state under the writable temp dir.
	testhelpers.TestCommandSucceeds(t, image, nil, "sh", "-c", `set -e
d=$(mktemp -d) && cd "$d"
printf 'config_version=5\n[application]\nconfig/name="smoke"\n' > project.godot
printf 'extends SceneTree\nfunc _init():\n\tprint("GATE_SMOKE_OK")\n\tquit()\n' > smoke.gd
export HOME=/tmp
godot --headless --path . --script res://smoke.gd | grep -q GATE_SMOKE_OK`)

	// The foreman gate runs as this image's non-root user and clones the target
	// repo into /work; it must be writable by that uid (regression: nobody cannot
	// mkdir under root-owned /, so /work is pre-created world-writable).
	testhelpers.TestCommandSucceeds(t, image, nil, "sh", "-c", "touch /work/.probe && rm /work/.probe")

	// godot on PATH + git present (the gate checks out the PR branch).
	testhelpers.TestCommandSucceeds(t, image, nil, "sh", "-c", "command -v godot")
	testhelpers.TestCommandSucceeds(t, image, nil, "git", "--version")
}
