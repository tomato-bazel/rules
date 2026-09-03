"""Runtime helper for `playwright_chrome_py_test`.

Imported by user tests as:

    from rules_chrome_playwright import chrome_context

…and used as a context manager:

    with chrome_context() as ctx:
        page = ctx.new_page()
        page.goto("https://example.com")
        assert page.title() != ""

The macro wires three env vars into the underlying py_test:

| Env var                    | Meaning                                                                  |
| -------------------------- | ------------------------------------------------------------------------ |
| `RULES_CHROME_PATH`        | Absolute path to the @chrome launcher inside test runfiles.              |
| `RULES_CHROME_PROFILE_REL` | Workspace-relative user-data-dir path. Only set in `workspace` mode.     |
| `RULES_CHROME_HEADFUL`     | `"1"` if the macro was given `headless = False`; else unset (headless).  |

The helper always uses `launch_persistent_context` so the same call site
works in both ephemeral and workspace modes — only the underlying dir
changes. Consumers wanting full control can read these env vars directly.
"""

from __future__ import annotations

import contextlib
import os
import pathlib
import tempfile

from playwright.sync_api import sync_playwright

_CHROME_PATH_ENV = "RULES_CHROME_PATH"
_PROFILE_REL_ENV = "RULES_CHROME_PROFILE_REL"
_HEADFUL_ENV = "RULES_CHROME_HEADFUL"

# Flags every automation run almost always wants. Same set as chrome_run's
# defaults, minus chrome flags that Playwright sets itself.
_DEFAULT_ARGS = (
    "--disable-dev-shm-usage",
    "--no-sandbox",
    "--disable-gpu",
)


def _resolve_profile_dir(stack: contextlib.ExitStack) -> str:
    rel = os.environ.get(_PROFILE_REL_ENV)
    if rel:
        ws = os.environ.get("BUILD_WORKSPACE_DIRECTORY")
        if not ws:
            raise RuntimeError(
                "rules_chrome_playwright: user_data_dir_mode='workspace' requires "
                "`bazel run` (BUILD_WORKSPACE_DIRECTORY must be set)."
            )
        path = pathlib.Path(ws) / rel
        path.mkdir(parents=True, exist_ok=True)
        return str(path)

    # Ephemeral: TEST_TMPDIR if available (sandbox-cleaned), else system tmp.
    base = os.environ.get("TEST_TMPDIR")
    return stack.enter_context(
        tempfile.TemporaryDirectory(prefix="rules_chrome_profile_", dir=base),
    )


@contextlib.contextmanager
def chrome_context(**launch_kwargs):
    """Yield a Playwright BrowserContext bound to rules_chrome's chrome.

    Uses `launch_persistent_context` against an ephemeral or workspace
    user-data-dir, depending on which mode the macro selected.

    Extra keyword arguments are forwarded to Playwright's
    `launch_persistent_context`. `args` is merged with the rules_chrome
    automation defaults (consumer-supplied args win).
    """
    chrome_path = os.environ.get(_CHROME_PATH_ENV)
    if not chrome_path:
        raise RuntimeError(
            f"rules_chrome_playwright: {_CHROME_PATH_ENV} is not set. "
            "Use the playwright_chrome_py_test macro from "
            "@rules_chrome//chrome/playwright:py.bzl to wire it.",
        )
    headless = os.environ.get(_HEADFUL_ENV) != "1"
    user_args = launch_kwargs.pop("args", [])
    args = list(_DEFAULT_ARGS) + list(user_args)

    with contextlib.ExitStack() as stack:
        profile = _resolve_profile_dir(stack)
        p = stack.enter_context(sync_playwright())
        ctx = p.chromium.launch_persistent_context(
            user_data_dir=profile,
            executable_path=chrome_path,
            headless=headless,
            args=args,
            **launch_kwargs,
        )
        try:
            yield ctx
        finally:
            ctx.close()
