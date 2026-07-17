"""k8s_crd_library — CRD YAML as a real, cached, sandboxed Bazel action."""

load("@rules_go//go/tools/gopackagesdriver:aspect.bzl", "GoPkgInfo", "go_pkg_info_aspect")
load("//crd:providers.bzl", "K8sCrdInfo")

_TOOLCHAIN = "@rules_k8s//crd:toolchain_type"

def _crd_library_impl(ctx):
    crd_info = ctx.toolchains[_TOOLCHAIN].crd_info

    # The aspect has already produced the package graph as declared outputs: one
    # pkg.json per package, the compiled sources, and the stdlib's index. This is
    # the whole trick — we hand controller-tools a graph Bazel computed, instead
    # of letting it shell out to `go list` to rediscover one.
    pkg_json_files = []
    compiled_go_files = []
    stdlib_json = None
    stdlib_cache = None
    for dep in ctx.attr.deps:
        info = dep[GoPkgInfo]
        pkg_json_files.append(info.pkg_json_files)
        compiled_go_files.append(info.compiled_go_files)
        if stdlib_json == None:
            stdlib_json = info.stdlib_json_file
            stdlib_cache = info.stdlib_cache_dir

    if stdlib_json == None:
        fail("k8s_crd_library: no Go stdlib metadata reached {}. `deps` must name rules_go ".format(ctx.label) +
             "targets (go_library); the aspect found none.")

    # The stdlib is NOT optional, in two parts:
    #
    #  - its pkg.json, because the aspect's per-package Imports map only covers
    #    `archive.direct`, so stdlib edges are absent from it. Without this the
    #    driver can't resolve `import "time"` and controller-tools silently drops
    #    every field whose type it failed to follow;
    #  - its gocache TreeArtifact, because that pkg.json POINTS AT stdlib sources.
    #    Feed the index without the files it names and the driver dies resolving
    #    imports (it opens each CompiledGoFile to parse the package clause).
    all_pkg_jsons = depset([stdlib_json], transitive = pkg_json_files)
    srcs = depset(transitive = compiled_go_files + ([stdlib_cache] if stdlib_cache else []))

    params = ctx.actions.declare_file(ctx.label.name + ".pkg_json.params")
    args = ctx.actions.args()
    args.add_all(all_pkg_jsons)
    args.set_param_file_format("multiline")
    ctx.actions.write(params, args)

    out_dir = ctx.actions.declare_directory(ctx.label.name)
    listing = ctx.actions.declare_file(ctx.label.name + ".listing")

    gen_args = ctx.actions.args()
    gen_args.add("-out", out_dir.path)
    gen_args.add("-listing", listing.path)
    if ctx.attr.group:
        gen_args.add("-expect-group", ctx.attr.group)

    # The patterns. `str(label)` is the canonical form (`@@//api/v1:v1`), which is
    # exactly what the aspect writes as each pkg.json's ID — they must agree or
    # the driver matches no roots.
    for dep in ctx.attr.deps:
        gen_args.add(str(dep.label))

    ctx.actions.run(
        executable = crd_info.gen,
        arguments = [gen_args],
        inputs = depset([params], transitive = [all_pkg_jsons, srcs]),
        outputs = [out_dir, listing],
        tools = [crd_info.driver],
        env = {
            # This is the load-bearing line: it diverts go/packages off `go list`
            # and onto our manifest-fed driver. Without it controller-tools dies
            # with "go command required, not found" in the sandbox.
            "GOPACKAGESDRIVER": crd_info.driver.executable.path,
            "K8S_CRD_DRIVER_PKG_JSON": params.path,
            # Belt and braces: if GOPACKAGESDRIVER ever failed to take effect, we
            # want a hard failure rather than a silent fallback that works only on
            # a machine that happens to have Go and a warm module cache.
            "GOPATH": "/nonexistent",
            "GOMODCACHE": "/nonexistent",
            "GOPROXY": "off",
            "GOFLAGS": "-mod=mod",
        },
        mnemonic = "K8sCrdGen",
        progress_message = "Generating %s CRDs for %%{label}" % (ctx.attr.group or "all"),
        # Deliberately cacheable + remotable: that is the entire point of doing
        # this as an action rather than the `bazel run` + committed-output dance
        # operators commonly do today.
        execution_requirements = {},
    )

    outs = [out_dir]
    for pp in ctx.attr.post_processors:
        outs = [_run_post_processor(ctx, pp, outs[0])]

    return [
        DefaultInfo(files = depset(outs)),
        K8sCrdInfo(crds = outs[0], group = ctx.attr.group),
        # `listing` rides in an output group, not the default outputs, so a
        # write_source_files over this target copies only CRD YAML. Golden-test it
        # with filegroup(output_group = "listing").
        OutputGroupInfo(listing = depset([listing])),
    ]

