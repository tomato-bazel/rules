"""A per-target platform transition for operator images.

THE PROBLEM

An operator image must hold a linux/amd64 binary regardless of the host. The
fleet does that with an invocation-wide flag:

    # a real operator repo's .bazelrc
    build:operator-image --platforms=@rules_go//go/toolchain:linux_amd64

`--platforms` is invocation-wide, so it doesn't just retarget the image — it
retargets everything the invocation touches, including the push target and the
tools it drags in. Those then want a cpp toolchain for a platform that has none:

    No matching toolchains for cpp:toolchain_type

which is why at least one real repo's CI never runs its own `oci_push`. From
its image workflow, verbatim:

    # Build the OCI layout and crane-push it, rather than `bazel run :image_push`.
    # image_push pulls the crane push tool into the build graph, and under
    # --config=operator-image (--platforms=go/linux_amd64) that tool's launcher
    # can't resolve a cpp toolchain (No matching toolchains for cpp:toolchain_type).

So `:image_push` is dead code, and pushing falls back to a hand-rolled `crane`.

THE FIX, AND WHY IT GOES ON THE IMAGE

Put the retarget on the target, not the invocation. The transition wraps the
IMAGE rather than the binary: `oci_image`'s `base` is itself resolved in the
target configuration (an `oci_pull`ed base selects on os/cpu), so retargeting
only the binary leaves the base unresolvable — "could not find an image matching
the target platform".

Transitioning the image fixes both halves at once: the base, the layers and the
binary all resolve under linux/amd64, while `oci_push` sits OUTSIDE the
transition in the host configuration, where its launcher's cpp toolchain resolves
normally. Plain `bazel build //...` then yields a correct linux/amd64 image on any
host, with no `--config` and no global `--platforms`.
"""

def _platform_transition_impl(_settings, attr):
    return {"//command_line_option:platforms": str(attr.platform)}

_platform_transition = transition(
    implementation = _platform_transition_impl,
    inputs = [],
    outputs = ["//command_line_option:platforms"],
)

def _transitioned_image_impl(ctx):
    # `image` is a list because an incoming transition resolves the attr once per
    # configuration — here always exactly one.
    dep = ctx.attr.image[0]

    # Forward the image directory verbatim. oci_push/oci_load consume an
    # oci_image's DefaultInfo files, so passing them straight through makes this
    # wrapper invisible to them.
    return [DefaultInfo(files = dep[DefaultInfo].files)]

transitioned_image = rule(
    implementation = _transitioned_image_impl,
    doc = "Builds `image` (and everything under it) for `platform`, without retargeting the invocation.",
    attrs = {
        "image": attr.label(
            mandatory = True,
            cfg = _platform_transition,
            doc = "The oci_image to retarget.",
        ),
        "platform": attr.label(
            mandatory = True,
            doc = "The platform to build it for.",
        ),
        # Required by Bazel for a rule carrying an attr-level (incoming) transition.
        "_allowlist_function_transition": attr.label(
            default = "@bazel_tools//tools/allowlists/function_transition_allowlist",
        ),
    },
)

def _staged_binary_impl(ctx):
    """Stage the binary under a name the macro can predict."""
    exe = ctx.attr.binary[DefaultInfo].files_to_run.executable
    out = ctx.actions.declare_file(ctx.attr.out_name)
    ctx.actions.symlink(output = out, target_file = exe, is_executable = True)
    return [DefaultInfo(
        files = depset([out]),
        runfiles = ctx.attr.binary[DefaultInfo].default_runfiles,
    )]

staged_binary = rule(
    implementation = _staged_binary_impl,
    doc = """Stage a binary under an exact filename.

Exists because a macro cannot know what a binary's output file is CALLED. It has
a label, and the label name is not the basename:

    alias(name = "manager_alias", actual = ":manager")   -> file is `manager`
    go_binary(name = "manager2", out = "manager-bin")    -> file is `manager-bin`

k8s_operator_image used to derive the image entrypoint from the label name, so
both of those produced an image whose entrypoint pointed at a file that wasn't
there. Both BUILT GREEN; the failure was a CrashLoopBackOff in the cluster.

Restating the basename here makes the entrypoint correct by construction: the
macro picks the name, this rule guarantees the file has it. A symlink, not a copy
— the binary can be large and this runs every build.
""",
    attrs = {
        "binary": attr.label(
            mandatory = True,
            executable = True,
            cfg = "target",
            doc = "The binary to stage.",
        ),
        "out_name": attr.string(
            mandatory = True,
            doc = "The exact filename to stage it under.",
        ),
    },
)
