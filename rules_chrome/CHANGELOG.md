# Changelog

All notable changes to rules_chrome. The format is loosely
[Keep a Changelog](https://keepachangelog.com/) — version headers
mirror the published bazel-registry entries.

## 0.1.1 — fix: playwright macros loadable by consumers

- **Fix:** the `chrome/playwright` sub-module macros
  (`playwright_chrome_js_test` / `playwright_chrome_py_test`) were
  unusable outside this repo. Their `load()`s — and the
  `chrome/playwright` package's own `BUILD.bazel` — resolve
  `@aspect_rules_js` / `@rules_python` against **rules_chrome's** repo
  mapping, but both were declared `dev_dependency`, so a consumer hit
  `No repository visible as '@aspect_rules_js' from '@rules_chrome+'`
  merely by loading `js.bzl` or referencing any target in the package.
  They are now non-dev `bazel_dep`s.
- **Note (revises the 0.1.0 "zero-cost default" claim):** because a
  macro's `load()` resolves against the defining module, these deps
  must be visible to consumers, so the default `bazel_dep(rules_chrome)`
  now brings `aspect_rules_js` + `rules_python` into the module graph.
  The chrome/chromedriver **toolchain** still needs neither at fetch
  time; `rules_nodejs` remains dev-only (JS consumers bring their own
  node toolchain, per `docs/playwright_js.md`).

## 0.1.0 — initial release

- Initial release of Bazel rules for [Chrome for Testing]: a module
  extension that creates pinned `@chrome` + `@chromedriver` external
  repos, a `chrome_toolchain` (resolved via
  `@rules_chrome//chrome:toolchain_type`), and `chrome_run` /
  `chromedriver_run` launchers tuned for test automation.
- Optional `chrome/playwright` sub-module: `playwright_chrome_py_test`
  and `playwright_chrome_js_test` macros wire `@chrome` into a
  Playwright `launchPersistentContext` with a Bazel-managed
  `--user-data-dir`. The default `bazel_dep` stays a zero-cost
  chrome+chromedriver toolchain — `rules_python` / `aspect_rules_js`
  costs only apply when the sub-module is loaded.
- Pre-tag hardening: bumped pins, added workspace-mode + refresher
  tests, plus Playwright (py + node) smoke tests against the
  `@chrome` launcher.
