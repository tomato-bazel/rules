# rules_systemd

Bazel-idiomatic systemd unit provisioning: typed unit rules + providers + an aspect that emits the /etc/systemd/system layer with enable-symlinks

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
bazel_dep(name = "rules_systemd", version = "0.0.1")
```
