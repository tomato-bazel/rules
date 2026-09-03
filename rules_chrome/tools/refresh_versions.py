#!/usr/bin/env python3
"""Refresh chrome/private/known_versions.bzl from the Chrome for Testing JSON API.

Pulls the requested channel (default: Stable) from the upstream
`last-known-good-versions-with-downloads.json` endpoint, downloads each
(binary, platform) zip, hashes it, and rewrites `known_versions.bzl` in
place. Zero non-stdlib deps — runs on any CPython 3.8+ without `pip
install`.

Usage:

    tools/refresh_versions.py                 # add the current Stable channel
    tools/refresh_versions.py --channel Beta  # pull Beta instead
    tools/refresh_versions.py --version 148.0.7778.167  # pin a specific build
    tools/refresh_versions.py --replace       # discard prior pins, write only the new ones

Invoke from the repo root. Stdlib-only, so it also runs cleanly inside
GitHub Actions without any setup step.
"""

from __future__ import annotations

import argparse
import ast
import hashlib
import json
import sys
import urllib.request
from pathlib import Path
from typing import Dict

REPO_ROOT = Path(__file__).resolve().parent.parent
KNOWN_VERSIONS_BZL = REPO_ROOT / "chrome" / "private" / "known_versions.bzl"

CHANNELS_URL = (
    "https://googlechromelabs.github.io/chrome-for-testing/"
    "last-known-good-versions-with-downloads.json"
)
VERSION_URL_TEMPLATE = (
    "https://googlechromelabs.github.io/chrome-for-testing/{version}.json"
)

# Binaries we manage. chrome-headless-shell is also published by upstream
# but most callers want the full chrome binary; adding it later is a one-line
# change here + a new repo rule in extensions.bzl.
BINARIES = ("chrome", "chromedriver")

# Platforms we manage. Order is preserved in the generated dict for stable diffs.
PLATFORMS = ("linux64", "mac-arm64", "mac-x64", "win32", "win64")


def _http_get(url: str) -> bytes:
    req = urllib.request.Request(url, headers={"User-Agent": "rules_chrome-refresher"})
    with urllib.request.urlopen(req) as resp:
        return resp.read()


def _fetch_version(args: argparse.Namespace) -> dict:
    if args.version:
        url = VERSION_URL_TEMPLATE.format(version=args.version)
        print(f"-> fetching version metadata: {url}", file=sys.stderr)
        return json.loads(_http_get(url))

    print(f"-> fetching channel metadata: {CHANNELS_URL}", file=sys.stderr)
    data = json.loads(_http_get(CHANNELS_URL))
    channels = data.get("channels", {})
    if args.channel not in channels:
        raise SystemExit(
            f"channel {args.channel!r} not found; available: {sorted(channels)}"
        )
    return channels[args.channel]


def _download_and_hash(url: str) -> str:
    print(f"   ... hashing {url}", file=sys.stderr)
    h = hashlib.sha256()
    req = urllib.request.Request(url, headers={"User-Agent": "rules_chrome-refresher"})
    with urllib.request.urlopen(req) as resp:
        while True:
            chunk = resp.read(1 << 20)  # 1 MiB
            if not chunk:
                break
            h.update(chunk)
    return h.hexdigest()


def _collect_hashes(meta: dict) -> Dict[str, Dict[str, str]]:
    """Return {binary: {platform: sha256_hex}} for the given version metadata."""
    out: Dict[str, Dict[str, str]] = {}
    downloads = meta.get("downloads", {})
    for binary in BINARIES:
        entries = {entry["platform"]: entry["url"] for entry in downloads.get(binary, [])}
        per_platform: Dict[str, str] = {}
        for platform in PLATFORMS:
            url = entries.get(platform)
            if not url:
                print(
                    f"   ! upstream has no {binary} for {platform}; skipping",
                    file=sys.stderr,
                )
                continue
            per_platform[platform] = _download_and_hash(url)
        if per_platform:
            out[binary] = per_platform
    return out


