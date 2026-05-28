"""`hf_inference_endpoint` — control-plane runners over the typed CLI.

The HF Inference Endpoints REST API is a clean OpenAPI surface, so
unlike the data-plane rules (which shell to the hermetic `hf` binary
for the bespoke LFS/Xet protocol) the control plane goes through a
typed Rust client codegen'd by rules_openapi and wrapped by the
`//huggingface/endpoints:hf-endpoints` CLI. Deploy is config-file
driven — the JSON body is deserialized into the generated
`types::Endpoint`, so a malformed config fails with a serde error
rather than a silent API 400.
"""

def _rlocationpath(file, ctx):
    sp = file.short_path
    if sp.startswith("../"):
        return sp[3:]
    return ctx.workspace_name + "/" + sp

def _shquote(s):
    return "'" + s.replace("'", "'\\''") + "'"

def _hf_endpoint_op_impl(ctx):
    cli_default = ctx.attr._cli[DefaultInfo]
    cli_exec = cli_default.files_to_run.executable
    launcher = ctx.actions.declare_file(ctx.label.name + "_launcher.sh")

    args = [ctx.attr.verb]
    if ctx.attr.namespace:
        args += ["--namespace", ctx.attr.namespace]
    if ctx.attr.endpoint_name:
        args += ["--name", ctx.attr.endpoint_name]

    config_line = ""
    extra_files = []
    if ctx.file.config:
        config_line = 'CONFIG="$(rlocation %s)"\n' % _shquote(
            _rlocationpath(ctx.file.config, ctx),
        ) + 'if [[ -z "${CONFIG:-}" || ! -f "$CONFIG" ]]; then echo "fatal: endpoint config not found in runfiles" >&2; exit 3; fi'
        args += ["--config", '"$CONFIG"']
        extra_files.append(ctx.file.config)

    ctx.actions.expand_template(
        template = ctx.file._tpl,
        output = launcher,
        is_executable = True,
        substitutions = {
            "%%CLI_RLOCATION%%": _rlocationpath(cli_exec, ctx),
            "%%CONFIG_LINE%%": config_line,
            # `--config "$CONFIG"` is the one arg that references a shell
            # var; the rest are shell-quoted literals.
            "%%ARGS%%": " ".join([
                a if a == '"$CONFIG"' else _shquote(a)
                for a in args
            ]),
        },
    )

    runfiles = ctx.runfiles(files = [cli_exec] + extra_files)
    runfiles = runfiles.merge(cli_default.default_runfiles)
    runfiles = runfiles.merge(
        ctx.attr._runfiles_lib[DefaultInfo].default_runfiles,
    )
    return [DefaultInfo(executable = launcher, runfiles = runfiles)]

_hf_endpoint_op = rule(
    implementation = _hf_endpoint_op_impl,
    executable = True,
    attrs = {
        "verb": attr.string(mandatory = True),
        "namespace": attr.string(),
        "endpoint_name": attr.string(),
        "config": attr.label(allow_single_file = [".json"]),
        "_cli": attr.label(
            default = Label("//huggingface/endpoints:hf-endpoints"),
            executable = True,
            cfg = "target",
        ),
        "_tpl": attr.label(
            default = Label("//huggingface/private:hf_endpoints_runner.sh.tpl"),
            allow_single_file = True,
        ),
        "_runfiles_lib": attr.label(
            default = Label("@bazel_tools//tools/bash/runfiles"),
        ),
    },
)

# verb → (runner-suffix, needs an endpoint --name, needs --config)
_LIFECYCLE = [
    ("pause", "pause", True, False),
    ("resume", "resume", True, False),
    ("scale_to_zero", "scale-to-zero", True, False),
    ("delete", "delete", True, False),
    ("describe", "describe", True, False),
    ("list", "list", False, False),
]

def hf_inference_endpoint(
        name,
        config,
        endpoint_name = None,
        namespace = None,
        visibility = None):
    """Typed HF Inference Endpoints control plane.

    Emits `bazel run`-able runners (cluster verb-suffix convention):

      * `<name>.deploy`        — create the endpoint from `config`
      * `<name>.pause`         — pause it
      * `<name>.resume`        — resume it
      * `<name>.scale_to_zero` — scale to zero replicas
      * `<name>.delete`        — delete it
      * `<name>.describe`      — print its state
      * `<name>.list`          — list endpoints in the namespace

    Args:
      name: target base name.
      config: label of a JSON `Endpoint` body (deserialized + validated
        against the generated `types::Endpoint` at deploy time).
      endpoint_name: the endpoint's name for lifecycle verbs. Defaults
        to `name`. (Deploy reads the name from the config body.)
      namespace: HF namespace (user/org). If unset, the runner falls
        back to `HF_NAMESPACE` in the env.
      visibility: forwarded to every emitted runner.
    """
    endpoint_name = endpoint_name or name
    ns = namespace or ""

    _hf_endpoint_op(
        name = name + ".deploy",
        verb = "deploy",
        namespace = ns,
        config = config,
        visibility = visibility,
    )
    for suffix, verb, needs_name, _ in _LIFECYCLE:
        _hf_endpoint_op(
            name = name + "." + suffix,
            verb = verb,
            namespace = ns,
            endpoint_name = endpoint_name if needs_name else "",
            visibility = visibility,
        )
