"""Spec → VMM argv translation.

The one place that knows a backend's command-line vocabulary. Pure: it
takes a normalized `spec` struct (built by the `vm` rule) and returns a
list of *tokens*, each token a list of `(frag_kind, value)` fragments
that concatenate into a single argv word:

  * `("lit", "<text>")` — literal text. May contain shell `$VARS`
    (e.g. `$VM_RUNTIME`) that the launcher expands at run time; in the
    deterministic manifest it appears verbatim.
  * `("file", <File>)` — a runfile. The launcher renders it as
    `$(resolve '<short_path>')` (absolute at run time); the manifest
    renders the short_path (host-independent, golden-testable).

Adding a backend = add a `_<kind>_tokens(spec)` function and a branch in
`build_tokens`. vfkit is implemented; `mock` reuses it (the in-repo fake
is vfkit-CLI-compatible, so the same translation is exercised end-to-end
in tests). krunkit / qemu are future branches.
"""

def _lit(tokens, *words):
    for w in words:
        tokens.append([("lit", w)])

def _device(tokens, *frags):
    """Append a `--device <spec>` pair, where <spec> may embed a File."""
    tokens.append([("lit", "--device")])
    tokens.append(list(frags))

def _vfkit_tokens(spec):
    """Translate a spec into a vfkit (crc-org/vfkit) command line."""
    t = []
    _lit(t, "--cpus", str(spec.cpus))
    _lit(t, "--memory", str(spec.memory_mib))

    # Boot: direct Linux kernel, or EFI-boot a disk image.
    if spec.kernel:
        _lit(t, "--kernel")
        t.append([("file", spec.kernel)])
        if spec.initrd:
            _lit(t, "--initrd")
            t.append([("file", spec.initrd)])
        if spec.kernel_cmdline:
            _lit(t, "--kernel-cmdline", spec.kernel_cmdline)
    elif spec.efi:
        # A per-boot EFI variable store under the launcher's runtime dir.
        _lit(t, "--bootloader", "efi,variable-store=$VM_RUNTIME/efi-vars.nvram,create")
    else:
        fail("vm: set `kernel = ...` (Linux direct boot) or `efi = True` (EFI disk boot)")

    for d in spec.disks:
        _device(t, ("lit", "virtio-blk,path="), ("file", d))

    if spec.rosetta:
        _device(t, ("lit", "rosetta,mountTag=rosetta"))

    if spec.ignition:
        _lit(t, "--ignition")
        t.append([("file", spec.ignition)])

    for ci in spec.cloud_init:
        _lit(t, "--cloud-init")
        t.append([("file", ci)])

    if spec.nested:
        _lit(t, "--nested")
    if spec.gui:
        _lit(t, "--gui")
    if spec.restful_uri:
        _lit(t, "--restful-uri", spec.restful_uri)

    # Raw `--device` escape hatch (virtio-net, virtio-vsock, virtio-gpu,
    # virtio-serial, …) plus a final passthrough.
    for dev in spec.devices:
        _device(t, ("lit", dev))
    for a in spec.extra_args:
        _lit(t, a)

    return t

def build_tokens(kind, spec):
    """Dispatch to the backend's translator. Fails clearly for unknown kinds."""
    if kind in ("vfkit", "mock"):
        return _vfkit_tokens(spec)
    fail(("rules_macvm: no argv translator for provider kind %r. Implement " +
          "_%s_tokens(spec) in vm/private/argv.bzl and add a branch here.") % (kind, kind))
