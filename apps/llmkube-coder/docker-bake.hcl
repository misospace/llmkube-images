target "docker-metadata-action" {}

variable "APP" {
  default = "llmkube-coder"
}

variable "VERSION" {
  // renovate: datasource=github-releases depName=defilantech/llmkube
  default = "0.9.20"
}

variable "SOURCE" {
  default = "https://github.com/defilantech/LLMKube"
}

group "default" {
  targets = ["image-local"]
}

target "image" {
  inherits = ["docker-metadata-action"]
  args = {
    VERSION = "${VERSION}"
  }
  labels = {
    "org.opencontainers.image.source" = "${SOURCE}"
  }
}

target "image-local" {
  inherits = ["image"]
  output = ["type=docker"]
  tags = ["${APP}:${VERSION}"]
  // amd64 only: Godot ships a linux x86_64 headless binary and the fleet
  // nodes are amd64. Without this pin, an arm64 host builds a linux/arm64
  // image whose Godot binary segfaults (SIGSEGV) under every Godot test.
  platforms = [
    "linux/amd64"
  ]
}

target "image-all" {
  inherits = ["image"]
  // amd64 only: Godot ships a linux x86_64 headless binary and the fleet
  // nodes are amd64. The old arm64 target was a carryover from the containers
  // migration; nothing in the fleet pulls it.
  platforms = [
    "linux/amd64"
  ]
}