def _read_existing() -> Dict[str, Dict[str, Dict[str, str]]]:
    """Parse the current KNOWN_VERSIONS dict literal from known_versions.bzl.

    Returns {binary: {version: {platform: sha256}}}. Returns {} if the file
    doesn't exist or the dict is empty.
    """
    if not KNOWN_VERSIONS_BZL.exists():
        return {}
    src = KNOWN_VERSIONS_BZL.read_text()
    tree = ast.parse(src)
    for node in tree.body:
        if (
            isinstance(node, ast.Assign)
            and len(node.targets) == 1
            and isinstance(node.targets[0], ast.Name)
            and node.targets[0].id == "KNOWN_VERSIONS"
        ):
            return ast.literal_eval(node.value)
    return {}


def _format_known_versions(merged: Dict[str, Dict[str, Dict[str, str]]]) -> str:
    """Render the KNOWN_VERSIONS dict as the canonical Starlark literal."""
    lines = ["KNOWN_VERSIONS = {"]
    for binary in BINARIES:
        versions = merged.get(binary, {})
        if not versions:
            continue
        lines.append(f"    \"{binary}\": {{")
        # Sort versions descending — newest at top, easy to eyeball.
        for version in sorted(versions, key=_version_tuple, reverse=True):
            lines.append(f"        \"{version}\": {{")
            for platform in PLATFORMS:
                sha = versions[version].get(platform)
                if sha:
                    lines.append(f"            \"{platform}\": \"{sha}\",")
            lines.append("        },")
        lines.append("    },")
    lines.append("}")
    return "\n".join(lines)


def _version_tuple(v: str) -> tuple:
    try:
        return tuple(int(x) for x in v.split("."))
    except ValueError:
        return (0,)


def _write_known_versions(merged: Dict[str, Dict[str, Dict[str, str]]], default_version: str) -> None:
    known = _format_known_versions(merged)
    contents = f'''\
"""SHA-256 pins for prebuilt Chrome for Testing binaries.

Generated by `tools/refresh_versions.py`. Bumping a version means
running:

    tools/refresh_versions.py --version <X.Y.Z.W>

…which appends a new entry here. Unpinned versions still build
(warning emitted) but lose hermeticity. Always prefer pinning.
"""

# Map: binary -> version -> platform -> sha256.
{known}

# Upstream URL template. Common across both chrome + chromedriver; the
# tool name is interpolated as part of the path *and* the filename.
URL_TEMPLATE = (
    "https://storage.googleapis.com/chrome-for-testing-public/" +
    "{{version}}/{{platform}}/{{binary}}-{{platform}}.zip"
)

DEFAULT_VERSION = "{default_version}"
'''
    KNOWN_VERSIONS_BZL.parent.mkdir(parents=True, exist_ok=True)
    KNOWN_VERSIONS_BZL.write_text(contents)
    print(f"-> wrote {KNOWN_VERSIONS_BZL.relative_to(REPO_ROOT)}", file=sys.stderr)


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n", 1)[0])
    parser.add_argument(
        "--channel",
        default="Stable",
        help="Chrome release channel to pull (Stable/Beta/Dev/Canary). Ignored if --version is set.",
    )
    parser.add_argument(
        "--version",
        default=None,
        help="Pin a specific Chrome version (e.g. 148.0.7778.167). Overrides --channel.",
    )
    parser.add_argument(
        "--replace",
        action="store_true",
        help="Replace the existing KNOWN_VERSIONS map instead of merging into it.",
    )
    args = parser.parse_args(argv)

    meta = _fetch_version(args)
    version = meta["version"]
    print(f"-> resolving Chrome for Testing {version}", file=sys.stderr)

    new_hashes = _collect_hashes(meta)

    existing: Dict[str, Dict[str, Dict[str, str]]] = (
        {} if args.replace else _read_existing()
    )
    for binary, per_platform in new_hashes.items():
        existing.setdefault(binary, {})[version] = per_platform

    _write_known_versions(existing, default_version=version)
    print(f"-> done. Default version is now {version}.", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
