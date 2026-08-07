target "docker-metadata-action" {}

variable "APP" {
  default = "elixir-gate"
}

variable "VERSION" {
  // renovate: datasource=docker depName=hexpm/elixir
  default = "1.18.4-erlang-27.0.1-debian-bookworm-20260803"
}

variable "SOURCE" {
  default = "https://github.com/misospace/llmkube-images"
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
