#!/usr/bin/env python3
"""Refresh providers/vfkit/private/known_versions.bzl from crc-org/vfkit.

Resolves a vfkit release (default: latest stable), reads the sha256 of
the signed universal `vfkit` asset, and rewrites the `KNOWN_VERSIONS`
map + `DEFAULT_VERSION`. Prefers the GitHub API's `digest` field (no
download); falls back to streaming + hashing.

Stdlib-only (CPython 3.8+). Set GITHUB_TOKEN / GH_TOKEN to raise the API
rate limit.

Usage:
    tools/refresh_versions.py                 # latest stable
    tools/refresh_versions.py --version 0.6.3 # a specific version
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sys
import urllib.request
from pathlib import Path
from typing import Optional

REPO_ROOT = Path(__file__).resolve().parent.parent
KNOWN_VERSIONS_BZL = REPO_ROOT / "providers" / "vfkit" / "private" / "known_versions.bzl"

REPO = "crc-org/vfkit"
API_LATEST = f"https://api.github.com/repos/{REPO}/releases/latest"
API_BY_TAG = f"https://api.github.com/repos/{REPO}/releases/tags/v{{version}}"
ASSET = "vfkit"  # the SIGNED universal binary (never `vfkit-unsigned`)


def _request(url: str) -> urllib.request.Request:
    headers = {"User-Agent": "rules_macvm-refresher", "Accept": "application/vnd.github+json"}
    token = os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN")
    if token:
        headers["Authorization"] = f"Bearer {token}"
    return urllib.request.Request(url, headers=headers)


def _http_json(url: str) -> dict:
    with urllib.request.urlopen(_request(url)) as resp:
        return json.loads(resp.read())


def _download_and_hash(url: str) -> str:
    print(f"   ... hashing {url}", file=sys.stderr)
    h = hashlib.sha256()
    with urllib.request.urlopen(_request(url)) as resp:
        while True:
            chunk = resp.read(1 << 20)
            if not chunk:
                break
            h.update(chunk)
    return h.hexdigest()


def _asset_sha256(release: dict) -> str:
    for asset in release.get("assets", []):
        if asset["name"] == ASSET:
            digest: Optional[str] = asset.get("digest")
            if digest and digest.startswith("sha256:"):
                return digest[len("sha256:"):]
            return _download_and_hash(asset["browser_download_url"])
    raise SystemExit(f"release has no asset named {ASSET!r}")


def _splice(src: str, version: str, sha: str) -> str:
    block = "\n".join([
        "KNOWN_VERSIONS = {",
        f'    "{version}": "{sha}",',
        "}",
    ])
    src, n = re.subn(r"^KNOWN_VERSIONS = \{.*?^\}", lambda _m: block, src, count=1, flags=re.DOTALL | re.MULTILINE)
    if n != 1:
        raise SystemExit("could not locate the KNOWN_VERSIONS block to replace")
    src, n = re.subn(r'^DEFAULT_VERSION = ".*?"', f'DEFAULT_VERSION = "{version}"', src, count=1, flags=re.MULTILINE)
    if n != 1:
        raise SystemExit("could not locate the DEFAULT_VERSION line to replace")
    return src


def main(argv: list) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n", 1)[0])
    parser.add_argument("--version", default=None, help="Pin a specific vfkit version. Default: latest stable.")
    args = parser.parse_args(argv)

    version = args.version
    if not version:
        version = _http_json(API_LATEST)["tag_name"].lstrip("v")
        print(f"-> latest stable {REPO} release is v{version}", file=sys.stderr)

    release = _http_json(API_BY_TAG.format(version=version))
    sha = _asset_sha256(release)

    src = KNOWN_VERSIONS_BZL.read_text()
    KNOWN_VERSIONS_BZL.write_text(_splice(src, version, sha))
    print(f"-> wrote {KNOWN_VERSIONS_BZL.relative_to(REPO_ROOT)}; vfkit pinned to {version}.", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
