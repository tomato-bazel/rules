"""Module extension for the vfkit VMM backend.

Hermetically fetches the pinned, signed universal vfkit binary and emits
`@vfkit//:vfkit` (the binary), `@vfkit//:vfkit_provider` (a
`vm_provider` usable via `vm(provider = ...)`), and
`@vfkit//:vfkit_toolchain_def` (the same provider registered for
`//vm:toolchain_type`, constrained to a macOS exec platform since
Virtualization.framework is macOS-only).

    vfkit = use_extension("@rules_macvm//providers/vfkit:extensions.bzl", "vfkit")
    use_repo(vfkit, "vfkit")
    register_toolchains("@vfkit//:vfkit_toolchain_def")
"""

load(
    "//providers/vfkit/private:known_versions.bzl",
    "DEFAULT_VERSION",
    "KNOWN_VERSIONS",
    "URL_TEMPLATE",
)

_BUILD = """\
load("@bazel_skylib//rules:native_binary.bzl", "native_binary")
load("@rules_macvm//vm:toolchains.bzl", "vm_provider")

package(default_visibility = ["//visibility:public"])

# Copies the downloaded signed binary byte-for-byte (preserving the
# com.apple.security.virtualization entitlement) to a stable name.
native_binary(
    name = "vfkit",
    src = "vfkit.bin",
    out = "vfkit",
)

vm_provider(
    name = "vfkit_provider",
    kind = "vfkit",
    vmm = ":vfkit",
    rosetta = True,
    virtiofs = True,
    vsock = True,
    nested = True,
    efi_boot = True,
    linux_boot = True,
)

toolchain(
    name = "vfkit_toolchain_def",
    toolchain = ":vfkit_provider",
    toolchain_type = "@rules_macvm//vm:toolchain_type",
    # Virtualization.framework only exists on macOS; vfkit runs on the
    # exec machine (where `bazel run` happens).
    exec_compatible_with = ["@platforms//os:macos"],
)
"""

def _vfkit_repository_impl(rctx):
    version = rctx.attr.version
    sha256 = KNOWN_VERSIONS.get(version, "")
    if not sha256:
        # buildifier: disable=print
        print(("rules_macvm: WARNING — no pinned sha256 for vfkit@{v}; downloading " +
               "unverified. Run `tools/refresh_versions.py --version {v}` to lock it.").format(v = version))

    # A single raw Mach-O, not an archive — download (not extract),
    # keeping the executable bit + signature intact.
    rctx.download(
        url = URL_TEMPLATE.format(version = version),
        output = "vfkit.bin",
        sha256 = sha256 or "",
        executable = True,
    )
    rctx.file("BUILD.bazel", _BUILD)

_vfkit_repository = repository_rule(
    implementation = _vfkit_repository_impl,
    attrs = {
        "version": attr.string(mandatory = True, doc = "vfkit release version (e.g. \"0.6.3\")."),
    },
    doc = "Fetch the pinned signed universal vfkit binary.",
)

def _vfkit_extension_impl(mctx):
    version = DEFAULT_VERSION
    for mod in mctx.modules:
        for tag in mod.tags.toolchain:
            if tag.version:
                version = tag.version
    _vfkit_repository(name = "vfkit", version = version)

_toolchain_tag = tag_class(attrs = {
    "version": attr.string(default = "", doc = "Override the vfkit version."),
})

vfkit = module_extension(
    implementation = _vfkit_extension_impl,
    tag_classes = {"toolchain": _toolchain_tag},
    doc = "Sets up @vfkit: the pinned signed vfkit binary + a vm_provider + a macOS toolchain.",
)
