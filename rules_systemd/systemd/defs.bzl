"""User-facing rules for rules_systemd.

Typed rules that render systemd primitives from attrs (no external
codegen — pure Starlark `ctx.actions.write`), plus a `systemd_layer`
aggregator that packs them into an `/etc/systemd/system` tar with the
`*.target.wants/` enable-symlinks computed automatically:

  * `systemd_service`  — a `[Service]` unit.
  * `systemd_oneshot`  — `systemd_service` with `Type=oneshot` +
                         `RemainAfterExit=yes` (init/migration steps).
  * `systemd_target`   — a `[Unit]`/`[Install]` synchronization target.
  * `systemd_socket`   — a `[Socket]` unit.
  * `systemd_timer`    — a `[Timer]` unit.
  * `systemd_tmpfiles` — a `tmpfiles.d/*.conf` (first-boot dirs/perms).
  * `systemd_dropin`   — a drop-in `*.conf` for an existing unit.
  * `systemd_layer`    — collect transitive units → one tar layer for
                         `oci_image(tars = [...])`.

Enable-semantics: a build action never runs `systemctl enable`, so for
every unit whose `wanted_by` includes `T`, `systemd_layer` writes the
symlink `/etc/systemd/system/T.wants/<unit> -> ../<unit>` itself.
"""

load(
    "//systemd:providers.bzl",
    "SystemdLayerInfo",
    "SystemdTransitiveInfo",
    "SystemdUnitInfo",
)
load("//systemd/private:render.bzl", "dict_pairs", "join", "render_sections")

# --- shared attr blocks ------------------------------------------------

# [Unit]-section attrs common to service/socket/timer/target.
_UNIT_ATTRS = {
    "description": attr.string(doc = "Description= (the human label shown by `systemctl status`)."),
    "documentation": attr.string_list(doc = "Documentation= URIs."),
    "requires": attr.string_list(doc = "Requires= hard dependencies."),
    "wants": attr.string_list(doc = "Wants= soft dependencies."),
    "after": attr.string_list(doc = "After= ordering."),
    "before": attr.string_list(doc = "Before= ordering."),
    "binds_to": attr.string_list(doc = "BindsTo= units."),
    "part_of": attr.string_list(doc = "PartOf= units."),
    "conflicts": attr.string_list(doc = "Conflicts= units."),
    "unit_extra": attr.string_dict(doc = "Extra [Unit] Key=Value pairs not hoisted to an attr (e.g. ConditionPathExists)."),
    "unit_name": attr.string(doc = "Override the on-disk unit filename (default `<name>.<type-suffix>`)."),
}

# [Install]-section attrs.
_INSTALL_ATTRS = {
    "wanted_by": attr.string_list(doc = "WantedBy= targets; `systemd_layer` writes the enable-symlink for each."),
    "required_by": attr.string_list(doc = "RequiredBy= targets."),
    "alias": attr.string_list(doc = "Alias= names."),
    "install_extra": attr.string_dict(doc = "Extra [Install] Key=Value pairs."),
}

def _unit_section(ctx):
    return [
        ("Description", ctx.attr.description),
        ("Documentation", join(ctx.attr.documentation)),
        ("Requires", join(ctx.attr.requires)),
        ("Wants", join(ctx.attr.wants)),
        ("After", join(ctx.attr.after)),
        ("Before", join(ctx.attr.before)),
        ("BindsTo", join(ctx.attr.binds_to)),
        ("PartOf", join(ctx.attr.part_of)),
        ("Conflicts", join(ctx.attr.conflicts)),
    ] + dict_pairs(ctx.attr.unit_extra)

def _install_section(ctx):
    return [
        ("WantedBy", join(ctx.attr.wanted_by)),
        ("RequiredBy", join(ctx.attr.required_by)),
        ("Alias", join(ctx.attr.alias)),
    ] + dict_pairs(ctx.attr.install_extra)

def _emit(ctx, unit_type, unit_name, text, dest = None):
    if dest == None:
        dest = "/etc/systemd/system/" + unit_name
    out = ctx.actions.declare_file(unit_name)
    ctx.actions.write(out, text)
    return [
        DefaultInfo(files = depset([out])),
        SystemdUnitInfo(
            unit_type = unit_type,
            unit_name = unit_name,
            dest = dest,
            file = out,
            wanted_by = list(ctx.attr.wanted_by) if hasattr(ctx.attr, "wanted_by") else [],
        ),
    ]

# --- systemd_service / systemd_oneshot ---------------------------------

