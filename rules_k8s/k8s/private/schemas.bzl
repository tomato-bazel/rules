"""The `_k8s_schemas` aspect: collect CRD schemas across a `deps` graph."""

load("//crd:providers.bzl", "K8sCrdInfo", "K8sTransitiveSchemasInfo")

def _schemas_aspect_impl(target, ctx):
    # Defer to a rule that already threads its own schemas (k8s_bundle does).
    # Returning ours too would be "Provider K8sTransitiveSchemasInfo provided
    # twice" — an aspect and its target cannot both supply one.
    if K8sTransitiveSchemasInfo in target:
        return []

    direct = [target[K8sCrdInfo]] if K8sCrdInfo in target else []
    transitive = []
    for attr in ["deps", "srcs"]:
        for dep in getattr(ctx.rule.attr, attr, []) or []:
            if type(dep) != "Target":
                continue
            if K8sTransitiveSchemasInfo in dep:
                transitive.append(dep[K8sTransitiveSchemasInfo].schemas)
            elif K8sCrdInfo in dep:
                direct.append(dep[K8sCrdInfo])
    return [K8sTransitiveSchemasInfo(schemas = depset(direct, transitive = transitive))]

k8s_schemas_aspect = aspect(
    implementation = _schemas_aspect_impl,
    attr_aspects = ["deps", "srcs"],
    doc = """Collect `K8sCrdInfo` from a target and everything reachable via `deps`/`srcs`.

Exists so `k8s_validate` resolves its own schemas instead of making callers
hand-list every CRD set a bundle might contain:

    k8s_bundle(name = "fleet", deps = ["//op-a:bundle", "//op-b:bundle"])
    k8s_validate(name = "fleet_valid", bundle = ":fleet")   # finds both operators' CRDs

Plain provider-threading would cover that much. What needs an aspect is reaching
THROUGH a target that doesn't speak k8s at all — a `filegroup` or `genrule`
wrapping several `k8s_crd_library` targets. Those return neither of our providers,
so nothing would propagate; an aspect visits them anyway.

`srcs` is walked as well as `deps` because a filegroup carries its contents there.
""",
)
