target "docker-metadata-action" {}

variable "APP" {
  default = "llmkube-coder"
}

variable "VERSION" {
  // NOTE: This default is intentionally stale. Renovate only updates the VERSION
  // ARG at build time (via -set or env vars) and does not modify HCL defaults.
  // Always pass VERSION explicitly when running `docker buildx bake image-local`.
  // renovate: datasource=github-releases depName=defilantech/llmkube
  default = "0.9.16"
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
