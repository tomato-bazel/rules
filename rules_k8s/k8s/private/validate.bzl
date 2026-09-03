"""k8s_validate — check a bundle against the CRD schemas it should satisfy."""

load("//crd:providers.bzl", "K8sCrdInfo", "K8sTransitiveSchemasInfo")
load("//k8s:providers.bzl", "K8sBundleInfo")
load("//k8s/private:schemas.bzl", "k8s_schemas_aspect")

_KUBECONFORM_TOOLCHAIN = "@rules_k8s//validate:toolchain_type"

def _validate_impl(ctx):
    kc_info = ctx.toolchains[_KUBECONFORM_TOOLCHAIN].kubeconform_info
    kubeconform = kc_info.kubeconform
    bundle = ctx.attr.bundle[K8sBundleInfo]

    # Resolve schemas without making the caller list them. The aspect reaches
    # K8sCrdInfo through the bundle's deps — including through targets that don't
    # speak k8s (a filegroup, a genrule), which is the part plain
    # provider-threading can't do.
    schema_sets = []
    if K8sTransitiveSchemasInfo in ctx.attr.bundle:
        schema_sets.append(ctx.attr.bundle[K8sTransitiveSchemasInfo].schemas)
    direct = []
    for dep in ctx.attr.schemas:
        if K8sTransitiveSchemasInfo in dep:
            schema_sets.append(dep[K8sTransitiveSchemasInfo].schemas)
        elif K8sCrdInfo in dep:
            direct.append(dep[K8sCrdInfo])
    crds = depset(direct, transitive = schema_sets).to_list()

    crd_dirs = [c.crds for c in crds]

    # kubeconform wants JSON Schema; a CRD carries its schema nested inside a
    # Kubernetes object. Lift them out into the layout -schema-location expects.
    schema_dir = ctx.actions.declare_directory(ctx.label.name + ".schemas")
    conv_args = ctx.actions.args()
    conv_args.add("-out", schema_dir.path)
    # Strictness must be baked into the SCHEMA — kubeconform's -strict flag does
    # not itself forbid unknown fields (upstream ships a separate strict schema
    # set for that; hence its {{.StrictSuffix}} template var). Passing -strict
    # without this was a silent no-op.
    if ctx.attr.strict:
        conv_args.add("-strict")
    conv_args.add_all(crd_dirs)
    ctx.actions.run(
        executable = ctx.executable._crd2jsonschema,
        arguments = [conv_args],
        inputs = crd_dirs,
        outputs = [schema_dir],
        mnemonic = "K8sCrdSchemas",
        progress_message = "Extracting CRD schemas for %{label}",
    )

    # A test rather than a build action: this is a check, and a failing check
    # should read as a failing test rather than a broken build.
    runner = ctx.actions.declare_file(ctx.label.name + ".sh")
    strict = "-strict" if ctx.attr.strict else ""

    # Core Kubernetes kinds (Deployment, ConfigMap, ...) have no CRD, so their
    # schemas can only come from a vendored upstream set. Opt-in and hermetic:
    # a label, not a URL.
    core = ""
    core_files = []
    if ctx.attr.core_schemas:
        core_files = ctx.files.core_schemas
        core = "-schema-location '{}/{{{{.NormalizedKubernetesVersion}}}}-standalone{{{{.StrictSuffix}}}}/{{{{.ResourceKind}}}}{{{{.KindSuffix}}}}.json'".format(
            core_files[0].short_path,
        )
    ctx.actions.write(
        output = runner,
        is_executable = True,
        content = """#!/usr/bin/env bash
set -uo pipefail

# NO `-schema-location default`. kubeconform's "default" location is a raw
# GitHub URL — it would make every validate a NETWORK fetch, which is not a
# thing a build may depend on (and would fail outright on RBE). Only schemas
# produced in this build, plus any the caller vendored, are used.
"{kubeconform}" \\
  -schema-location '{schemas}/{{{{.Group}}}}/{{{{.ResourceKind}}}}_{{{{.ResourceAPIVersion}}}}.json' \\
  {core} \\
  -summary {strict} {skip} \\
  "{bundle}"
rc=$?
if [ $rc -ne 0 ]; then
  echo "" >&2
  echo "k8s_validate: {label} failed." >&2
  echo "NOTE: this checks STRUCTURE only. x-kubernetes-validations (CEL) rules are" >&2
  echo "not evaluated here — nothing can evaluate them at build time." >&2
fi
exit $rc
""".format(
            kubeconform = kubeconform.executable.short_path,
            schemas = schema_dir.short_path,
            bundle = bundle.dir.short_path,
            strict = strict,
            core = core,
            skip = " ".join(["-skip " + k for k in ctx.attr.skip_kinds]) if ctx.attr.skip_kinds else "",
            label = str(ctx.label),
        ),
    )

    return [DefaultInfo(
        executable = runner,
        # The executable must be listed explicitly: the default toolchain's
        # kubeconform is a plain file from a release archive (exports_files), so
        # its default_runfiles is empty. Merging default_runfiles as well keeps a
        # toolchain whose kubeconform IS a real binary target working too.
        runfiles = ctx.runfiles(
            files = [schema_dir, bundle.dir, kubeconform.executable] + core_files,
        ).merge(kc_info.default_runfiles),
    )]

