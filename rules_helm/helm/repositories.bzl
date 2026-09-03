"""Hermetic Helm CLI download.

`helm_repository` fetches the pinned helm release for the *host* platform and
exposes the binary as `@helm//:helm`. The build is hermetic per host: a
`bazel build` of a chart never touches a system-installed helm.

Bumping helm is two edits: `HELM_VERSION` + the four `HELM_SHA256` lines.
Refresh a checksum with:

    curl -fsSL https://get.helm.sh/helm-v<ver>-<plat>.tar.gz.sha256sum

Cross-platform note: this v0.1.0 downloads only the host platform's binary
(chart packaging always runs host-native). A future revision can graduate this
to a full multi-platform Bazel toolchain (exec-platform selection for RBE).
"""

HELM_VERSION = "4.2.1"

# get.helm.sh release archive checksums, keyed by the helm platform string
# (which is also the archive's top-level directory, stripped on extract).
HELM_SHA256 = {
    "linux-amd64": "479dca836e5b45e8bd222400c5591b0e3a647378f03ff96597180db97c17fdae",
    "linux-arm64": "596b9a73d366c1e72ce67d595c22805480e30914593aafbc9f547694e72814db",
    "darwin-amd64": "2a21c9f368d608bcf6eb794ebc06514eb6b529a846b60fe4a43dea7bcce65228",
    "darwin-arm64": "896472d2ec0740c60f64a9df0fc30d478beee38a1a2a6ed91aa6e6ee177c1575",
}

_BUILD = """\
package(default_visibility = ["//visibility:public"])

# The extracted helm binary (the archive's `<platform>/helm`, top dir stripped).
# Exported as a source file; rules reach it via the `//helm:helm_bin` alias.
exports_files(["helm"])
"""

def _host_platform(rctx):
    """Map the host os/arch to a helm release platform string."""
    os = rctx.os.name.lower()
    if os.startswith("mac") or "darwin" in os:
        hos = "darwin"
    elif "linux" in os:
        hos = "linux"
    else:
        fail("rules_helm: unsupported host OS %r" % rctx.os.name)

    arch = rctx.os.arch.lower()
    if arch in ("aarch64", "arm64"):
        harch = "arm64"
    elif arch in ("x86_64", "amd64", "x64"):
        harch = "amd64"
    else:
        fail("rules_helm: unsupported host arch %r" % rctx.os.arch)

    return "%s-%s" % (hos, harch)

def _helm_repository_impl(rctx):
    plat = _host_platform(rctx)
    sha256 = HELM_SHA256.get(plat)
    if not sha256:
        fail("rules_helm: no pinned checksum for host platform %r" % plat)

    rctx.download_and_extract(
        url = "https://get.helm.sh/helm-v{ver}-{plat}.tar.gz".format(
            ver = HELM_VERSION,
            plat = plat,
        ),
        sha256 = sha256,
        # Archive lays out as `<platform>/{helm,LICENSE,README.md}`.
        stripPrefix = plat,
    )
    rctx.file("BUILD.bazel", _BUILD)

helm_repository = repository_rule(
    implementation = _helm_repository_impl,
    doc = "Downloads the pinned helm CLI for the host platform as `@helm//:helm`.",
)
