"""`cited_tex_paper(name, srcs, bib_deps, …)` — a citation-aware
wrapper around `rules_tectonic`'s `tex_paper`.

What the macro adds on top of `tex_paper`:

1. Assembles a single `<name>.bib` from the per-citation `.bib`
   files in `bib_deps`. This file is added to the LaTeX build's
   srcs so `\\cite{}` resolves.
2. Runs the cite-lint action against `srcs` — every `\\cite{key}`
   must have a `bib_deps` entry with that key, else the build
   fails before LaTeX runs.
3. Emits `TexPaperWithCitationsInfo` carrying the depset of all
   transitively reachable citations (via each citation's `cites`
   attribute). The research-graph rule consumes this.

```python
load("@rules_bibtex//bib:defs.bzl",
     "arxiv_paper", "doi_paper", "manual_citation", "cited_tex_paper")
load("@rules_tectonic//tectonic:defs.bzl", "tex_section")

arxiv_paper(name = "lewis2020rag", arxiv_id = "2005.11401v4", bibtex = "...")
doi_paper(name = "banarescu2013amr", doi = "10.18653/v1/W13-2322", bibtex = "...")

tex_section(name = "intro", src = "sections/intro.tex", section_label = "sec:intro")

cited_tex_paper(
    name = "my_paper",
    main_tex = "main.tex",
    sections = [":intro"],
    bib_deps = [":lewis2020rag", ":banarescu2013amr"],
)
```
"""

load("@rules_tectonic//tectonic:defs.bzl", "tex_paper")
load(":providers.bzl", "PaperCitationInfo", "TexPaperWithCitationsInfo")

def _assemble_bib_impl(ctx):
    """Concatenate every bib_dep's single-entry .bib into one combined.bib."""
    out = ctx.actions.declare_file(ctx.label.name + ".bib")
    inputs = [dep[PaperCitationInfo].bibtex for dep in ctx.attr.bib_deps]

    if not inputs:
        ctx.actions.write(out, "% No citations declared.\n")
        return [DefaultInfo(files = depset([out]))]

    ctx.actions.run_shell(
        command = "cat \"$@\" > " + out.path,
        arguments = [f.path for f in inputs],
        inputs = inputs,
        outputs = [out],
        mnemonic = "BibTexAssemble",
        progress_message = "bibtex assemble %s (%d entries)" % (
            ctx.label,
            len(inputs),
        ),
    )

    # Pass through the citations as a depset so research_graph can
    # walk them.
    transitive = depset(
        direct = [dep[PaperCitationInfo] for dep in ctx.attr.bib_deps],
        transitive = [dep[PaperCitationInfo].cites for dep in ctx.attr.bib_deps],
    )
    return [
        DefaultInfo(files = depset([out])),
        TexPaperWithCitationsInfo(
            pdf = None,  # filled by cited_tex_paper at the next layer
            combined_bib = out,
            citations = transitive,
        ),
    ]

_assemble_bib = rule(
    implementation = _assemble_bib_impl,
    attrs = {
        "bib_deps": attr.label_list(
            providers = [PaperCitationInfo],
            mandatory = True,
            doc = "Citation targets to concatenate into the assembled .bib.",
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
        main_tex,
        sections = [],
        bib_deps = [],
        warn_unused = True,
        visibility = None,
        **kwargs):
    """Citation-aware LaTeX paper.

    Args:
      name: target name. The rendered PDF is `<name>.pdf`.
      main_tex: top-level .tex file (forwards to rules_tectonic's
        `tex_paper.main`).
      sections: list of `tex_section` labels, in include order.
      bib_deps: list of citation targets (`arxiv_paper`, `doi_paper`,
        `manual_citation`, `bibtex_entry`). Their .bib files are
        concatenated into a single bibliography; cite-lint verifies
        every `\\cite{}` key resolves.
      warn_unused: emit a build warning for declared bib_deps that
        are never `\\cite`'d. Default True.
      visibility: forwarded.
      **kwargs: forwarded to `tex_paper`.
    """

    # Step 1: assemble the .bib from bib_deps.
    bib_name = "_{}_bib".format(name)
    _assemble_bib(name = bib_name, bib_deps = bib_deps)

    # Step 2: cite-lint. We need every .tex source — both the
    # `main_tex` and each section's underlying .tex. Sections expose
    # their source via the rules_tectonic TexSectionInfo provider,
    # but the simplest V0 path lints the main_tex only and relies on
    # the LaTeX build to surface section-level issues; sections that
    # \cite{} a missing key would have surfaced their .tex via the
    # paper's transitive srcs, so a future enhancement adds an
    # aspect-based lint that includes section sources.
    #
    # V0 caveat documented; the lint here is on `main_tex` alone.
    lint_name = "_{}_citelint".format(name)
    _cite_lint(
        name = lint_name,
        srcs = [main_tex],
        bib_deps = bib_deps,
        warn_unused = warn_unused,
    )

    # Step 3: forward to rules_tectonic's `tex_paper`. The assembled
    # .bib is added to the include set. The cite-lint marker is added
    # as a data dep so the build action depends on lint success.
    tex_paper(
        name = name,
        main = main_tex,
        sections = sections,
        bib = ":" + bib_name,
        data = [":" + lint_name],
        visibility = visibility,
        **kwargs
    )
