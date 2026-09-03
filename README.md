# tomato-bazel/rules

This repository is a **git / CI / release vehicle** for tomato-bazel `rules_*`
Bazel modules. It is **not** a Bazel module.

**Git repo ≠ Bazel module.** Each subdirectory is its own module, with its own
`MODULE.bazel`, its own version, and its own tests. Consumers keep writing:

```python
bazel_dep(name = "rules_jena", version = "0.3.2")
bazel_dep(name = "rules_rdf", version = "0.4.0")
bazel_dep(name = "rules_ci", version = "0.3.0")
```

Module names and versions are **not** lockstepped. A change that ships
`rules_jena` 0.3.3 does not bump `rules_rdf`. There is no repo-wide `0.0.1`.

Published module identity lives in each subdirectory's `MODULE.bazel`
(`module(name = ..., version = ...)`). This git repo only groups those trees,
runs path-filtered CI, and is the place tags are cut from.

The Bazel Central Registry and `registry.fastverk.com` (tomato-bazel/bazel-registry)
are **not** vendored here. They stay separate publishing surfaces.

## Layout

```
rules/
  README.md                 # this file — vehicle, not a module
  LEDGER.md                 # every include / exclude row + import provenance
  LICENSE                   # Apache-2.0 for vehicle docs/CI
  .github/workflows/ci.yml  # one path-filtered workflow
  tools/ci/                 # affected-module detection + ledger check
  rules_jena/               # module(name = "rules_jena", version = "0.3.2")
  rules_ci/                 # module(name = "rules_ci", version = "0.3.0")
  …
```

One subdirectory per module. Each imported tree keeps the source repo's
`MODULE.bazel` pins, license, and tests. See [LEDGER.md](LEDGER.md) for which
modules are in the tree today and which are follow-up imports.

Cluster 1 is imported (`rules_tomato`, `rules_ci`, `rules_github`,
`rules_rdf`, `rules_jena`). Cluster 2 adds schema/RDF dependents and the
docs stack `rules_tomato` already uses: `rules_jsonschema`, `rules_openapi`,
`rules_aip`, `rules_schema_org`, `rules_xsd`, `rules_markdown`,
`rules_mdbook`, `rules_readme`. Cluster 3 adds the JS/web stack:
`rules_bun`, `rules_nextjs`, `rules_vite`, `rules_eslint`, `rules_astro`,
`rules_storybook`, `rules_web`, `rules_chrome`. Cluster 4 adds the infra
stack: `rules_helm`, `rules_k8s`, `rules_cloudformation`,
`rules_docker_compose`, `rules_gitlab`, `rules_podman`. Cluster 5 adds
the IDE / Fastverk plugin + language spine: `rules_fastverk_plugin`,
`rules_agentic_ide`, `rules_vscode`, `rules_lean`, `rules_lang`,
`rules_postgres`, `rules_uv`. Remaining public `rules_*` modules stay
unchecked in the ledger. Source repos are not deleted or archived by
this work.

## Tags

Tags are **per module**, never repo-wide:

```
rules_<name>/vX.Y.Z
```

Example: `rules_jena/v0.3.3`.

Do not tag `v0.0.1` (or any other version) at the repository root. That would
imply a lockstep bump of every module.

GitHub's archive for a slash tag on this repo unpacks as
`rules-rules_<name>-vX.Y.Z/rules_<name>/`. That directory is the module root
`rels release` must `strip_prefix` to.

## How to cut a release for one module

