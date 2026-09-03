"""`hf_dataset_repository` — build-time, sha-pinned fetch of a file from
a HuggingFace Hub dataset (or model) repo.

Unlike `hf_download` (a `bazel run` materializer for whole-repo model
serving), this is a **repository rule**: it runs at fetch time, is
content-addressed via `sha256`, and exposes the result as a normal
`@repo//...` target — the right shape for a hermetic *build input*
(e.g. a benchmark archive pinned into a consumer's `MODULE.bazel`).

The data plane's bespoke LFS/Xet protocol is irrelevant here: we hit
the plain `resolve/<revision>/<file>` URL, which serves a single
content-addressable blob.
"""

def _hf_dataset_repo_impl(rctx):
    sha = rctx.attr.sha256
    if not sha and not rctx.attr.allow_unverified:
        fail("rules_huggingface: hf_dataset_repository {name}: sha256 required (or set allow_unverified = True)".format(
            name = rctx.name,
        ))
    if not sha:
        # buildifier: disable=print
        print("rules_huggingface: WARNING — downloading {name} ({repo}@{rev}) unverified".format(
            name = rctx.name,
            repo = rctx.attr.repo,
            rev = rctx.attr.revision,
        ))

    # Dataset repos resolve under `/datasets/`; model repos at the root.
    prefix = "datasets/" if rctx.attr.repo_type == "dataset" else ""
    url = "https://huggingface.co/{prefix}{repo}/resolve/{rev}/{file}".format(
        prefix = prefix,
        repo = rctx.attr.repo,
        rev = rctx.attr.revision,
        file = rctx.attr.file,
    )

    if rctx.attr.extract:
        rctx.download_and_extract(
            url = url,
            sha256 = sha,
            stripPrefix = rctx.attr.strip_prefix,
        )
    else:
        # Single file: preserve its basename at the repo root.
        out = rctx.attr.file.split("/")[-1]
        rctx.download(
            url = url,
            sha256 = sha,
            output = out,
        )

    _write_build_overlay(rctx)

def _write_build_overlay(rctx):
    if rctx.attr.build_file_content and rctx.attr.build_file:
        fail("rules_huggingface: {name}: pass exactly one of `build_file_content` or `build_file`.".format(name = rctx.name))
    if rctx.attr.build_file_content:
        rctx.file("BUILD.bazel", rctx.attr.build_file_content)
    elif rctx.attr.build_file:
        rctx.symlink(rctx.attr.build_file, "BUILD.bazel")
    else:
        # Default: export everything so consumers can reference files.
        rctx.file("BUILD.bazel", "exports_files(glob([\"**\"]))\n")

hf_dataset_repository = repository_rule(
    implementation = _hf_dataset_repo_impl,
    attrs = {
        "repo": attr.string(
            mandatory = True,
            doc = "HF repo id, e.g. `stabletoolbench/ToolEnv2404`.",
        ),
        "revision": attr.string(
            mandatory = True,
            doc = "Git revision (commit SHA / branch / tag). Pin to a SHA " +
                  "for reproducibility.",
        ),
        "file": attr.string(
            mandatory = True,
            doc = "Path of the file within the repo to fetch, e.g. " +
                  "`toolenv2404_filtered.tar.gz`.",
        ),
        "sha256": attr.string(
            default = "",
            doc = "sha256 of the fetched blob. Required unless " +
                  "`allow_unverified = True`.",
        ),
        "repo_type": attr.string(
            default = "dataset",
            values = ["dataset", "model"],
            doc = "`dataset` (resolves under /datasets/) or `model`.",
        ),
        "extract": attr.bool(
            default = False,
            doc = "If True, the file is an archive — download + extract. " +
                  "Else fetch the single file verbatim.",
        ),
        "strip_prefix": attr.string(
            default = "",
            doc = "Archive strip-prefix (extract mode only).",
        ),
        "allow_unverified": attr.bool(
            default = False,
            doc = "Skip the sha256 requirement; downgrade to a warning.",
        ),
        "build_file_content": attr.string(
            default = "",
            doc = "Inline BUILD.bazel content. Default exports all files.",
        ),
        "build_file": attr.label(
            allow_single_file = True,
            doc = "BUILD.bazel as a label. Alternative to build_file_content.",
        ),
    },
    doc = "Fetch a sha-pinned file from a HuggingFace dataset/model repo.",
)
