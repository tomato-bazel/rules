"""markdown_fragment — declare one composable markdown fragment (a section).

A fragment carries a body (`src` or inline `content`), an optional `title`
heading (which md_gen injects at `level`, controlling the GitHub heading-id), and
a deep-link `handle` (the `anchor`, defaulting to the target name). Other
fragments deep-link to it by writing `mdref:<handle>` in their body — the
aggregator resolves that to the final in-doc anchor and fails the build on a
dangling reference (link_check).
"""

load(":providers.bzl", "MarkdownFragmentInfo")

def _frag_id(label):
    """A globally-unique, slug-safe id from a (globally-unique) Bazel label."""
    s = str(label)
    if s.startswith("@"):
        s = s.lstrip("@")
    return s.replace("//", "").replace("/", "_").replace(":", "__").replace(".", "_")

def _markdown_fragment_impl(ctx):
    if ctx.file.src and ctx.attr.content:
        fail("markdown_fragment %s: set exactly one of `src` or `content`." % ctx.label)
    if ctx.file.src:
        md = ctx.file.src
    elif ctx.attr.content:
        md = ctx.actions.declare_file(ctx.label.name + ".frag.md")
        ctx.actions.write(md, ctx.attr.content)
    else:
        fail("markdown_fragment %s: set one of `src` or `content`." % ctx.label)

    own = struct(
        frag_id = _frag_id(ctx.label),
        md_file = md,
        title = ctx.attr.title,
        level = ctx.attr.level,
        weight = ctx.attr.weight,
        handle = ctx.attr.anchor or ctx.label.name,
        tags = tuple(ctx.attr.classifiers),
    )
    transitive = [d[MarkdownFragmentInfo].fragments for d in ctx.attr.deps]
    return [
        DefaultInfo(files = depset([md])),
        MarkdownFragmentInfo(fragments = depset(direct = [own], transitive = transitive)),
    ]

markdown_fragment = rule(
    implementation = _markdown_fragment_impl,
    attrs = {
        "src": attr.label(allow_single_file = [".md"], doc = "The fragment body (.md). Mutually exclusive with `content`."),
        "content": attr.string(doc = "Inline fragment body. Mutually exclusive with `src`."),
        "title": attr.string(doc = "Section heading text. If set, md_gen injects a `level` heading; it's also the deep-link target."),
        "level": attr.int(default = 2, doc = "Heading level for `title` (default 2 -> `##`)."),
        "weight": attr.int(default = 0, doc = "Sort key within the document (ascending)."),
        "anchor": attr.string(doc = "Explicit deep-link handle (defaults to the target name). Reference it elsewhere as `mdref:<handle>`."),
        "classifiers": attr.string_list(doc = "Free-form classifiers (e.g. category/section); exposed in fragment metadata."),
        "deps": attr.label_list(providers = [[MarkdownFragmentInfo]], doc = "Child fragments folded in transitively."),
    },
    provides = [MarkdownFragmentInfo],
    doc = "Declare one composable markdown fragment (a section of a document).",
)
