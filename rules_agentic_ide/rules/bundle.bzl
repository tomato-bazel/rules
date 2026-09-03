"""`agent_bundle` — project a canonical graph into one per-IDE filespec.

A bundle runs each per-IDE projection CONSTRUCT query (each is its own
`sparql_query` target) against the same canonical authored graph and
merges the resulting `aide:OutputFile` filespecs into a single
N-Triples artifact `<name>.nt`. That bundle is what the `agentic-ide
generate` CLI consumes to materialize the actual config files:

```starlark
load("@rules_agentic_ide//rules:defs.bzl", "agent_bundle")

agent_bundle(
    name = "agents",
    graph = ":canonical",          # an rdf_dataset (authored .ttl + ide spec)
    projections = [
        "@rules_agentic_ide//rdf/projections:claude_code/skills.rq",
        # … one .rq per IDE × surface …
    ],
)
```

Then:

```
bazel build //path:agents          # produces path/agents.nt
bazel run @rules_agentic_ide//crates/agentic_ide_generate:agentic-ide-generate -- \\
    --filespec $(...)/agents.nt --out <repo>
```

Adding an IDE or a surface is adding a query to `projections` — never
editing a switch (registry/visitor dispatch keyed on rdf:type, the
Forge normalization model).
"""

load("@rules_rdf//rdf:providers.bzl", "RdfDatasetInfo")
load("@rules_rdf//sparql:defs.bzl", "sparql_query")

def _merge_datasets_impl(ctx):
    files = depset(transitive = [
        d[RdfDatasetInfo].transitive_files
        for d in ctx.attr.members
    ])
    return [
        DefaultInfo(files = files),
        RdfDatasetInfo(files = files, transitive_files = files, in_format = "turtle"),
    ]

# Union the authored-TTL closures of several agent_* definition targets
# into one RdfDatasetInfo, so a bundle can project their combined graph.
_merge_datasets = rule(
    implementation = _merge_datasets_impl,
    attrs = {
        "members": attr.label_list(
            providers = [RdfDatasetInfo],
            doc = "agent_* definition targets to union into one graph.",
        ),
    },
    provides = [RdfDatasetInfo],
)

def agent_bundle(name, projections, members = None, graph = None, visibility = None):
    """Merge per-IDE projection filespecs into one N-Triples bundle.

    Args:
      name: target name; produces `<name>.nt`.
      graph: an `rdf_dataset` (or any `RdfDatasetInfo`) — the canonical
        authored graph the projection queries run against.
      projections: list of `.rq`/`.sparql` CONSTRUCT query labels/files,
        one per IDE × surface. Each emits an `aide:OutputFile` graph.
      visibility: standard visibility for the bundle target.
    """
    if (members == None) == (graph == None):
        fail("agent_bundle: pass exactly one of `members` (agent_* definition " +
             "targets) or `graph` (an rdf_dataset / single RdfDatasetInfo).")
    if members != None:
        merged = "_{}_graph".format(name)
        _merge_datasets(name = merged, members = members)
        graph = ":" + merged

    parts = []
    for i, query in enumerate(projections):
        part = "_{}_p{}".format(name, i)
        sparql_query(
            name = part,
            dataset = graph,
            query = query,
            out_format = "ntriples",
        )
        parts.append(":" + part)

    # Concatenate the per-query N-Triples into one filespec. N-Triples is
    # line-oriented and order-independent, so a plain cat is a valid
    # merge; Jena mints content-hash blank-node labels, so a frontmatter
    # entry shared across IDE projections collapses to one bnode.
    native.genrule(
        name = name,
        srcs = parts,
        outs = [name + ".nt"],
        cmd = "cat $(SRCS) > $@",
        visibility = visibility,
    )
