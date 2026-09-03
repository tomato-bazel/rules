"""fastverk_plugin — one macro for a fastverk console-plugin backend's Bazel targets.

Promoted out of botnoc/tools/plugin so a STANDALONE module can build a plugin with
the macro. Collapses the ~60-90 lines every plugin repeated: an optional
`cargo_build_script` (proto → prost/tonic via the hermetic protoc), the
`rust_library`, the `rust_binary` (carrying its compiled panel bundle as runfiles),
a `rust_test`, a `srcs` filegroup, `exports_files`, and the `rust_service_image`.

The portability contract (why this differs from the botnoc-internal original):
  * NO `load("@crates//:defs.bzl", ...)` — an `@crates` load binds to the DEFINING
    module's crate universe, never the caller's. Instead the CALLER loads
    `all_crate_deps` from its OWN `@crates` and passes the lists in via `deps` /
    `build_deps`.
  * NO hardcoded `//crates/fastverk-plugin-server` / `//crates/fastverk-layout`
    labels — bare labels in a macro resolve in the CALLER's repo (missing there).
    The shared runtime facade (`fastverk-plugin-server`) is instead a cargo dep in
    the caller's Cargo.toml, so it arrives inside `deps` — one crate universe, no
    duplicate tonic/tokio symbols across a module boundary.

Naming is by convention from `name` + optional `crate_prefix`:
  crate  = <prefix_>_<name>       (must match the [lib] name in Cargo.toml)
  binary = <prefix->-<name>-server
  image  = <prefix->-<name>-image   (+ :…-image_push — the release pipeline)
  panels = //services/<name>/ui:panels          (override via `panels`)
"""

load("@rules_rust//cargo:defs.bzl", "cargo_build_script")
load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")
load("//oci:defs.bzl", "rust_service_image")

def fastverk_plugin(
        name,
        deps,
        build_deps = None,
        extra_deps = None,
        crate_prefix = None,
        proto_data = None,
        panels = None,
        exposed_ports = None,
        image_repository = None,
        base_image = None):
    """Emit a fastverk plugin backend's full target set.

    Args:
      name: plugin id (e.g. "spec"). Drives every derived target name.
      deps: the caller's normal crate deps — pass `all_crate_deps(normal = True)`
        loaded from the CALLER's own `@crates`. Must include the plugin's
        `fastverk-plugin-server` cargo dep (the shared HTTP facade).
      build_deps: the caller's build-script crate deps — pass
        `all_crate_deps(build = True)`. Required (non-empty) when `proto_data` is set.
      extra_deps: extra bazel-label deps (proto_library targets, in-repo crates).
      crate_prefix: optional crate/target name prefix. botnoc's shim passes
        "botnoc" (crate `botnoc_<name>`); a standalone plugin omits it (crate
        `<name>`, so it matches a bare `[lib] name = "<name>"`).
      proto_data: list of `.proto` file labels the plugin's `build.rs` compiles.
        Omit/empty for a plugin with no proto (no cargo_build_script emitted).
      panels: the compiled PanelBundle label the binary ships as runfiles.
        Defaults to `//services/<name>/ui:panels`.
      exposed_ports: OCI image ports. Defaults to `["8080/tcp"]` (the HTTP facade).
      image_repository: OCI repo. REQUIRED — there is no botnoc-specific default
        that makes sense off-repo (e.g. "ghcr.io/fastverk/spec-server").
      base_image: OCI base image override. Defaults to this module's distroless/cc.
    """
    if image_repository == None:
        fail("fastverk_plugin: image_repository is required " +
             "(e.g. \"ghcr.io/fastverk/<repo>\") — no botnoc default off-repo.")

    extra_deps = extra_deps if extra_deps != None else []
    build_deps = build_deps if build_deps != None else []
    prefix_u = (crate_prefix + "_") if crate_prefix else ""
    prefix_h = (crate_prefix + "-") if crate_prefix else ""
    crate = prefix_u + name
    binary = prefix_h + name + "-server"
    image = prefix_h + name + "-image"
    panels = panels if panels != None else "//services/{}/ui:panels".format(name)
    exposed_ports = exposed_ports if exposed_ports != None else ["8080/tcp"]

    lib_prefix = []
    exported = ["Cargo.toml"]
    if proto_data:
        cargo_build_script(
            name = "build_script",
            srcs = ["build.rs"],
            data = proto_data,
            edition = "2021",
            build_script_env = {"PROTOC": "$(execpath @protobuf//:protoc)"},
            tools = ["@protobuf//:protoc"],
            deps = build_deps,
        )
        lib_prefix = [":build_script"]
        exported = exported + ["build.rs"]

    rust_library(
        name = crate,
        srcs = native.glob(["src/**/*.rs"]),
        crate_root = "src/lib.rs",
        edition = "2021",
        deps = lib_prefix + extra_deps + deps,
    )

    rust_binary(
        name = binary,
        srcs = ["src/main.rs"],
        edition = "2021",
        data = [panels],
        deps = [":" + crate] + extra_deps + deps,
    )

    rust_test(
        name = crate + "_test",
        crate = ":" + crate,
        edition = "2021",
    )

    native.filegroup(
        name = "srcs",
        srcs = native.glob(["src/**/*.rs"]),
    )

    native.exports_files(exported)

    rust_service_image(
        name = image,
        binary = ":" + binary,
        repository = image_repository,
        exposed_ports = exposed_ports,
        base = base_image,
    )
