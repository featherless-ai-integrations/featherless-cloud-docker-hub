variable "REGISTRY" { default = "localhost/featherless-ai" }
variable "VERSION" { default = "local" }

group "default" { targets = ["pytorch", "sgl-dev", "vllm"] }

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
  dockerfile = "rocm-pytorch/Dockerfile"
  tags = ["${REGISTRY}/rocm-pytorch:${VERSION}"]
}
target "sgl-dev" {
  inherits = ["common"]
  dockerfile = "rocm-sgl/Dockerfile"
  tags = ["${REGISTRY}/rocm-sgl:${VERSION}"]
}
target "vllm" {
  inherits = ["common"]
  dockerfile = "rocm-vllm/Dockerfile"
  tags = ["${REGISTRY}/rocm-vllm:${VERSION}"]
}
