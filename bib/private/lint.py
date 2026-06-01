"""Cite-lint: verify every \\cite{key} in the .tex inputs has a
corresponding declared bib_dep.

Invoked by cite_lint_action. Reads --declared (a sorted-keys file)
+ --tex (one or more .tex paths) + --marker (an ok-file to touch
on success); fails the build with exit 1 on a missing citation.
With --warn-unused, also prints a warning for any declared key
that no .tex source cites (build does not fail).
"""

import argparse
import re
import sys
from pathlib import Path


CITE_RE = re.compile(r"\\cite[a-zA-Z]*\s*\{([^}]+)\}")


def extract_keys(tex_paths):
    cited = set()
    for path in tex_paths:
        text = Path(path).read_text(errors="replace")
        for match in CITE_RE.finditer(text):
            for key in match.group(1).split(","):
                key = key.strip()
                if key:
                    cited.add(key)
    return cited


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--declared", required=True, help="File of declared bib keys, one per line")
    parser.add_argument("--tex", action="append", required=True, help="A .tex source path")
    parser.add_argument("--marker", required=True, help="Touch this file on success")
    parser.add_argument("--warn-unused", action="store_true", help="Warn on declared-but-uncited keys")
    args = parser.parse_args()

    declared = set(
        line.strip()
        for line in Path(args.declared).read_text().splitlines()
        if line.strip()
    )
    cited = extract_keys(args.tex)

    missing = cited - declared
    unused = declared - cited

    if missing:
        print(
            "cite-lint: \\cite{} keys with no bib_deps entry:\n"
            + "\n".join(f"  - {k}" for k in sorted(missing)),
            file=sys.stderr,
        )
        print(
            "\nDeclared bib_deps keys (for reference):\n"
            + "\n".join(f"  - {k}" for k in sorted(declared)),
            file=sys.stderr,
        )
        sys.exit(1)

    if unused and args.warn_unused:
        print(
            "cite-lint: bib_deps declared but never cited:\n"
            + "\n".join(f"  - {k}" for k in sorted(unused)),
            file=sys.stderr,
        )

    Path(args.marker).touch()


if __name__ == "__main__":
    main()
