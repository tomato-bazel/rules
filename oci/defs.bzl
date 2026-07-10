"""`rust_service_image`: package a rust_binary + its runfiles as
one OCI image rooted at /app.

Moved here from botnoc/tools/oci/defs.bzl so a standalone plugin's image target
needs no botnoc deps. One change vs the original: a `base` parameter (defaults to
this module's `//oci:base_image` distroless/cc), so the base is pinned to THIS
module regardless of which repo calls the macro.

Usage:

```python
load("@rules_fastverk_plugin//oci:defs.bzl", "rust_service_image")

rust_service_image(
    name = "spec-image",
    binary = ":spec-server",
    repository = "ghcr.io/fastverk/spec-server",
    exposed_ports = ["8080/tcp"],
)
```

Emits:
  - `<name>_layer`    — tar with the binary + its runfiles, rooted at /app.
                         `include_runfiles = True` so data deps (panel bundles,
                         static assets) ship inside the image.
  - `<name>`          — oci_image on `base` (default `//oci:base_image`,
                         distroless/cc). Entrypoint is /app/<binary>.
  - `<name>_tarball`  — `bazel run //…:<name>_tarball` loads it into the local
                         docker / podman daemon.
  - `<name>_push`     — `bazel run :<name>_push -- --tag <sha>` pushes to
                         `<repository>:<sha>` (only when `repository` is set).
"""

load("@rules_oci//oci:defs.bzl", "oci_image", "oci_load", "oci_push")
load("@rules_pkg//pkg:tar.bzl", "pkg_tar")

def rust_service_image(
        name,
        binary,
        repository = None,
        exposed_ports = None,
        env = None,
        user = None,
        args = None,
        base = None,
        visibility = None):
    """Bundle a rust_binary + its runfiles into a runnable OCI image.

    Args:
      name: target name for the image.
      binary: label of a rust_binary. Its runfiles ride along so `data = [...]`
        deps (static dirs, .binpb panel bundles, embedded protos) work inside the
        container the same as under `bazel run` locally.
      repository: optional ghcr-style repo path. Stored as the OCI annotation
        `org.opencontainers.image.ref.name`, used as the default `oci_load` tag,
        and (when set) enables the `<name>_push` target.
      exposed_ports: list of `"<port>/<proto>"` strings to record on the image.
      env: dict of env vars to bake in (e.g. `{"RUST_LOG": "info"}`).
      user: uid to run as. Defaults to None (root).
      args: extra args to pass to the binary after the entrypoint.
      base: oci_image base. Defaults to this module's `//oci:base_image`
        (distroless/cc); `Label()` pins it to rules_fastverk_plugin regardless of
        the calling repo.
      visibility: bazel visibility for the produced targets.
    """

    exposed_ports = exposed_ports or []
    env = dict(env or {})

    # Layer: binary + runfiles rooted at /app.
    pkg_tar(
        name = name + "_layer",
        srcs = [binary],
        include_runfiles = True,
        package_dir = "/app",
        visibility = ["//visibility:private"],
    )

    # Resolve the binary's filename inside /app. rust_binary names match the file
    # name on disk (`:foo` and `//path:foo` both give `foo`).
    binary_name = binary.rsplit(":", 1)[-1] if ":" in binary else binary.rsplit("/", 1)[-1]

    annotations = {}
    if repository:
        annotations["org.opencontainers.image.ref.name"] = repository

    oci_image(
        name = name,
        base = base or Label("//oci:base_image"),
        entrypoint = ["/app/" + binary_name],
        cmd = args,
        env = env,
        exposed_ports = exposed_ports,
        tars = [name + "_layer"],
        user = str(user) if user != None else None,
        workdir = "/app",
        annotations = annotations,
        visibility = visibility,
    )

    oci_load(
        name = name + "_tarball",
        image = ":" + name,
        repo_tags = [(repository or name) + ":latest"],
        visibility = visibility,
    )

    # Direct registry push — `bazel run :<name>_push -- --tag <sha>` pushes to
    # `<repository>:<sha>`. Used by the CI deploy job so no docker daemon is needed.
    if repository:
        oci_push(
            name = name + "_push",
            image = ":" + name,
            repository = repository,
            visibility = visibility,
        )