def _run_post_processor(ctx, pp, in_dir):
    """Run one post-processor over the CRD directory, dir-in/dir-out.

    This seam is not speculative. A real consumer splices a schema generated
    elsewhere (from TypeScript types) over controller-gen's
    `x-kubernetes-preserve-unknown-fields` block, because the Go field is a
    runtime.RawExtension and controller-gen can only render it as opaque. Without
    a hook here, that consumer cannot adopt this rule at all.
    """
    out = ctx.actions.declare_directory("{}.{}".format(ctx.label.name, pp.label.name))
    args = ctx.actions.args()
    args.add("-in", in_dir.path)
    args.add("-out", out.path)
    ctx.actions.run(
        executable = pp[DefaultInfo].files_to_run,
        arguments = [args],
        inputs = [in_dir],
        outputs = [out],
        mnemonic = "K8sCrdPostProcess",
        progress_message = "Post-processing CRDs with %s for %%{label}" % pp.label.name,
    )
    return out

k8s_crd_library = rule(
    implementation = _crd_library_impl,
    doc = """Generate CRD YAML from kubebuilder markers, as a cached Bazel action.

Unlike the usual controller-gen invocation, this runs sandboxed:
no host Go, no `go list`, no module cache, no network, no `bazel query`. It works
because rules_go's `go_pkg_info_aspect` already emits the package graph as
declared outputs, and controller-tools only asks go/packages for metadata (it
type-checks itself). A small driver serves that frozen graph over
GOPACKAGESDRIVER.

The output is a directory, so pair it with `write_source_files` to keep committed
copies (`config/crd`, a chart's `crds/`) in lockstep — a whole-directory sync
catches a stale file, a never-copied new CRD, and an orphan left behind, which a
per-file diff_test cannot.

    k8s_crd_library(
        name = "crds",
        deps = ["//api/v1:v1"],
        group = "platform.example.com",
    )

    write_source_files(
        name = "update",
        files = {
            "//operator/config/crd": ":crds",
            "//helm/my-operator/crds": ":crds",
        },
    )
""",
    attrs = {
        "deps": attr.label_list(
            mandatory = True,
            providers = [GoPkgInfo],
            aspects = [go_pkg_info_aspect],
            doc = "The rules_go `go_library` targets holding the API types (the packages with `+kubebuilder:object:root`).",
        ),
        "group": attr.string(
            doc = "The API group every generated CRD must be in, e.g. 'platform.example.com'. Verified against the output, so it fails the build rather than rotting. Empty skips the check.",
        ),
        # No `executable = True` — attr.label_list doesn't take it (only
        # attr.label does). files_to_run is what we actually use anyway, and it
        # is available on any target with an executable output.
        "post_processors": attr.label_list(
            cfg = "exec",
            doc = "Binaries run in order over the CRD directory, each `-in DIR -out DIR`. For schemas controller-gen can only emit as opaque (a runtime.RawExtension needing a real schema spliced in).",
        ),
    },
    toolchains = [_TOOLCHAIN],
    provides = [K8sCrdInfo],
)
