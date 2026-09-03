"""`cross_cc_toolchain_config` — cc_toolchain_config for an ARM GNU
bare-metal cross install.

This is intentionally minimal: we wire up tool paths, the C/C++
builtin include search dirs (computed at analysis from the tool
prefix), and a couple of always-on flag sets (`-ffreestanding`,
`-nostdlib` defaults). seL4 / microkit binaries supply their own
linker scripts via target-level `linkopts`, so we don't impose one.
"""

load("@rules_cc//cc:cc_toolchain_config_lib.bzl",
     "feature", "flag_group", "flag_set", "tool_path")
load("@rules_cc//cc:action_names.bzl",
     "ASSEMBLE_ACTION_NAME",
     "CPP_COMPILE_ACTION_NAME",
     "CPP_LINK_EXECUTABLE_ACTION_NAME",
     "CPP_LINK_STATIC_LIBRARY_ACTION_NAME",
     "C_COMPILE_ACTION_NAME",
     "LINKSTAMP_COMPILE_ACTION_NAME")
load("@rules_cc//cc:defs.bzl", "CcToolchainConfigInfo", "cc_common")

_ALL_C_COMPILE = [
    C_COMPILE_ACTION_NAME,
    CPP_COMPILE_ACTION_NAME,
    LINKSTAMP_COMPILE_ACTION_NAME,
    ASSEMBLE_ACTION_NAME,
]
_ALL_LINK = [
    CPP_LINK_EXECUTABLE_ACTION_NAME,
    CPP_LINK_STATIC_LIBRARY_ACTION_NAME,
]

def _builtin_include_dirs(ctx):
    # cc internals' `_resolve_include_dir` requires `%package(...)%`
    # arguments to be package identifiers (`@@repo//some/pkg`),
    # NOT label identifiers (`@@repo//some/pkg:target`). We strip
    # the target portion explicitly here.
    triple = ctx.attr.target_system_name
    gccv = ctx.attr.gcc_version
    sysroot = ctx.attr.sysroot
    # Construct absolute exec-root-relative paths directly. Paths
    # are listed without a leading `%...%` prefix so they're treated
    # as absolute by `_resolve_include_dir`. The cc_toolchain
    # config rule's `ctx.label.workspace_root` gives us the
    # `external/<canonical>` prefix.
    root = ctx.label.workspace_root  # e.g. "external/rules_cc_cross++cc_cross+arm_gnu_aarch64_none_elf"
    bases = [
        sysroot + "/include",
        "lib/gcc/" + triple + "/" + gccv + "/include",
        "lib/gcc/" + triple + "/" + gccv + "/include-fixed",
    ]
    return [root + "/" + b for b in bases]

def _impl(ctx):
    prefix = ctx.attr.tool_prefix
    tool_paths = [
        tool_path(name = "gcc", path = "bin/" + prefix + "gcc"),
        tool_path(name = "ld", path = "bin/" + prefix + "ld"),
        tool_path(name = "ar", path = "bin/" + prefix + "ar"),
        tool_path(name = "cpp", path = "bin/" + prefix + "g++"),
        tool_path(name = "gcov", path = "bin/" + prefix + "gcov"),
        tool_path(name = "nm", path = "bin/" + prefix + "nm"),
        tool_path(name = "objdump", path = "bin/" + prefix + "objdump"),
        tool_path(name = "strip", path = "bin/" + prefix + "strip"),
    ]

    freestanding = feature(
        name = "freestanding",
        enabled = True,
        flag_sets = [
            flag_set(
                actions = _ALL_C_COMPILE,
                flag_groups = [flag_group(flags = [
                    "-ffreestanding",
                    "-fno-stack-protector",
                    "-fno-builtin",
                ])],
            ),
            flag_set(
                actions = _ALL_LINK,
                flag_groups = [flag_group(flags = [
                    "-nostdlib",
                    "-Wl,--build-id=none",
                ])],
            ),
        ],
    )

    # Without these flags, gcc's `-MD` output reports realpath()'d
    # absolute paths for system headers (e.g.
    # `/Users/.../external/<canonical>/lib/gcc/.../stdint.h`),
    # which trips Bazel's "absolute path inclusions" check because
    # our `cxx_builtin_include_directories` declarations are
    # exec-root-relative. `-no-canonical-prefixes` (gcc + clang)
    # and `-fno-canonical-system-headers` (gcc-only) make gcc emit
    # the exec-root-relative path it was actually invoked with.
    no_canonical = feature(
        name = "no_canonical_prefixes",
        enabled = True,
        flag_sets = [
            flag_set(
                actions = _ALL_C_COMPILE,
                flag_groups = [flag_group(flags = [
                    "-no-canonical-prefixes",
                    "-fno-canonical-system-headers",
                ])],
            ),
        ],
    )

    return cc_common.create_cc_toolchain_config_info(
        ctx = ctx,
        toolchain_identifier = ctx.attr.toolchain_identifier,
        host_system_name = "local",
        target_system_name = ctx.attr.target_system_name,
        target_cpu = ctx.attr.target_cpu,
        target_libc = "newlib",
        compiler = "gcc",
        abi_version = "eabi",
        abi_libc_version = "newlib",
        tool_paths = tool_paths,
        # Include search paths reported back to Bazel for source
        # tracking. Paths are interpreted relative to the
        # `cc_toolchain`'s package (the arm_gnu repo root), which
        # is where the GCC tarball was extracted. We list the most
        # common directories under the install — Bazel only
        # requires headers actually used by compiles to be reachable.
        # Builtin include dirs reported back to Bazel's "no absolute
        # path inclusions" check. We use %package(...)% syntax so
        # Bazel resolves the path against the cc_toolchain target's
        # package (the arm_gnu repo root) — relative paths don't
        # work reliably for external repos with `+` in their
        # canonical names.
        cxx_builtin_include_directories = _builtin_include_dirs(ctx),
        features = [freestanding, no_canonical],
    )

cross_cc_toolchain_config = rule(
    implementation = _impl,
    attrs = {
        "toolchain_identifier": attr.string(mandatory = True),
        "target_system_name": attr.string(mandatory = True),
        "target_cpu": attr.string(mandatory = True),
        "tool_prefix": attr.string(mandatory = True),
        "sysroot": attr.string(mandatory = True),
        "gcc_version": attr.string(
            default = "14.2.1",
            doc = "GCC internal version (e.g. 14.2.1 for ARM " +
                  "release 14.2.rel1). Used to locate the " +
                  "lib/gcc/<triple>/<version>/include dir.",
        ),
    },
    provides = [CcToolchainConfigInfo],
)
