"""The `vm_provider` rule — declares a VMM backend.

A `vm_provider` target does double duty: it returns `VmProviderInfo`
(so a `vm` can reference it directly via its `provider` attribute) *and*
`platform_common.ToolchainInfo` (so it can be registered for
`//vm:toolchain_type` and resolved automatically by platform). One
target, both wiring styles.

Each fetched/built backend declares one:

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
    )
"""

load(":providers.bzl", "VmProviderInfo", "provider_supports")

def _vm_provider_impl(ctx):
    info = VmProviderInfo(
        kind = ctx.attr.kind,
        vmm = ctx.attr.vmm,
        supports = provider_supports(
            rosetta = ctx.attr.rosetta,
            virtiofs = ctx.attr.virtiofs,
            vsock = ctx.attr.vsock,
            nested = ctx.attr.nested,
            efi_boot = ctx.attr.efi_boot,
            linux_boot = ctx.attr.linux_boot,
        ),
    )

    # Returned twice: as a normal provider (for `vm(provider = ...)`) and
    # wrapped in ToolchainInfo (for `register_toolchains` / automatic
    # resolution via //vm:toolchain_type).
    return [
        info,
        platform_common.ToolchainInfo(vmprovider = info),
    ]

vm_provider = rule(
    implementation = _vm_provider_impl,
    attrs = {
        "kind": attr.string(
            mandatory = True,
            doc = "Backend identity; selects the argv translator " +
                  "(\"vfkit\", \"mock\", …).",
        ),
        "vmm": attr.label(
            mandatory = True,
            executable = True,
            cfg = "exec",
            doc = "The hypervisor executable target.",
        ),
        "rosetta": attr.bool(default = False, doc = "Backend can expose Rosetta x86-64 translation."),
        "virtiofs": attr.bool(default = False, doc = "Backend supports virtio-fs directory shares."),
        "vsock": attr.bool(default = False, doc = "Backend supports virtio-vsock."),
        "nested": attr.bool(default = False, doc = "Backend supports nested virtualization."),
        "efi_boot": attr.bool(default = False, doc = "Backend can EFI-boot a disk image."),
        "linux_boot": attr.bool(default = False, doc = "Backend can direct-boot a Linux kernel + initrd."),
    },
    doc = "Declare a VMM backend usable as both a `vm` provider and a registered toolchain.",
)
