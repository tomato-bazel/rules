"""Workspace-mode coverage for rules_chrome_playwright.chrome_context.

`user_data_dir_mode = "workspace"` is intended for `bazel run` — Bazel
sets `BUILD_WORKSPACE_DIRECTORY` then, but not under `bazel test`. The
helper's workspace-mode code path is otherwise untested in CI.

This py_test fakes `BUILD_WORKSPACE_DIRECTORY` by pointing it at a
tempdir and re-invokes the helper; it then asserts:

1. The helper resolves the profile to `<fake_ws>/<RULES_CHROME_PROFILE_REL>`.
2. The profile dir survives after the BrowserContext closes (the
   defining trait of workspace mode — unlike ephemeral mode, the dir is
   *not* cleaned up by the helper).
3. Without `BUILD_WORKSPACE_DIRECTORY`, the helper raises a clear
   RuntimeError instead of silently misbehaving.
"""

from __future__ import annotations

import os
import pathlib
import sys
import tempfile

from rules_chrome_playwright import chrome_context


def _exercise_workspace_mode() -> str:
    with tempfile.TemporaryDirectory(prefix="fake_ws_") as fake_ws:
        # Replicate what `bazel run` would set, in addition to the env
        # vars the macro already set on this py_test.
        os.environ["BUILD_WORKSPACE_DIRECTORY"] = fake_ws
        os.environ["RULES_CHROME_PROFILE_REL"] = "rc_test_profile"
        try:
            with chrome_context() as ctx:
                page = ctx.new_page()
                page.goto("about:blank")
                ua = page.evaluate("navigator.userAgent")
                if "Chrome" not in ua and "HeadlessChrome" not in ua:
                    raise AssertionError(f"unexpected UA in workspace mode: {ua}")
        finally:
            os.environ.pop("BUILD_WORKSPACE_DIRECTORY", None)
            os.environ.pop("RULES_CHROME_PROFILE_REL", None)

        profile = pathlib.Path(fake_ws) / "rc_test_profile"
        if not profile.is_dir():
            raise AssertionError(f"workspace profile dir not created at {profile}")
        # Chrome should have written *something* to the persistent profile —
        # at minimum a `Default/` subdir or a top-level `Local State` file.
        # Bazel's sandbox would clean an ephemeral profile under
        # $TEST_TMPDIR; a workspace dir we created ourselves persists.
        contents = list(profile.iterdir())
        if not contents:
            raise AssertionError(f"workspace profile dir is empty: {profile}")
        return f"workspace mode wrote {len(contents)} top-level entries"


def _exercise_missing_workspace_dir() -> str:
    # Helper sees RULES_CHROME_PROFILE_REL but no BUILD_WORKSPACE_DIRECTORY
    # — should fail loudly.
    os.environ.pop("BUILD_WORKSPACE_DIRECTORY", None)
    os.environ["RULES_CHROME_PROFILE_REL"] = "should_fail"
    try:
        with chrome_context():
            raise AssertionError("expected RuntimeError, helper opened a chrome anyway")
    except RuntimeError as e:
        if "BUILD_WORKSPACE_DIRECTORY" not in str(e):
            raise AssertionError(f"RuntimeError did not mention env var: {e}") from None
        return "missing-workspace error path raised expected RuntimeError"
    finally:
        os.environ.pop("RULES_CHROME_PROFILE_REL", None)


def main() -> int:
    try:
        msg = _exercise_workspace_mode()
        print(f"workspace_mode_smoke: {msg}")
        msg = _exercise_missing_workspace_dir()
        print(f"workspace_mode_smoke: {msg}")
    except AssertionError as e:
        print(f"workspace_mode_smoke FAILED: {e}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
