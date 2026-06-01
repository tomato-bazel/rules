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
    #                        no \\cite{} usage. Set False to silence.
)
```

V0 implementation: a simple Python script (lint.py) extracts the
keys via regex and diffs against the declared set. V1 may upgrade
to a proper bibtex parser if richer cross-checks are needed.
"""

load(":providers.bzl", "PaperCitationInfo")

def _cite_lint_test_impl(ctx):
    # Standalone test: scans `srcs` for \cite{key} and checks that every
    # key is in `bib_deps`. Exits non-zero on a missing citation. Useful
    # for papers that don't migrate to `cited_tex_paper` but still want
    # the build-time hygiene check (agora's `tex_paper`-shaped papers
    # are the motivating consumer).
    declared_keys = sorted([dep[PaperCitationInfo].key for dep in ctx.attr.bib_deps])
    keys_file = ctx.actions.declare_file(ctx.label.name + ".declared")
    ctx.actions.write(keys_file, "\n".join(declared_keys) + "\n")

    # Test rules emit a runnable script. We write a wrapper bash
    # that re-execs the lint script with the same arguments the
    # build-action version uses.
    wrapper = ctx.actions.declare_file(ctx.label.name + ".sh")
    lint_path = ctx.executable._lint.short_path
    keys_path = keys_file.short_path
    tex_args = " ".join(["--tex \"%s\"" % src.short_path for src in ctx.files.srcs])
    unused_flag = "--warn-unused" if ctx.attr.warn_unused else ""
    marker_path = ctx.label.name + ".marker"
    ctx.actions.write(
        wrapper,
        "#!/bin/bash\nset -e\nexec %s --declared %s --marker /tmp/%s %s %s\n" % (
            lint_path,
            keys_path,
            marker_path,
            tex_args,
            unused_flag,
        ),
        is_executable = True,
    )

    runfiles = ctx.runfiles(
        files = [keys_file] + ctx.files.srcs,
        transitive_files = ctx.attr._lint[DefaultInfo].default_runfiles.files,
    )
    return [DefaultInfo(executable = wrapper, runfiles = runfiles)]

cite_lint_test = rule(
    implementation = _cite_lint_test_impl,
    attrs = {
        "srcs": attr.label_list(
            allow_files = [".tex"],
            mandatory = True,
            doc = "`.tex` files to scan for `\\cite{key}` references.",
        ),
        "bib_deps": attr.label_list(
            providers = [PaperCitationInfo],
            mandatory = True,
            doc = "Citation targets that must contain every cited key.",
        ),
        "warn_unused": attr.bool(
            default = True,
            doc = "Print a non-fatal warning for declared bib_deps that " +
                  "no .tex source cites.",
        ),
        "_lint": attr.label(
            default = Label("//bib/private:lint"),
            executable = True,
            cfg = "target",  # runs at test time, not build time
        ),
    },
    test = True,
    doc = "Bazel test that verifies every `\\cite{}` key in `srcs` has " +
          "a `bib_deps` entry. Fails the test on a missing citation. " +
          "Use as `bazel test //paper:cite_lint` and add to CI.",
)

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
