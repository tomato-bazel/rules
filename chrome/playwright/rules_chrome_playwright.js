// Runtime helper for `playwright_chrome_js_test`.
//
// The macro wires this module's runfiles path into the test through
// the `RULES_CHROME_PLAYWRIGHT_HELPER` env var; user tests load it via:
//
//     const { withChromeContext } = require(process.env.RULES_CHROME_PLAYWRIGHT_HELPER);
//
//     await withChromeContext(async (ctx) => {
//         const page = await ctx.newPage();
//         await page.goto('https://example.com');
//     });
//
// See rules_chrome_playwright.py's module docstring for the env-var
// contract — it's the same here, just expressed through process.env.

const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { chromium } = require('playwright');

const CHROME_PATH_ENV = 'RULES_CHROME_PATH';
const PROFILE_REL_ENV = 'RULES_CHROME_PROFILE_REL';
const HEADFUL_ENV = 'RULES_CHROME_HEADFUL';

const DEFAULT_ARGS = [
  '--disable-dev-shm-usage',
  '--no-sandbox',
  '--disable-gpu',
];

function resolveProfileDir() {
  const rel = process.env[PROFILE_REL_ENV];
  if (rel) {
    const ws = process.env.BUILD_WORKSPACE_DIRECTORY;
    if (!ws) {
      throw new Error(
        "rules_chrome_playwright: user_data_dir_mode='workspace' requires `bazel run`.",
      );
    }
    const p = path.join(ws, rel);
    fs.mkdirSync(p, { recursive: true });
    return p;
  }
  // Ephemeral: TEST_TMPDIR if available (sandbox-cleaned), else system tmp.
  const base = process.env.TEST_TMPDIR || os.tmpdir();
  return fs.mkdtempSync(path.join(base, 'rules_chrome_profile_'));
}

async function withChromeContext(userFn, options = {}) {
  const chromePath = process.env[CHROME_PATH_ENV];
  if (!chromePath) {
    throw new Error(
      `rules_chrome_playwright: ${CHROME_PATH_ENV} is not set. ` +
      'Use the playwright_chrome_js_test macro from ' +
      '@rules_chrome//chrome/playwright:js.bzl to wire it.',
    );
  }
  const headless = process.env[HEADFUL_ENV] !== '1';
  const profileDir = resolveProfileDir();
  const userArgs = options.args || [];
  const mergedOptions = {
    executablePath: chromePath,
    headless,
    ...options,
    args: [...DEFAULT_ARGS, ...userArgs],
  };

  const ctx = await chromium.launchPersistentContext(profileDir, mergedOptions);
  try {
    return await userFn(ctx);
  } finally {
    await ctx.close();
  }
}

module.exports = { withChromeContext };
