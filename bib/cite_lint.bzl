"""Aspect-shaped cite-lint check.

For each `cited_tex_paper`, the aspect extracts every `\\cite{<key>}`
from every `.tex` source and verifies that the key is declared in
`bib_deps`. Build fails on undeclared cites.

The check runs as a build action so the failure is fatal — the
PDF doesn't get built with a missing citation. This is the
mechanism that would have caught the recent `openie2007banko`
miss in the agora paper.

```python
cited_tex_paper(
    name = "grounding",
    srcs = [...],
    bib_deps = [":lewis2020rag", ":openie2007banko"],
    # warn_unused = True   (default) — also warn on bib_deps with
    #                        no \cite{} usage. Set False to silence.
)
```

V0 implementation: a simple Python script (lint.py) extracts the
keys via regex and diffs against the declared set. V1 may upgrade
to a proper bibtex parser if richer cross-checks are needed.
"""

load(":providers.bzl", "PaperCitationInfo")

def cite_lint_action(ctx, tex_srcs, bib_deps, lint_tool, warn_unused = True):
    """Run cite-lint against `tex_srcs` + `bib_deps`. Produces a marker
    file (passes-or-fails the build action). Called by `cited_tex_paper`.
    """
    marker = ctx.actions.declare_file(ctx.label.name + ".citelint.ok")

    declared_keys = sorted([dep[PaperCitationInfo].key for dep in bib_deps])
    keys_file = ctx.actions.declare_file(ctx.label.name + ".citelint.declared")
    ctx.actions.write(keys_file, "\n".join(declared_keys) + "\n")

    args = ctx.actions.args()
    args.add("--declared", keys_file.path)
    args.add("--marker", marker.path)
    if warn_unused:
        args.add("--warn-unused")
    for src in tex_srcs:
        args.add("--tex", src.path)

    ctx.actions.run(
        executable = lint_tool,
        arguments = [args],
        inputs = tex_srcs + [keys_file],
        outputs = [marker],
        mnemonic = "BibTexCiteLint",
        progress_message = "cite-lint %s (%d srcs, %d declared keys)" % (
            ctx.label,
            len(tex_srcs),
            len(declared_keys),
        ),
    )
    return marker
