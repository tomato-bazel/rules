#!/usr/bin/env python3
"""Compile-test probe: tries to compile (and optionally link) a small C
program against the host toolchain. Writes a single-character result file:

    "1" — compile/link succeeded (feature available)
    "0" — compile/link failed (feature unavailable)

Used by `cc_check_header`, `cc_check_function`, etc. as the implementation
of autoconf-style host probing in Bazel-native form. The C source is
constructed on-the-fly from rule attrs so the probe is self-contained;
all the rule has to supply is `--mode`, the symbol/header, and any
required libraries.
"""

from __future__ import annotations

import argparse
import os
import subprocess
import sys
import tempfile


def _build_source(mode: str, *, header: str | None, symbol: str | None) -> str:
    if mode == "header":
        if not header:
            raise SystemExit("--header is required for mode=header")
        return f"#include <{header}>\nint main(void) {{ return 0; }}\n"
    if mode == "function":
        if not symbol:
            raise SystemExit("--symbol is required for mode=function")
        inc = f"#include <{header}>\n" if header else ""
        # Take the address of the symbol so the linker actually resolves it;
        # discarding via (void) makes it impossible for the optimizer to drop.
        return (
            f"{inc}"
            f"int main(void) {{\n"
            f"    extern void *_p;\n"
            f"    _p = (void *)&{symbol};\n"
            f"    return _p ? 0 : 0;\n"
            f"}}\n"
            f"void *_p;\n"
        )
    if mode == "symbol":
        if not symbol:
            raise SystemExit("--symbol is required for mode=symbol")
        inc = f"#include <{header}>\n" if header else ""
        # Use the symbol in a context that requires it (sizeof works for
        # both functions and #defined constants).
        return (
            f"{inc}"
            f"int main(void) {{\n"
            f"    return sizeof({symbol}) > 0 ? 0 : 0;\n"
            f"}}\n"
        )
    raise SystemExit(f"unknown mode: {mode}")


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--mode", required=True, choices=["header", "function", "symbol"])
    p.add_argument("--header", help="header to #include (e.g. string.h)")
    p.add_argument("--symbol", help="function name or symbol to probe")
    p.add_argument("--lib", action="append", default=[],
                   help="link library (added as -l<lib>). Repeatable.")
    p.add_argument("--cc", default=None,
                   help="compiler invocation. Defaults to $CC then 'cc'.")
    p.add_argument("--cflag", action="append", default=[],
                   help="extra compiler flag. Repeatable.")
    p.add_argument("--out", required=True, help="path to write result ('1' or '0')")
    p.add_argument("--logfile", help="if set, write the compile invocation + " +
                   "stderr to this path (useful for debugging probe failures).")
    args = p.parse_args()

    cc = args.cc or os.environ.get("CC", "cc")
    source = _build_source(args.mode, header=args.header, symbol=args.symbol)

    with tempfile.TemporaryDirectory() as tmp:
        src_path = os.path.join(tmp, "probe.c")
        out_obj = os.path.join(tmp, "probe.out")
        with open(src_path, "w") as f:
            f.write(source)

        cmd = [cc, src_path, "-o", out_obj] + args.cflag
        cmd.extend(f"-l{lib}" for lib in args.lib)

        result = subprocess.run(cmd, capture_output=True, text=True)
        success = result.returncode == 0

        if args.logfile:
            with open(args.logfile, "w") as lf:
                lf.write(f"CMD: {' '.join(cmd)}\n")
                lf.write(f"EXIT: {result.returncode}\n")
                lf.write("STDOUT:\n" + result.stdout + "\n")
                lf.write("STDERR:\n" + result.stderr + "\n")

    with open(args.out, "w") as f:
        f.write("1" if success else "0")
    return 0


if __name__ == "__main__":
    sys.exit(main())
