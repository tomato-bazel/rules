"""The kubeconform toolchain."""

KubeconformToolchainInfo = provider(
    doc = "The kubeconform binary used to validate manifests against schemas.",
    fields = {
        "kubeconform": "FilesToRunProvider: its `.executable` is the kubeconform entry point.",
        "default_runfiles": "runfiles: needed to invoke kubeconform at runtime. Carried separately because FilesToRunProvider has no runfiles — it must come off the target's DefaultInfo. (rules_cloudformation's AwsCliToolchainInfo carries the same pair for the same reason.)",
    },
)

def _kubeconform_toolchain_impl(ctx):
    info = ctx.attr.kubeconform[DefaultInfo]
    return [platform_common.ToolchainInfo(
        kubeconform_info = KubeconformToolchainInfo(
            kubeconform = info.files_to_run,
            default_runfiles = info.default_runfiles,
        ),
    )]

kubeconform_toolchain = rule(
    implementation = _kubeconform_toolchain_impl,
    doc = """Declares a kubeconform toolchain.

The default (`@rules_k8s//validate:default_kubeconform_toolchain`) fetches a
sha256-pinned release binary. Register with `--extra_toolchains` in .bazelrc, not
`register_toolchains()` in MODULE.bazel.
""",
    attrs = {
        "kubeconform": attr.label(
            mandatory = True,
            executable = True,
            cfg = "exec",
            allow_files = True,
            doc = "The kubeconform binary.",
        ),
    },
)
