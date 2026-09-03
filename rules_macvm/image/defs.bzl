"""Guest-image helpers for rules_macvm.

Provider-agnostic: the artifacts here boot under vfkit, krunkit, qemu, or
bare metal. v0.0.1 ships `ignition_config` — generate an Ignition
(Fedora CoreOS-style) provisioning file from typed attrs, entirely with
Starlark `json.encode` (hermetic, golden-testable). Feed it to a VM via
`vm(ignition = ":provision")`.

Roadmap (documented, not yet built): rootfs assembly from OCI layers /
mkosi, kernel+initrd extraction, inline-file Ignition stanzas (need an
encoder tool), and butane → Ignition transpilation.
"""

VmIgnitionInfo = provider(
    doc = "A generated Ignition provisioning file.",
    fields = {"file": "File: the rendered Ignition JSON."},
)

# Ignition spec version we target. 3.4.0 is broadly supported by current
# Fedora CoreOS / podman-machine images.
_IGNITION_VERSION = "3.4.0"

def _ignition_config_impl(ctx):
    config = {"ignition": {"version": _IGNITION_VERSION}}

    if ctx.attr.ssh_authorized_keys:
        config["passwd"] = {
            "users": [{
                "name": ctx.attr.username,
                "sshAuthorizedKeys": ctx.attr.ssh_authorized_keys,
            }],
        }

    if ctx.attr.enable_units:
        config["systemd"] = {
            "units": [
                {"name": name, "enabled": True}
                for name in ctx.attr.enable_units
            ],
        }

    out = ctx.outputs.ign
    ctx.actions.write(out, json.encode(config))

    return [
        DefaultInfo(files = depset([out])),
        VmIgnitionInfo(file = out),
    ]

ignition_config = rule(
    implementation = _ignition_config_impl,
    outputs = {"ign": "%{name}.ign"},
    attrs = {
        "username": attr.string(
            default = "core",
            doc = "User to attach `ssh_authorized_keys` to.",
        ),
        "ssh_authorized_keys": attr.string_list(
            default = [],
            doc = "SSH public keys authorized for `username`.",
        ),
        "enable_units": attr.string_list(
            default = [],
            doc = "systemd unit names to enable (e.g. `podman.socket`).",
        ),
    },
    doc = "Render an Ignition provisioning JSON from typed attrs. Output: `<name>.ign`.",
)
