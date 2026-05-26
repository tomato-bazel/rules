"""`cc_cross` module extension.

A consumer's MODULE.bazel declares one tag per desired cross target:

    cc_cross = use_extension("@rules_cc_cross//cc_cross:extensions.bzl", "cc_cross")
    cc_cross.toolchain(target = "aarch64-none-elf", version = "14.2.rel1")
    use_repo(cc_cross, "arm_gnu_aarch64_none_elf")
    register_toolchains("@arm_gnu_aarch64_none_elf//:all")

The extension materializes one repo per (target, host) pair. The
repo name is `arm_gnu_<target_underscored>` (e.g.
`arm_gnu_aarch64_none_elf`) so a downstream consumer can predictably
`register_toolchains("@arm_gnu_aarch64_none_elf//:all")`.

Today only `target = "aarch64-none-elf"` is implemented. `riscv64-elf`
and `x86_64-elf` ride on the same machinery and will land in 0.1.0.
"""

load("//cc_cross/private:arm_gnu_toolchain.bzl", "arm_gnu_toolchain")
load("//cc_cross/private:known_versions.bzl", "KNOWN_ARM_GNU_VERSIONS")

_SUPPORTED_TARGETS = ["aarch64-none-elf"]

_toolchain = tag_class(
    attrs = {
        "target": attr.string(
            mandatory = True,
            values = _SUPPORTED_TARGETS,
            doc = "Cross-compilation target triple. Today only " +
                  "aarch64-none-elf is supported.",
        ),
        "version": attr.string(
            default = "14.2.rel1",
            doc = "ARM GNU Toolchain release version (e.g. 14.2.rel1).",
        ),
    },
)

def _cc_cross_impl(module_ctx):
    seen = {}
    for mod in module_ctx.modules:
        for tag in mod.tags.toolchain:
            key = tag.target
            if key in seen and seen[key] != tag.version:
                fail("cc_cross.toolchain: target {} requested at two " +
                     "versions ({} vs {}). Pin one in the root module."
                     .format(key, seen[key], tag.version))
            seen[key] = tag.version

    for target, version in seen.items():
        if version not in KNOWN_ARM_GNU_VERSIONS:
            fail("cc_cross: unknown ARM GNU Toolchain version {!r}. " +
                 "Known: {}. Add it to known_versions.bzl or pin a " +
                 "supported version.".format(
                     version, sorted(KNOWN_ARM_GNU_VERSIONS.keys())))
        arm_gnu_toolchain(
            name = "arm_gnu_" + target.replace("-", "_"),
            target = target,
            version = version,
        )

cc_cross = module_extension(
    implementation = _cc_cross_impl,
    tag_classes = {"toolchain": _toolchain},
)
