"""Bzlmod module extension wrapping the GitHub repository rules.

```starlark
github = use_extension("@rules_github//github:extensions.bzl", "github")
github.source(
    name = "metatool_raw",
    repo = "HowieHwong/MetaTool",
    commit = "<full-sha>",
    sha256 = "<sha256>",
    build_file_content = "exports_files(glob([\\"**\\"]))",
)
use_repo(github, "metatool_raw")
```

Two tag classes mirror the repository rules in `:repositories.bzl`:

* `github.source` — `github_source_repository` (release tag *or* untagged
  `commit`).
* `github.binary` — `github_binary_repository` (per-platform release asset).
"""

load(
    "//github:repositories.bzl",
    "github_binary_repository",
    "github_source_repository",
)

def _github_impl(mctx):
    for mod in mctx.modules:
        for s in mod.tags.source:
            github_source_repository(
                name = s.name,
                repo = s.repo,
                version = s.version,
                commit = s.commit,
                tag_format = s.tag_format,
                sha256 = s.sha256,
                strip_prefix_template = s.strip_prefix_template,
                allow_unverified = s.allow_unverified,
                build_file = s.build_file,
                build_file_content = s.build_file_content,
            )
        for b in mod.tags.binary:
            github_binary_repository(
                name = b.name,
                repo = b.repo,
                version = b.version,
                tag_format = b.tag_format,
                asset_template = b.asset_template,
                strip_prefix_template = b.strip_prefix_template,
                platform_aliases = b.platform_aliases,
                platform_shas = b.platform_shas,
                allow_unverified = b.allow_unverified,
                platform = b.platform,
                build_file = b.build_file,
                build_file_content = b.build_file_content,
            )
    return mctx.extension_metadata(reproducible = True)

_source = tag_class(
    attrs = {
        "name": attr.string(mandatory = True, doc = "Generated repo name (use_repo this)."),
        "repo": attr.string(mandatory = True, doc = "GitHub repo as `owner/name`."),
        "version": attr.string(doc = "Release-tag version. Exclusive with `commit`."),
        "commit": attr.string(doc = "Full commit SHA for an untagged ref. Exclusive with `version`."),
        "tag_format": attr.string(default = "v{version}"),
        "sha256": attr.string(default = ""),
        "strip_prefix_template": attr.string(default = ""),
        "allow_unverified": attr.bool(default = False),
        "build_file": attr.label(allow_single_file = True),
        "build_file_content": attr.string(default = ""),
    },
)

_binary = tag_class(
    attrs = {
        "name": attr.string(mandatory = True, doc = "Generated repo name (use_repo this)."),
        "repo": attr.string(mandatory = True),
        "version": attr.string(mandatory = True),
        "tag_format": attr.string(default = "v{version}"),
        "asset_template": attr.string(mandatory = True),
        "strip_prefix_template": attr.string(default = ""),
        "platform_aliases": attr.string_dict(default = {}),
        "platform_shas": attr.string_dict(default = {}),
        "allow_unverified": attr.bool(default = False),
        "platform": attr.string(default = ""),
        "build_file": attr.label(allow_single_file = True),
        "build_file_content": attr.string(default = ""),
    },
)

github = module_extension(
    implementation = _github_impl,
    tag_classes = {
        "source": _source,
        "binary": _binary,
    },
    doc = "Declare GitHub-release-backed repos from MODULE.bazel.",
)
