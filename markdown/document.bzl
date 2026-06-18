"""markdown_document — aggregate fragments into one rendered markdown document.

Collects fragments (via markdown_link_aspect over `fragments` + `roots`), orders
them by (weight, frag_id), and renders with the md_gen tool: heading injection,
TOC, template splice, and `mdref:` deep-link resolution + dangling-link check.

`write_to` adds a `<name>.write` materialization target (and `<name>.write_test`
drift gate) via aspect_bazel_lib's write_source_files — the same pattern
rules_vscode uses, so a doc lands in the source tree the canonical way.
"""

load("@aspect_bazel_lib//lib:write_source_files.bzl", "write_source_files")
load(":aspect.bzl", "markdown_link_aspect")
load(":providers.bzl", "MarkdownDocInfo", "MarkdownFragmentInfo")

def _safe(s):
    return s.replace("/", "_").replace(":", "_").replace("@", "_").replace(".", "_")

def _markdown_document_impl(ctx):
    frags = []
    for dep in ctx.attr.fragments + ctx.attr.roots:
        if MarkdownFragmentInfo in dep:
            frags.append(dep[MarkdownFragmentInfo].fragments)
    fragments = sorted(
        depset(transitive = frags).to_list(),
        key = lambda f: (f.weight, f.frag_id),
    )

    out = ctx.actions.declare_file(ctx.attr.out)
    anchor_index = ctx.actions.declare_file(ctx.attr.out + ".anchors.json")

    args = ctx.actions.args()
    args.add(ctx.file._md_gen)
    args.add("--out", out)
    args.add("--anchor-index-out", anchor_index)
    if ctx.file.template:
        args.add("--template", ctx.file.template)
    if ctx.attr.toc:
        args.add("--toc")
    if ctx.attr.link_check:
        args.add("--link-check")

    inputs = [ctx.file._md_gen]
    if ctx.file.template:
        inputs.append(ctx.file.template)
    for f in fragments:
        meta = ctx.actions.declare_file("_md/%s/%s.meta.json" % (ctx.attr.name, _safe(f.frag_id)))
        ctx.actions.write(meta, json.encode({
            "frag_id": f.frag_id,
            "title": f.title,
            "level": f.level,
            "weight": f.weight,
            "handle": f.handle,
            "tags": list(f.tags),
        }))
        args.add("--fragment", f.frag_id, format = "%s=" + f.md_file.path)
        args.add("--meta", f.frag_id, format = "%s=" + meta.path)
        inputs.append(f.md_file)
        inputs.append(meta)

    ctx.actions.run_shell(
        command = 'python3 "$@"',
        arguments = [args],
        inputs = depset(inputs),
        outputs = [out, anchor_index],
        mnemonic = "MarkdownRender",
        progress_message = "Rendering markdown document %{label}",
    )

    return [
        DefaultInfo(files = depset([out])),
        MarkdownDocInfo(md = out, anchor_index = anchor_index, fragments = depset(fragments)),
    ]

_markdown_document = rule(
    implementation = _markdown_document_impl,
    attrs = {
        "out": attr.string(mandatory = True, doc = "Output filename."),
        "template": attr.label(
            allow_single_file = True,
            doc = "Prose template with `<!-- FRAGMENTS -->` (required) and optional `<!-- TOC -->` markers.",
        ),
        "fragments": attr.label_list(
            providers = [[MarkdownFragmentInfo]],
            aspects = [markdown_link_aspect],
            doc = "Fragment targets to compose (each carries its transitive deps).",
        ),
        "roots": attr.label_list(
            aspects = [markdown_link_aspect],
            doc = "Arbitrary targets whose graph contributes fragments.",
        ),
        "toc": attr.bool(default = True, doc = "Emit a table of contents."),
        "link_check": attr.bool(default = True, doc = "Fail the build on a dangling `mdref:` deep link."),
        "_md_gen": attr.label(
            default = Label("//markdown/private:md_gen.py"),
            allow_single_file = True,
        ),
    },
    provides = [MarkdownDocInfo],
)

def markdown_document(
        name,
        out = None,
        template = None,
        fragments = [],
        roots = [],
        toc = True,
        link_check = True,
        write_to = None,
        **kwargs):
    """Aggregate fragments into one rendered markdown document.

    Args:
      name: target name.
      out: output filename (defaults to `<name>.md`).
      template: optional prose template with `<!-- FRAGMENTS -->` + `<!-- TOC -->`.
      fragments: fragment targets to compose.
      roots: arbitrary targets whose graph contributes fragments (via the aspect).
      toc: emit a table of contents.
      link_check: fail on a dangling `mdref:` deep link.
      write_to: if set (a source-relative path), also create `<name>.write`
        (`bazel run` materializes the doc into the tree) + `<name>.write_test`
        (drift gate), via write_source_files.
      **kwargs: forwarded (visibility, tags, …).
    """
    out = out if out else (name + ".md")
    _markdown_document(
        name = name,
        out = out,
        template = template,
        fragments = fragments,
        roots = roots,
        toc = toc,
        link_check = link_check,
        **kwargs
    )
    if write_to:
        write_source_files(
            name = name + ".write",
            files = {write_to: ":" + name},
            diff_test = True,
            visibility = kwargs.get("visibility", None),
        )
