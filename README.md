# rules_fastverk

The fastverk **foundation** module — conventions + coordination on the
"how to build one target / one repo" axis. (Its sibling, `rules_ci`, owns the
project-orchestration axis: `fastverk_project` + release/versioning.)

Three things:

## 1. Convention macros — [`//fastverk:defs.bzl`](fastverk/defs.bzl)

- **`fastverk_mdbook`** — a brand-themed mdBook in one call: wraps
  `rules_mdbook`'s `mdbook_book` and stages `@brand//mdbook:theme` at the book's
  `theme/`, so every docs site is branded by construction.

  ```python
  load("@rules_fastverk//fastverk:defs.bzl", "fastverk_mdbook")
  fastverk_mdbook(name = "site")   # globs src/**/*.md, themes with @brand, -> site.tar.gz
  ```

  (More to follow: `fastverk_rust_library`, etc.)

## 2. The dependency BOM — [`//bom/versions.json`](bom/versions.json)

The canonical third-party + constellation versions. It's a **manifest** (data),
not transitive `bazel_dep`s — so consuming `rules_fastverk` doesn't drag the
whole constellation into your graph. The **`rels deps` ratchet** audits every
repo's `MODULE.bazel` against it and opens coordinated bumps; CI fails on drift.
This is how ~60 repos stay in sync without a monorepo (today they drift —
`bazel_skylib` 1.7.1↔1.8.2, `platforms` 0.0.10↔1.0.0, `rules_python`
0.40↔1.7↔2.0.1, …).

## 3. The shared `.bazelrc` — [`//bazelrc:common.bazelrc`](bazelrc/common.bazelrc)

The registry chain + flags, in one place, so they stop drifting. Repos
`try-import` it (the ratchet syncs a vendored copy).

## Status

v0.0.1 — macros + BOM + shared bazelrc scaffolded; `//fastverk:defs` builds.
Next: dogfood `fastverk_mdbook` in `fastverk/docs`, add `fastverk_rust_library`,
and implement the `rels deps` ratchet (audit + bump) against the BOM.
