# rules_k8s

Kubernetes CRDs as build artifacts. `k8s_crd_library` runs controller-tools as a
real Bazel action — sandboxed, cached, remotable — with **no host Go, no `go
list`, no module cache, no network, and no `bazel query`**.

That combination is supposed to be impossible, which is why every operator in the
fleet regenerates CRDs out of band and commits the result. It isn't impossible:
`go/packages` accepts a custom driver, and inside a rule we already know the
package graph, because rules_go's `go_pkg_info_aspect` emits it as declared
outputs. rules_k8s ships the small driver that closes the loop.

The payoff is that CRD drift stops being something you gate and starts being
something that cannot happen.

```
//crd/          k8s_crd_library · the CRD toolchain · K8sCrdInfo
//crd/private/  driver/ (the go/packages driver) · gen/ (controller-tools, as a library)
//k8s/          k8s_object · k8s_bundle · k8s_validate · k8s_diff
//k8s/private/  bundle/ (the aggregator) · schemas.bzl (the aspect)
//validate/     the kubeconform toolchain · crd2jsonschema
//kubectl/      the kubectl toolchain (PATH default + escape hatch)
//oci/          k8s_operator_image (+ the platform transition)
//docs/         stardoc reference, generated + committed + gated
//examples/smoke/  the end-to-end proof
```

## Status: v0.0.2

`k8s_crd_library` works and is verified byte-identical to stock
`controller-gen v0.16.5`, including against every CRD of a real operator.
`k8s_object` / `k8s_bundle` / `k8s_validate` / `k8s_diff` work.
`k8s_operator_image` builds a linux/amd64 operator image on any host with no
`--platforms` flag, and its `_push` target actually works.

## Why this exists

The pipeline in every operator repo today is:

```
Go type + markers → controller-gen → operator/config/crd/*.yaml  (committed)
                                   → [ an unautomated human `cp` ]
                                   → helm/<chart>/crds/*.yaml    (committed, byte-duplicated)
```

Nothing in any BUILD file, script, or workflow performs that `cp`. It goes stale. A stale chart CRD is not a build error: ArgoCD
renders the chart's `crds/`, server-side-applies the older schema over the live
CRD, and the API server then structurally prunes the now-unknown fields off live
custom resources. Silent data loss, from a copy nobody made.

With CRDs as a build artifact, the duplicate is generated, so it cannot go stale:

```python
load("@aspect_bazel_lib//lib:write_source_files.bzl", "write_source_files")
load("@rules_k8s//crd:defs.bzl", "k8s_crd_library")

k8s_crd_library(
    name = "crds",
    deps = ["//api/v1:v1"],          # a plain rules_go go_library
    group = "platform.example.com",  # verified against the output, so it can't rot
)

# `bazel run //crd:update` regenerates both trees; `bazel test` gates them.
write_source_files(
    name = "update",
    files = {
        "//operator/config/crd": ":crds",
        "//helm/my-operator/crds": ":crds",   # <- this line replaces the human `cp`
    },
)
```

A whole-directory sync catches all three ways the hand-copy fails: a stale file,
a **new CRD nobody remembered to copy**, and an orphan left behind. A per-file
`diff_test` catches only the first.

## How it works

controller-tools asks `go/packages` for **metadata only**:

```go
// controller-tools/pkg/loader/loader.go
l.cfg.Mode |= packages.NeedName | packages.NeedFiles |
              packages.NeedCompiledGoFiles | packages.NeedImports | packages.NeedTypesSizes
```

No `NeedTypes`, no `NeedSyntax` — it type-checks itself from `CompiledGoFiles`.
So `go/packages` is a pure metadata channel here, and a driver that serves file
paths is a complete answer. `//crd/private/driver` is that driver: it reads the
`pkg.json` files `go_pkg_info_aspect` already produced and never consults the go
command, the network, the module cache, or Bazel.

rules_go's own `gopackagesdriver` can't be used directly — it shells out to
`bazel query`, and you cannot run Bazel inside a Bazel action. Its
*manifest-reading half* can be, so that half is vendored (Apache-2.0) and the
`bazel query` half is dropped. See `//crd/private/driver/BUILD.bazel`.

