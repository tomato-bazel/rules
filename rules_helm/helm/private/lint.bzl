"""`helm_lint` — validate a chart with `helm lint` (build action; fails the build)."""

def _helm_lint_impl(ctx):
    chart_yaml = ctx.file.chart_yaml
    chart_dir = chart_yaml.dirname
    helm = ctx.file._helm
    marker = ctx.actions.declare_file(ctx.label.name + ".lint.ok")

    command = """\
set -euo pipefail
export HOME="$PWD/.helmhome"
export HELM_CACHE_HOME="$HOME/cache" HELM_CONFIG_HOME="$HOME/config" HELM_DATA_HOME="$HOME/data"
mkdir -p "$HELM_CACHE_HOME" "$HELM_CONFIG_HOME" "$HELM_DATA_HOME"
{helm} lint {chart_dir} {strict}
touch {marker}
""".format(
        helm = helm.path,
        chart_dir = chart_dir,
        strict = "--strict" if ctx.attr.strict else "",
        marker = marker.path,
    )

    ctx.actions.run_shell(
        inputs = [chart_yaml] + ctx.files.srcs,
        outputs = [marker],
        tools = [helm],
        command = command,
        mnemonic = "HelmLint",
        progress_message = "Linting Helm chart %s" % ctx.label,
    )
    return [DefaultInfo(files = depset([marker]))]

helm_lint = rule(
    implementation = _helm_lint_impl,
    doc = """`helm lint` a chart as a build action.

`bazel build //chart:lint` fails if the chart doesn't lint; the (empty) marker
output makes it cacheable. Wire it into CI alongside the package step.
""",
    attrs = {
        "chart_yaml": attr.label(
            allow_single_file = ["Chart.yaml"],
            mandatory = True,
        ),
        "srcs": attr.label_list(allow_files = True),
        "strict": attr.bool(
            default = True,
            doc = "Pass --strict (warnings fail the lint).",
        ),
        "_helm": attr.label(
            default = "//helm:helm_bin",
            allow_single_file = True,
            cfg = "exec",
        ),
    },
)
