"""k8s_operator_image — an operator binary as a linux/amd64 container image.

    load("@rules_k8s//oci:defs.bzl", "k8s_operator_image")
"""

load("@rules_oci//oci:defs.bzl", "oci_image", "oci_load", "oci_push")
load("@rules_pkg//pkg:tar.bzl", "pkg_tar")
load("//oci/private:transition.bzl", "staged_binary", "transitioned_image")

def k8s_operator_image(
        name,
        binary,
        repository = None,
        base = None,
        platform = None,
        entrypoint_path = None,
        env = None,
        user = "65532:65532",
        exposed_ports = None,
        tars = None,
        visibility = None,
        **kwargs):
    """An operator binary, packaged as a linux/amd64 image.

    Emits:

      <name>           the oci_image
      <name>_push      oci_push  (only when `repository` is set)
      <name>_tarball   oci_load, for `docker load`

    The binary is retargeted by a PER-TARGET transition, not a global
    `--platforms` flag. That distinction is the whole point: a global flag
    retargets the push tooling too, which then can't resolve a cpp toolchain —
    the reason real repos bypass their own `oci_push` with a
    hand-rolled `crane push`. With the transition, plain `bazel build //...`
    produces a linux/amd64 image on any host and `<name>_push` works.

        k8s_operator_image(
            name = "my-operator-image",
            binary = "//operator/cmd:manager",
            repository = "ghcr.io/example/my-operator",
        )

    Note some CI systems derive the image repo from the target name; if yours does,
    keep them equal.

    Args:
        name: Target name. Also the image target.
        binary: The operator binary (`go_binary`, `rust_binary`, ...). Built for
            `platform`, host-independent.
        repository: Image repository. Omit and no `_push` target is created.
        base: Base image. Defaults to `//oci:base_image` in RULES_K8S — a
            `Label()`, so it pins here regardless of caller. This is the exact bug
            that made a shared image macro get copy-pasted across repos: it used a
            bare `//tools/oci:base_image`, which silently resolved in the CALLER's
            repo, so every consumer got a different base and the macro could not be
            shared.
        platform: Platform to build `binary` for. Defaults to `//oci:linux_amd64`
            (plain os:linux + cpu:x86_64, so it suits Go and Rust alike).
        entrypoint_path: Path of the binary inside the image. Defaults to
            `/usr/local/bin/<binary basename>`.
        env: Image environment, as a dict.
        user: Image user. Defaults to distroless' nonroot uid:gid.
        exposed_ports: Ports to declare.
        tars: Extra layers to include (e.g. a CRD bundle).
        visibility: Target visibility.
        **kwargs: Forwarded to `oci_image`.
    """
    platform = platform or Label("//oci:linux_amd64")
    base = base or Label("//oci:base_image")

    # Use the TARGET name, not a parse of the binary label. The old code did
    #     Label(binary).name if binary.startswith("//") ...
    # which (a) crashed on a Label object, since Labels have no .startswith, and
    # (b) named the entrypoint after the LABEL while pkg_tar packaged the file
    # under its real BASENAME — which differ for an alias or an `out =` binary.
    # Both shipped green and CrashLoopBackOff'd. staged_binary makes the two agree
    # by construction: we choose the filename, it guarantees it.
    binary_name = name + "_bin"
    entrypoint_path = entrypoint_path or "/usr/local/bin/" + binary_name

    staged_binary(
        name = name + "_staged",
        binary = binary,
        out_name = binary_name,
        tags = ["manual"],
    )

    pkg_tar(
        name = name + "_layer",
        srcs = [":" + name + "_staged"],
        # Matters for a binary with data deps; a static Go operator has none, a
        # Rust one may.
        include_runfiles = True,
        package_dir = "/usr/local/bin",
        tags = ["manual"],
    )

    # The untransitioned image. Never build this directly on a non-linux host —
    # its base won't resolve. `:<name>` below is the one to use.
    oci_image(
        name = name + "_impl",
        base = base,
        entrypoint = [entrypoint_path],
        env = env,
        exposed_ports = exposed_ports,
        tars = [name + "_layer"] + (tars or []),
        user = user,
        tags = ["manual"],
        **kwargs
    )

    # The transition goes HERE, on the image, not on the binary: oci_image's
    # `base` resolves in the target configuration too, so retargeting only the
    # binary leaves the base unresolvable. Everything beneath this — base, layers,
    # binary — lands on linux/amd64; oci_push below stays outside it, in the host
    # configuration where its launcher's cpp toolchain resolves.
    transitioned_image(
        name = name,
        image = ":" + name + "_impl",
        platform = platform,
        visibility = visibility,
    )

    oci_load(
        name = name + "_tarball",
        image = ":" + name,
        repo_tags = [(repository or name) + ":latest"],
        tags = ["manual"],
        visibility = visibility,
    )

    if repository:
        oci_push(
            name = name + "_push",
            image = ":" + name,
            repository = repository,
            visibility = visibility,
        )
