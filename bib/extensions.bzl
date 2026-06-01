"""`arxiv` module extension — Bazel-pinned arxiv source archives.

Companion to `arxiv_paper` (bibtex declaration). `arxiv_paper` pins
the *bibliographic metadata*; `arxiv` (this extension) pins the
actual LaTeX *source bundle* fetched from `arxiv.org/e-print/<id>`.
The two together turn an arxiv paper into a fully-reproducible
Bazel artifact: cite it, parse its sources, embed snippets in your
own paper.

Usage (in the consumer's MODULE.bazel):

```python
arxiv = use_extension("@rules_bibtex//bib:extensions.bzl", "arxiv")
arxiv.fetch(
    id = "2005.11401v4",          # arxiv id (with optional version)
    sha256 = "abc123...",         # sha256 of the tar.gz from e-print/<id>
)
arxiv.fetch(id = "2302.04761", sha256 = "...")
use_repo(arxiv, "arxiv_2005_11401v4", "arxiv_2302_04761")
```

Then in BUILD files:

```python
filegroup(
    name = "rag_paper_sources",
    srcs = ["@arxiv_2005_11401v4//:source"],
)

# Or feed it to rules_lang/latex:
load("@rules_lang//rules/latex:rules.bzl", "latex_ast_dump")

latex_ast_dump(
    name = "rag_ast",
    src = "@arxiv_2005_11401v4//:main_tex",
)
```

Computing the sha256: run `bazel mod tidy` (it'll resolve the
download once and write the computed hash back into the lockfile),
or fetch manually and `shasum -a 256 source.tar.gz`. The hash is
required so the build is reproducible across machines / time.

Sibling to: the runtime Beam closure walker in agora's
`research_closure/` package. That walker DISCOVERS papers at run
time; `arxiv_source_archive` PINS papers at build time. Use the
walker for breadth (1000+ papers in a closure), use this extension
for paper-specific build dependencies (e.g., a `latex_ast_dump` of
a paper you cite, baked into your own paper's build graph).

V0 limitations:
  * Only `.tar.gz` source bundles are supported — the common case
    on arxiv CS/ML. A handful of single-file `.tex.gz` submissions
    will fail at fetch; the workaround is to use the runtime
    walker for those cases.
  * `sha256` is mandatory. arxiv sometimes re-serves the same id
    with a newer version (the version suffix `v4` etc. is a
    weak version pin); supplying the hash anchors the content
    even if arxiv silently rotates.
"""

_USER_AGENT = "fastverk-rules-bibtex/0.0.6 (mateomm@gmail.com)"

def _normalize_id(arxiv_id):
    """Convert an arxiv id into a workspace-safe repository name suffix.

    Strips the optional `arXiv:` prefix and replaces `/` (legacy
    `cs/0610028`-style ids) and `.` with `_`. Periods are illegal in
    workspace names per Bazel's external-repo rules.
    """
    s = arxiv_id
    if s.startswith("arXiv:"):
        s = s[len("arXiv:"):]
    return s.replace("/", "_").replace(".", "_")

