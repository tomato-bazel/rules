"""Playwright (Node) wrappers for rules_chrome.

Exports `playwright_chrome_js_test`, a thin macro over `js_test`
(`aspect_rules_js`) that wires `@chrome` into the test's runfiles and
exposes a Bazel-managed user-data-dir through env vars. The runtime
helper at `@rules_chrome//chrome/playwright:rules_chrome_playwright.js`
reads those env vars and returns a Playwright `BrowserContext` via
`launchPersistentContext`.

Consumers bring their own `playwright` npm dep (so the version isn't
pinned by rules_chrome). The typical layout:

    bazel_dep(name = "rules_chrome", version = "...")
    bazel_dep(name = "aspect_rules_js", version = "...")
    bazel_dep(name = "rules_nodejs", version = "...")

    node = use_extension("@rules_nodejs//nodejs:extensions.bzl", "node")
    node.toolchain(node_version = "22.11.0")

    npm = use_extension("@aspect_rules_js//npm:extensions.bzl", "npm")
    npm.npm_translate_lock(
        name = "my_npm",
        pnpm_lock = "//:pnpm-lock.yaml",  # must include playwright
    )
    use_repo(npm, "my_npm")

    chrome = use_extension("@rules_chrome//chrome:extensions.bzl", "chrome")
    use_repo(chrome, "chrome", "chromedriver")

In your BUILD.bazel:

    load("@rules_chrome//chrome/playwright:js.bzl", "playwright_chrome_js_test")
    load("@my_npm//:defs.bzl", "npm_link_all_packages")

    npm_link_all_packages(name = "node_modules")

    playwright_chrome_js_test(
        name = "browser_test",
        entry_point = "browser_test.js",
        data = [":node_modules/playwright"],
    )

Then in `browser_test.js`:

    const { withChromeContext } = require(process.env.RULES_CHROME_PLAYWRIGHT_HELPER);

    withChromeContext(async (ctx) => {
        const page = await ctx.newPage();
        await page.goto('about:blank');
        if (await page.evaluate(() => 1 + 1) !== 2) process.exit(1);
    });
"""

load("@aspect_rules_js//js:defs.bzl", "js_test")
load("@bazel_skylib//rules:copy_file.bzl", "copy_file")

_DEFAULT_USER_DATA_DIR_PREFIX = ".cache/rules_chrome_playwright"

def playwright_chrome_js_test(
        name,
        entry_point,
        user_data_dir_mode = "ephemeral",
        user_data_dir = "",
        headless = True,
        data = None,
        env = None,
        env_inherit = None,
        **kwargs):
    """Define a Node test that drives Chrome for Testing through Playwright.

    Args:
        name: Test target name.
        entry_point: Path to the JS file to execute. The script reads the
            helper's runfiles path from `RULES_CHROME_PLAYWRIGHT_HELPER`.
        user_data_dir_mode: One of `"ephemeral"` (fresh per test, default —
            cleaned by Bazel's sandbox via `$TEST_TMPDIR`) or `"workspace"`
            (persistent under `$BUILD_WORKSPACE_DIRECTORY/<user_data_dir>`).
            `"workspace"` mode requires `bazel run` — Bazel's test sandbox
            doesn't set `BUILD_WORKSPACE_DIRECTORY`, so `bazel test` will
            fail at runtime.
        user_data_dir: Workspace-relative profile path for `workspace` mode.
            Defaults to `.cache/rules_chrome_playwright/<name>`.
        headless: Whether to run chrome in headless mode (default True).
        data: Extra js_test data. `@chrome`, the helper JS file, and any
            `node_modules` deps the consumer adds get appended. The
            `playwright` npm package (`:node_modules/playwright`) must be
            included here (consumer-supplied).
        env: Extra env vars. The macro adds `RULES_CHROME_PATH`,
            `RULES_CHROME_PLAYWRIGHT_HELPER`, `RULES_CHROME_PROFILE_REL`
            (workspace mode only), and `RULES_CHROME_HEADFUL` (when
            `headless = False`).
        env_inherit: Extra env vars to inherit from the host. `PATH` and
            `HOME` are inherited by default — Playwright needs both.
        **kwargs: Forwarded to js_test.
    """
    if user_data_dir_mode not in ("ephemeral", "workspace"):
        fail("playwright_chrome_js_test: user_data_dir_mode must be 'ephemeral' " +
             "or 'workspace' (got %r)" % user_data_dir_mode)

    # The helper has to live in the *consumer's* package at runtime so
    # Node's module resolution walks up to the consumer's node_modules
    # tree (where the playwright npm package lives). Copy it in via
    # `copy_file`; the copied target becomes the data dep + the
    # `RULES_CHROME_PLAYWRIGHT_HELPER` env points at the copy.
    helper_copy_name = "_" + name + "_rules_chrome_playwright.js"
    copy_file(
        name = "_" + name + "_helper_copy",
        src = "@rules_chrome//chrome/playwright:rules_chrome_playwright.js",
        out = helper_copy_name,
        allow_symlink = True,
    )

    final_env = dict(env or {})
    final_env["RULES_CHROME_PATH"] = "$(rootpath @chrome//:chrome)"
    final_env["RULES_CHROME_PLAYWRIGHT_HELPER"] = "$(rootpath :%s)" % helper_copy_name
    if user_data_dir_mode == "workspace":
        rel = user_data_dir or (_DEFAULT_USER_DATA_DIR_PREFIX + "/" + name)
        final_env["RULES_CHROME_PROFILE_REL"] = rel
    if not headless:
        final_env["RULES_CHROME_HEADFUL"] = "1"

    final_env_inherit = list(env_inherit or [])
    for needed in ("PATH", "HOME"):
        if needed not in final_env_inherit:
            final_env_inherit.append(needed)

    js_test(
        name = name,
        entry_point = entry_point,
        data = (data or []) + [
            "@chrome//:chrome",
            ":" + helper_copy_name,
        ],
        env = final_env,
        env_inherit = final_env_inherit,
        **kwargs
    )
