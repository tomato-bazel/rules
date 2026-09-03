"""`agentic_kg` — roll up the aspect-emitted per-target RDF fragments.

Applies `agentic_kg_aspect` to `roots`, collects the transitive
`AgenticKgInfo.fragments` closure, and merges them into one N-Triples
knowledge-graph artifact. Exposes `RdfDatasetInfo` so the projection
`sparql_query` targets query the rolled-up KG directly — all
Bazel-cached and incremental. `bazel run` a sibling persist target to
load the rollup into the user-cache TDB2 for the runtime/MCP path.

```starlark
load("@rules_agentic_ide//kg:defs.bzl", "agentic_kg")

agentic_kg(name = "kg", roots = ["//:all_agent_defs"])
```
"""

load("@rules_rdf//rdf:providers.bzl", "RdfDatasetInfo")
load(":aspect.bzl", "agentic_kg_aspect")
load(":providers.bzl", "AgenticKgInfo")

def _agentic_kg_impl(ctx):
    fragments = depset(transitive = [
        r[AgenticKgInfo].fragments
        for r in ctx.attr.roots
        if AgenticKgInfo in r
    ])
    out = ctx.actions.declare_file(ctx.label.name + ".nt")
    args = ctx.actions.args()
    args.add(out)
    args.add_all(fragments)
    ctx.actions.run_shell(
        outputs = [out],
        inputs = fragments,
        arguments = [args],
        command = 'out="$1"; shift; cat "$@" > "$out" || : > "$out"',
        mnemonic = "AgenticKgRollup",
        progress_message = "rolling up knowledge graph %s" % ctx.label,
    )
    return [
        DefaultInfo(files = depset([out])),
        AgenticKgInfo(fragments = fragments),
        RdfDatasetInfo(
            files = depset([out]),
            transitive_files = depset([out]),
            # The rollup mixes structural N-Triples fragments with folded
            # authored Turtle; N-Triples ⊂ Turtle, so it parses as Turtle.
            in_format = "turtle",
        ),
    ]

agentic_kg = rule(
    implementation = _agentic_kg_impl,
    attrs = {
        "roots": attr.label_list(
            aspects = [agentic_kg_aspect],
            doc = "Targets whose transitive dep-graph RDF is rolled up.",
        ),
    },
    doc = "Roll up the aspect-emitted KG fragments of `roots` into one " +
          "queryable RdfDatasetInfo (+ an N-Triples artifact).",
)

# ---- demo-only no-op rule, to exercise the aspect over a small DAG ----

def _kg_node_impl(_ctx):
    return [DefaultInfo()]

kg_node = rule(
    implementation = _kg_node_impl,
    attrs = {
        "deps": attr.label_list(doc = "Other kg_nodes this one depends on."),
        "srcs": attr.label_list(allow_files = True),
    },
    doc = "A no-op node with deps/srcs — only to demonstrate that the " +
          "KG aspect + rollup traverse a dependency DAG.",
)
