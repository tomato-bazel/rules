#!/usr/bin/env python3
"""Render a markdown document from ordered fragments + an optional template.

v0.1 is intentionally parse-free: headings are injected from each fragment's
`title`/`level` (so the GitHub heading-id slug is fully controlled), the TOC +
anchor index are built from those, and `mdref:<handle>` deep links resolve
against the fragment handle table (a dangling reference fails the build when
--link-check is set). A future v0.2 swaps this for a CommonMark-aware renderer
(comrak) that parses bodies for full GFM parity.

Inputs are passed by the markdown_document rule:
  --fragment <frag_id>=<body.md>   (repeated, already in weight order)
  --meta     <frag_id>=<meta.json> (repeated: title/level/handle/...)
  --template <tmpl>                (optional; <!-- FRAGMENTS --> + <!-- TOC -->)
  --toc / --link-check
  --out <file>  --anchor-index-out <file>
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

FRAGMENTS_MARK = "<!-- FRAGMENTS -->"
NAMED_SLOT = re.compile(r"<!-- FRAGMENTS:([A-Za-z0-9_-]+) -->")
TOC_MARK = "<!-- TOC -->"
MDREF = re.compile(r"mdref:([A-Za-z0-9_.\-]+)")


def slugify(text: str) -> str:
    """GitHub-flavored heading-id slug: lowercase, drop punctuation, spaces->-."""
    s = text.strip().lower()
    s = re.sub(r"[^\w\s-]", "", s)
    s = re.sub(r"\s+", "-", s)
    return s


def parse_pairs(items):
    out = []
    for it in items or []:
        key, _, value = it.partition("=")
        out.append((key, value))
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--fragment", action="append", default=[], help="frag_id=path-to-body.md")
    ap.add_argument("--meta", action="append", default=[], help="frag_id=path-to-meta.json")
    ap.add_argument("--template", type=Path)
    ap.add_argument("--toc", action="store_true")
    ap.add_argument("--link-check", action="store_true")
    ap.add_argument("--out", required=True, type=Path)
    ap.add_argument("--anchor-index-out", type=Path)
    args = ap.parse_args()

    bodies = parse_pairs(args.fragment)               # ordered list of (frag_id, path)
    metas = {k: json.loads(Path(v).read_text()) for k, v in parse_pairs(args.meta)}

    handle_to_slug = {}     # deep-link handle -> final in-doc anchor
    slug_counts = {}        # heading-id collision counter (GitHub -N suffixing)
    toc_entries = []        # (level, title, slug)
    slot_sections = {}      # slot ("" = default) -> rendered section blocks, in order

    for frag_id, body_path in bodies:
        meta = metas.get(frag_id, {})
        title = meta.get("title", "")
        level = int(meta.get("level", 2))
        handle = meta.get("handle", frag_id)
        slot = meta.get("slot", "")
        body = Path(body_path).read_text().rstrip()

        if title:
            base = slugify(title)
            n = slug_counts.get(base, 0)
            slug = base if n == 0 else "%s-%d" % (base, n)
            slug_counts[base] = n + 1
            if handle in handle_to_slug:
                sys.stderr.write(
                    "error: duplicate deep-link handle %r (fragment %s)\n" % (handle, frag_id)
                )
                return 1
            handle_to_slug[handle] = slug
            toc_entries.append((level, title, slug))
            rendered = "%s %s\n\n%s" % ("#" * level, title, body)
        else:
            rendered = body
        slot_sections.setdefault(slot, []).append(rendered)

    def slot_md(name):
        return "\n\n".join(s for s in slot_sections.get(name, []) if s).strip()

    toc_md = ""
    if args.toc and toc_entries:
        min_level = min(level for level, _, _ in toc_entries)
        toc_md = "\n".join(
            "%s- [%s](#%s)" % ("  " * (level - min_level), title, slug)
            for level, title, slug in toc_entries
        )

    if args.template:
        text = args.template.read_text()
        # Named slots: <!-- FRAGMENTS:<slot> --> <- fragments declaring slot="<slot>".
        used = set()

        def _named(m):
            used.add(m.group(1))
            return slot_md(m.group(1))

        text = NAMED_SLOT.sub(_named, text)
        # Default slot: the unnamed <!-- FRAGMENTS -->.
        default_md = slot_md("")
        if default_md and FRAGMENTS_MARK not in text:
            sys.stderr.write("error: template %s is missing %s\n" % (args.template, FRAGMENTS_MARK))
            return 1
        text = text.replace(FRAGMENTS_MARK, default_md)
        text = text.replace(TOC_MARK, toc_md)
        # Every slot that has fragments must have a placeholder in the template.
        missing = sorted(s for s in slot_sections if s and s not in used)
        if missing:
            sys.stderr.write(
                "error: template %s missing placeholder(s): %s\n"
                % (args.template, ", ".join("<!-- FRAGMENTS:%s -->" % s for s in missing))
            )
            return 1
    else:
        parts = [toc_md, slot_md("")] + [slot_md(s) for s in sorted(slot_sections) if s]
        text = "\n\n".join(p for p in parts if p)

    # Resolve mdref:<handle> deep links against the handle table.
    dangling = []

    def _resolve(m):
        handle = m.group(1)
        if handle in handle_to_slug:
            return "#" + handle_to_slug[handle]
        dangling.append(handle)
        return m.group(0)

    text = MDREF.sub(_resolve, text)

    if dangling and args.link_check:
        uniq = sorted(set(dangling))
        sys.stderr.write("error: %d dangling deep link(s): %s\n" % (len(uniq), ", ".join(uniq)))
        sys.stderr.write("known handles: %s\n" % (", ".join(sorted(handle_to_slug)) or "(none)"))
        return 1

    args.out.write_text(text.rstrip() + "\n")
    if args.anchor_index_out:
        args.anchor_index_out.write_text(json.dumps(handle_to_slug, indent=2, sort_keys=True) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
