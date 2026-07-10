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

	// The foreman gate runs as this image's non-root user and clones the target
	// repo into /work; it must be writable by that uid (regression: nobody cannot
	// mkdir under root-owned /, so /work is pre-created world-writable).
	testhelpers.TestCommandSucceeds(t, image, nil, "sh", "-c", "touch /work/.probe && rm /work/.probe")

	// godot on PATH + git present (the gate checks out the PR branch).
	testhelpers.TestCommandSucceeds(t, image, nil, "sh", "-c", "command -v godot")
	testhelpers.TestCommandSucceeds(t, image, nil, "git", "--version")
}
