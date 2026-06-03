"""Providers for the Bazel-cached knowledge-graph ingest."""

AgenticKgInfo = provider(
    doc = "RDF fragments forming the knowledge graph for a target and " +
          "its transitive deps. Each fragment is a per-target action " +
          "output, so Bazel's action cache makes KG ingest incremental: " +
          "change one target and only its fragment (+ the rollup) re-run.",
    fields = {
        "fragments": "depset[File]: this target's RDF fragment plus the " +
                     "fragments of all transitive deps (N-Triples).",
    },
)
