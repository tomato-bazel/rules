"""Providers for rules_systemd.

`SystemdUnitInfo` is emitted by every unit rule (`systemd_service`,
`systemd_target`, `systemd_tmpfiles`, …). The `_systemd_units` aspect
walks a `deps` graph collecting them into a `SystemdTransitiveInfo`
depset, which `systemd_layer` reads to assemble the
`/etc/systemd/system` tar (computing the `multi-user.target.wants/*`
enable-symlinks from each unit's `wanted_by`).
"""

SystemdUnitInfo = provider(
    doc = "A single rendered systemd unit or config file.",
    fields = {
        "unit_type": "str: one of service|oneshot|target|socket|timer|tmpfiles|dropin.",
        "unit_name": "str: on-disk basename, e.g. 'postgres.service' or 'devstack.conf'.",
        "dest": "str: absolute install path inside the image, e.g. '/etc/systemd/system/postgres.service'.",
        "file": "File: the rendered file.",
        "wanted_by": "list[str]: install targets to symlink-enable this unit under (e.g. ['multi-user.target']); empty for none.",
    },
)

SystemdTransitiveInfo = provider(
    doc = "Transitive set of units, threaded by the `_systemd_units` aspect.",
    fields = {
        "units": "depset[SystemdUnitInfo].",
    },
)

SystemdLayerInfo = provider(
    doc = "A tar layer of /etc/systemd/system (+ /etc/tmpfiles.d, drop-ins) with enable-symlinks, for oci_image(tars=[...]).",
    fields = {
        "tar": "File: the layer tarball.",
        "units": "depset[SystemdUnitInfo]: everything packed into the layer.",
    },
)
