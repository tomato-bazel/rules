"""Smoke for `playwright_chrome_py_test` (ephemeral mode).

Uses the rules_chrome_playwright helper — no environment-variable
plumbing in the test body. The macro wires chrome path + a tmpdir
profile through env vars; the helper consumes them and exposes a
Playwright `BrowserContext` via `launch_persistent_context`.
"""

import sys

from rules_chrome_playwright import chrome_context


def main() -> int:
    with chrome_context() as ctx:
        page = ctx.new_page()
        page.goto("about:blank")

        if page.evaluate("1 + 41") != 42:
            print("playwright_module_smoke: bad JS eval", file=sys.stderr)
            return 1

        ua = page.evaluate("navigator.userAgent")
        if "Chrome" not in ua and "HeadlessChrome" not in ua:
            print(f"playwright_module_smoke: unexpected UA: {ua}", file=sys.stderr)
            return 2

        print(f"playwright_module_smoke (py) OK: UA={ua}")
        return 0


if __name__ == "__main__":
    sys.exit(main())