## Install

`.bazelrc`:

```
common --registry=https://registry.fastverk.com/
common --registry=https://bcr.bazel.build/

# Register the CRD toolchain. This goes in .bazelrc and NOT MODULE.bazel:
# register_toolchains() propagates to every consumer, which would drag a Go SDK
# into the Rust services that only ever READ CRD schemas.
common --extra_toolchains=@rules_k8s//crd:default_k8s_crd_toolchain
```

`MODULE.bazel`:

```python
bazel_dep(name = "rules_k8s", version = "0.0.2")

# Only repos that actually RUN controller-gen need these.
bazel_dep(name = "rules_go", version = "0.60.0")
bazel_dep(name = "gazelle", version = "0.51.0")
```

## Rules

| Rule | Kind | What it does |
|---|---|---|
| `k8s_crd_library` | rule | `go_library` deps → CRD YAML as a declared TreeArtifact. Emits `K8sCrdInfo`. Optional `post_processors`. |
| `k8s_object` | rule | Adopt checked-in manifests into the graph; optionally assert their Kind/apiVersion. |
| `k8s_bundle` | rule | Collect manifests into one directory, failing on duplicate group/Kind/namespace/name. |
| `k8s_validate` | test | kubeconform a bundle against CRD schemas resolved through its `deps`. |
| `k8s_diff` | executable | `bazel run` — diff a bundle against a live cluster. Read-only. |
| `k8s_operator_image` | macro | An operator binary → a linux/amd64 image, via a per-target transition. Emits `<name>`, `<name>_push`, `<name>_tarball`. |
| `k8s_crd_toolchain` | rule | Declares a CRD codegen toolchain (controller-gen + driver). |

### Why `k8s_operator_image` exists

An operator image needs a linux/amd64 binary regardless of the host. The fleet
does that with an invocation-wide flag:

```
build:operator-image --platforms=@rules_go//go/toolchain:linux_amd64
```

That retargets *everything* the invocation touches, including the tools rules_oci
pulls in to push — which then want a cpp toolchain for a platform that has none.
So one such repo's CI does not use its own `oci_push` at all. From its image
workflow:

> *"image_push pulls the crane push tool into the build graph, and under
> `--config=operator-image` (`--platforms=go/linux_amd64`) that tool's launcher
> can't resolve a cpp toolchain (No matching toolchains for cpp:toolchain_type)."*

`:image_push` ends up dead code, and pushing falls back to a hand-rolled `crane`.

`k8s_operator_image` puts the retarget on the **target**: only the image (and
everything under it — base, layers, binary) lands on linux/amd64, while `oci_push`
stays in the host configuration where its launcher resolves normally. So a plain
`go_binary` — no `goos`, no `goarch`, no `pure = "on"`, no second
cross-compiled target beside the real one — becomes a correct image:

```python
k8s_operator_image(
    name = "my-operator-image",
    binary = "//operator/cmd:manager",
    repository = "ghcr.io/example/my-operator",
)
```

Verified on an arm64 Mac with no flags: the shipped binary is
`ELF 64-bit LSB executable, x86-64, statically linked`, and
`:operator-image_push` builds. `//examples/smoke/cmd:image_is_linux_amd64_test`
keeps it that way — a transition that stops firing still builds and still pushes,
it just ships a binary that cannot exec.

### What `k8s_validate` does not check

It is worth being blunt, because a validator people over-trust is worse than none:

- **CEL is not evaluated.** `x-kubernetes-validations` (`self == oldSelf`) can
  reference an object's prior state, which does not exist at build time.
- **Policy is not checked.** A field can be well-typed and still wrong — an
  ArgoCD `Application` pinned to an unmerged feature branch is a valid string.
  That needs a policy engine, which rules_k8s deliberately does not ship (no
  consumer has asked for one, and a speculative seam that nobody walks through
  is worse than an honest gap).
- **Core Kubernetes kinds need `core_schemas`.** They have no CRD to derive a
  schema from. There is no network fallback on purpose: kubeconform's own
  `-schema-location default` is a raw GitHub URL, which would make every
  validation a network fetch and fail on RBE.

## Testing

