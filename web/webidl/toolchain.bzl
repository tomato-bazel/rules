"""WebIDL toolchain — the *interface*, plus a small helper rule for impls.

This file defines NO implementation. It only defines the contract that
every WebIDL-parser implementation must satisfy, and a thin helper rule
that saves implementations from re-deriving the `ToolchainInfo` wrapping.
Same shape as `rules_cc`'s `cc_toolchain` (helper rule in rules_cc) vs
the concrete LLVM/Xcode/MSVC toolchains (impls live in their own repos).

Two things live here:

  * `WebIDLToolchainInfo` — the provider every webidl toolchain
    implementation must return. Carries a single `runner` label: an
    executable satisfying the CLI contract.

  * `webidl_toolchain` — a thin *helper rule* that takes a `runner` label
    and wraps it in `ToolchainInfo(webidl_toolchain_info = ...)`. NOT an
    implementation — implementations instantiate this helper with their
    actual runner binary (e.g. `firefox_webidl_parser` instantiates it
    with a `py_binary` wrapping Mozilla's `WebIDL.py`). The instantiation
    + the `toolchain(...)` registration shim live in the implementation
    module, NOT here.

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
