"""The kubectl toolchain.

DELIBERATELY NON-HERMETIC, and this is the right call rather than a shortcut.

kubectl is version-skew-sensitive to the cluster it talks to: upstream supports
±1 minor between client and server. A single pinned kubectl across a fleet whose
clusters sit at different minors would be the bug, not the fix — so the default
wraps whatever kubectl the operator already has on PATH, which is the one matched
to the cluster they are pointed at.

This mirrors rules_cloudformation's `AwsCliToolchainInfo`, which wraps system
`aws` for the same reason and documents the same trade. The org's three
hermetic-binary idioms exist to be chosen between per tool: kubeconform is a pure
function of its inputs and gets a sha-pinned release binary (//validate); kubectl
talks to a live cluster and gets this.

Nothing that BUILDS depends on this toolchain — only `k8s_diff`, which is a
`bazel run` against a real cluster and therefore already non-hermetic by nature.

To pin a specific kubectl anyway, declare your own `kubectl_toolchain` and
register it ahead of the default.
"""

KubectlToolchainInfo = provider(
    doc = "The kubectl binary used by cluster-facing `bazel run` targets.",
    fields = {
        "kubectl": "FilesToRunProvider: its `.executable` is the kubectl entry point.",
        "default_runfiles": "runfiles: needed to invoke kubectl at runtime (the sh_binary wrapper's own runfiles).",
    },
)

def _kubectl_toolchain_impl(ctx):
    info = ctx.attr.kubectl[DefaultInfo]
    return [platform_common.ToolchainInfo(
        kubectl_info = KubectlToolchainInfo(
            kubectl = info.files_to_run,
            default_runfiles = info.default_runfiles,
        ),
    )]

kubectl_toolchain = rule(
    implementation = _kubectl_toolchain_impl,
    doc = "Declares a kubectl toolchain. The default wraps system kubectl on PATH.",
    attrs = {
        "kubectl": attr.label(
            mandatory = True,
            executable = True,
            cfg = "exec",
            allow_files = True,
            doc = "The kubectl binary, or a wrapper that finds one.",
        ),
    },
)