| Target | What it proves |
|---|---|
| `//examples/smoke:crds_match_stock_controller_gen` | The generated CRD is **byte-identical** to stock `controller-gen v0.16.5`. |
| `//examples/smoke:crds_listing_test` | No Kind silently appeared or vanished. |
| `//crd/private/driver:driver_test` | The driver serves a graph from `pkg.json`; `pkg.Name` is backfilled; missing inputs fail loudly rather than yielding an empty graph. |

### Verifying against stock controller-gen

`examples/smoke/testdata/expected_widgets.yaml` is **not** this rule's output
blessed into a file — it is the verbatim output of stock controller-gen:

```sh
go run sigs.k8s.io/controller-tools/cmd/controller-gen@v0.16.5 \
  crd paths=./examples/smoke/api/v1/... output:crd:artifacts:config=/tmp/stockcrd
diff /tmp/stockcrd/smoke.rules-k8s.dev_widgets.yaml \
     bazel-bin/examples/smoke/crds/smoke.rules-k8s.dev_widgets.yaml
```

Regenerate the golden only from stock controller-gen, never from this rule.

This matters because a real fleet has its CRDs committed to git and rendered into
charts that a GitOps controller server-side-applies. If output drifted from stock
by one line, adopting rules_k8s would rewrite every schema and push the rewrite
live. It has already caught one such instance: a Bazel-built binary has no
`debug.ReadBuildInfo()`, so controller-tools stamped
`controller-gen.kubebuilder.io/version: (unknown)` until `//crd/private/gen`'s
`x_defs` supplied the version.

The version pins in `//:go.mod` are schema decisions, not dependency bumps — read
the comment there before touching them.

### Proving it is really hermetic

The claim is only worth anything if it fails when it should:

```sh
env PATH=<bazel-only-dir>:/usr/bin:/bin GOROOT=/nonexistent \
    GOMODCACHE=/nonexistent GOPROXY=off \
  bazel build //examples/smoke:crds --disk_cache= --spawn_strategy=sandboxed
```

If `go` is reachable, the control is invalid — check with `command -v go` first.
Without the driver, controller-tools fails with `go command required, not found`.

## Docs

`//docs` holds stardoc reference, generated from the `.bzl` docstrings and
committed, with a gate: change a rule without running `bazel run //docs:update`
and `bazel test //docs:all` fails. Same generated-committed-gated shape this
module argues for everywhere else.

Covered: `//crd:providers.bzl`, `//crd:toolchains.bzl`, `//k8s:defs.bzl`.

**Two gaps**, both blocked upstream — stardoc needs a `bzl_library` for every
transitively loaded module, and a file you cannot see is a file you cannot wrap:

- **`//crd:defs.bzl`** loads `@rules_go//go/tools/gopackagesdriver:aspect.bzl`,
  which rules_go neither wraps nor exports (`Visibility error`). Vendoring the
  aspect doesn't help either: it reads `GoStdLib`, which `@rules_go//go:def.bzl`
  doesn't export, and providers are *identity*-based — a copied definition is a
  different provider, so a vendored aspect couldn't read it off a rules_go target.
- **`//oci:defs.bzl`** loads `@rules_pkg//pkg:tar.bzl`, which is public, but whose
  loads reach `@rules_pkg//pkg/private:util.bzl` — exported only to rules_pkg's
  own packages. (`@rules_oci//oci:defs` *does* ship a `bzl_library`; rules_oci is
  not the problem.)

Both rules are documented in this README and in their own docstrings; only the
generated page is missing. Stub `bzl_library` targets over someone else's private
modules would rot silently against the upstream file — worse than an honest gap.

## Compatibility

- Bazel 7+ (bzlmod).
- rules_go 0.60.0. `//crd/private/driver` vendors files from rules_go's
  `go/tools/gopackagesdriver`, and the rule loads `go_pkg_info_aspect` from it —
  both are rules_go **internals** with no compatibility promise. On a rules_go
  bump, re-diff the vendored files and re-run the smoke test.
- controller-tools v0.16.5.

## License

MIT. `//crd/private/driver` contains files vendored from rules_go under
Apache-2.0; each retains its original header.