def _service_impl(ctx):
    name = ctx.attr.unit_name or (ctx.label.name + ".service")
    remain = ctx.attr.remain_after_exit

    # oneshot units default to RemainAfterExit=yes unless overridden.
    if remain == "auto":
        remain = "yes" if ctx.attr.type == "oneshot" else ""
    service = [
        ("Type", ctx.attr.type),
        ("ExecStartPre", ctx.attr.exec_start_pre),
        ("ExecStart", ctx.attr.exec_start),
        ("ExecStartPost", ctx.attr.exec_start_post),
        ("ExecStop", ctx.attr.exec_stop),
        ("ExecReload", ctx.attr.exec_reload),
        ("Restart", ctx.attr.restart),
        ("RestartSec", ctx.attr.restart_sec),
        ("RemainAfterExit", remain),
        ("User", ctx.attr.user),
        ("Group", ctx.attr.group),
        ("WorkingDirectory", ctx.attr.working_directory),
        ("Environment", ctx.attr.environment),
        ("EnvironmentFile", ctx.attr.environment_file),
        ("StandardOutput", ctx.attr.standard_output),
        ("StandardError", ctx.attr.standard_error),
        ("TimeoutStartSec", ctx.attr.timeout_start_sec),
    ] + dict_pairs(ctx.attr.service_extra)
    text = render_sections([
        ("Unit", _unit_section(ctx)),
        ("Service", service),
        ("Install", _install_section(ctx)),
    ])
    return _emit(ctx, "oneshot" if ctx.attr.type == "oneshot" else "service", name, text)

_SERVICE_ATTRS = dict(_UNIT_ATTRS)
_SERVICE_ATTRS.update(_INSTALL_ATTRS)
_SERVICE_ATTRS.update({
    "type": attr.string(
        default = "simple",
        values = ["simple", "exec", "forking", "oneshot", "dbus", "notify", "notify-reload", "idle"],
        doc = "Type=.",
    ),
    "exec_start": attr.string(doc = "ExecStart= command."),
    "exec_start_pre": attr.string_list(doc = "ExecStartPre= commands (repeatable)."),
    "exec_start_post": attr.string_list(doc = "ExecStartPost= commands (repeatable)."),
    "exec_stop": attr.string(doc = "ExecStop= command."),
    "exec_reload": attr.string(doc = "ExecReload= command."),
    "restart": attr.string(doc = "Restart= policy (e.g. on-failure, always)."),
    "restart_sec": attr.string(doc = "RestartSec= delay (e.g. '2s')."),
    "remain_after_exit": attr.string(default = "auto", doc = "RemainAfterExit=; 'auto' = yes for oneshot, else unset."),
    "user": attr.string(doc = "User= to drop to."),
    "group": attr.string(doc = "Group= to drop to."),
    "working_directory": attr.string(doc = "WorkingDirectory=."),
    "environment": attr.string_list(doc = "Environment= entries (repeatable, 'K=V')."),
    "environment_file": attr.string_list(doc = "EnvironmentFile= paths (repeatable; prefix '-' = optional)."),
    "standard_output": attr.string(doc = "StandardOutput= (e.g. journal)."),
    "standard_error": attr.string(doc = "StandardError= (e.g. journal)."),
    "timeout_start_sec": attr.string(doc = "TimeoutStartSec=."),
    "service_extra": attr.string_dict(doc = "Extra [Service] Key=Value pairs."),
})

systemd_service = rule(
    implementation = _service_impl,
    attrs = _SERVICE_ATTRS,
    provides = [SystemdUnitInfo],
    doc = "Render a `[Service]` unit. Output: `<name>.service` (or `unit_name`).",
)

def systemd_oneshot(name, **kwargs):
    """A `systemd_service` with `Type=oneshot` (RemainAfterExit=yes by default).

    Convenience for first-boot init / one-shot migration steps that
    other units order `After=` / `Requires=`.
    """
    kwargs.pop("type", None)
    systemd_service(name = name, type = "oneshot", **kwargs)

# --- systemd_target ----------------------------------------------------

def _target_impl(ctx):
    name = ctx.attr.unit_name or (ctx.label.name + ".target")
    text = render_sections([
        ("Unit", _unit_section(ctx)),
        ("Install", _install_section(ctx)),
    ])
    return _emit(ctx, "target", name, text)

_TARGET_ATTRS = dict(_UNIT_ATTRS)
_TARGET_ATTRS.update(_INSTALL_ATTRS)

systemd_target = rule(
    implementation = _target_impl,
    attrs = _TARGET_ATTRS,
    provides = [SystemdUnitInfo],
    doc = "Render a `[Unit]`/`[Install]` synchronization target. Output: `<name>.target`.",
)

