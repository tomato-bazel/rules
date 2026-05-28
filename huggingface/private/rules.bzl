"""rules_huggingface private rule implementations."""

HfModelInfo = provider(
    doc = "A typed reference to a HuggingFace Hub model repo.",
    fields = {
        "repo": "str — HF repo id (e.g. `Qwen/Qwen2.5-1.5B-Instruct`).",
        "revision": "str — branch / tag / commit sha pin.",
        "repo_type": "str — `model` | `dataset`.",
    },
)

def _hf_model_impl(ctx):
    return [
        HfModelInfo(
            repo = ctx.attr.repo,
            revision = ctx.attr.revision,
            repo_type = ctx.attr.repo_type,
        ),
        # A tiny marker file so the target produces something
        # `bazel build`-able + can be a dep.
        DefaultInfo(files = depset([_marker(ctx)])),
    ]

def _marker(ctx):
    out = ctx.actions.declare_file(ctx.label.name + ".hfref.json")
    ctx.actions.write(
        output = out,
        content = json.encode({
            "repo": ctx.attr.repo,
            "revision": ctx.attr.revision,
            "repo_type": ctx.attr.repo_type,
        }),
    )
    return out

hf_model = rule(
    implementation = _hf_model_impl,
    doc = (
        "Declare a typed reference to a HuggingFace Hub model/dataset. " +
        "Carries `HfModelInfo` for downstream consumers (e.g. a " +
        "serverless endpoint that serves it, or a training job that " +
        "pulls it as a base). Pull-at-runtime is the consumer's job " +
        "(hf-hub / transformers); this rule is the typed handle."
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
