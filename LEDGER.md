# Ledger

Provenance for every tomato-bazel `rules_*` include and every explicit exclude.
This file is the source of truth for what belongs in this git vehicle.

**Git repo ≠ Bazel module.** Importing a tree does not rename `module(name=...)`
and does not rewrite `module(version=...)`. SHAs below are the source default
branch (`main`) at ledger write / import time.

Status:

- `imported` — subdirectory present; SHA is the subtree-imported commit.
- `pending` — listed for a follow-up PR; SHA is source `main` HEAD when this
  row was written. Do not pretend these are in the tree.
- `excluded` — must not appear as a module directory here.

Imported via `git subtree add` (no squash) from each source `main` SHA:

- Cluster 1: `rules_tomato`, `rules_ci`, `rules_github`, `rules_rdf`, `rules_jena`.
- Cluster 2: `rules_jsonschema`, `rules_openapi`, `rules_aip`,
  `rules_schema_org`, `rules_xsd`, `rules_markdown`, `rules_mdbook`,
  `rules_readme`.
- Cluster 3: `rules_bun`, `rules_nextjs`, `rules_vite`, `rules_eslint`,
  `rules_astro`, `rules_storybook`, `rules_web`, `rules_chrome`.
- Cluster 4: `rules_helm`, `rules_k8s`, `rules_cloudformation`,
  `rules_docker_compose`, `rules_gitlab`, `rules_podman`.

## Includes (public tomato-bazel/rules_*)

