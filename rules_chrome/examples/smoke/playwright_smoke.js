// Playwright (Node) integration smoke for rules_chrome.
//
// Mirror of playwright_smoke.py — launches Chrome for Testing via the
// @chrome launcher target through Playwright's Node bindings, opens
// about:blank, evaluates a trivial JS expression, exits 0.
//
// Confirms the launcher works under Playwright's *Node* subprocess
// spawn (different code path from the Python driver — Playwright Node
// is the primary implementation; Python wraps it via stdio).

const path = require('node:path');
const { chromium } = require('playwright');

async function main(argv) {
  if (argv.length !== 1) {
    console.error('usage: node playwright_smoke.js <path-to-chrome-launcher>');
    process.exit(2);
  }

  const chromePath = path.resolve(argv[0]);

  // Playwright manages its own ephemeral profile when launch() is used.
  // Don't pass --user-data-dir ourselves — Playwright rejects it.
  const browser = await chromium.launch({
    executablePath: chromePath,
    headless: true,
    args: [
      '--disable-dev-shm-usage',
      '--no-sandbox',
      '--disable-gpu',
    ],
  });

  try {
    const page = await browser.newPage();
    await page.goto('about:blank');

    const computed = await page.evaluate(() => 1 + 41);
    if (computed !== 42) {
      console.error(`playwright_smoke: unexpected JS eval result: ${computed}`);
      process.exit(4);
    }

    const ua = await page.evaluate(() => navigator.userAgent);
    if (!ua.includes('Chrome') && !ua.includes('HeadlessChrome')) {
      console.error(`playwright_smoke: unexpected userAgent: ${ua}`);
      process.exit(5);
    }

    console.log(`playwright_smoke (node) OK: 1+41=${computed}, UA=${ua}`);
  } finally {
    await browser.close();
  }
}

main(process.argv.slice(2)).catch((err) => {
  console.error('playwright_smoke: uncaught error:', err);
  process.exit(6);
});
