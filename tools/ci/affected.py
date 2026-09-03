#!/usr/bin/env python3
"""Map a git diff onto imported module directories for path-filtered CI.

A module is an immediate child of the vehicle root that contains MODULE.bazel.
Git repo ≠ Bazel module: this script never treats the vehicle root as a workspace.

Prints a GitHub Actions job output block:

    matrix=<json>
    any=true|false

If CI vehicle files change (.github/workflows/ci.yml, tools/ci/**), every
imported module is affected. README/LEDGER-only changes affect none.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
VEHICLE_FORCE_ALL_PREFIXES = (
    ".github/workflows/ci.yml",
    "tools/ci/",
    # Shared registry-chain flags; a change here affects every module job.
)


def run(args: list[str]) -> str:
    return subprocess.check_output(args, cwd=ROOT, text=True).strip()


def imported_modules() -> list[str]:
    names = []
    for child in sorted(ROOT.iterdir()):
        if child.is_dir() and (child / "MODULE.bazel").is_file():
            names.append(child.name)
    return names


def load_overrides() -> dict:
    path = Path(__file__).with_name("modules.json")
    data = json.loads(path.read_text())
    return {k: v for k, v in data.items() if not k.startswith("_")}


def changed_files(base: str, head: str) -> list[str]:
    if not base or set(base) == {"0"}:
        # New branch / empty before SHA: treat as vehicle-wide so the first
        # push still exercises imported modules.
        return ["tools/ci/affected.py"]
    try:
        out = run(["git", "diff", "--name-only", f"{base}...{head}"])
    except subprocess.CalledProcessError:
        out = run(["git", "diff", "--name-only", base, head])
    return [line for line in out.splitlines() if line]


def affected(modules: list[str], files: list[str]) -> list[str]:
    if any(
        f == p.rstrip("/") or f.startswith(p)
        for f in files
        for p in VEHICLE_FORCE_ALL_PREFIXES
    ):
        return list(modules)
    hit = []
    for name in modules:
        prefix = name + "/"
        if any(f == name or f.startswith(prefix) for f in files):
            hit.append(name)
    return hit


OS_RUNNERS = ("ubuntu-latest", "macos-latest")


def matrix_rows(name: str, overrides: dict) -> list[dict]:
    ov = overrides.get(name, {})
    extra = ov.get("extra") or []
    common = {
        "module": name,
        "bazel": ov.get("bazel", "test //... --test_output=errors"),
    }
    if extra:
        # One extra command is enough for the first cluster (rules_ci cargo).
        common["extra_cmd"] = extra[0]["cmd"]
        common["extra_workdir"] = extra[0].get("workdir", ".")
    else:
        common["extra_cmd"] = ""
        common["extra_workdir"] = "."
    # rules_tomato's in-tree .bazelrc points at a missing cred-helper binary;
    # vehicle.bazelrc already has the public registry chain.
    common["noworkspace_rc"] = "true" if ov.get("noworkspace_rc") else "false"
    return [{**common, "os": os_name} for os_name in OS_RUNNERS]


def resolve_range() -> tuple[str, str]:
    head = os.environ.get("AFFECTED_HEAD") or os.environ.get("GITHUB_SHA") or "HEAD"
    base = os.environ.get("AFFECTED_BASE") or ""
    if not base:
        event = os.environ.get("GITHUB_EVENT_NAME", "")
        if event == "pull_request":
            base = os.environ.get("GITHUB_BASE_SHA") or os.environ.get(
                "AFFECTED_PR_BASE", "origin/main"
            )
        else:
            base = os.environ.get("GITHUB_EVENT_BEFORE", "")
    return base, head


def main() -> int:
    modules = imported_modules()
    overrides = load_overrides()
    if os.environ.get("AFFECTED_ALL") == "1":
        names = modules
    else:
        base, head = resolve_range()
        files = changed_files(base, head)
        names = affected(modules, files)
    rows = [row for n in names for row in matrix_rows(n, overrides)]
    # Entire matrix object is `{include: [...]}` so OS is per-row, not a
    # broken cartesian with a second axis.
    payload = {"include": rows}
    any_modules = "true" if rows else "false"
    if os.environ.get("GITHUB_OUTPUT"):
        with open(os.environ["GITHUB_OUTPUT"], "a", encoding="utf-8") as fh:
            fh.write(f"any={any_modules}\n")
            fh.write(f"matrix={json.dumps(payload)}\n")
    else:
        print(json.dumps({"any": any_modules, "matrix": payload, "modules": modules}, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