| Module | Status | Source repo | Source SHA | `module(name)` | `module(version)` | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| rules_agentic_ide | pending | [tomato-bazel/rules_agentic_ide](https://github.com/tomato-bazel/rules_agentic_ide) | `f8741d360a6ae454cf63690c73f81b8daa44ef05` | rules_agentic_ide | 0.0.4 | |
| rules_aip | imported | [tomato-bazel/rules_aip](https://github.com/tomato-bazel/rules_aip) | `1c28e8c7ad38ea866ffc2b472aba644ffb3656a2` | rules_aip | 0.3.0 | cluster 2 |
| rules_astro | imported | [tomato-bazel/rules_astro](https://github.com/tomato-bazel/rules_astro) | `5625f86d3ab123b623264747bf47ba2e92270be0` | rules_astro | 0.0.1 | cluster 3; no LICENSE; HEAD cannot analyze (`aspect_rules_js` 2.1.3 / no `sh_test`) |
| rules_autoconf | pending | [tomato-bazel/rules_autoconf](https://github.com/tomato-bazel/rules_autoconf) | `82fdab99cf48b50931abc31febe98a8876d9a068` | rules_autoconf | 0.1.0 | |
| rules_beam | pending | [tomato-bazel/rules_beam](https://github.com/tomato-bazel/rules_beam) | `eebd9dc18e762e32a8f449ec9d704857ca28ad5f` | rules_beam | 0.0.2 | |
| rules_bibtex | pending | [tomato-bazel/rules_bibtex](https://github.com/tomato-bazel/rules_bibtex) | `83cb11ba5ffd0271aeca762f6d1aff0827b987a8` | rules_bibtex | 0.0.6 | |
| rules_bun | imported | [tomato-bazel/rules_bun](https://github.com/tomato-bazel/rules_bun) | `395372ea3639805131bcc6d63a0be3166c6a3aba` | rules_bun | 0.4.1 | cluster 3; still pins `rules_github` 0.1.1 |
| rules_cc_cross | pending | [tomato-bazel/rules_cc_cross](https://github.com/tomato-bazel/rules_cc_cross) | `41e338bc4a60b9fa7f4fa68c6f4a812793b82ac6` | rules_cc_cross | 0.1.0 | |
| rules_cc_host | pending | [tomato-bazel/rules_cc_host](https://github.com/tomato-bazel/rules_cc_host) | `526bf84f6b45bc557518686f363d5e23a4843a3f` | rules_cc_host | 0.1.0 | |
| rules_chrome | imported | [tomato-bazel/rules_chrome](https://github.com/tomato-bazel/rules_chrome) | `4ac1f8e8383fc9583d742514117d46e372fbf154` | rules_chrome | 0.1.1 | cluster 3; source `main` moved since the pending ledger SHA |
| rules_ci | imported | [tomato-bazel/rules_ci](https://github.com/tomato-bazel/rules_ci) | `2fc336a762dd33693ef63c5510b0d4935e079f41` | rules_ci | 0.3.0 | first cluster; project/release |
| rules_cloudformation | imported | [tomato-bazel/rules_cloudformation](https://github.com/tomato-bazel/rules_cloudformation) | `d16954abd5ae9613f82c1da00b6384159cd23058` | rules_cloudformation | 0.10.0 | cluster 4 |
| rules_docker_compose | imported | [tomato-bazel/rules_docker_compose](https://github.com/tomato-bazel/rules_docker_compose) | `b08f81148e8efd47c170e6379798f52ba215c3aa` | rules_docker_compose | 0.2.6 | cluster 4; source CI is the broken cross-org reusable workflow |
| rules_eslint | imported | [tomato-bazel/rules_eslint](https://github.com/tomato-bazel/rules_eslint) | `859add1992697a7f0b32b57a03535a4b6cb9ed8b` | rules_eslint | 0.1.0 | cluster 3 |
| rules_fastverk_plugin | pending | [tomato-bazel/rules_fastverk_plugin](https://github.com/tomato-bazel/rules_fastverk_plugin) | `51660e7e8352ba0cc23ad08fe45dae862376f71b` | rules_fastverk_plugin | 0.0.1 | no LICENSE in source |
| rules_github | imported | [tomato-bazel/rules_github](https://github.com/tomato-bazel/rules_github) | `c23109bba2638ff474071878feafd24b7917e12b` | rules_github | 0.1.2 | first cluster |
| rules_gitlab | imported | [tomato-bazel/rules_gitlab](https://github.com/tomato-bazel/rules_gitlab) | `7e88d1eee76bc3e53afa5236f5f42de90d6bb34f` | rules_gitlab | 0.3.4 | cluster 4; source CI red without registry.tbzl.dev (vehicle.bazelrc supplies it) |
| rules_graphviz | pending | [tomato-bazel/rules_graphviz](https://github.com/tomato-bazel/rules_graphviz) | `ea2c90c6e37b0f185063ddc3dad8b135a55c54da` | rules_graphviz | 0.2.0 | |
| rules_helm | imported | [tomato-bazel/rules_helm](https://github.com/tomato-bazel/rules_helm) | `75c9d32bee410616fe5e8998dabd2e84a31f37f4` | rules_helm | 0.2.0 | cluster 4; no source CI workflow |
| rules_huggingface | pending | [tomato-bazel/rules_huggingface](https://github.com/tomato-bazel/rules_huggingface) | `5a2d56dd82adf71a1f98cf9117e17498610dc5c2` | rules_huggingface | 0.0.4 | |
| rules_jena | imported | [tomato-bazel/rules_jena](https://github.com/tomato-bazel/rules_jena) | `dc0fff487ef5d4084a4ceb1a104e3ef1128e25b1` | rules_jena | 0.3.2 | first cluster |
| rules_jsonschema | imported | [tomato-bazel/rules_jsonschema](https://github.com/tomato-bazel/rules_jsonschema) | `c707ecd0dd8c6dfd5170038b64317b8d20b54138` | rules_jsonschema | 0.4.0 | cluster 2 |
| rules_k8s | imported | [tomato-bazel/rules_k8s](https://github.com/tomato-bazel/rules_k8s) | `c42aa0a5b0c3e71a3880e07d33f67f0cb8f2180a` | rules_k8s | 0.0.3 | cluster 4; no source CI workflow |
| rules_lang | pending | [tomato-bazel/rules_lang](https://github.com/tomato-bazel/rules_lang) | `dd9b9b61b5a4f8e6462d0aa2636b06d4ee03d09b` | rules_lang | 0.5.0 | |
| rules_lean | pending | [tomato-bazel/rules_lean](https://github.com/tomato-bazel/rules_lean) | `6abaa70b3b917304752719ae539c59eacdaa521c` | rules_lean | 0.7.0 | HEAD version; registry latest listed 0.6.2 |
| rules_lora | pending | [tomato-bazel/rules_lora](https://github.com/tomato-bazel/rules_lora) | `b0496fcff29858a0048e839467ebaf63660b3be3` | rules_lora | 0.1.4 | |
| rules_macvm | pending | [tomato-bazel/rules_macvm](https://github.com/tomato-bazel/rules_macvm) | `38d325b81cc66451787015d0f96a95b72e124ed7` | rules_macvm | 0.0.1 | |
| rules_markdown | imported | [tomato-bazel/rules_markdown](https://github.com/tomato-bazel/rules_markdown) | `19f7561452f379273fe5c13520f6e0984ba30f8e` | rules_markdown | 0.0.3 | cluster 2 |
| rules_mdbook | imported | [tomato-bazel/rules_mdbook](https://github.com/tomato-bazel/rules_mdbook) | `75ebacc6083f1e2ee0904badcdd5dc173bde5a9d` | rules_mdbook | 0.3.1 | cluster 2 |
| rules_meson | pending | [tomato-bazel/rules_meson](https://github.com/tomato-bazel/rules_meson) | `51e339cbd57550fdc99985928f46827fe3ce5aba` | rules_meson | 0.0.1 | |
| rules_nextjs | imported | [tomato-bazel/rules_nextjs](https://github.com/tomato-bazel/rules_nextjs) | `234de738a4400b8ecdc136076cd617a55b5e120a` | rules_nextjs | 0.3.0 | cluster 3; `//docs` stardoc missing `copy_to_directory.bzl` bzl_library |
| rules_openapi | imported | [tomato-bazel/rules_openapi](https://github.com/tomato-bazel/rules_openapi) | `00e3f8794dd1924a8f39c76bfa25e1ac6f31d58d` | rules_openapi | 0.4.0 | cluster 2; HEAD cannot `bazel test` (`go_client_codegen_toolchain_type` still reserved) |
| rules_podman | imported | [tomato-bazel/rules_podman](https://github.com/tomato-bazel/rules_podman) | `548ff53f9bb1879a735c7b34a361ffe1826d8e8b` | rules_podman | 0.0.2 | cluster 4 |
| rules_postgres | pending | [tomato-bazel/rules_postgres](https://github.com/tomato-bazel/rules_postgres) | `a471dc40cddd8c97e5f170e5e6c6658e85c4d13c` | rules_postgres | 0.12.0 | |
| rules_puml | pending | [tomato-bazel/rules_puml](https://github.com/tomato-bazel/rules_puml) | `80ed7791f91611fc23baa004cf9e6f92915b7c54` | rules_puml | 0.0.2 | |
| rules_rdf | imported | [tomato-bazel/rules_rdf](https://github.com/tomato-bazel/rules_rdf) | `949e6a2fb5fb2caa65fcf16264f7cb313b1f5c62` | rules_rdf | 0.4.0 | first cluster |
| rules_readme | imported | [tomato-bazel/rules_readme](https://github.com/tomato-bazel/rules_readme) | `855f2197077c1a0fac1476c0cd19c7bfa76f461b` | rules_readme | 0.0.3 | cluster 2 |
| rules_schema_org | imported | [tomato-bazel/rules_schema_org](https://github.com/tomato-bazel/rules_schema_org) | `1a9665c4cd76b4ecf8ef008594e89df3926b784c` | rules_schema_org | 0.0.3 | cluster 2 |
| rules_ssh_tui | pending | [tomato-bazel/rules_ssh_tui](https://github.com/tomato-bazel/rules_ssh_tui) | `9f973cb0d8338a8cc2328763706e05f762cc8234` | rules_ssh_tui | 0.0.5 | |
| rules_storybook | imported | [tomato-bazel/rules_storybook](https://github.com/tomato-bazel/rules_storybook) | `e4359d12ed3136ff59700935a16171fd6d51c54d` | rules_storybook | 0.2.0 | cluster 3; still pins `rules_bun` 0.3.0; `//docs` stardoc drift |
| rules_systemd | pending | [tomato-bazel/rules_systemd](https://github.com/tomato-bazel/rules_systemd) | `45d20b24c1906c541a7c336c931fc44af462091e` | rules_systemd | 0.0.1 | |
| rules_tap | pending | [tomato-bazel/rules_tap](https://github.com/tomato-bazel/rules_tap) | `3567697ede16e0378f6501ed32b7436c8f01a441` | rules_tap | 0.0.3 | public rules; private engine is `tap` (excluded) |
| rules_tectonic | pending | [tomato-bazel/rules_tectonic](https://github.com/tomato-bazel/rules_tectonic) | `ed693324ead9c0796442ffd4d9ad12b27f9cd01d` | rules_tectonic | 0.2.0 | |
| rules_tla | pending | [tomato-bazel/rules_tla](https://github.com/tomato-bazel/rules_tla) | `b39eb6fc672a67a7d40f1cd258d2eb3abc13f0a3` | rules_tla | 0.2.0 | |
| rules_tomato | imported | [tomato-bazel/rules_tomato](https://github.com/tomato-bazel/rules_tomato) | `6d3cc9fc181dbcc4cbe683d06422e5f20af2d956` | rules_tomato | 0.1.2 | first cluster; BOM + shared bazelrc |
| rules_uv | pending | [tomato-bazel/rules_uv](https://github.com/tomato-bazel/rules_uv) | `7a43b9b6878608aa91f23110b4dc3cb719ce8ef0` | rules_uv | 0.7.4 | |
| rules_vite | imported | [tomato-bazel/rules_vite](https://github.com/tomato-bazel/rules_vite) | `093dbdcaba31ec0de2d45fb1e6cce719a34fec59` | rules_vite | 0.1.1 | cluster 3 |
| rules_vscode | pending | [tomato-bazel/rules_vscode](https://github.com/tomato-bazel/rules_vscode) | `0099c257414fe8a69ed07db642810167e7d63a29` | rules_vscode | 0.0.2 | |
| rules_web | imported | [tomato-bazel/rules_web](https://github.com/tomato-bazel/rules_web) | `aefdb773bd1792ebbaa520e2d693ced233fdda35` | rules_web | 0.0.1 | cluster 3; no tests on HEAD |
| rules_xsd | imported | [tomato-bazel/rules_xsd](https://github.com/tomato-bazel/rules_xsd) | `b2d7f0fcb8256d45499517e559c95e96109b1001` | rules_xsd | 0.0.1 | cluster 2 |

## Follow-up import checklist

Unchecked rows are **not** in this tree. Import with `git subtree add` (no
squash) from the source default branch, then flip the row to `imported` and
set the SHA to the commit that landed.

- [x] rules_tomato
- [x] rules_ci
- [x] rules_github
- [x] rules_rdf
- [x] rules_jena
- [ ] rules_agentic_ide
- [x] rules_aip
- [x] rules_astro
- [ ] rules_autoconf
- [ ] rules_beam
- [ ] rules_bibtex
- [x] rules_bun
- [ ] rules_cc_cross
- [ ] rules_cc_host
- [x] rules_chrome
- [x] rules_cloudformation
- [x] rules_docker_compose
- [x] rules_eslint
- [ ] rules_fastverk_plugin
- [x] rules_gitlab
- [ ] rules_graphviz
- [x] rules_helm
- [ ] rules_huggingface
- [x] rules_jsonschema
- [x] rules_k8s
- [ ] rules_lang
- [ ] rules_lean
- [ ] rules_lora
- [ ] rules_macvm
- [x] rules_markdown
- [x] rules_mdbook
- [ ] rules_meson
- [x] rules_nextjs
- [x] rules_openapi
- [x] rules_podman
- [ ] rules_postgres
- [ ] rules_puml
- [x] rules_readme
- [x] rules_schema_org
- [ ] rules_ssh_tui
- [x] rules_storybook
- [ ] rules_systemd
- [ ] rules_tap
- [ ] rules_tectonic
- [ ] rules_tla
- [ ] rules_uv
- [x] rules_vite
- [ ] rules_vscode
- [x] rules_web
- [x] rules_xsd

## Excludes

Do not create these directories. Do not import them into this vehicle.

### tomato-bazel (and sibling) non-module repos

| Name | Status | Why excluded |
| --- | --- | --- |
| rbe-api | excluded | not a `rules_*` module |
| setup-tbzl | excluded | installer, not a rules module |
| gate | excluded | not a `rules_*` module |
| cred-helper | excluded | credential helper, not a rules module |
| infra | excluded | infrastructure, not a rules module |
| bazel-registry | excluded | publishing surface; do not vendor BCR / registry.fastverk.com |
| brand | excluded | brand assets module lives outside this vehicle |
| docs | excluded | documentation site, not a rules module |
| build | excluded | build repo, not a rules module |
| site | excluded | site, not a rules module |
| crova | excluded | product, not a `rules_*` module |
| crovad | excluded | product, not a `rules_*` module |
| roma | excluded | product, not a `rules_*` module |
| truss | excluded | product, not a `rules_*` module |
| tap | excluded | private tap engine; `rules_tap` stays an include |
| governor | excluded | not a `rules_*` module |
| buildbarn | excluded | not a tomato-bazel `rules_*` module |
| modgraph | excluded | not a `rules_*` module |
| modgraph-mcp | excluded | not a `rules_*` module |
| modgraph-operator | excluded | not a `rules_*` module |
| tbzl | excluded | product / control plane, not a rules module |
| tbzl-build-operator | excluded | operator, not a rules module |
| tbzl-console | excluded | console, not a rules module |
| tbzl-control-plane | excluded | control plane, not a rules module |
| tbzl-profile | excluded | profile, not a rules module |

### fastverk-org `rules_*` (out of scope)

| Name | Status | Why excluded |
| --- | --- | --- |
| rules_runpod | excluded | fastverk-org; do not import |
| rules_walkthrough | excluded | fastverk-org; do not import |
| rules_texlive | excluded | fastverk-org; do not import |
| rules_aws_workflows | excluded | fastverk-org; do not import |

## Import method

For each imported row:

```sh
git subtree add --prefix=<module> https://github.com/tomato-bazel/<module>.git main
```

No `--squash`. Source history is merged under the prefix; source remotes are
not rewritten. After the add, confirm `<module>/MODULE.bazel` still declares
the same `name` and `version` as the source default branch (do not reset
versions to a vehicle-wide number).
