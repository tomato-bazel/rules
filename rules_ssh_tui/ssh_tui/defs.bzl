"""`ssh_tui_image`: package a russh SSH server + a login binary as one
OCI image. SSH in, get the TUI.

Usage:

```python
load("@rules_ssh_tui//ssh_tui:defs.bzl", "ssh_tui_image")

ssh_tui_image(
    name = "noc-tui",
    login_binary = "//cli:botnoc",
    # File target whose contents are an OpenSSH-format
    # authorized_keys file. Mounted into the container by the
    # compose layer; the server reads it at startup.
    authorized_keys = ":authorized_keys",
    # Args to pass to login_binary after `--`. Typically the
    # in-compose service addresses.
    login_args = [
        "--org-addr", "http://org:50051",
        "--agent-addr", "http://agent:50052",
        "--planning-addr", "http://planning:50053",
    ],
    repository = "ghcr.io/fastverk/noc-tui",
)
```

Emits:
  - `<name>_layer`     — tar with /app/ssh-tui-server + login binary +
                          its runfiles, rooted at /app.
  - `<name>`           — oci_image on distroless_cc. Entrypoint is
                          /app/ssh-tui-server with --login-binary
                          pinned to the bundled login binary.
  - `<name>_tarball`   — `bazel run //…:<name>_tarball` loads it into
                          the local docker/podman daemon.

Bind-mounts the consumer should provide via compose:
  - <some path>/authorized_keys → /var/lib/ssh-tui/authorized_keys
  - <some path>/host_key        → /var/lib/ssh-tui/host_key  (generated
                                   on first start if absent)
"""

load("@rules_oci//oci:defs.bzl", "oci_image", "oci_load", "oci_push")
load("@rules_pkg//pkg:tar.bzl", "pkg_tar")

def ssh_tui_image(
        name,
        login_binary,
        login_args = None,
        listen_port = 22,
        repository = None,
        env = None,
        user = None,
        visibility = None):
    """Compose ssh-tui-server + a login binary into one OCI image.

    Args:
      name: target name.
      login_binary: label of a rust_binary (or any executable) the
        server spawns under a PTY for every authenticated session.
        Its runfiles ride along in the layer.
      login_args: list of strings passed positionally to login_binary
        (after `--` on the server's argv). Useful for pre-baking
        in-compose service addresses.
      listen_port: int port the server binds to. Default 22.
      repository: optional ghcr-style repo path; stored as the OCI
        annotation `org.opencontainers.image.ref.name` so the
        compose-side resolver can produce `<repo>@<digest>`.
      env: dict of extra env vars to bake into the image.
      user: uid to run as. Defaults to None (root), required to
        bind low ports like 22.
      visibility: bazel visibility.
    """

    login_args = login_args or []
    env = dict(env or {})

    # Layer 1: ssh-tui-server binary + runfiles.
    pkg_tar(
        name = name + "_server_layer",
        srcs = ["@rules_ssh_tui//server:ssh-tui-server"],
        include_runfiles = True,
        package_dir = "/app",
        visibility = ["//visibility:private"],
    )

    # Layer 2: the consumer's login binary + its runfiles.
    pkg_tar(
        name = name + "_login_layer",
        srcs = [login_binary],
        include_runfiles = True,
        package_dir = "/app",
        visibility = ["//visibility:private"],
    )

    # Resolve the login_binary label's tail to its filename inside
    # /app. Callers in other packages produce binaries named after
    # their rust_binary's `name` field.
    login_name = login_binary.rsplit(":", 1)[-1] if ":" in login_binary else login_binary.rsplit("/", 1)[-1]

    # The entrypoint runs ssh-tui-server with --login-binary pinned
    # plus any --foo args passed by the caller. Server flags first,
    # then `--` to delimit login args.
    entrypoint = [
        "/app/ssh-tui-server",
        "--listen",
        "0.0.0.0:{}".format(listen_port),
        "--login-binary",
        "/app/" + login_name,
    ]
    if login_args:
        entrypoint = entrypoint + ["--"] + login_args

    annotations = {}
    if repository:
        annotations["org.opencontainers.image.ref.name"] = repository

    oci_image(
        name = name,
        # `@rules_ssh_tui//:base_image` is an alias re-exporting the
        # base image we pulled in MODULE.bazel; consumer BUILDs can't
        # see the underlying `@ssh_tui_distroless_cc` repo directly.
        base = "@rules_ssh_tui//:base_image",
        entrypoint = entrypoint,
        env = env,
        exposed_ports = ["{}/tcp".format(listen_port)],
        tars = [
            name + "_server_layer",
            name + "_login_layer",
        ],
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

    # Direct registry push — `bazel run :<name>_push -- --tag <sha>
    # --repository <registry>/<repo>` pushes without needing a docker
    # daemon (uses crane internally).
    if repository:
        oci_push(
            name = name + "_push",
            image = ":" + name,
            repository = repository,
            visibility = visibility,
        )
