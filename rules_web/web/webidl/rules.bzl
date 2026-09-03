"""WebIDL consumer-facing rules.

`webidl_library(name, srcs, deps)` — bundles a set of `.webidl` files into a
`WebIDLInfo` provider that downstream rules consume. Transitive: `deps`
forwards each dep's `WebIDLInfo.srcs` so downstream `webidl_parse` sees
the full closure.

`webidl_parse(name, src)` — runs the registered `webidl_toolchain_type`'s
parser over a `webidl_library`'s full transitive source set, writing a
JSON AST to `<name>.json`. The toolchain's runner contract is
`runner <out.json> <in1.webidl> [in2.webidl ...]` (see toolchain.bzl).
"""

WebIDLInfo = provider(
    doc = "A set of .webidl source files plus their transitive dependencies.",
    fields = {
        "srcs": "depset of File — direct .webidl sources from this library.",
        "transitive_srcs": "depset of File — direct + dep-transitive .webidl sources.",
    },
)

def _webidl_library_impl(ctx):
    direct = depset(ctx.files.srcs)
    transitive = depset(
        direct = ctx.files.srcs,
        transitive = [d[WebIDLInfo].transitive_srcs for d in ctx.attr.deps],
    )
    return [
        WebIDLInfo(srcs = direct, transitive_srcs = transitive),
        DefaultInfo(files = direct),
    ]

webidl_library = rule(
    implementation = _webidl_library_impl,
    attrs = {
        "srcs": attr.label_list(
            allow_files = [".webidl"],
            doc = "WebIDL interface files (e.g. `HTMLDetailsElement.webidl`).",
        ),
        "deps": attr.label_list(
            providers = [WebIDLInfo],
            doc = "Other webidl_library targets whose interfaces this one references.",
        ),
    },
    doc = "Collects a set of .webidl files (with transitive deps) into a WebIDLInfo.",
)

def _webidl_parse_impl(ctx):
    info = ctx.attr.src[WebIDLInfo]
    toolchain = ctx.toolchains["@rules_web//web/webidl:toolchain_type"].webidl_toolchain_info
    runner = toolchain.runner

    out = ctx.actions.declare_file(ctx.label.name + ".json")
    inputs = info.transitive_srcs

    args = ctx.actions.args()
    args.add(out)
    args.add_all(inputs)

    ctx.actions.run(
        outputs = [out],
        inputs = inputs,
        executable = runner.files_to_run.executable,
        tools = [runner.files_to_run],
        arguments = [args],
        mnemonic = "WebIDLParse",
        progress_message = "Parsing %{label}",
    )

    return [DefaultInfo(files = depset([out]))]

webidl_parse = rule(
    implementation = _webidl_parse_impl,
    attrs = {
        "src": attr.label(
            mandatory = True,
            providers = [WebIDLInfo],
            doc = "A webidl_library target whose interfaces to parse.",
        ),
    },
    toolchains = ["@rules_web//web/webidl:toolchain_type"],
    doc = "Parses a webidl_library's transitive sources into a JSON AST.",
)