# --- systemd_socket ----------------------------------------------------

def _socket_impl(ctx):
    name = ctx.attr.unit_name or (ctx.label.name + ".socket")
    socket = [
        ("ListenStream", ctx.attr.listen_stream),
        ("ListenDatagram", ctx.attr.listen_datagram),
        ("Accept", ctx.attr.accept),
        ("SocketUser", ctx.attr.socket_user),
        ("SocketGroup", ctx.attr.socket_group),
        ("Service", ctx.attr.service),
    ] + dict_pairs(ctx.attr.socket_extra)
    text = render_sections([
        ("Unit", _unit_section(ctx)),
        ("Socket", socket),
        ("Install", _install_section(ctx)),
    ])
    return _emit(ctx, "socket", name, text)

_SOCKET_ATTRS = dict(_UNIT_ATTRS)
_SOCKET_ATTRS.update(_INSTALL_ATTRS)
_SOCKET_ATTRS.update({
    "listen_stream": attr.string_list(doc = "ListenStream= addresses/ports (repeatable)."),
    "listen_datagram": attr.string_list(doc = "ListenDatagram= addresses/ports (repeatable)."),
    "accept": attr.string(doc = "Accept= (yes/no)."),
    "socket_user": attr.string(doc = "SocketUser=."),
    "socket_group": attr.string(doc = "SocketGroup=."),
    "service": attr.string(doc = "Service= unit to activate."),
    "socket_extra": attr.string_dict(doc = "Extra [Socket] Key=Value pairs."),
})

systemd_socket = rule(
    implementation = _socket_impl,
    attrs = _SOCKET_ATTRS,
    provides = [SystemdUnitInfo],
    doc = "Render a `[Socket]` unit. Output: `<name>.socket`.",
)

# --- systemd_timer -----------------------------------------------------

def _timer_impl(ctx):
    name = ctx.attr.unit_name or (ctx.label.name + ".timer")
    timer = [
        ("OnCalendar", ctx.attr.on_calendar),
        ("OnBootSec", ctx.attr.on_boot_sec),
        ("OnUnitActiveSec", ctx.attr.on_unit_active_sec),
        ("Persistent", ctx.attr.persistent),
        ("Unit", ctx.attr.unit),
    ] + dict_pairs(ctx.attr.timer_extra)
    text = render_sections([
        ("Unit", _unit_section(ctx)),
        ("Timer", timer),
        ("Install", _install_section(ctx)),
    ])
    return _emit(ctx, "timer", name, text)

_TIMER_ATTRS = dict(_UNIT_ATTRS)
_TIMER_ATTRS.update(_INSTALL_ATTRS)
_TIMER_ATTRS.update({
    "on_calendar": attr.string_list(doc = "OnCalendar= schedules (repeatable)."),
    "on_boot_sec": attr.string(doc = "OnBootSec=."),
    "on_unit_active_sec": attr.string(doc = "OnUnitActiveSec=."),
    "persistent": attr.string(doc = "Persistent= (yes/no)."),
    "unit": attr.string(doc = "Unit= to activate (defaults to the same-named .service)."),
    "timer_extra": attr.string_dict(doc = "Extra [Timer] Key=Value pairs."),
})

systemd_timer = rule(
    implementation = _timer_impl,
    attrs = _TIMER_ATTRS,
    provides = [SystemdUnitInfo],
    doc = "Render a `[Timer]` unit. Output: `<name>.timer`. Default WantedBy=timers.target if unset.",
)

# --- systemd_tmpfiles --------------------------------------------------

def _tmpfiles_impl(ctx):
    name = ctx.attr.unit_name or (ctx.label.name + ".conf")
    text = "\n".join([entry for entry in ctx.attr.lines if entry]) + "\n"
    return _emit(ctx, "tmpfiles", name, text, dest = "/etc/tmpfiles.d/" + name)

systemd_tmpfiles = rule(
    implementation = _tmpfiles_impl,
    attrs = {
        "lines": attr.string_list(
            mandatory = True,
            doc = "tmpfiles.d lines, e.g. 'd /var/lib/devstack/postgres 0700 postgres postgres -'.",
        ),
        "unit_name": attr.string(doc = "Override the on-disk filename (default `<name>.conf`)."),
    },
    provides = [SystemdUnitInfo],
    doc = "Render a `tmpfiles.d/*.conf` (first-boot dirs/perms). Installs to /etc/tmpfiles.d.",
)

# --- systemd_dropin ----------------------------------------------------

