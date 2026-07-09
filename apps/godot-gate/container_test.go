package main

import (
	"testing"

	"github.com/misospace/llmkube-images/testhelpers"
)

func Test(t *testing.T) {
	image := testhelpers.GetTestImage("ghcr.io/misospace/godot-gate:4.2.2")

	// The foreman gate runs on a read-only rootfs with only /tmp writable. The
	// previous apt-based gate died here; this asserts Godot headless actually
	// runs under that exact constraint.
	roCfg := &testhelpers.ContainerConfig{ReadOnlyRootfs: true}
	testhelpers.TestCommandSucceeds(t, image, roCfg, "godot", "--headless", "--version")

	// godot on PATH + git present (the gate checks out the PR branch).
	testhelpers.TestCommandSucceeds(t, image, nil, "sh", "-c", "command -v godot")
	testhelpers.TestCommandSucceeds(t, image, nil, "git", "--version")
}
