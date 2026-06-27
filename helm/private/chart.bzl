"""`helm_chart` — package a chart directory into a versioned `.tgz` (build action)."""

def _helm_chart_impl(ctx):
    chart_yaml = ctx.file.chart_yaml
    chart_dir = chart_yaml.dirname
    helm = ctx.file._helm
    out = ctx.actions.declare_file(ctx.label.name + ".tgz")

    ver_flag = ('--version "%s"' % ctx.attr.version) if ctx.attr.version else ""
    app_flag = ('--app-version "%s"' % ctx.attr.app_version) if ctx.attr.app_version else ""

    # helm wants writable HOME/cache dirs even for offline `package`; point them
    # at a scratch dir inside the sandbox. `package` of a leaf chart is fully
    # offline (charts with subchart deps must vendor charts/ first).
    command = """\
set -euo pipefail
export HOME="$PWD/.helmhome"
export HELM_CACHE_HOME="$HOME/cache" HELM_CONFIG_HOME="$HOME/config" HELM_DATA_HOME="$HOME/data"
mkdir -p "$HELM_CACHE_HOME" "$HELM_CONFIG_HOME" "$HELM_DATA_HOME"
DEST="$(mktemp -d)"
{helm} package {chart_dir} --destination "$DEST" {ver} {app} >/dev/null
cp "$DEST"/*.tgz {out}
""".format(
        helm = helm.path,
        chart_dir = chart_dir,
        ver = ver_flag,
        app = app_flag,
        out = out.path,
    )

    ctx.actions.run_shell(
        inputs = [chart_yaml] + ctx.files.srcs,
        outputs = [out],
        tools = [helm],
        command = command,
        mnemonic = "HelmPackage",
        progress_message = "Packaging Helm chart %s" % ctx.label,
    )
    return [DefaultInfo(files = depset([out]))]

helm_chart = rule(
    implementation = _helm_chart_impl,
    doc = """Package a Helm chart directory into a versioned `.tgz`.

The output is `<name>.tgz`. `srcs` must list every file helm should package
(values.yaml, templates/**, .helmignore, ...) since the action runs in a sandbox
that contains only the declared inputs. Leaf charts only — a chart with subchart
dependencies must have its `charts/` vendored and passed in `srcs`.
""",
    attrs = {
        "chart_yaml": attr.label(
            allow_single_file = ["Chart.yaml"],
            mandatory = True,
            doc = "The chart's Chart.yaml; its directory is the chart root.",
        ),
        "srcs": attr.label_list(
            allow_files = True,
            doc = "All other chart files (values.yaml, templates/**, .helmignore).",
        ),
        "version": attr.string(
            doc = "Chart SemVer (helm --version). Defaults to Chart.yaml's value.",
        ),
        "app_version": attr.string(
            doc = "App version (helm --app-version). Defaults to Chart.yaml's value.",
        ),
        "_helm": attr.label(
            default = "//helm:helm_bin",
            allow_single_file = True,
            cfg = "exec",
        ),
    },
)
