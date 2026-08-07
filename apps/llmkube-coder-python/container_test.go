package main

import (
	"testing"

	"github.com/misospace/llmkube-images/testhelpers"
)

func Test(t *testing.T) {
	// Default tag is the fallback used when $TEST_IMAGE is unset; CI sets
	// $TEST_IMAGE to the freshly built image. See AGENTS.md → Container Test Patterns.
	image := testhelpers.GetTestImage("ghcr.io/misospace/llmkube-coder-python:rolling")
	testhelpers.TestFileExists(t, image, "/foreman-agent", nil)
	// The agent binary and the Python toolchain the coder self-gate uses.
	testhelpers.TestCommandSucceeds(t, image, nil, "foreman-agent", "--version")
	testhelpers.TestCommandSucceeds(t, image, nil, "python3", "--version")
	testhelpers.TestCommandSucceeds(t, image, nil, "git", "--version")
	// Representative Python linter.
	testhelpers.TestCommandSucceeds(t, image, nil, "ruff", "--version")
}

func TestReadOnlyRootfs(t *testing.T) {
	// Default tag is the fallback used when $TEST_IMAGE is unset; CI sets
	// $TEST_IMAGE to the freshly built image. See AGENTS.md → Container Test Patterns.
	image := testhelpers.GetTestImage("ghcr.io/misospace/llmkube-coder-python:rolling")
	roCfg := &testhelpers.ContainerConfig{ReadOnlyRootfs: true}
	testhelpers.TestCommandSucceeds(t, image, roCfg, "foreman-agent", "--version")
	testhelpers.TestCommandSucceeds(t, image, roCfg, "python3", "--version")
}
