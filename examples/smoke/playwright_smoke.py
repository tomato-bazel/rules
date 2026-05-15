"""Playwright integration smoke for rules_chrome.

Launches Chrome for Testing via Playwright using `executable_path` pointing
at the @chrome launcher target, opens about:blank, evaluates a trivial JS
expression, and exits 0. Confirms three things end-to-end:

1. The launcher script (which exec's the real bundle binary) is well-behaved
   under subprocess spawn — Playwright's pipe-based CDP handshake survives
   the exec.
2. Chrome boots with the rules_chrome default automation flags, the headless
   flag, and the per-launch ephemeral user-data-dir wired by Playwright.
3. The chromedriver-companion-free CDP path (Playwright doesn't use
   chromedriver) works against our chrome build.
"""

from __future__ import annotations

import os
import sys

from playwright.sync_api import sync_playwright


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print("usage: playwright_smoke.py <path-to-chrome-launcher>", file=sys.stderr)
        return 2

    chrome_path = os.path.abspath(argv[1])
    if not os.access(chrome_path, os.X_OK):
        print(f"playwright_smoke: chrome launcher not executable: {chrome_path}", file=sys.stderr)
        return 3

    # Playwright manages its own ephemeral profile under TMPDIR when
    # `launch()` is used (vs. `launch_persistent_context()`). Don't pass
    # `--user-data-dir` ourselves — Playwright rejects it with a hint to
    # use the persistent-context API instead.
    with sync_playwright() as p:
        browser = p.chromium.launch(
            executable_path=chrome_path,
            headless=True,
            args=[
                # CI runners often lack /dev/shm size needed for chrome;
                # forcing tmpfs avoids "session storage init failed".
                "--disable-dev-shm-usage",
                "--no-sandbox",
                "--disable-gpu",
            ],
        )
        try:
            page = browser.new_page()
            page.goto("about:blank")

            # Run a trivial expression to confirm the JS context is live.
            computed = page.evaluate("1 + 41")
            if computed != 42:
                print(f"playwright_smoke: unexpected JS eval result: {computed!r}", file=sys.stderr)
                return 4

            ua = page.evaluate("navigator.userAgent")
            if "Chrome" not in ua and "HeadlessChrome" not in ua:
                print(f"playwright_smoke: unexpected userAgent: {ua!r}", file=sys.stderr)
                return 5

            print(f"playwright_smoke OK: 1+41={computed}, UA={ua}")
        finally:
            browser.close()

    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
