"""Bzlmod module extension for HuggingFace Hub repository fetches.

```starlark
hf = use_extension("@rules_huggingface//huggingface:extensions.bzl", "huggingface")
hf.dataset(
    name = "toolenv_raw",
    repo = "stabletoolbench/ToolEnv2404",
    revision = "<commit-sha>",
    file = "toolenv2404_filtered.tar.gz",
    sha256 = "<sha256>",
    extract = True,
)
use_repo(hf, "toolenv_raw")
```

The `dataset` tag class mirrors `hf_dataset_repository` — a build-time,
sha-pinned fetch suitable for hermetic build inputs (e.g. benchmark
archives). For run-time model push/pull use the `hf_*` build rules in
`:defs.bzl` instead.
"""

load("//huggingface/private:dataset_repo.bzl", "hf_dataset_repository")

def _huggingface_impl(mctx):
    for mod in mctx.modules:
        for d in mod.tags.dataset:
            hf_dataset_repository(
                name = d.name,
                repo = d.repo,
                revision = d.revision,
                file = d.file,
                sha256 = d.sha256,
                repo_type = d.repo_type,
                extract = d.extract,
                strip_prefix = d.strip_prefix,
                allow_unverified = d.allow_unverified,
                build_file = d.build_file,
                build_file_content = d.build_file_content,
            )
    return mctx.extension_metadata(reproducible = True)

_dataset = tag_class(
    attrs = {
        "name": attr.string(mandatory = True, doc = "Generated repo name (use_repo this)."),
        "repo": attr.string(mandatory = True),
        "revision": attr.string(mandatory = True),
        "file": attr.string(mandatory = True),
        "sha256": attr.string(default = ""),
        "repo_type": attr.string(default = "dataset", values = ["dataset", "model"]),
        "extract": attr.bool(default = False),
        "strip_prefix": attr.string(default = ""),
        "allow_unverified": attr.bool(default = False),
        "build_file": attr.label(allow_single_file = True),
        "build_file_content": attr.string(default = ""),
    },
)

huggingface = module_extension(
    implementation = _huggingface_impl,
    tag_classes = {"dataset": _dataset},
    doc = "Declare sha-pinned HF dataset/model file fetches from MODULE.bazel.",
)
