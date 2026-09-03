"""Core providers for rules_macvm.

Two providers carry the data the rules pass around:

- `VmProviderInfo` — a VMM backend (vfkit, mock, …): the hypervisor
  binary plus its identity (`kind`) and capability flags. Produced by
  the `vm_provider` rule; resolved by `vm` either through the
  `//vm:toolchain_type` toolchain or an explicit `provider` attribute.

- `VmInfo` — a declared virtual machine: the resolved spec scalars, the
  launcher, and the deterministic argv manifest. Lets other rules
  introspect / depend on a VM without re-deriving its definition.
"""

VmProviderInfo = provider(
    doc = "A VMM backend that can launch a `vm`.",
    fields = {
        "kind": "String: backend identity (e.g. \"vfkit\", \"mock\"). Selects the " +
                "argv translator in //vm/private:argv.bzl.",
        "vmm": "Target: the hypervisor executable (its runfiles ride along).",
        "supports": "struct: capability flags — rosetta, virtiofs, vsock, nested, " +
                    "efi_boot, linux_boot. Used for early, clear validation errors.",
    },
)

VmInfo = provider(
    doc = "A declared virtual machine.",
    fields = {
        "kind": "String: the provider kind this VM was built for.",
        "cpus": "Int: virtual CPU count.",
        "memory_mib": "Int: RAM in MiB.",
        "launcher": "File: the executable that boots the VM (also the rule's " +
                    "DefaultInfo executable).",
        "argv_manifest": "File: deterministic, host-independent record of the VMM " +
                         "command line (short_paths, not resolved absolutes). For " +
                         "golden tests and `bazel build`-time inspection.",
    },
)

def provider_supports(
        *,
        rosetta = False,
        virtiofs = False,
        vsock = False,
        nested = False,
        efi_boot = False,
        linux_boot = False):
    """Construct the `supports` capability struct for a VmProviderInfo."""
    return struct(
        rosetta = rosetta,
        virtiofs = virtiofs,
        vsock = vsock,
        nested = nested,
        efi_boot = efi_boot,
        linux_boot = linux_boot,
    )
