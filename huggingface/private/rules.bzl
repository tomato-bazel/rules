"""rules_huggingface private rule implementations.

The data-plane rules (`hf_upload`, `hf_repo`, `hf_download`) resolve a
hermetic `hf` CLI through `//huggingface:toolchain_type` and emit a
`bazel run`-able launcher that drives it against the user's workspace.
`hf_model` is a typed repo reference carrying `HfModelInfo`.
"""

_HF_TOOLCHAIN_TYPE = Label("//huggingface:toolchain_type")

# ── HfModelInfo: typed repo reference ─────────────────────────────

HfModelInfo = provider(
    doc = "A typed reference to a HuggingFace Hub model/dataset repo.",
    fields = {
        "repo": "str — HF repo id (e.g. `Qwen/Qwen2.5-1.5B-Instruct`).",
        "revision": "str — branch / tag / commit sha pin.",
        "repo_type": "str — `model` | `dataset`.",
    },
)

def _hf_model_impl(ctx):
    out = ctx.actions.declare_file(ctx.label.name + ".hfref.json")
    ctx.actions.write(
        output = out,
        content = json.encode({
            "repo": ctx.attr.repo,
            "revision": ctx.attr.revision,
            "repo_type": ctx.attr.repo_type,
        }),
    )
    return [
        HfModelInfo(
            repo = ctx.attr.repo,
            revision = ctx.attr.revision,
            repo_type = ctx.attr.repo_type,
        ),
        DefaultInfo(files = depset([out])),
    ]

hf_model = rule(
    implementation = _hf_model_impl,
    doc = (
        "Declare a typed reference to a HuggingFace Hub model/dataset. " +
        "Carries `HfModelInfo` for downstream consumers (e.g. an " +
        "inference endpoint that serves it, or a training job that " +
        "pulls it as a base)."
    ),
    attrs = {
        "repo": attr.string(mandatory = True),
        "revision": attr.string(default = "main"),
        "repo_type": attr.string(
            default = "model",
            values = ["model", "dataset"],
        ),
    },
)

# ── shared launcher plumbing ──────────────────────────────────────

def _rlocationpath(file, ctx):
    """Runfiles-root-relative path for `rlocation` (bzlmod-safe)."""
    sp = file.short_path
    if sp.startswith("../"):
        return sp[3:]
    return ctx.workspace_name + "/" + sp

def _emit_launcher(ctx, template, extra_subs):
    """Expand a runner template into an executable launcher that has
    the hermetic `hf` binary + the bash runfiles lib in its runfiles.
    """
    hf = ctx.toolchains[_HF_TOOLCHAIN_TYPE].hfinfo
    launcher = ctx.actions.declare_file(ctx.label.name + "_launcher.sh")
    subs = {"%%HF_RLOCATION%%": _rlocationpath(hf.executable, ctx)}
    subs.update(extra_subs)
    ctx.actions.expand_template(
        template = template,
        output = launcher,
        is_executable = True,
        substitutions = subs,
    )
    runfiles = ctx.runfiles(files = [hf.executable])
    runfiles = runfiles.merge(hf.runfiles)
    runfiles = runfiles.merge(
        ctx.attr._runfiles_lib[DefaultInfo].default_runfiles,
    )
    return [DefaultInfo(executable = launcher, runfiles = runfiles)]

_RUNNER_ATTRS = {
    "_runfiles_lib": attr.label(
        default = Label("@bazel_tools//tools/bash/runfiles"),
    ),
}

# ── hf_upload ─────────────────────────────────────────────────────

def _hf_upload_impl(ctx):
    return _emit_launcher(ctx, ctx.file._tpl, {
        "%%REPO%%": ctx.attr.repo,
        "%%REPO_TYPE%%": ctx.attr.repo_type,
        "%%PRIVATE%%": "1" if ctx.attr.private else "0",
        "%%LOCAL_DIR%%": ctx.attr.local_dir,
    })

hf_upload = rule(
    implementation = _hf_upload_impl,
    doc = "Push a local directory to a HF Hub repo (create-if-missing + sync).",
    executable = True,
    toolchains = [_HF_TOOLCHAIN_TYPE],
    attrs = dict(_RUNNER_ATTRS, **{
        "repo": attr.string(mandatory = True),
        "local_dir": attr.string(mandatory = True),
        "repo_type": attr.string(default = "model", values = ["model", "dataset"]),
        "private": attr.bool(default = True),
        "_tpl": attr.label(
            default = Label("//huggingface/private:hf_upload.sh.tpl"),
            allow_single_file = True,
        ),
    }),
)

# ── hf_repo (create) ──────────────────────────────────────────────

def _hf_repo_impl(ctx):
    args = ["repos", "create", ctx.attr.repo, "--repo-type", ctx.attr.repo_type, "--exist-ok"]
    if ctx.attr.private:
        args.append("--private")
    return _emit_launcher(ctx, ctx.file._tpl, {
        "%%VERB_AND_ARGS%%": " ".join([_shquote(a) for a in args]),
    })

hf_repo = rule(
    implementation = _hf_repo_impl,
    doc = "Create (or no-op reuse) a HF Hub repo. Emits a `bazel run`-able target.",
    executable = True,
    toolchains = [_HF_TOOLCHAIN_TYPE],
    attrs = dict(_RUNNER_ATTRS, **{
        "repo": attr.string(mandatory = True),
        "repo_type": attr.string(default = "model", values = ["model", "dataset", "space"]),
        "private": attr.bool(default = True),
        "_tpl": attr.label(
            default = Label("//huggingface/private:hf_runner.sh.tpl"),
            allow_single_file = True,
        ),
    }),
)

# ── hf_download (run-time materializer) ───────────────────────────

def _hf_download_impl(ctx):
    args = ["download", ctx.attr.repo, "--repo-type", ctx.attr.repo_type]
    if ctx.attr.revision:
        args += ["--revision", ctx.attr.revision]
    if ctx.attr.local_dir:
        args += ["--local-dir", ctx.attr.local_dir]
    args += ctx.attr.files
    return _emit_launcher(ctx, ctx.file._tpl, {
        "%%VERB_AND_ARGS%%": " ".join([_shquote(a) for a in args]),
    })

hf_download = rule(
    implementation = _hf_download_impl,
    doc = (
        "Materialize a HF Hub repo (or specific files) into a local " +
        "dir on `bazel run`. v0.0.2 is run-time; a hermetic " +
        "repository-rule variant for build-time inputs is future work."
    ),
    executable = True,
    toolchains = [_HF_TOOLCHAIN_TYPE],
    attrs = dict(_RUNNER_ATTRS, **{
        "repo": attr.string(mandatory = True),
        "repo_type": attr.string(default = "model", values = ["model", "dataset"]),
        "revision": attr.string(default = ""),
        "local_dir": attr.string(default = ""),
        "files": attr.string_list(doc = "Specific files to fetch; empty ⇒ whole repo."),
        "_tpl": attr.label(
            default = Label("//huggingface/private:hf_runner.sh.tpl"),
            allow_single_file = True,
        ),
    }),
)

def _shquote(s):
    return "'" + s.replace("'", "'\\''") + "'"
