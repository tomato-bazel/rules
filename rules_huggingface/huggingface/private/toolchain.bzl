"""The `hf` CLI toolchain.

A single hermetic `hf` binary (the `huggingface_hub` console script,
served from the pinned `@hf_pypi` hub) is exposed through
`//huggingface:toolchain_type`. Every data-plane rule (hf_upload /
hf_repo / hf_download) resolves the binary via toolchain resolution
rather than a hard-coded label, so a consumer can `register_toolchains`
to pin a different `huggingface_hub` version without forking the rules.
"""

HfToolchainInfo = provider(
    doc = "Resolved `hf` CLI for the data-plane rules.",
    fields = {
        "executable": "File — the hermetic `hf` launcher.",
        "runfiles": "runfiles — the `hf` binary's runfiles (interpreter + deps).",
    },
)

def _hf_toolchain_impl(ctx):
    default = ctx.attr.hf[DefaultInfo]
    return [platform_common.ToolchainInfo(
        hfinfo = HfToolchainInfo(
            executable = default.files_to_run.executable,
            runfiles = default.default_runfiles,
        ),
    )]

hf_toolchain = rule(
    implementation = _hf_toolchain_impl,
    doc = "Wraps a `hf` binary as a resolvable toolchain.",
    attrs = {
        "hf": attr.label(
            mandatory = True,
            executable = True,
            cfg = "target",
            doc = "The `hf` CLI binary (py_console_script_binary).",
        ),
    },
)
