# Changelog

## 0.2.0 — helm_template

- **`helm_template`** — render a packaged chart to a single manifest file, as a
  build action. `helm_chart` packages a chart WE author; this renders a chart
  SOMEONE ELSE published into something we can read, review, diff and gate.
  Opposite directions, and the second is what a consumer of a third-party chart
  actually needs.
- The point is that the output becomes an artifact rather than an event. `helm
  install` renders and applies in one motion, so what reached the cluster is
  knowable only afterwards by asking the cluster. Rendering to a file makes it
  reviewable BEFORE anything moves, byte-stable across rebuilds, and diffable
  against a live cluster with `rules_k8s`'s `k8s_diff`.
- Fully offline: the action has no network, so `chart` must be a self-contained
  `.tgz`. A chart with unvendored subchart dependencies fails loudly here rather
  than silently fetching them. Pin it with `http_file` + sha256 so the render is
  a pure function of committed inputs.
- `set` uses `--set-string` deliberately. Plain `--set` applies YAML type
  inference, so an image tag like `1.34` renders as a float and `true` becomes a
  bool. A value that must keep its type belongs in a values file.
- Attrs: `chart`, `values`, `set`, `release_name`, `namespace`, `include_crds`,
  `kube_version`, `api_versions`.
- Smoke test round-trips the example chart through `helm_chart` then
  `helm_template` and diff-tests the result, so a helm upgrade that perturbs the
  output fails a test rather than silently changing what would reach a cluster.
  The example template now reads `.Release.Name`/`.Release.Namespace` so the
  golden file actually proves those flags are plumbed — it did not before.


All notable changes to this module are documented here; this project adheres to
[Keep a Changelog](https://keepachangelog.com/) and [SemVer](https://semver.org/).

## [Unreleased]
