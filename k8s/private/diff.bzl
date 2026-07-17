"""k8s_diff — show what a bundle would change on a live cluster. Read-only."""

load("//k8s:providers.bzl", "K8sBundleInfo")

_KUBECTL_TOOLCHAIN = "@rules_k8s//kubectl:toolchain_type"

def _diff_impl(ctx):
    kc_info = ctx.toolchains[_KUBECTL_TOOLCHAIN].kubectl_info
    kubectl = kc_info.kubectl
    bundle = ctx.attr.bundle[K8sBundleInfo]

    runner = ctx.actions.declare_file(ctx.label.name + ".sh")
    ctx.actions.write(
        output = runner,
        is_executable = True,
        content = """#!/usr/bin/env bash
# READ-ONLY. `kubectl diff` never mutates; it server-side dry-runs and prints.
#
# There is deliberately no k8s_apply beside this. a GitOps controller typically owns apply,
# with self-heal on — an apply from Bazel wouldn't duplicate ArgoCD, it would
# FIGHT it, and lose within a sync interval. (A `bazel run` deploy rule in a
# sibling ruleset already exists and has zero callers.) Diff is the half that's actually useful: it's the documented
# workflow for an app deliberately left un-automated so a human can look before
# anything moves.
set -uo pipefail

exec "{kubectl}" diff -f "{bundle}" "$@"
""".format(
            kubectl = kubectl.executable.short_path,
            bundle = bundle.dir.short_path,
        ),
    )

    return [DefaultInfo(
        executable = runner,
        runfiles = ctx.runfiles(
            files = [bundle.dir, kubectl.executable],
        ).merge(kc_info.default_runfiles),
    )]

k8s_diff = rule(
    implementation = _diff_impl,
    executable = True,
    doc = """`bazel run` to diff a bundle against the live cluster. Read-only.

    bazel run //argocd:apps_diff -- --context=my-cluster

Extra arguments after `--` pass through to `kubectl diff`. Exits non-zero when
there is a difference, which is kubectl's own convention.

Uses whatever kubectl is on your PATH — see //kubectl/toolchains.bzl for why
pinning one would be wrong.
""",
    attrs = {
        "bundle": attr.label(
            mandatory = True,
            providers = [K8sBundleInfo],
            doc = "The `k8s_bundle` to compare against the cluster.",
        ),
    },
    toolchains = [_KUBECTL_TOOLCHAIN],
)
