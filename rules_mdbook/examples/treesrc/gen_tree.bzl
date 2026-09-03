"""Minimal rule that emits a directory (tree artifact) of mdbook chapters.

Stands in for a real upstream generator (a doc emitter, a layout-remapper)
whose output filenames aren't known statically. Exercises `mdbook_book`'s
ability to consume a directory src and copy it in recursively.
"""

def _gen_tree_impl(ctx):
    out = ctx.actions.declare_directory(ctx.label.name)
    ctx.actions.run_shell(
        outputs = [out],
        command = """
set -euo pipefail
mkdir -p "{d}"
printf '# Summary\\n\\n- [Intro](intro.md)\\n' > "{d}/SUMMARY.md"
printf '# Intro\\n\\nGenerated chapter from a tree artifact.\\n' > "{d}/intro.md"
""".format(d = out.path),
        mnemonic = "GenTree",
    )
    return [DefaultInfo(files = depset([out]))]

gen_tree = rule(
    implementation = _gen_tree_impl,
    doc = "Emit a directory of generated mdbook chapters (SUMMARY.md + intro.md).",
)
