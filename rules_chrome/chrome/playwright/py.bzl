"""Playwright (Python) wrappers for rules_chrome.

Exports `playwright_chrome_py_test`, a thin macro over `py_test` that
wires `@chrome` into the test's runfiles and exposes a Bazel-managed
user-data-dir through env vars. The runtime helper at
`@rules_chrome//chrome/playwright:helper.py` reads those env vars and
returns a Playwright `BrowserContext` via `launch_persistent_context`.

Consumers bring their own `playwright` pip dep (so the version isn't
pinned by rules_chrome). The typical layout:

    bazel_dep(name = "rules_chrome", version = "...")
    bazel_dep(name = "rules_python", version = "...")

    pip = use_extension("@rules_python//python/extensions:pip.bzl", "pip")
    pip.parse(
        hub_name = "my_pip",
        python_version = "3.12",
        requirements_lock = "//:requirements_lock.txt",  # must include playwright
    )
    use_repo(pip, "my_pip")

    chrome = use_extension("@rules_chrome//chrome:extensions.bzl", "chrome")
    use_repo(chrome, "chrome", "chromedriver")

In your BUILD.bazel:

    load("@rules_chrome//chrome/playwright:py.bzl", "playwright_chrome_py_test")
    load("@my_pip//:requirements.bzl", "requirement")

    playwright_chrome_py_test(
        name = "browser_test",
        srcs = ["browser_test.py"],
        deps = [requirement("playwright")],
    )

Then in `browser_test.py`:

    from rules_chrome_playwright import chrome_context

    def test_x():
        with chrome_context() as ctx:
            page = ctx.new_page()
            page.goto("about:blank")
            assert page.evaluate("1+1") == 2
"""

load("@rules_python//python:py_test.bzl", "py_test")

_DEFAULT_USER_DATA_DIR_PREFIX = ".cache/rules_chrome_playwright"

def playwright_chrome_py_test(
        name,
        srcs,
        main = None,
        user_data_dir_mode = "ephemeral",
        user_data_dir = "",
        headless = True,
        deps = None,
        data = None,
        env = None,
        env_inherit = None,
        **kwargs):
    """Define a Python test that drives Chrome for Testing through Playwright.

    Args:
        name: Test target name.
        srcs: Python source files.
        main: Entry-point Python file. Defaults to `srcs[0]` when a single src
            is given, so `srcs = ["browser_test.py"]` Just Works regardless of
            the target's `name`.
        user_data_dir_mode: One of `"ephemeral"` (fresh per test, default —
            cleaned by Bazel's sandbox via `$TEST_TMPDIR`) or `"workspace"`
            (persistent under `$BUILD_WORKSPACE_DIRECTORY/<user_data_dir>`).
            `"workspace"` mode requires `bazel run` — Bazel's test sandbox
            doesn't set `BUILD_WORKSPACE_DIRECTORY`, so `bazel test` will
            fail at runtime.
        user_data_dir: Workspace-relative profile path for `workspace` mode.
            Defaults to `.cache/rules_chrome_playwright/<name>`.
        headless: Whether to run chrome in headless mode (default True).
        deps: Extra py_test deps. The `playwright` pip requirement must be
            included here (consumer-supplied). The helper py_library is added
            automatically.
        data: Extra py_test data. `@chrome` is added automatically.
        env: Extra env vars. The macro adds `RULES_CHROME_PATH`,
            `RULES_CHROME_PROFILE_REL` (workspace mode only), and
            `RULES_CHROME_HEADFUL` (when `headless = False`).
        env_inherit: Extra env vars to inherit from the host. `PATH` and `HOME`
            are inherited by default — Playwright needs both to spawn its
            bundled node driver.
        **kwargs: Forwarded to py_test.
    """
    if user_data_dir_mode not in ("ephemeral", "workspace"):
        fail("playwright_chrome_py_test: user_data_dir_mode must be 'ephemeral' " +
             "or 'workspace' (got %r)" % user_data_dir_mode)

    final_env = dict(env or {})
    final_env["RULES_CHROME_PATH"] = "$(rootpath @chrome//:chrome)"
    if user_data_dir_mode == "workspace":
        rel = user_data_dir or (_DEFAULT_USER_DATA_DIR_PREFIX + "/" + name)
        final_env["RULES_CHROME_PROFILE_REL"] = rel
    if not headless:
        final_env["RULES_CHROME_HEADFUL"] = "1"

    final_env_inherit = list(env_inherit or [])
    for needed in ("PATH", "HOME"):
        if needed not in final_env_inherit:
            final_env_inherit.append(needed)

    resolved_main = main
    if not resolved_main and len(srcs) == 1:
        resolved_main = srcs[0]

    py_test(
        name = name,
        srcs = srcs,
        main = resolved_main,
        deps = (deps or []) + ["@rules_chrome//chrome/playwright:py_helper"],
        data = (data or []) + ["@chrome//:chrome"],
        env = final_env,
        env_inherit = final_env_inherit,
        **kwargs
    )
