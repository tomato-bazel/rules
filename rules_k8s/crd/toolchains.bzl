"""The CRD codegen toolchain: controller-tools plus the driver that feeds it."""

K8sCrdToolchainInfo = provider(
    doc = "The tools that turn kubebuilder markers into CRD YAML inside an action.",
    fields = {
        "gen": "FilesToRunProvider: the CRD generator — controller-tools' genall driven as a library, writing to a named directory.",
        "driver": "FilesToRunProvider: the go/packages external driver. `gen` reaches it via GOPACKAGESDRIVER; it is never invoked directly.",
    },
)

def _k8s_crd_toolchain_impl(ctx):
    return [platform_common.ToolchainInfo(
        crd_info = K8sCrdToolchainInfo(
            gen = ctx.attr.gen[DefaultInfo].files_to_run,
            driver = ctx.attr.driver[DefaultInfo].files_to_run,
        ),
    )]

k8s_crd_toolchain = rule(
    implementation = _k8s_crd_toolchain_impl,
    doc = """Declares a CRD codegen toolchain.

The default implementation (`@rules_k8s//crd:default_k8s_crd_toolchain`) builds
controller-tools from the version pinned in rules_k8s's go.mod. That pin is a
schema decision — see the comment there — so an override should be a deliberate
"we generate with a different controller-tools", not a convenience.

Register with `--extra_toolchains` in .bazelrc, never `register_toolchains()` in
MODULE.bazel: the latter propagates to every consumer, which would drag a Go SDK
into the Rust services that only ever *read* CRD schemas.
""",
    attrs = {
        "gen": attr.label(
            mandatory = True,
            executable = True,
            cfg = "exec",
            doc = "The CRD generator binary. Must accept `-out DIR [-expect-group G] [-listing F] PATTERN...`.",
        ),
        "driver": attr.label(
            mandatory = True,
            executable = True,
            cfg = "exec",
            doc = "The go/packages external driver. Must read its package-graph file list from K8S_CRD_DRIVER_PKG_JSON.",
        ),
    },
)