def _arxiv_source_archive_impl(ctx):
    url = "https://arxiv.org/e-print/" + ctx.attr.arxiv_id

    # Download the source bundle. arxiv.org/e-print serves either a
    # .tar.gz (the common case) or a gzipped single .tex (rare); the
    # download itself is the same regardless of content shape.
    ctx.download(
        url = url,
        output = "source.tar.gz",
        sha256 = ctx.attr.sha256,
        executable = False,
    )

    # Extract. ctx.extract handles tar.gz cleanly; if the bundle is
    # a single-file .tex.gz, this errors out and we fall back to
    # exposing the raw download as `source`.
    extracted_ok = True
    extract_result = ctx.execute(
        ["tar", "tzf", "source.tar.gz"],
        quiet = True,
    )
    if extract_result.return_code != 0:
        extracted_ok = False

    if extracted_ok:
        ctx.extract(
            archive = "source.tar.gz",
            output = "src",
        )
        # Find main.tex (first .tex with \documentclass) by walking
        # the extracted tree.
        find_result = ctx.execute(
            ["bash", "-c",
             "find src -name '*.tex' -print0 | xargs -0 grep -l '\\\\documentclass' | head -1"],
        )
        main_tex_path = find_result.stdout.strip() or ""
        if main_tex_path:
            # Symlink for a stable `main_tex` label.
            ctx.symlink(main_tex_path, "main.tex")
    else:
        # Not a tar — leave source.tar.gz as the only artifact.
        main_tex_path = ""

    # Emit a BUILD file that exposes:
    #   :source     — every extracted file as one filegroup
    #   :main_tex   — the identified entry-point .tex (when found)
    build_lines = [
        "package(default_visibility = [\"//visibility:public\"])",
        "",
        "exports_files([\"source.tar.gz\"])",
        "",
    ]

    if extracted_ok:
        build_lines.extend([
            "filegroup(",
            "    name = \"source\",",
            "    srcs = glob([\"src/**/*\"], exclude = [\"src/**/*.png\", \"src/**/*.jpg\", \"src/**/*.pdf\"]),",
            ")",
            "",
            "filegroup(",
            "    name = \"all\",",
            "    srcs = glob([\"src/**/*\"]),",
            ")",
            "",
        ])
        if main_tex_path:
            build_lines.extend([
                "exports_files([\"main.tex\"])",
                "",
                "filegroup(",
                "    name = \"main_tex\",",
                "    srcs = [\"main.tex\"],",
                ")",
                "",
            ])
    else:
        # Single-file fallback — the .tar.gz is itself the source.
        build_lines.extend([
            "filegroup(",
            "    name = \"source\",",
            "    srcs = [\"source.tar.gz\"],",
            ")",
            "",
        ])

    ctx.file("BUILD.bazel", "\n".join(build_lines))

_arxiv_source_archive = repository_rule(
    implementation = _arxiv_source_archive_impl,
    attrs = {
        "arxiv_id": attr.string(
            mandatory = True,
            doc = "arxiv id including optional version, e.g. " +
                  "'2005.11401v4' or 'cs/0610028'. Used to construct " +
                  "the fetch URL: https://arxiv.org/e-print/<id>.",
        ),
        "sha256": attr.string(
            mandatory = True,
            doc = "Required sha256 of the fetched tarball. Compute " +
                  "with `bazel mod tidy` or `shasum -a 256 source.tar.gz`.",
        ),
    },
    doc = "Repository rule (internal). Use the `arxiv` module " +
          "extension instead.",
)

def _arxiv_impl(module_ctx):
    """Iterate every `arxiv.fetch(...)` tag across the module graph
    and instantiate one `_arxiv_source_archive` repo per call."""
    seen = {}
    for module in module_ctx.modules:
        for tag in module.tags.fetch:
            repo_name = "arxiv_" + _normalize_id(tag.id)
            if repo_name in seen:
                if seen[repo_name] != tag.sha256:
                    fail(
                        "Conflicting `arxiv.fetch(id=%r)` across modules: " % tag.id +
                        "sha256=%r vs %r" % (seen[repo_name], tag.sha256),
                    )
                continue
            seen[repo_name] = tag.sha256
            _arxiv_source_archive(
                name = repo_name,
                arxiv_id = tag.id,
                sha256 = tag.sha256,
            )

arxiv = module_extension(
    implementation = _arxiv_impl,
    tag_classes = {
        "fetch": tag_class(
            attrs = {
                "id": attr.string(
                    mandatory = True,
                    doc = "arxiv id (with optional version), e.g. 2005.11401v4.",
                ),
                "sha256": attr.string(
                    mandatory = True,
                    doc = "Required sha256 of the source tarball from " +
                          "arxiv.org/e-print/<id>.",
                ),
            },
            doc = "Fetch one arxiv paper's source bundle. Creates a " +
                  "repository named `@arxiv_<normalized_id>` exposing " +
                  ":source / :main_tex / source.tar.gz.",
        ),
    },
    doc = "Pin arxiv source bundles for build-time consumption (parse, " +
          "embed, cross-reference). Use the runtime Beam closure walker " +
          "in agora/research_closure for runtime DISCOVERY.",
)
