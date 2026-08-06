target "docker-metadata-action" {}

variable "APP" {
  default = "godot-gate"
}

variable "VERSION" {
  // renovate: datasource=github-releases depName=godotengine/godot
  default = "4.7.1"
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
  // amd64 only: Godot upstream ships a linux x86_64 headless binary and the
  // foreman fleet nodes are amd64.
  platforms = [
    "linux/amd64"
  ]
}
