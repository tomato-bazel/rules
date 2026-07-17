"""Fetch the kubeconform binary.

kubeconform ships per-platform binaries as GitHub release assets, which is
precisely the case `rules_github` exists for — so this is a thin call rather than
a hand-rolled repository_rule. (The org has three competing hermetic-binary
idioms; this tool picks the one that fits. `kubectl` picks a different one, and
//kubectl/toolchain.bzl says why.)
"""

load("@rules_github//github:repositories.bzl", "github_binary_repository")

# Bumping: get the shas from the release's own CHECKSUMS asset, e.g.
#   curl -sSL https://github.com/yannh/kubeconform/releases/download/v0.6.7/CHECKSUMS
KUBECONFORM_VERSION = "0.6.7"

KUBECONFORM_SHAS = {
    "darwin_aarch64": "cbb47d938a8d18eb5f79cb33663b2cecdee0c8ac0bf562ebcfca903df5f0802f",
    "darwin_x86_64": "3b5324ac4fd38ac60a49823b4051ff42ff7eb70144f1e9741fed1d14bc4fdb4e",
    "linux_aarch64": "dc82f79bb03c5479b1ae5fd4af221e4b5a3111f62bf01a2795d9c5c20fa96644",
    "linux_x86_64": "95f14e87aa28c09d5941f11bd024c1d02fdc0303ccaa23f61cef67bc92619d73",
}

_BUILD = """\
package(default_visibility = ["//visibility:public"])

exports_files(["kubeconform"])

filegroup(
    name = "binary",
    srcs = ["kubeconform"],
)
"""

def kubeconform_repository(name = "kubeconform"):
    github_binary_repository(
        name = name,
        repo = "yannh/kubeconform",
        version = KUBECONFORM_VERSION,
        tag_format = "v{version}",
        asset_template = "kubeconform-{platform}.tar.gz",
        platform_aliases = {
            "darwin_aarch64": "darwin-arm64",
            "darwin_x86_64": "darwin-amd64",
            "linux_aarch64": "linux-arm64",
            "linux_x86_64": "linux-amd64",
        },
        platform_shas = KUBECONFORM_SHAS,
        build_file_content = _BUILD,
    )
