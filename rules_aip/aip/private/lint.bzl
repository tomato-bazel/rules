"""aip_proto_lint — run the Google AIP api-linter over a proto_library, as a test.

Hermetic by construction: a source-info-bearing `FileDescriptorSet` is built
from the proto_library's transitive sources with `protoc --include_source_info
--include_imports`, then handed to api-linter via `--descriptor-set-in`. This
matters because Bazel's `proto_library` descriptor sets are generated *without*
source info — so the comments are stripped and AIP-0192 (has-comments) fires on
every symbol. Regenerating with source info restores the comments while keeping
the linter fully fed from Bazel-provided inputs (no `--proto-path` plumbing, no
googleapis sources pulled in by hand). Target files are named by their import
path (proto-source-root-relative), so AIP-191 (proto-package ↔ directory) passes
when the layout is idiomatic.
"""

load("@bazel_skylib//rules:build_test.bzl", "build_test")
load("@protobuf//bazel/common:proto_info.bzl", "ProtoInfo")

# protobuf's own proto_library resolves protoc through this toolchain type rather
# than naming a target, and //bazel/private/toolchain_helpers.bzl says outright
# that other repos should COPY the two helpers below instead of loading them from
# a private package. That is what these are.
#
# Why it matters here: a direct `@protobuf//:protoc` label is the FROM-SOURCE
# cc_binary. Depending on it forces protobuf, abseil and upb to be compiled — so
# every consumer of this rule needs a working C++ toolchain fetched AND executed,
# in repos that frequently contain no C++ at all. It also makes
# `--@protobuf//bazel/toolchains:prefer_prebuilt_protoc` inert, because that flag
# redirects the toolchain this rule never consulted. Resolving the toolchain lets
# the prebuilt protoc win, and the compiler leaves the graph entirely.
_PROTO_TOOLCHAIN = Label("@protobuf//bazel/private:proto_toolchain_type")

def _use_proto_toolchain():
    return [config_common.toolchain_type(_PROTO_TOOLCHAIN, mandatory = False)]

def _resolve_protoc(ctx):
    """protoc from the proto toolchain.

    There is deliberately NO attribute fallback. An `attr.label` default is a
    dependency edge whether or not the implementation reads it, so keeping one
    pointed at `@protobuf//:protoc` would still drag the from-source cc_binary
    through ANALYSIS — and analysing it needs a C++ toolchain, which is the whole
    problem. Measured: with the fallback attr present the prebuilt was used and
    CppCompile actions were 0, yet `cc_binary @protobuf//:protoc` remained in
    `deps()`. Removing the attr is what removes the edge.
    """
    toolchain = ctx.toolchains[_PROTO_TOOLCHAIN]
    if not toolchain or not toolchain.proto:
        fail(
            "aip_proto_lint needs proto toolchain resolution, which is on by " +
            "default in Bazel 9. On Bazel 8 or older, add " +
            "--incompatible_enable_proto_toolchain_resolution.",
        )
    return toolchain.proto.proto_compiler

def _import_path(f, root):
    """The file's name as recorded in the descriptor set (what api-linter expects)."""
    if root and root != "." and f.path.startswith(root + "/"):
        return f.path[len(root) + 1:]
    return f.short_path

def _aip_lint_impl(ctx):
    info = ctx.attr.proto[ProtoInfo]
    names = [_import_path(f, info.proto_source_root) for f in info.direct_sources]

    # Bazel's proto_library descriptor sets (`transitive_descriptor_sets`) are
    # generated WITHOUT source info, so comments are stripped and AIP-0192
    # (has-comments) fires on every symbol. Regenerate a self-contained
    # descriptor set *from source* with --include_source_info so api-linter sees
    # the comments; --include_imports keeps it standalone (imported types resolve
    # from the same set).
    desc = ctx.actions.declare_file(ctx.label.name + ".srcinfo.desc")
    ctx.actions.run(
        outputs = [desc],
        inputs = info.transitive_sources,
        executable = _resolve_protoc(ctx),
        arguments = (
            ["-I%s" % p for p in info.transitive_proto_path.to_list()] +
            [
                "--include_source_info",
                "--include_imports",
                "--descriptor_set_out=%s" % desc.path,
            ] + names
        ),
        mnemonic = "AipDescriptorSet",
        progress_message = "Building source-info descriptor set for %{label}",
    )

    marker = ctx.actions.declare_file(ctx.label.name + ".ok")

    flags = ["--set-exit-status"]
    flags += ["--disable-rule=%s" % r for r in ctx.attr.disable_rules]
    flags += ["--enable-rule=%s" % r for r in ctx.attr.enable_rules]
    flags += ["--descriptor-set-in=%s" % desc.path]

    extra_inputs = [desc]
    if ctx.file.config:
        flags.append("--config=%s" % ctx.file.config.path)
        extra_inputs.append(ctx.file.config)

    cmd = "{linter} {flags} {names} && touch {marker}".format(
        linter = ctx.executable._linter.path,
        flags = " ".join(flags),
        names = " ".join(names),
        marker = marker.path,
    )
    ctx.actions.run_shell(
        outputs = [marker],
        inputs = depset(extra_inputs),
        tools = [ctx.executable._linter],
        command = cmd,
        mnemonic = "AipLint",
        progress_message = "AIP-linting %{label}",
    )
    return [DefaultInfo(files = depset([marker]))]

_aip_lint = rule(
    implementation = _aip_lint_impl,
    attrs = {
        "proto": attr.label(mandatory = True, providers = [ProtoInfo]),
        "config": attr.label(allow_single_file = [".yaml", ".yml"]),
        "disable_rules": attr.string_list(),
        "enable_rules": attr.string_list(),
        "_linter": attr.label(
            default = "@rules_aip//tools/api-linter:api-linter",
            executable = True,
            cfg = "exec",
        ),
    },
    toolchains = _use_proto_toolchain(),
)

def aip_proto_lint(name, proto, disable_rules = [], enable_rules = [], config = None, **kwargs):
    """A `bazel test` target that AIP-lints `proto` (a proto_library).

    Args:
      name: test target name.
      proto: the proto_library to lint.
      disable_rules: AIP rule IDs to disable (e.g. ["core::0191::proto-package"]).
      enable_rules: AIP rule IDs to force-enable.
      config: optional api-linter YAML config.
      **kwargs: forwarded to the build_test (tags, visibility, …).
    """
    tags = kwargs.pop("tags", [])
    _aip_lint(
        name = name + ".run",
        proto = proto,
        disable_rules = disable_rules,
        enable_rules = enable_rules,
        config = config,
        tags = tags,
        testonly = True,
        visibility = ["//visibility:private"],
    )
    build_test(
        name = name,
        targets = [":" + name + ".run"],
        tags = tags,
        **kwargs
    )
