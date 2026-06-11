# rules_macvm

Bazel-idiomatic, hermetic Linux VMs on macOS via Apple Virtualization.framework, with a pluggable VMM provider seam (vfkit first).

## Status: v0.0.1 — scaffold

No public surface yet. See `CHANGELOG.md` for what has shipped.

## Install

`.bazelrc`:

```
common --registry=https://raw.githubusercontent.com/fastverk/bazel-registry/main/
common --registry=https://bcr.bazel.build/
```

`MODULE.bazel`:

```python
bazel_dep(name = "rules_macvm", version = "0.0.1")
```
