"""rules_huggingface public API.

```starlark
load("@rules_huggingface//huggingface:defs.bzl", "hf_model", "hf_upload")
```

* `hf_model`  — typed reference to a HF Hub model/dataset repo
                (carries `HfModelInfo`; consumers pull at runtime).
* `hf_upload` — push a local directory to a HF Hub repo. Emits a
                `<name>.push` runner: `bazel run :<name>.push`.

The ergonomic home for the trained-artifact lifecycle across the
fastverk cluster: rules_lora trains an adapter, agora_infer merges
it into a deployable model, `hf_upload` pushes that model, and a
`rules_runpod` serverless endpoint serves it.
"""

load("@rules_shell//shell:sh_binary.bzl", "sh_binary")
load("//huggingface/private:rules.bzl", _hf_model = "hf_model")

hf_model = _hf_model

def hf_upload(
        name,
        repo,
        local_dir,
        repo_type = "model",
        private = True,
        visibility = None):
    """Push a local directory to a HuggingFace Hub repo.

    Emits a `<name>.push` sh_binary. `bazel run :<name>.push`
    ensures the repo exists (creating it private/public as
    configured) then uploads `local_dir`. A trailing
    `bazel run :<name>.push -- <other_dir>` overrides `local_dir`
    at runtime (useful when the dir is produced by a separate
    `bazel run` export step).

    Requires the `hf` CLI on PATH + `HF_TOKEN` in the env.

    Args:
      name: target name.
      repo: HF repo id (e.g. `fastverk/agora-parser-qwen2.5-1.5b`).
      local_dir: default directory to upload, relative to the
        workspace root.
      repo_type: `model` (default) or `dataset`.
      private: create the repo private (default True).
      visibility: standard.
    """
    sh_binary(
        name = name + ".push",
        srcs = ["@rules_huggingface//huggingface:upload.sh"],
        args = [
            repo,
            repo_type,
            "1" if private else "0",
            local_dir,
        ],
        visibility = visibility,
    )
