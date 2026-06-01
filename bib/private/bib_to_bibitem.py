"""Convert one-or-more bibtex .bib files into a single `thebibliography`
.tex file with `\\bibitem` entries.

Used by `cited_tex_paper` to produce the `bibliography` argument for
`rules_tectonic`'s `tex_paper` (which expects a .tex file containing
the `\\begin{thebibliography}{99} … \\end{thebibliography}`
environment, not a raw .bib).

The converter is regex-based and handles the entry types this
toolkit's citation rules emit: `@inproceedings`, `@article`,
`@misc`, `@book`, `@techreport`. Fields it reads: `title`, `author`,
`booktitle`, `journal`, `year`, `note`, `url`. Other fields (DOI,
eprint, archivePrefix) round-trip into provider metadata but don't
need to appear in the rendered bibitem.

Output style is the conventional `<authors>, \\emph{<title>}, <venue>
<year>.` — same shape as the entries agora's paper used before the
migration, so the rendered PDF visual is unchanged.
"""

import argparse
import re
import sys
from pathlib import Path


# A bibtex entry: `@type{key,\n  field = {...},\n  ...}`. We capture
# the type, the key, and the raw field block; per-field parsing
# happens in `parse_fields`.
ENTRY_RE = re.compile(
    r"@(\w+)\s*\{\s*([A-Za-z0-9_]+)\s*,\s*(.*?)\n\}",
    re.DOTALL,
)

# Fields are `name = {value}` or `name = "value"`. Values can contain
# escaped braces (`{\\"u}`) so the parser walks brace depth.
FIELD_NAME_RE = re.compile(r"\s*([A-Za-z_]+)\s*=\s*")


def parse_entry(text):
    m = ENTRY_RE.search(text)
    if not m:
        return None
    entry_type, key, fields_block = m.groups()
    fields = parse_fields(fields_block)
    return {"type": entry_type.lower(), "key": key, "fields": fields}


def parse_fields(block):
    """Walk a `name = {value}` block respecting brace depth."""
    fields = {}
    i = 0
    while i < len(block):
        # Skip whitespace / commas.
        while i < len(block) and block[i] in " \t\n\r,":
            i += 1
        if i >= len(block):
            break
        m = FIELD_NAME_RE.match(block, i)
        if not m:
            break
        name = m.group(1).lower()
        i = m.end()
        if i >= len(block):
            break
        # Value: either `{ ... }` (brace-balanced) or `"..."` (no
        # nested quotes for our use).
        if block[i] == "{":
            i += 1
            depth = 1
            start = i
            while i < len(block) and depth > 0:
                if block[i] == "\\" and i + 1 < len(block):
                    i += 2
                    continue
                if block[i] == "{":
                    depth += 1
                elif block[i] == "}":
                    depth -= 1
                    if depth == 0:
                        break
                i += 1
            value = block[start:i]
            i += 1  # skip closing }
        elif block[i] == '"':
            i += 1
            start = i
            while i < len(block) and block[i] != '"':
                if block[i] == "\\" and i + 1 < len(block):
                    i += 2
                    continue
                i += 1
            value = block[start:i]
            i += 1  # skip closing "
        else:
            # Bare token (year=2020, etc).
            start = i
            while i < len(block) and block[i] not in " \t\n\r,":
                i += 1
            value = block[start:i]
        fields[name] = value
    return fields


def format_authors(raw):
    """Collapse the author field to `First~Author~et~al.` form."""
    if not raw:
        return ""
    # Authors are joined by " and " in bibtex.
    authors = [a.strip() for a in raw.split(" and ")]
    if not authors:
        return ""
    first = authors[0]
    # bibtex author shapes:
    #   "Lewis, Patrick"   → "P.~Lewis"
    #   "Patrick Lewis"    → "P.~Lewis"
    if "," in first:
        last, first_names = [s.strip() for s in first.split(",", 1)]
    else:
        parts = first.split()
        last = parts[-1]
        first_names = " ".join(parts[:-1])
    initials = "".join(p[0] + "." for p in first_names.split() if p)
    formatted_first = f"{initials}~{last}" if initials else last
    if len(authors) == 1:
        return formatted_first
    return f"{formatted_first} et al."


def venue_year(fields):
    """Best-effort `<venue> <year>` line."""
    venue = (
        fields.get("booktitle")
        or fields.get("journal")
        or fields.get("publisher")
        or fields.get("howpublished")
        or ""
    )
    venue = venue.strip()
    year = fields.get("year", "").strip()
    if venue and year:
        return f"{venue} {year}"
    return venue or year


def format_bibitem(entry):
    key = entry["key"]
    fields = entry["fields"]
    title = fields.get("title", "").strip()
    authors = format_authors(fields.get("author", ""))
    vy = venue_year(fields)
    note = fields.get("note", "").strip()
    url = fields.get("url", "").strip()

    lines = [f"\\bibitem{{{key}}}"]
    parts = []
    if authors:
        parts.append(authors + ",")
    if title:
        parts.append(f"\\emph{{{title}}},")
    if vy:
        parts.append(vy + ".")
    if note:
        parts.append(f"({note}).")
    if url and not note and not vy:
        # Fall back to URL when nothing else identifies the venue
        # (e.g. raw misc citations).
        parts.append(f"\\url{{{url}}}.")
    lines.append(" ".join(parts).strip())
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", required=True, help="Output .tex path")
    parser.add_argument("--bib", action="append", required=True, help="One input .bib file (single entry each)")
    args = parser.parse_args()

    entries = []
    for bib_path in args.bib:
        text = Path(bib_path).read_text()
        entry = parse_entry(text)
        if not entry:
            print(f"WARN: could not parse {bib_path} as a bibtex entry", file=sys.stderr)
            continue
        entries.append(entry)

    # Stable ordering: sort by key so the rendered bibliography is
    # deterministic regardless of bib_deps order.
    entries.sort(key=lambda e: e["key"])

    out_lines = ["\\begin{thebibliography}{99}", ""]
    for entry in entries:
        out_lines.append(format_bibitem(entry))
        out_lines.append("")
    out_lines.append("\\end{thebibliography}")

    Path(args.out).write_text("\n".join(out_lines))


if __name__ == "__main__":
    main()
