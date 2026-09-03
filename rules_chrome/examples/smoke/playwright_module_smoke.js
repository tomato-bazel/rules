// Smoke for `playwright_chrome_js_test` (ephemeral mode).
//
// Uses the rules_chrome_playwright helper — the macro injects the
// helper's runfiles path through RULES_CHROME_PLAYWRIGHT_HELPER, and
// the helper consumes RULES_CHROME_PATH + profile env vars to launch
// Playwright via launchPersistentContext.

const path = require('node:path');

// $(rootpath) gives a workspace-relative path; resolve against cwd
// (the test's runfiles root under aspect_rules_js) for require().
const { withChromeContext } = require(
  path.resolve(process.env.RULES_CHROME_PLAYWRIGHT_HELPER),
);

withChromeContext(async (ctx) => {
  const page = await ctx.newPage();
  await page.goto('about:blank');

  const computed = await page.evaluate(() => 1 + 41);
  if (computed !== 42) {
    console.error(`playwright_module_smoke: bad JS eval: ${computed}`);
    process.exit(1);
  }

  const ua = await page.evaluate(() => navigator.userAgent);
  if (!ua.includes('Chrome') && !ua.includes('HeadlessChrome')) {
    console.error(`playwright_module_smoke: unexpected UA: ${ua}`);
    process.exit(2);
  }

  console.log(`playwright_module_smoke (js) OK: UA=${ua}`);
}).catch((err) => {
  console.error('playwright_module_smoke: uncaught error:', err);
  process.exit(3);
});
