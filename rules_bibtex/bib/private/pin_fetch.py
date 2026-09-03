"""Fetch authoritative bibtex for an arXiv id or DOI and diff against
an inline bibtex string.

Used by the `pin_check` rule to verify that a paper's checked-in
inline bibtex matches the canonical source. Exits non-zero with a
diff on mismatch.

Both sources are free + public:
  - arXiv: GET https://arxiv.org/bibtex/<id>          (text/plain)
  - DOI:   GET https://api.crossref.org/works/<doi>/transform/application/x-bibtex

Normalization (because formatting differs between sources):
  - whitespace runs collapsed
  - field order ignored (we compare {field: value} dicts, not text)
  - bibtex key compared separately
  - case-insensitive field-name compare

Usage (one of `--arxiv-id` or `--doi` is required):
    pin_fetch.py --arxiv-id 2005.11401v4 --inline path/to/lewis2020rag.bib
    pin_fetch.py --doi 10.5555/3495724.3496517 --inline path/to/lewis2020rag.bib
"""

import argparse
import re
import sys
import urllib.error
import urllib.request
from pathlib import Path


# We reuse the bibtex parser from bib_to_bibitem.py via a small shim
# (sibling module import). When py_binary bundles both, the import
# works from the same package; when run by hand, the sys.path tweak
# below lets it find the sibling.
sys.path.insert(0, str(Path(__file__).parent))
from bib_to_bibitem import parse_entry, parse_fields  # noqa: E402


ARXIV_URL = "https://arxiv.org/bibtex/{arxiv_id}"
CROSSREF_URL = "https://api.crossref.org/works/{doi}/transform/application/x-bibtex"

USER_AGENT = "rules_bibtex pin_fetch (https://github.com/fastverk/rules_bibtex)"


def fetch(url):
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req, timeout=30) as resp:
        return resp.read().decode("utf-8", errors="replace")


def normalize(entry):
    """Return a comparable shape: lowercased field names + whitespace-
    collapsed values, ignoring entry-type case + the bibtex key
    (the key is verified separately so a mismatch surfaces cleanly).
    """
    if entry is None:
        return None
    norm = {
        "type": entry["type"].lower(),
        "key": entry["key"],
        "fields": {},
    }
    for name, value in entry["fields"].items():
        # Collapse internal whitespace runs to one space, strip ends.
        collapsed = re.sub(r"\s+", " ", value).strip()
        norm["fields"][name.lower()] = collapsed
    return norm


def diff_entries(authoritative, inline):
    """Yield human-readable diff lines."""
    if authoritative is None:
        yield "[FETCH] authoritative bibtex could not be parsed"
        return
    if inline is None:
        yield "[INLINE] checked-in bibtex could not be parsed"
        return
    if authoritative["type"] != inline["type"]:
        yield f"  entry type: authoritative=@{authoritative['type']} inline=@{inline['type']}"
    if authoritative["key"] != inline["key"]:
        yield f"  bibtex key: authoritative={authoritative['key']!r} inline={inline['key']!r}"
    auth_fields = authoritative["fields"]
    inline_fields = inline["fields"]
    for name in sorted(set(auth_fields) | set(inline_fields)):
        if name not in auth_fields:
            yield f"  field {name!r}: missing from authoritative (inline has {inline_fields[name]!r})"
        elif name not in inline_fields:
            yield f"  field {name!r}: missing from inline (authoritative has {auth_fields[name]!r})"
        elif auth_fields[name] != inline_fields[name]:
            yield f"  field {name!r} differs:"
            yield f"    authoritative: {auth_fields[name]!r}"
            yield f"    inline:        {inline_fields[name]!r}"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    src = parser.add_mutually_exclusive_group(required=True)
    src.add_argument("--arxiv-id", help="arXiv identifier (e.g. 2005.11401v4)")
    src.add_argument("--doi", help="DOI (e.g. 10.18653/v1/W13-2322)")
    parser.add_argument(
        "--inline",
        required=True,
        help="Path to the checked-in single-entry .bib file to compare against",
    )
    parser.add_argument(
        "--key",
        default="",
        help="Expected bibtex key (defaults to the inline file's key)",
    )
    args = parser.parse_args()

    if args.arxiv_id:
        url = ARXIV_URL.format(arxiv_id=args.arxiv_id)
        source_label = f"arxiv:{args.arxiv_id}"
    else:
        url = CROSSREF_URL.format(doi=args.doi)
        source_label = f"doi:{args.doi}"

    print(f"[pin] fetching {source_label} ← {url}", file=sys.stderr)
    try:
        text = fetch(url)
    except urllib.error.HTTPError as e:
        print(f"[pin] HTTP {e.code} fetching {url}: {e.reason}", file=sys.stderr)
        sys.exit(2)
    except Exception as e:  # noqa: BLE001
        print(f"[pin] fetch failed for {url}: {e}", file=sys.stderr)
        sys.exit(2)

    authoritative = normalize(parse_entry(text))
    inline = normalize(parse_entry(Path(args.inline).read_text()))

    diff_lines = list(diff_entries(authoritative, inline))
    if not diff_lines:
        print(f"[pin] OK: inline matches {source_label}", file=sys.stderr)
        sys.exit(0)

    print(
        f"[pin] DRIFT: inline diverges from authoritative {source_label}:",
        file=sys.stderr,
    )
    for line in diff_lines:
        print(line, file=sys.stderr)
    print(
        "\nAuthoritative bibtex (copy into the inline `bibtex = …` if you want to accept):",
        file=sys.stderr,
    )
    print(text, file=sys.stderr)
    sys.exit(1)


if __name__ == "__main__":
    main()
