"""`cited_tex_paper(name, preamble, sections, bib_deps, …)` — a
citation-aware wrapper around `rules_tectonic`'s `tex_paper`.

What the macro adds on top of `tex_paper`:

1. Assembles a `<name>_bibliography.tex` from the `.bib` snippets
   contributed by `bib_deps`. The assembly walks each citation's
   single-entry `.bib` and renders it as a `\\bibitem` inside a
   single `thebibliography` environment. Passed to `tex_paper`'s
   `bibliography` attr — drops the need to hand-maintain a
   separate `bibliography.tex`.
2. Runs the cite-lint action against the section sources +
   preamble — every `\\cite{key}` must have a `bib_deps` entry,
   else the build fails before LaTeX runs.
3. Emits `TexPaperWithCitationsInfo` carrying the depset of
   all transitively reachable citations (via each citation's
   `cites` attribute). The research-graph rule consumes this.

Future direction: rules_bibtex's scope may broaden into
`rules_research` — a paper is a projection of a body of research,
and citations are only one kind of provenance edge (code,
datasets, blog posts, talks all carry the same shape). See the
`paper_claim_graph` design discussion in the agora roadmap.

```python
load("@rules_bibtex//bib:defs.bzl",
     "arxiv_paper", "manual_citation", "cited_tex_paper")
load("@rules_tectonic//tectonic:defs.bzl", "tex_section")

arxiv_paper(name = "lewis2020rag", arxiv_id = "2005.11401v4", bibtex = "...")

tex_section(name = "intro", src = "sections/intro.tex",
            section_label = "sec:intro")

cited_tex_paper(
    name = "my_paper",
    preamble = "preamble.tex",
    sections = [":intro"],
    bib_deps = [":lewis2020rag"],
)
```
"""

load("@rules_tectonic//tectonic:defs.bzl", "tex_paper")
load(":providers.bzl", "PaperCitationInfo", "TexPaperWithCitationsInfo")

def _assemble_bibliography_impl(ctx):
    """Render every bib_dep's .bib snippet into a single thebibliography .tex.

    The actual bibtex → \\bibitem conversion lives in the
    bib_to_bibitem.py script. We pass it every .bib file from the
    declared bib_deps and capture the assembled .tex output.
    """
    out = ctx.actions.declare_file(ctx.label.name + ".tex")
    bib_files = [dep[PaperCitationInfo].bibtex for dep in ctx.attr.bib_deps]

    if not bib_files:
        ctx.actions.write(out, "% cited_tex_paper: no bib_deps declared.\n")
    else:
        args = ctx.actions.args()
        args.add("--out", out.path)
        for f in bib_files:
            args.add("--bib", f.path)

        ctx.actions.run(
            executable = ctx.executable._bib_to_bibitem,
            arguments = [args],
            inputs = bib_files,
            outputs = [out],
            mnemonic = "BibTexAssemble",
            progress_message = "bibtex → \\bibitem %s (%d entries)" % (
                ctx.label,
                len(bib_files),
            ),
        )

    # Carry the transitive citations forward for the research-graph rule.
    transitive = depset(
        direct = [dep[PaperCitationInfo] for dep in ctx.attr.bib_deps],
        transitive = [dep[PaperCitationInfo].cites for dep in ctx.attr.bib_deps],
    )
    return [
        DefaultInfo(files = depset([out])),
        TexPaperWithCitationsInfo(
            pdf = None,  # filled later if the consumer wires it in
            combined_bib = out,
            citations = transitive,
        ),
    ]

_assemble_bibliography = rule(
    implementation = _assemble_bibliography_impl,
    attrs = {
        "bib_deps": attr.label_list(
            providers = [PaperCitationInfo],
            mandatory = True,
            doc = "Citation targets to render into a single bibliography .tex.",
        ),
        "_bib_to_bibitem": attr.label(
            default = Label("//bib/private:bib_to_bibitem"),
            executable = True,
            cfg = "exec",
        ),
    },
    provides = [TexPaperWithCitationsInfo],
)

