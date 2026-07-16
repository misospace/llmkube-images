target "docker-metadata-action" {}

variable "APP" {
  default = "llmkube-coder-python"
}

variable "VERSION" {
  // renovate: datasource=github-releases depName=defilantech/LLMKube
  // NOTE: This default is intentionally stale. Renovate only updates the VERSION
  // ARG at build time (via -set or env vars) and does not modify HCL defaults.
  // Always pass VERSION explicitly when running `docker buildx bake image-local`.
  default = "0.9.6"
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
  platforms = [
    "linux/amd64",
    "linux/arm64"
  ]
}
