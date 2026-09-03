"""Providers for the manifest half of rules_k8s."""

K8sObjectInfo = provider(
    doc = """Kubernetes manifests contributed by a target.

Carries files and nothing else. Identity (group/version/kind, name, namespace) is
resolved by the bundle ACTION, not here — Starlark cannot read files, so a rule
that adopts a checked-in manifest has no way to know its Kind at analysis time.
Duplicate detection and the listing therefore live in the tool.
(rules_cloudformation's stack aggregator makes the same trade for the same
reason: it can't load many hundreds of per-kind providers, so it reads the shards.)
""",
    fields = {
        "files": "depset[File]: manifest YAMLs. Each may hold multiple documents.",
    },
)

K8sBundleInfo = provider(
    doc = "A collected, conflict-checked set of Kubernetes objects.",
    fields = {
        "dir": "File: TreeArtifact of the manifests, one file per object, named from its identity.",
        "files": "depset[File]: the source manifests that composed it.",
    },
)
