"""`helm_push` — publish a packaged chart `.tgz` to an OCI Helm repo (`bazel run`)."""

# Bazel Bash runfiles library v3 preamble (resolves $(rlocation ...) at runtime).
_RUNFILES_PREAMBLE = """\
# --- begin runfiles.bash initialization v3 ---
set -uo pipefail; set +e; f=bazel_tools/tools/bash/runfiles/runfiles.bash
source "${RUNFILES_DIR:-/dev/null}/$f" 2>/dev/null || \\
  source "$(grep -sm1 "^$f " "${RUNFILES_MANIFEST_FILE:-/dev/null}" | cut -f2- -d' ')" 2>/dev/null || \\
  source "$0.runfiles/$f" 2>/dev/null || \\
  source "$(grep -sm1 "^$f " "$0.runfiles_manifest" | cut -f2- -d' ')" 2>/dev/null || \\
  source "$(grep -sm1 "^$f " "$0.exe.runfiles_manifest" | cut -f2- -d' ')" 2>/dev/null || \\
  { echo>&2 "ERROR: cannot find runfiles.bash"; exit 1; }; f=; set -e
# --- end runfiles.bash initialization v3 ---
"""

def _helm_push_impl(ctx):
    launcher = ctx.actions.declare_file(ctx.label.name + ".sh")

    helm_rloc = ctx.expand_location("$(rlocationpath //helm:helm_bin)", targets = [ctx.attr._helm])
    tgz_rloc = ctx.expand_location("$(rlocationpath %s)" % ctx.attr.chart.label, targets = [ctx.attr.chart])

    script = _RUNFILES_PREAMBLE + """\
HELM="$(rlocation {helm})"
TGZ="$(rlocation {tgz})"
echo "helm push $TGZ -> oci://{repo}" >&2
exec "$HELM" push "$TGZ" "oci://{repo}" "$@"
""".format(helm = helm_rloc, tgz = tgz_rloc, repo = ctx.attr.repository)

    ctx.actions.write(launcher, script, is_executable = True)

    runfiles = ctx.runfiles(files = [ctx.file._helm] + ctx.files.chart)
    runfiles = runfiles.merge(ctx.attr._runfiles_lib[DefaultInfo].default_runfiles)
    return [DefaultInfo(executable = launcher, runfiles = runfiles)]

helm_push = rule(
    implementation = _helm_push_impl,
    executable = True,
    doc = """`helm push` a packaged chart to an OCI Helm repo (`oci://<repository>`).

`bazel run //chart:push` publishes the `.tgz`. Authenticate first with
`helm registry login` (CI uses the GITHUB_TOKEN, same as the rules_oci images).
Extra `bazel run ... -- <args>` are forwarded to `helm push`.
""",
    attrs = {
        "chart": attr.label(
            allow_single_file = [".tgz"],
            mandatory = True,
            doc = "A helm_chart target (the packaged .tgz).",
        ),
        "repository": attr.string(
            mandatory = True,
            doc = "OCI repo without the scheme, e.g. ghcr.io/fastverk/charts.",
        ),
        "_helm": attr.label(
            default = "//helm:helm_bin",
            allow_single_file = True,
        ),
        "_runfiles_lib": attr.label(
            default = "@bazel_tools//tools/bash/runfiles",
        ),
    },
)