Prefer the existing tomato-bazel machinery: `rules_ci` (`fastverk_project` /
`tomato_project`, `//release`, `//version`) plus
[bazel-registry `tools/rels`](https://github.com/tomato-bazel/bazel-registry/tree/main/tools/rels).
Do not invent a second release stack.

1. Change only that module's subdirectory. Leave other `MODULE.bazel` versions
   alone.
2. Bump **that** module's `module(version = ...)` and its `CHANGELOG.md`.
3. Merge to this repo's default branch.
4. Tag the merge commit:

   ```sh
   git tag rules_jena/v0.3.3
   git push origin rules_jena/v0.3.3
   ```

5. Publish the registry entry from a bazel-registry checkout with `rels`
   pointed at this tree (see below). Existing published versions keep resolving
   to the historical per-repo tags (`tomato-bazel/rules_jena` `v0.3.2`, etc.).
   Only **new** versions use this vehicle's tags.

```sh
# from a bazel-registry checkout; this repo is the workspaces root
rels --workspaces-root /path/to/tomato-bazel/rules release \
  --repo tomato-bazel/rules \
  --name rules_jena \
  --version 0.3.3 \
  --tag-prefix 'rules_jena/v' \
  --strip-prefix 'rules-rules_jena-v0.3.3/rules_jena'
```

`rels audit` / `rels bump` / `rels deps` already treat a directory with
`MODULE.bazel` as a module checkout. Passing `--workspaces-root` at **this**
repository turns the old multi-repo crawl into a path walk of this tree.
Do not vendor `rels` or the registry here; change discovery in bazel-registry
when that repo is ready, or keep passing `--workspaces-root`.

## Path-filtered CI

There is one workflow: [`.github/workflows/ci.yml`](.github/workflows/ci.yml).

A change under `rules_jena/` runs that module's tests (and buildifier), not
the whole tree. The detector is [`tools/ci/affected.py`](tools/ci/affected.py):
it diffs against the PR base (or the push before-SHA) and maps paths to
immediate children that contain `MODULE.bazel`.

| Change | What runs |
| --- | --- |
| `rules_jena/**` | `rules_jena` only |
| `rules_jena/**` and `rules_rdf/**` | those two modules |
| `.github/workflows/ci.yml` or `tools/ci/**` | every imported module |
| `README.md` / `LEDGER.md` only | ledger check, no module test matrix |

Per-module commands start from the existing `ci.yml` convention (the
`fastverk/.github` `reusable-rules-ci.yml` default is `bazel test //...`).
Overrides live in [`tools/ci/modules.json`](tools/ci/modules.json):
`rules_ci` matches its source workflow (`cargo test --workspace` in `translator/`, no bazel);
`rules_jena` runs `//jena/...` (examples/docs on HEAD need a newer `rules_rdf` than the preserved 0.3.0 pin);
`rules_github` `bazel build //...` (the `//docs` drift test is dirty on HEAD);
cluster 2 keeps source commands (`rules_markdown` / `rules_readme` `//examples/...`,
`rules_mdbook` `//docs/... //examples/...`);
`rules_openapi` skips bazel (`register_toolchains("//go:default_go_client_codegen_toolchain")`
points at a toolchain type still commented out on HEAD) and compiles the
Go plugin with `go test ./tools/openapi_to_go_client/`.
Cluster 3: `rules_bun` / `rules_vite` / `rules_chrome` `//docs/...`
(examples need a consumer `@npm` / Chrome runtime);
`rules_nextjs` `build //next/...` (`//docs` stardoc is missing a
`copy_to_directory.bzl` bzl_library);
`rules_storybook` `build //...` (`//docs` stardoc drift);
`rules_astro` no bazel (`aspect_rules_js` 2.1.3 cannot analyze).
Cluster 4 uses the default `bazel test //...` except `rules_docker_compose`
`//compose/... //examples/...` (`//docs` stardoc cannot parse a
`docker_compose_run` docstring on HEAD). Source `rules_gitlab` CI was red
only because that repo lacked the registry chain `vehicle.bazelrc` now
supplies.
Cluster 5: `rules_lean` / `rules_lang` `//docs/...` (source fast gates;
examples pull Lean toolchains / lake workspaces);
`rules_postgres` `//docs/... //examples/parse_smoke/...` (`meson_smoke`
needs host flex; `//lean` proofs stay out of the vehicle matrix);
`rules_uv` `//docs/...` (examples cargo-bootstrap the uv binary; source
CI is the broken cross-org reusable workflow);
`rules_vscode` default `bazel test //...`;
`rules_fastverk_plugin` default (no tests; exit 4 → `bazel build //...`);
`rules_agentic_ide` `//crates/...` (`//...` Jena SPARQL needs Java 17+
that the imported `rules_jena` 0.3.2 wrapper does not pick up).
A module with no test targets (`bazel test` exit 4) falls back to
`bazel build //...`. Buildifier runs as a warning so this PR does not rewrite
imported Starlark.

Bazel invocations pass [`tools/ci/vehicle.bazelrc`](tools/ci/vehicle.bazelrc),
the public half of `rules_tomato//bazelrc:common.bazelrc` (registry.tbzl.dev
then BCR). Source repos lifted that chain into a meta-repo `~/.bazelrc`; this
vehicle is that missing home. The registry itself is not vendored.

[`rules_tap`](https://github.com/tomato-bazel/rules_tap) is change-based test
selection **inside one Bazel workspace**. This git repo is many workspaces
(one `MODULE.bazel` per subdirectory), so tap does not fit at the vehicle
layer. Path filters select the workspace; that workspace's own tests run in
full. Individual modules may still depend on `rules_tap` after they are
imported.

## Provenance

Imports use `git subtree add` from each source repo's default branch. Source
history is not rewritten. Source repos are not deleted or archived here.

[LEDGER.md](LEDGER.md) records, for every include and exclude row: source
repo, default-branch commit SHA, `module(name=...)`, `module(version=...)`,
and whether the tree is imported.

## What this repo is not

- Not a single Bazel module and not a root `MODULE.bazel`.
- Not a lockstep version for the constellation.
- Not a vendor of BCR or `registry.fastverk.com`.
- Not a replacement for the existing `rules_*` GitHub repos in this PR.
