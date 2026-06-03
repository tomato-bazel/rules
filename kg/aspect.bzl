"""`agentic_kg_aspect` — emit one cached RDF fragment per build target.

Walks the target dep graph and writes, for each first-party target, an
N-Triples fragment of `bzl:` structural facts (label, kind, dep edges,
source files). Because each fragment is a `ctx.actions.write` output,
Bazel's action cache makes the knowledge-graph ingest incremental — the
KG is rebuilt *for targets, along with Bazel*. The transitive depset on
`AgenticKgInfo` rolls the closure up to any root (see `agentic_kg`).

This is the v1 ingest: Bazel targets are the source of truth, so we
don't manage a git object store ourselves. Authored `aide:`/TTL
definition closures fold in here too as the `agent_*` rules land.
"""

load("@rules_rdf//rdf:providers.bzl", "RdfDatasetInfo")
load(":providers.bzl", "AgenticKgInfo")

_BZL = "https://fastverk.dev/ontology/bazel#"
_RDF_TYPE = "http://www.w3.org/1999/02/22-rdf-syntax-ns#type"

def _iri(s):
    return "<" + s + ">"

def _lit(s):
    return "\"" + s.replace("\\", "\\\\").replace("\"", "\\\"") + "\""

def _target_iri(label):
    # Bazel labels contain no N-Triples-illegal chars (space, <>"{}|^`\),
    # so they embed directly in an IRI fragment.
    return _iri(_BZL + "target/" + str(label))

def _is_first_party(label):
    # Skip external repos (@crates//…, @rules_*//…) — the KG models this
    # repo's targets, not the toolchain/dependency universe.
    return label.workspace_name == "" or label.workspace_name == "rules_agentic_ide+"

def _agentic_kg_aspect_impl(target, ctx):
    deps = getattr(ctx.rule.attr, "deps", [])

    transitive = [
        d[AgenticKgInfo].fragments
        for d in deps
        if AgenticKgInfo in d
    ]

    if not _is_first_party(target.label):
        # Don't mint a fragment for external targets; still thread any
        # first-party fragments reachable through them.
        return [AgenticKgInfo(fragments = depset(transitive = transitive))]

    subj = _target_iri(target.label)
    lines = [
        subj + " " + _iri(_RDF_TYPE) + " " + _iri(_BZL + "Target") + " .",
        subj + " " + _iri(_BZL + "label") + " " + _lit(str(target.label)) + " .",
        subj + " " + _iri(_BZL + "kind") + " " + _lit(ctx.rule.kind) + " .",
    ]
    for d in deps:
        if _is_first_party(d.label):
            lines.append(subj + " " + _iri(_BZL + "dep") + " " + _target_iri(d.label) + " .")
    for f in getattr(ctx.rule.files, "srcs", []):
        lines.append(subj + " " + _iri(_BZL + "srcFile") + " " + _lit(f.short_path) + " .")

    frag = ctx.actions.declare_file(target.label.name + ".kg.nt")
    ctx.actions.write(frag, "\n".join(lines) + "\n")

    # Fold authored RDF into the rollup: a definition target (agent_skill /
    # agent_ruleset / mcp_server / rdf_dataset) provides RdfDatasetInfo, so
    # its aide: TTL joins the KG alongside the structural bzl: facts. The
    # mixed N-Triples + Turtle rollup parses as Turtle (N-Triples ⊂ Turtle;
    # the agentic_kg rule declares in_format = "turtle").
    authored = [target[RdfDatasetInfo].transitive_files] if RdfDatasetInfo in target else []

    return [AgenticKgInfo(
        fragments = depset(direct = [frag], transitive = transitive + authored),
    )]

agentic_kg_aspect = aspect(
    implementation = _agentic_kg_aspect_impl,
    attr_aspects = ["deps"],
    doc = "Emit a cached per-target RDF fragment; propagate over deps.",
)
