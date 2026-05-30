"""WebIDL toolchain — interface and impl-side helper rule.

Two things live here:

  * `WebIDLToolchainInfo` — the provider every webidl toolchain implementation
    must return. Carries a single `runner` label: an executable that parses
    `.webidl` files passed as positional args and writes a JSON AST to
    stdout (or to the path in `$WEBIDL_AST_OUT` if set).

  * `webidl_toolchain` — a thin rule implementations use to expose their
    runner as a toolchain. Mozilla's `firefox_webidl_parser` declares a
    `py_binary` wrapping `WebIDL.py` and feeds it here.

Consumers don't load this file directly — they use the rules in
`//web/webidl:rules.bzl`, which resolve the toolchain via
`ctx.toolchains["@rules_web//web/webidl:toolchain_type"]`.
"""

WebIDLToolchainInfo = provider(
    doc = "Information needed to run a WebIDL parser.",
    fields = {
        "runner": "Executable target. Invoked as `runner <out.json> <in1.webidl> [in2.webidl ...]`.",
    },
)

def _webidl_toolchain_impl(ctx):
    return [
        platform_common.ToolchainInfo(
            webidl_toolchain_info = WebIDLToolchainInfo(
                runner = ctx.attr.runner,
            ),
        ),
    ]

webidl_toolchain = rule(
    implementation = _webidl_toolchain_impl,
    attrs = {
        "runner": attr.label(
            mandatory = True,
            executable = True,
            cfg = "exec",
            doc = "An executable that parses .webidl files. CLI contract: " +
                  "`runner <out.json> <in1.webidl> [in2.webidl ...]`.",
        ),
    },
    doc = "Declares a WebIDL toolchain. Used by impl modules (e.g. firefox_webidl_parser).",
)
