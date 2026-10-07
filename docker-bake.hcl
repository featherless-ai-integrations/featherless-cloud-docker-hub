variable "REGISTRY" { default = "localhost/featherless-ai" }
variable "VERSION" { default = "local" }

group "default" { targets = ["pytorch", "sgl-dev", "vllm", "axolotl", "featherless-init"] }

target "common" {
  context = "."
  dockerfile = "Dockerfile"
  platforms = ["linux/amd64"]
  labels = {
    "com.featherless.gpu.model" = "AMD Instinct MI325X"
    "com.featherless.gpu.compatibility" = "mi325x-only"
  }
}

target "pytorch" {
  inherits = ["common"]
  dockerfile = "docker-image/rocm-pytorch/Dockerfile"
  tags = ["${REGISTRY}/rocm-pytorch:${VERSION}"]
}
target "sgl-dev" {
  inherits = ["common"]
  dockerfile = "docker-image/rocm-sgl/Dockerfile"
  tags = ["${REGISTRY}/rocm-sgl:${VERSION}"]
}
target "vllm" {
  inherits = ["common"]
  dockerfile = "docker-image/rocm-vllm/Dockerfile"
  tags = ["${REGISTRY}/rocm-vllm:${VERSION}"]
}
target "axolotl" {
  inherits = ["common"]
  dockerfile = "docker-image/rocm-axolotl/Dockerfile"
  tags = ["${REGISTRY}/rocm-axolotl:${VERSION}"]
}

# Mounted into instance containers; built FROM scratch around static tini.
target "featherless-init" {
  context = "."
  dockerfile = "docker-image/featherless-init/Dockerfile"
  platforms = ["linux/amd64"]
  tags = ["${REGISTRY}/featherless-init:${VERSION}"]
}
