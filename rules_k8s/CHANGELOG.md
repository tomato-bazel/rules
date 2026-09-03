# Changelog

## v0.0.3

First usable release. 0.0.1 and 0.0.2 are withdrawn — their tags are deleted and
they are not in the registry.

- **`k8s_crd_library`** — controller-tools as a real Bazel action: sandboxed,
  cached, remotable, with no host Go, no `go list`, no module cache, no network
  and no `bazel query`. Verified byte-identical to stock `controller-gen v0.16.5`.
- **`k8s_object` / `k8s_bundle` / `k8s_validate` / `k8s_diff`** — adopt
  checked-in manifests, collect them with conflict detection, check them against
  CRD schemas generated in the same build, and diff a bundle against a live
  cluster (read-only).
- **`k8s_operator_image`** — a linux/amd64 operator image on any host via a
  per-target platform transition, so `oci_push` works without a global
  `--platforms` retargeting the push tooling out of a cpp toolchain.

Fixed before release, each of which built green and failed only in production:

- `k8s_bundle` **silently dropped manifests** whose separator carried an inline
  document (`--- {kind: Secret, ...}`) or a trailing tab. Now uses apimachinery's
  `YAMLReader` — the splitter kubectl applies with. A bundle that disagrees with
  the applier's splitter is wrong by definition.
- `k8s_operator_image`'s **entrypoint named a file that wasn't there** for an
  `alias` or an `out =` binary: it came from the label name while the file was
  packaged under its basename. Green build, green push, CrashLoopBackOff.
- The CRD driver **returned a vacuous success** when a root's source could not be
  read, emitting nothing — or a CRD under the wrong version, since
  controller-tools derives the version from the package name.
- `k8s_validate(strict = True)` was a **no-op**, then over-corrected into
  rejecting valid manifests (composition branches, embedded resources).
