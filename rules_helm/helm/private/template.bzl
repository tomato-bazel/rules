"""`helm_template` — render a chart to plain manifests, as a build action."""

def _helm_template_impl(ctx):
    helm = ctx.file._helm
    chart = ctx.file.chart
    out = ctx.actions.declare_file(ctx.label.name + ".yaml")

    args = []
    for v in ctx.files.values:
        args.append('--values "%s"' % v.path)
    for k, v in ctx.attr.set.items():
        # --set-string, not --set: `--set` applies YAML type inference, so an image
        # tag like `1.34` becomes a float and renders as `1.34`, and a value like
        # `true` becomes a bool. For a rendered manifest the string is always what
        # was meant; a caller wanting a typed value should put it in a values file.
        args.append('--set-string "%s=%s"' % (k, v))
    if ctx.attr.include_crds:
        args.append("--include-crds")
    if ctx.attr.kube_version:
        args.append('--kube-version "%s"' % ctx.attr.kube_version)
    for a in ctx.attr.api_versions:
        args.append('--api-versions "%s"' % a)

    # helm insists on writable HOME/cache dirs even for an offline `template`; point
    # them inside the sandbox. Mirrors helm_chart.
    command = """\
set -euo pipefail
export HOME="$PWD/.helmhome"
export HELM_CACHE_HOME="$HOME/cache" HELM_CONFIG_HOME="$HOME/config" HELM_DATA_HOME="$HOME/data"
mkdir -p "$HELM_CACHE_HOME" "$HELM_CONFIG_HOME" "$HELM_DATA_HOME"
{helm} template {release} {chart} --namespace {ns} {args} > {out}
""".format(
        helm = helm.path,
        release = ctx.attr.release_name or ctx.label.name,
        chart = chart.path,
        ns = ctx.attr.namespace,
        args = " ".join(args),
        out = out.path,
    )

    ctx.actions.run_shell(
        inputs = [chart] + ctx.files.values,
        outputs = [out],
        tools = [helm],
        command = command,
        mnemonic = "HelmTemplate",
        progress_message = "Rendering Helm chart %s" % ctx.label,
    )
    return [DefaultInfo(files = depset([out]))]

helm_template = rule(
    implementation = _helm_template_impl,
    doc = """Render a packaged chart to a single manifest file, offline and hermetically.

```python
helm_template(
    name = "argocd_manifests",
    chart = "@argo_cd_chart//file",      # an http_file-pinned .tgz
    release_name = "argocd",
    namespace = "argocd",
    values = ["values.yaml"],
)
```

⭐ WHY THIS EXISTS ALONGSIDE `helm_chart`. `helm_chart` packages a chart WE author;
this renders a chart SOMEONE ELSE published into manifests we can read, review,
diff and gate. Those are opposite directions and the second is what a consumer of
a third-party chart actually needs.

The point is that the output becomes an artifact rather than an event. `helm
install` renders and applies in one motion, so what actually reached the cluster
is knowable only afterwards, by asking the cluster. Rendering to a file makes it
reviewable BEFORE anything moves, byte-stable across rebuilds, and diffable
against the live cluster with `k8s_diff`.

⛔ FULLY OFFLINE, WHICH CONSTRAINS `chart`. The action runs in a sandbox with no
network, so `chart` must be a self-contained `.tgz` — a chart with unvendored
subchart dependencies fails here rather than silently fetching them. Pin it with
`http_file` + sha256 so the rendered output is a pure function of committed
inputs; a chart pinned only by version is a moving target and the render will
change under you when upstream republishes.

⚠ `set` uses `--set-string`. Plain `--set` applies YAML type inference, so `1.34`
becomes a float and `true` becomes a bool. For a value that must keep its type,
use a values file.
""",
    attrs = {
        "chart": attr.label(
            allow_single_file = [".tgz"],
            mandatory = True,
            doc = "The packaged chart. Must vendor any subcharts — the action has no network.",
        ),
        "values": attr.label_list(
            allow_files = [".yaml", ".yml"],
            doc = "Values files, applied in order (helm --values). Later files win.",
        ),
        "set": attr.string_dict(
            doc = "Individual overrides, passed as --set-string. Prefer a values file.",
        ),
        "release_name": attr.string(
            doc = "Helm release name. Defaults to the target name. Appears in rendered labels, so changing it churns the output.",
        ),
        "namespace": attr.string(
            default = "default",
            doc = "Namespace passed to helm (--namespace). Templates read this via .Release.Namespace.",
        ),
        "include_crds": attr.bool(
            default = False,
            doc = "Emit the chart's crds/ directory too (helm --include-crds). Off by default, matching helm.",
        ),
        "kube_version": attr.string(
            doc = "Capabilities.KubeVersion for templates that branch on it (helm --kube-version). Set it when the chart gates on API availability, or the render depends on helm's built-in default.",
        ),
        "api_versions": attr.string_list(
            doc = "Extra Capabilities.APIVersions entries (helm --api-versions).",
        ),
        "_helm": attr.label(
            default = "//helm:helm_bin",
            allow_single_file = True,
            cfg = "exec",
        ),
    },
)
