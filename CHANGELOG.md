# Changelog

All notable changes to rules_nextjs. The format is loosely
[Keep a Changelog](https://keepachangelog.com/) — version headers
mirror the published bazel-registry entries.

## 0.2.0 — next_dev + bundler selection

- Add a `next_dev` rule: a `bazel run`-launched Next.js dev server in
  the workspace tree (companion to the hermetic `next_build`).
- `next_build`: add a `bundler` attribute (`webpack` | `turbopack`) to
  select the Next.js bundler.
- `next_build`: two-action design with tsconfig / next.config rewrites;
  the next.config wrapper handles peer-dep visibility, workspace
  `transpilePackages`, and the `.ts` `extensionAlias`.
- New dependency: `aspect_bazel_lib` (2.22.5).

## 0.1.1 — hermeticity fixes for next_build

- Fix `BAZEL_BINDIR` propagation, pass workspace deps as explicit
  action inputs, and switch to `FilesToRunProvider` so `next build`
  runs cleanly inside the Bazel sandbox.

## 0.1.0 — initial release

- First cut of Bazel rules for [Next.js](https://nextjs.org/): a
  `next_build` rule that runs `next build` as a hermetic Bazel action
  with workspace deps as inputs and `.next/` as the declared output,
  plus a `NextBuildInfo` provider so downstream rules (deploy targets,
  `oci_image` wrappers, doc extractors) can consume builds.
