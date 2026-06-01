"""Concatenate N Turtle files into one with deduped `@prefix` lines.

Used by `research_graph` to assemble:
  * the bib closure TTL (emitted by Starlark via `ctx.actions.write`)
  * zero or more LaTeX-AST TTLs (emitted by `latex_ast_to_rdf`)

into a single output file consumers can SPARQL over without
federated joins. Prefix dedup is value-aware: two `@prefix bib:`
lines pointing at the same IRI collapse to one; pointing at
DIFFERENT IRIs is a build failure (the inputs disagree on what
`bib:` means).

Not a real Turtle parser. The inputs are emitted by code we own —
both `_emit_turtle` in research_graph.bzl and `ast_to_ttl.py` in
rules_lang emit one `@prefix <pfx>: <iri> .` per line at the top
of the file, with no inline `@prefix` directives mid-document.
"""

import argparse
import re
import sys
from pathlib import Path


_PREFIX_RE = re.compile(r"^\s*@prefix\s+([A-Za-z_][A-Za-z0-9_-]*):\s*<([^>]+)>\s*\.\s*$")


def parse_prefix(line):
    """Return (prefix, iri) if `line` is an `@prefix` directive, else None."""
    m = _PREFIX_RE.match(line)
    if m:
        return m.group(1), m.group(2)
    return None


def merge(inputs):
    """Read each input file, collect a unified prefix table, and
    return the merged text (prefixes block + each file's body).

    Raises ValueError on prefix-IRI disagreement across files.
    """
    prefixes = {}  # name → iri
    bodies = []    # one entry per input, post-prefix lines

    for path in inputs:
        text = Path(path).read_text()
        body_lines = []
        for line in text.splitlines():
            pfx = parse_prefix(line)
            if pfx is None:
                body_lines.append(line)
                continue
            name, iri = pfx
            existing = prefixes.get(name)
            if existing is not None and existing != iri:
                raise ValueError(
                    "@prefix %s: disagrees across inputs: "
                    "%r (existing) vs %r (in %s)" % (name, existing, iri, path),
                )
            prefixes[name] = iri
        # Strip leading blank lines so the file boundary isn't visible
        # as a paragraph gap when bodies concatenate.
        while body_lines and body_lines[0].strip() == "":
            body_lines.pop(0)
        bodies.append("\n".join(body_lines))

    # Emit prefixes in stable (alphabetical) order; column-aligned for
    # readability — width matches research_graph.bzl's _emit_turtle.
    pad_width = max((len(name) + 1 for name in prefixes), default=0)
    prefix_lines = [
        "@prefix %s %s<%s> ." % (
            (name + ":").ljust(pad_width + 1),
            "",
            iri,
        )
        for name, iri in sorted(prefixes.items())
    ]

    return "\n".join(prefix_lines) + "\n\n" + "\n\n".join(b for b in bodies if b.strip()) + "\n"


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--input", action="append", required=True,
                   help="Input .ttl path (repeat for multiple)")
    p.add_argument("--output", required=True, help="Output .ttl path")
    args = p.parse_args()

    try:
        merged = merge(args.input)
    except ValueError as e:
        print("merge_ttl: %s" % e, file=sys.stderr)
        sys.exit(1)

    Path(args.output).write_text(merged)


if __name__ == "__main__":
    main()
