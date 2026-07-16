package main

import (
	"testing"

	"github.com/misospace/llmkube-images/testhelpers"
)

func Test(t *testing.T) {
	// The default tag below is the CI-published :rolling build of this image. CI
	// overrides TEST_IMAGE to the exact digest it just published, so a stale or
	// failed :rolling tag cannot silently test an old image. Local dev should set
	// TEST_IMAGE explicitly (e.g. TEST_IMAGE=ghcr.io/misospace/llmkube-coder:dev).
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
}