def _dropin_impl(ctx):
    base = ctx.attr.unit
    name = ctx.attr.dropin_name or ctx.label.name
    dest = "/etc/systemd/system/{}.d/{}.conf".format(base, name)
    out_name = "{}.d__{}.conf".format(base, name)
    out = ctx.actions.declare_file(out_name)
    ctx.actions.write(out, ctx.attr.content if ctx.attr.content.endswith("\n") else ctx.attr.content + "\n")
    return [
        DefaultInfo(files = depset([out])),
        SystemdUnitInfo(unit_type = "dropin", unit_name = out_name, dest = dest, file = out, wanted_by = []),
    ]

systemd_dropin = rule(
    implementation = _dropin_impl,
    attrs = {
        "unit": attr.string(mandatory = True, doc = "Base unit this drop-in extends, e.g. 'postgres.service'."),
        "content": attr.string(mandatory = True, doc = "Raw drop-in content (INI sections)."),
        "dropin_name": attr.string(doc = "Drop-in filename stem (default `<name>`)."),
    },
    provides = [SystemdUnitInfo],
    doc = "Render a drop-in `*.conf` for an existing unit. Installs to /etc/systemd/system/<unit>.d/.",
)

# --- the aspect + systemd_layer ----------------------------------------

def _units_aspect_impl(target, ctx):
    direct = [target[SystemdUnitInfo]] if SystemdUnitInfo in target else []
    transitive = []
    if hasattr(ctx.rule.attr, "deps"):
        for dep in ctx.rule.attr.deps:
            if type(dep) == "Target" and SystemdTransitiveInfo in dep:
                transitive.append(dep[SystemdTransitiveInfo].units)
    return [SystemdTransitiveInfo(units = depset(direct, transitive = transitive))]

_systemd_units_aspect = aspect(
    implementation = _units_aspect_impl,
    attr_aspects = ["deps"],
    doc = "Collect SystemdUnitInfo from a target and its transitive `deps`.",
)

def _layer_impl(ctx):
    units = depset(
        transitive = [d[SystemdTransitiveInfo].units for d in ctx.attr.deps],
    ).to_list()

    files = []
    symlinks = []
    seen = {}
    inputs = []
    for u in units:
        if u.unit_name in seen:
            if seen[u.unit_name] != u.dest:
                fail("systemd_layer: two units named '{}' at different paths ({} vs {})".format(
                    u.unit_name,
                    seen[u.unit_name],
                    u.dest,
                ))
            continue
        seen[u.unit_name] = u.dest
        files.append({"path": u.dest, "src": u.file.path, "mode": 420})  # 0644
        inputs.append(u.file)
        for target in u.wanted_by:
            symlinks.append({
                "path": "/etc/systemd/system/{}.wants/{}".format(target, u.unit_name),
                "target": "../" + u.unit_name,
            })

    manifest = ctx.actions.declare_file(ctx.label.name + ".manifest.json")
    ctx.actions.write(manifest, json.encode({"files": files, "symlinks": symlinks}))

    tar = ctx.actions.declare_file(ctx.label.name + ".tar")
    listing = ctx.actions.declare_file(ctx.label.name + ".listing.txt")
    ctx.actions.run_shell(
        inputs = inputs + [manifest, ctx.file._mklayer],
        outputs = [tar, listing],
        command = "python3 {script} {manifest} {tar} {listing}".format(
            script = ctx.file._mklayer.path,
            manifest = manifest.path,
            tar = tar.path,
            listing = listing.path,
        ),
        use_default_shell_env = True,
        mnemonic = "SystemdLayer",
        progress_message = "Assembling systemd layer %s" % ctx.label,
    )

    return [
        DefaultInfo(files = depset([tar])),
        SystemdLayerInfo(tar = tar, units = depset(units)),
        OutputGroupInfo(listing = depset([listing])),
    ]

systemd_layer = rule(
    implementation = _layer_impl,
    attrs = {
        "deps": attr.label_list(
            aspects = [_systemd_units_aspect],
            providers = [[SystemdUnitInfo], [SystemdTransitiveInfo]],
            doc = "Unit targets (or other targets carrying units transitively via `deps`).",
        ),
        "_mklayer": attr.label(
            default = "//systemd/private:mklayer.py",
            allow_single_file = True,
        ),
    },
    provides = [SystemdLayerInfo],
    doc = "Pack transitive units into one `/etc/systemd/system` tar layer with enable-symlinks. " +
          "The tar is the default output; the deterministic `.listing.txt` is in output group `listing`.",
)
