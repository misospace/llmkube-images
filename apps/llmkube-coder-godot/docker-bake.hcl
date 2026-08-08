target "docker-metadata-action" {}

variable "APP" {
  default = "llmkube-coder-godot"
}

variable "VERSION" {
  // NOTE: This default is intentionally stale. Renovate only updates the VERSION
  // ARG at build time (via -set or env vars) and does not modify HCL defaults.
  // Always pass VERSION explicitly when running `docker buildx bake image-local`.
  // renovate: datasource=github-releases depName=defilantech/LLMKube
  default = "0.9.14"
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
  // amd64 only: Godot upstream ships a linux x86_64 headless binary and
  // the foreman fleet nodes are amd64 (mirrors godot-gate).
  platforms = [
    "linux/amd64"
  ]
}
