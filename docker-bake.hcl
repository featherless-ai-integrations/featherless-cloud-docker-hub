variable "REGISTRY" { default = "ghcr.io/featherless-ai" }
variable "VERSION" { default = "dev" }

# These outputs are MI325X-only. Although MI300X and MI325X both expose gfx942,
# they are separate products and are not treated as interchangeable here.
# Never use an mi300x/mi30x-specific tag. Generic AMD tags are allowed only after
# validation on physical MI325X hardware; releases should use immutable digests.
variable "BASE_PYTORCH" { default = "rocm/pytorch:latest" }
variable "BASE_SGL" { default = "rocm/sgl-dev:v0.5.13.post1-ubuntu24.04-py3.14-rocm7.14" }
variable "BASE_VLLM" { default = "rocm/vllm:rocm7.14.0_cdna_ubuntu24.04_py3.14_pytorch_2.11.0_vllm_0.23.0" }

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
  args = { BASE_IMAGE = BASE_PYTORCH }
  tags = ["${REGISTRY}/rocm-pytorch:${VERSION}"]
}
target "sgl-dev" {
  inherits = ["common"]
  dockerfile = "rocm-sgl/Dockerfile"
  args = { BASE_IMAGE = BASE_SGL }
  tags = ["${REGISTRY}/rocm-sgl-dev:${VERSION}"]
}
target "vllm" {
  inherits = ["common"]
  dockerfile = "rocm-vllm/Dockerfile"
  args = { BASE_IMAGE = BASE_VLLM }
  tags = ["${REGISTRY}/rocm-vllm:${VERSION}"]
}