# Bazel requires a test RULE CLASS to be named `*_test` (target names are free).
# The public name is `k8s_validate` because that reads better at the call site, so
# the class is private and a macro fronts it.
_k8s_validate_test = rule(
    implementation = _validate_impl,
    test = True,
    doc = """Validate a `k8s_bundle` against the CRD schemas it should satisfy.

Exists because CRD schemas are a public API surface that usually has no gate at
all. It is common to see gRPC/proto contracts held to a build-time check while the
CRD schemas beside them have none.

Schemas resolve automatically through the bundle's `deps` (see the `_k8s_schemas`
aspect); `schemas` is for the cases that don't.

    k8s_bundle(name = "apps", srcs = glob(["argocd/apps/*.yaml"]))
    k8s_validate(name = "apps_valid", bundle = ":apps")

WHAT GREEN MEANS. Structurally valid, and nothing more.

  - `x-kubernetes-validations` (CEL rules like `self == oldSelf`) are NOT
    evaluated. They can reference an object's prior state, which doesn't exist at
    build time, so no build-time tool can check them.
  - Nor is any POLICY checked. A field can be perfectly well-typed and still
    wrong — an ArgoCD Application pinned to an unmerged branch is a valid string.
    That needs a policy engine, which rules_k8s deliberately does not ship.
  - Only CRD kinds are covered unless you pass `core_schemas`. Core Kubernetes
    kinds have no CRD to derive a schema from.

Don't read a pass as "the API server will accept this".
""",
    attrs = {
        "bundle": attr.label(
            mandatory = True,
            providers = [K8sBundleInfo],
            aspects = [k8s_schemas_aspect],
            doc = "The `k8s_bundle` to validate.",
        ),
        "schemas": attr.label_list(
            aspects = [k8s_schemas_aspect],
            doc = "Extra `k8s_crd_library` targets whose schemas the bundle needs but doesn't depend on.",
        ),
        "strict": attr.bool(
            default = False,
            doc = "Reject fields the schema doesn't declare, by sealing every object node with `additionalProperties: false` (subtrees marked `x-kubernetes-preserve-unknown-fields` are left open — they are meant to accept arbitrary keys). Worth turning on: the API server PRUNES undeclared fields rather than rejecting them, so a typo'd field is silently dropped and the object admitted having lost its meaning. Off by default only because it can reject manifests that a lax older schema accepted.",
        ),
        "skip_kinds": attr.string_list(
            doc = "Kinds to skip. Use for an object whose schema genuinely isn't available — a third-party CRD you don't vendor. Prefer vendoring: a skipped Kind is unvalidated, silently.",
        ),
        "core_schemas": attr.label(
            allow_files = True,
            doc = "A vendored upstream Kubernetes JSON-Schema tree (e.g. yannh/kubernetes-json-schema), for validating CORE kinds. Omit and a bundle containing a Deployment will fail with \"could not find schema\" — deliberately, because the alternative is fetching schemas over the network at build time.",
        ),
        "_crd2jsonschema": attr.label(
            default = Label("//validate/private/crd2jsonschema"),
            executable = True,
            cfg = "exec",
        ),
    },
    toolchains = [_KUBECONFORM_TOOLCHAIN],
)

def k8s_validate(name, **kwargs):
    """Validate a `k8s_bundle` against its CRD schemas. See `_k8s_validate_test`.

    A macro only because Bazel requires test rule classes to end in `_test`.
    """
    _k8s_validate_test(name = name, **kwargs)
