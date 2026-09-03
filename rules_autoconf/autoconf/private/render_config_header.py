#!/usr/bin/env python3
"""Render an autoconf-style config header.

Reads a template (typically `config.h.in` or `pg_config.h.in`) and emits
a concrete header by substituting two kinds of placeholders:

    `#undef VAR`        — if VAR is in the defines dict, replaced with
                          `#define VAR <value>`. Otherwise the line is
                          emitted unchanged (so consumers can still
                          `#ifdef VAR` against it).

    `@VAR@`             — replaced inline with the value from defines.
                          Used for autoconf's AC_SUBST substitution.

Probe results are merged into the defines dict. Each probe outputs a
file containing either '1' or '0'. For each `(probe_label, define_name)`
pair, the renderer reads the probe's result; if '1', sets
`<define_name>=1` in the defines dict, otherwise omits it (matches
autoconf's HAVE_* convention: define iff feature present).
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path


UNDEF_RE = re.compile(r"^\s*#undef\s+(\w+)\s*$")
SUBST_RE = re.compile(r"@(\w+)@")


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--template", required=True, help="path to config.h.in")
    p.add_argument("--defines", required=True,
                   help="JSON dict of {VAR: value} substitutions")
    p.add_argument("--probe", action="append", default=[],
                   metavar="DEFINE_NAME:PROBE_RESULT_FILE",
                   help="probe result mapping. The DEFINE_NAME is set to 1 " +
                        "in the defines dict iff the probe result file " +
                        "contains '1'. Repeatable.")
    p.add_argument("--out", required=True, help="path to write the rendered header")
    args = p.parse_args()

    defines = json.loads(args.defines)

    for spec in args.probe:
        name, _, path = spec.partition(":")
        if not name or not path:
            print(f"error: malformed --probe spec: {spec}", file=sys.stderr)
            return 1
        result = Path(path).read_text().strip()
        if result == "1":
            defines.setdefault(name, "1")

    template = Path(args.template).read_text().splitlines(keepends=True)
    output_lines = []

    for line in template:
        m = UNDEF_RE.match(line.rstrip("\n"))
        if m and m.group(1) in defines:
            var = m.group(1)
            output_lines.append(f"#define {var} {defines[var]}\n")
            continue
        # Apply @VAR@ substitutions for AC_SUBST-style fields.
        line = SUBST_RE.sub(
            lambda mm: str(defines[mm.group(1)]) if mm.group(1) in defines else mm.group(0),
            line,
        )
        output_lines.append(line)

    Path(args.out).write_text("".join(output_lines))
    return 0


if __name__ == "__main__":
    sys.exit(main())
