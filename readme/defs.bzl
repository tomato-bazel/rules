"""Public API for rules_readme — README-shaped sugar over rules_markdown.

```starlark
load("@rules_readme//readme:defs.bzl", "readme", "markdown_fragment")
```
"""

load(
    "@rules_markdown//markdown:defs.bzl",
    _markdown_document = "markdown_document",
    _markdown_fragment = "markdown_fragment",
)

markdown_fragment = _markdown_fragment
markdown_document = _markdown_document

def readme(
        name,
        template,
        fragments = [],
        roots = [],
        toc = True,
        link_check = True,
        write_to = "README.md",
        **kwargs):
    """Render a templated README from fragments and materialize it into the tree.

    A thin façade over `markdown_document` with README defaults. Because
    materialize-to-source is the dominant case, `write_to` defaults to
    `"README.md"` — so `readme(...)` creates `<name>.write` (`bazel run`
    materializes the README) + `<name>.write_test` (the drift gate) out of the
    box, via `write_source_files`. Pass `write_to = None` to opt out (you then
    just get the rendered file in bazel-bin + `MarkdownDocInfo`).

    Args:
      name: target name.
      template: prose template with `<!-- FRAGMENTS -->` (required) and an
        optional `<!-- TOC -->` marker.
      fragments: fragment targets to compose (ordered by their `weight`).
      roots: arbitrary targets whose graph contributes fragments.
      toc: emit a table of contents.
      link_check: fail the build on a dangling `mdref:` deep link.
      write_to: source-relative path to materialize into (default `"README.md"`);
        `None` to skip materialization.
      **kwargs: forwarded (visibility, tags, …).
    """
    _markdown_document(
        name = name,
        template = template,
        fragments = fragments,
        roots = roots,
        toc = toc,
        link_check = link_check,
        write_to = write_to,
        **kwargs
    )
