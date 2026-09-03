"""k8s_object and k8s_bundle — adopt manifests into the build graph."""

load("//crd:providers.bzl", "K8sCrdInfo", "K8sTransitiveSchemasInfo")
load("//k8s:providers.bzl", "K8sBundleInfo", "K8sObjectInfo")
load("//k8s/private:schemas.bzl", "k8s_schemas_aspect")

def _object_impl(ctx):
    files = depset(ctx.files.srcs)
    outs = [DefaultInfo(files = files)]

    # The verify action is optional because most manifests don't need it. When a
    # target DOES declare what it is, disagreeing with the file is a build error —
    # rules_cloudformation's philosophy: typos surface at build time, not at
    # deploy time.
    if ctx.attr.expect_kind or ctx.attr.expect_api_version:
        marker = ctx.actions.declare_file(ctx.label.name + ".verified.ok")
        args = ctx.actions.args()
        args.add("-verify")
        args.add("-marker", marker)
        if ctx.attr.expect_kind:
            args.add("-expect-kind", ctx.attr.expect_kind)
        if ctx.attr.expect_api_version:
            args.add("-expect-api-version", ctx.attr.expect_api_version)
        args.add_all(ctx.files.srcs)
        ctx.actions.run(
            executable = ctx.executable._bundler,
            arguments = [args],
            inputs = ctx.files.srcs,
            outputs = [marker],
            mnemonic = "K8sVerifyObject",
            progress_message = "Verifying %{label}",
        )
        # The marker rides in the default outputs so `bazel build` on this target
        # actually runs the check. An empty declared output is what makes a pure
        # check cacheable (rules_helm's helm_lint does the same).
        outs = [DefaultInfo(files = depset([marker], transitive = [files]))]

    return outs + [K8sObjectInfo(files = files)]

k8s_object = rule(
    implementation = _object_impl,
    doc = """Adopt checked-in Kubernetes manifests into the build graph.

No codegen and no rewriting — it types the graph so `k8s_bundle` and
`k8s_validate` can consume the files, and optionally asserts that a manifest is
what the BUILD file says it is.

Reach for `k8s_bundle(srcs = ...)` directly unless you want the assertion; this
rule earns its place when a manifest's identity is load-bearing elsewhere.

    k8s_object(
        name = "myresource",
        srcs = ["myresource.yaml"],
        expect_kind = "MyResource",
        expect_api_version = "platform.example.com/v1",
    )
""",
    attrs = {
        "srcs": attr.label_list(
            allow_files = [".yaml", ".yml"],
            mandatory = True,
            doc = "Manifest files. Each may hold multiple documents.",
        ),
        "expect_kind": attr.string(
            doc = "If set, every object in `srcs` must be this Kind, or the build fails.",
        ),
        "expect_api_version": attr.string(
            doc = "If set, every object in `srcs` must be this apiVersion, or the build fails.",
        ),
        "_bundler": attr.label(
            default = Label("//k8s/private/bundle"),
            executable = True,
            cfg = "exec",
        ),
    },
    provides = [K8sObjectInfo],
)

def _bundle_impl(ctx):
    direct = list(ctx.files.srcs)
    transitive = []
    for dep in ctx.attr.deps:
        if K8sBundleInfo in dep:
            transitive.append(dep[K8sBundleInfo].files)
        elif K8sObjectInfo in dep:
            transitive.append(dep[K8sObjectInfo].files)
        elif K8sCrdInfo in dep:
            # A k8s_crd_library in `deps` contributes its SCHEMAS, not its
            # manifests: `deps = [":crds"]` means "these CRs are of those kinds",
            # which is the overwhelmingly common intent. Adding the CRD manifests
            # too would silently put a CustomResourceDefinition in the bundle,
            # which then needs an apiextensions schema of its own to validate.
            # To ship the CRDs as manifests, put the target in `srcs`.
            pass
        else:
            transitive.append(dep[DefaultInfo].files)

    files = depset(direct, transitive = transitive)

    out_dir = ctx.actions.declare_directory(ctx.label.name)
    listing = ctx.actions.declare_file(ctx.label.name + ".listing")

    args = ctx.actions.args()
    args.add("-out", out_dir.path)
    args.add("-listing", listing.path)
    args.add_all(files)
    args.use_param_file("@%s", use_always = False)
    args.set_param_file_format("multiline")

    ctx.actions.run(
        executable = ctx.executable._bundler,
        arguments = [args],
        inputs = files,
        outputs = [out_dir, listing],
        mnemonic = "K8sBundle",
        progress_message = "Bundling Kubernetes manifests for %{label}",
    )

    # Thread schemas so k8s_validate can resolve them without a hand-written list.
    schemas = []
    schema_sets = []
    for dep in ctx.attr.deps:
        if K8sTransitiveSchemasInfo in dep:
            schema_sets.append(dep[K8sTransitiveSchemasInfo].schemas)
        elif K8sCrdInfo in dep:
            schemas.append(dep[K8sCrdInfo])

    return [
        DefaultInfo(files = depset([out_dir])),
        K8sBundleInfo(dir = out_dir, files = files),
        K8sTransitiveSchemasInfo(schemas = depset(schemas, transitive = schema_sets)),
        OutputGroupInfo(listing = depset([listing])),
    ]

k8s_bundle = rule(
    implementation = _bundle_impl,
    doc = """Collect Kubernetes manifests into one conflict-checked directory.

Fails the build if two manifests declare the same group/Kind/namespace/name.
That is the whole point over a `filegroup`: applying such a pair keeps whichever
came last, and which that is depends on ordering. Note identity excludes the API
VERSION — `Foo/v1` and `Foo/v1beta1` with the same name are the same object.

Manifests are placed, never rewritten: source bytes are copied verbatim, so key
order and comments survive. A bundle that round-tripped YAML through a marshaller
would silently rewrite the API surface it is supposed to be checking.

`deps` composes bundles without needing an aspect; the `_k8s_schemas` aspect is
there to reach CRD schemas through targets that don't speak k8s.

    k8s_bundle(name = "apps", srcs = glob(["argocd/apps/*.yaml"]))
    k8s_bundle(name = "fleet", deps = [":apps", "//op-a:bundle"])
""",
    attrs = {
        "srcs": attr.label_list(
            allow_files = [".yaml", ".yml"],
            doc = "Manifest files to include directly.",
        ),
        "deps": attr.label_list(
            aspects = [k8s_schemas_aspect],
            doc = "Other bundles, `k8s_object` targets, `k8s_crd_library` targets, or plain file-providing targets.",
        ),
        "_bundler": attr.label(
            default = Label("//k8s/private/bundle"),
            executable = True,
            cfg = "exec",
        ),
    },
    provides = [K8sBundleInfo, K8sTransitiveSchemasInfo],
)