def _cite_lint_impl(ctx):
    """Run cite-lint over the paper's .tex sources + declared bib_deps."""
    tex_srcs = ctx.files.srcs
    bib_deps = ctx.attr.bib_deps

    out = ctx.actions.declare_file(ctx.label.name + ".citelint.ok")
    declared_keys = sorted([dep[PaperCitationInfo].key for dep in bib_deps])
    keys_file = ctx.actions.declare_file(ctx.label.name + ".citelint.declared")
    ctx.actions.write(keys_file, "\n".join(declared_keys) + "\n")

    args = ctx.actions.args()
    args.add("--declared", keys_file.path)
    args.add("--marker", out.path)
    if ctx.attr.warn_unused:
        args.add("--warn-unused")
    for src in tex_srcs:
        args.add("--tex", src.path)

    ctx.actions.run(
        executable = ctx.executable._lint,
        arguments = [args],
        inputs = tex_srcs + [keys_file],
        outputs = [out],
        mnemonic = "BibTexCiteLint",
        progress_message = "cite-lint %s (%d srcs, %d keys)" % (
            ctx.label,
            len(tex_srcs),
            len(declared_keys),
        ),
    )
    return [DefaultInfo(files = depset([out]))]

_cite_lint = rule(
    implementation = _cite_lint_impl,
    attrs = {
        "srcs": attr.label_list(allow_files = [".tex"], mandatory = True),
        "bib_deps": attr.label_list(providers = [PaperCitationInfo], mandatory = True),
        "warn_unused": attr.bool(default = True),
        "_lint": attr.label(
            default = Label("//bib/private:lint"),
            executable = True,
            cfg = "exec",
        ),
    },
)

def cited_tex_paper(
        name,
        preamble,
        sections = [],
        bib_deps = [],
        section_srcs = [],
        warn_unused = True,
        visibility = None,
        **kwargs):
    """Citation-aware LaTeX paper.

    Args:
      name: target name. The rendered PDF is `<name>.pdf`.
      preamble: label to a `.tex` containing `\\documentclass{…}`
        through `\\begin{document}` and any front matter
        (\\maketitle, abstract). Matches rules_tectonic's
        `tex_paper.preamble`.
      sections: ordered list of `tex_section` labels.
      bib_deps: list of citation targets (`arxiv_paper`, `doi_paper`,
        `manual_citation`, `bibtex_entry`). Their `.bib` files are
        rendered into a `thebibliography` .tex via the
        `bib_to_bibitem` script and passed as `bibliography` to
        `tex_paper`; cite-lint verifies every `\\cite{}` key resolves.
      section_srcs: raw `.tex` files contributing to the cite-lint
        scan (in addition to `preamble`). Use when a section's
        actual `.tex` source isn't reachable through the
        `tex_section` provider — pass the file labels directly so
        cite-lint sees their content.
      warn_unused: emit a build warning for declared bib_deps that
        are never `\\cite`'d. Default True.
      visibility: forwarded.
      **kwargs: forwarded to `tex_paper`.
    """

    # Step 1: assemble the bibliography .tex from bib_deps.
    bib_name = "_{}_bibliography".format(name)
    _assemble_bibliography(name = bib_name, bib_deps = bib_deps)

    # Step 2: cite-lint. Walk the preamble + any section_srcs (the
    # tex_section provider doesn't expose its .tex source as a file
    # label in V0 of rules_tectonic, so consumers pass the section
    # .tex paths explicitly via `section_srcs`).
    lint_name = "_{}_citelint".format(name)
    _cite_lint(
        name = lint_name,
        srcs = [preamble] + section_srcs,
        bib_deps = bib_deps,
        warn_unused = warn_unused,
    )

    # Step 3: forward to rules_tectonic's `tex_paper`. The assembled
    # bibliography .tex is the `bibliography` argument; the cite-lint
    # marker is wired in via the `extra_srcs` so the LaTeX build
    # depends on lint success transitively.
    tex_paper(
        name = name,
        preamble = preamble,
        sections = sections,
        bibliography = ":" + bib_name,
        extra_srcs = kwargs.pop("extra_srcs", []) + [":" + lint_name],
        visibility = visibility,
        **kwargs
    )
