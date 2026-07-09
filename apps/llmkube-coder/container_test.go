package main

import (
	"testing"

	"github.com/misospace/llmkube-images/testhelpers"
)

func Test(t *testing.T) {
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
