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

    # `markdown_document` names its rendered output `<name>.md`, and `write_to`
    # puts the source file in the same package. If those two differ only by
    # case, they are DISTINCT paths on Linux and the SAME path on macOS and
    # Windows, whose filesystems are case-insensitive by default.
    #
    # The failure that produces is unrecognizable as a naming problem:
    #
    #   Could not copy inputs into sandbox: [unix_jni.cc:297]
    #   .../examples/profile/readme.md (File exists)
    #
    # and it only appears on some machines — a case-sensitive APFS volume
    # reproduces Linux's behavior and passes, so it reads as flaky CI.
    #
    # The obvious spelling is the one that breaks: readme(name = "readme")
    # with the default write_to = "README.md" collides. Fail at load time with
    # something actionable instead.
    if write_to:
        rendered = name + ".md"
        if rendered != write_to and rendered.lower() == write_to.lower():
            fail(
                ("readme(name = %r) renders to %r, which differs from write_to = %r " +
                 "only by case. Those are two files on Linux but one on macOS and " +
                 "Windows, where the build fails with an opaque \"Could not copy " +
                 "inputs into sandbox ... (File exists)\".\n" +
                 "Rename the target (e.g. name = %r) so the rendered file and the " +
                 "materialized file have genuinely different names.") %
                (name, rendered, write_to, name + "_doc"),
            )

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
