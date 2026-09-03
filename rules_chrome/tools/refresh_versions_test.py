"""Unit coverage for tools/refresh_versions.py — no-network paths only.

The download-and-hash path needs the internet, which we don't have under
Bazel's test sandbox. So this test covers the bits that are pure data
plumbing:

1. `_read_existing` round-trips with `_format_known_versions` — what we
   parse out of `known_versions.bzl` is what we'd write back.
2. New (version, sha) entries merge cleanly into an existing dict
   without dropping prior pins (the `--replace` codepath is the only
   way to drop them).
3. `_format_known_versions` emits version keys newest-first when they
   sort as semver-ish dotted tuples.
"""

from __future__ import annotations

import importlib.util
import os
import pathlib
import sys
import tempfile

# Locate refresh_versions.py via Bazel runfiles — the macro adds it as data.
_REFRESHER = os.environ["RULES_CHROME_REFRESHER_PY"]


def _load_module():
    spec = importlib.util.spec_from_file_location("refresh_versions", _REFRESHER)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def _assert(cond, msg):
    if not cond:
        raise AssertionError(msg)


def test_roundtrip(rv):
    """Parse a known_versions dict literal, format it back, parse again — equal."""
    original = {
        "chrome": {
            "148.0.7778.167": {
                "linux64": "a" * 64,
                "mac-arm64": "b" * 64,
            },
        },
        "chromedriver": {
            "148.0.7778.167": {
                "linux64": "c" * 64,
            },
        },
    }
    formatted = rv._format_known_versions(original)
    _assert(formatted.startswith("KNOWN_VERSIONS = {"), "missing header")
    _assert(formatted.endswith("}"), "missing trailer")

    with tempfile.TemporaryDirectory() as td:
        fake = pathlib.Path(td) / "known_versions.bzl"
        fake.write_text(formatted + "\n")
        rv.KNOWN_VERSIONS_BZL = fake
        parsed = rv._read_existing()
    _assert(parsed == original, f"roundtrip mismatch:\nin:  {original}\nout: {parsed}")


def test_version_sort(rv):
    """Multiple versions should serialize newest-first."""
    multi = {
        "chrome": {
            "148.0.7778.167": {"linux64": "a" * 64},
            "149.0.7800.0": {"linux64": "b" * 64},
            "147.0.7700.99": {"linux64": "c" * 64},
        },
    }
    formatted = rv._format_known_versions(multi)
    idx = lambda s: formatted.index('"' + s + '"')
    _assert(
        idx("149.0.7800.0") < idx("148.0.7778.167") < idx("147.0.7700.99"),
        "versions not sorted newest-first:\n" + formatted,
    )


def test_merge_preserves_prior(rv):
    """Adding a new version doesn't drop existing pins."""
    prior = {
        "chrome": {"148.0.7778.167": {"linux64": "a" * 64}},
        "chromedriver": {"148.0.7778.167": {"linux64": "b" * 64}},
    }
    new = {
        "chrome": {"linux64": "c" * 64},
        "chromedriver": {"linux64": "d" * 64},
    }
    # Same merge logic as main(): existing[binary][new_version] = per_platform
    for binary, per_platform in new.items():
        prior.setdefault(binary, {})["149.0.7800.0"] = per_platform

    formatted = rv._format_known_versions(prior)
    _assert('"148.0.7778.167"' in formatted, "prior chrome 148 pin dropped")
    _assert('"149.0.7800.0"' in formatted, "new chrome 149 pin missing")


def main() -> int:
    rv = _load_module()
    for fn in (test_roundtrip, test_version_sort, test_merge_preserves_prior):
        try:
            fn(rv)
            print(f"refresh_versions_test: {fn.__name__} OK")
        except AssertionError as e:
            print(f"refresh_versions_test: {fn.__name__} FAILED: {e}", file=sys.stderr)
            return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
