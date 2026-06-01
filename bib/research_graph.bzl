"""`research_graph(name, roots)` — emit a Turtle RDF graph of
`(paper, cites, paper)` edges over the citation closure of one or
more paper targets.

The shape of the emitted graph:

```turtle
@prefix bib:     <https://fastverk.dev/bib/> .
@prefix dcterms: <http://purl.org/dc/terms/> .
@prefix fabio:   <http://purl.org/spar/fabio/> .
@prefix cito:    <http://purl.org/spar/cito/> .

bib:lewis2020rag a fabio:JournalArticle ;
    dcterms:title "Retrieval-Augmented Generation for ..." ;
    bib:arxivId "2005.11401v4" ;
    bib:doi "10.5555/3495724.3496517" ;
    cito:cites bib:guu2020realm , bib:vaswani2017attention .
```

The CITO ontology (Citation Typing Ontology) provides
`cito:cites` for the citation predicate; FABIO (FRBR-aligned
Bibliographic Ontology) gives types like `fabio:JournalArticle`,
`fabio:ConferencePaper`. Both are well-established W3C-adjacent
research-bibliography vocabularies that align cleanly with the
project's existing schema.org grounding.

The aspect walks `bib_deps` on each `cited_tex_paper` root and
the transitive `cites` graph on each citation. Output is one TTL
file under `bazel-bin/<package>/<name>.ttl`.

```python
load("@rules_bibtex//bib:defs.bzl", "research_graph")

research_graph(
    name = "agora_research_closure",
    roots = [
        "//papers/grounding",
        "//papers/geometry",
        "//papers/pcc",
    ],
)
```
"""

load(":providers.bzl",
     "PaperCitationInfo",
     "ResearchGraphInfo",
     "TexPaperWithCitationsInfo")

def _emit_turtle(papers):
    """Emit a Turtle serialization for a depset of PaperCitationInfo."""
    lines = [
        "@prefix bib:     <https://fastverk.dev/bib/> .",
        "@prefix dcterms: <http://purl.org/dc/terms/> .",
        "@prefix fabio:   <http://purl.org/spar/fabio/> .",
        "@prefix cito:    <http://purl.org/spar/cito/> .",
        "",
    ]
    # Sort by key for deterministic output.
    sorted_papers = sorted(papers, key = lambda p: p.key)
    for p in sorted_papers:
        lines.append("bib:%s a fabio:Expression ;" % p.key)
        if p.arxiv_id:
            lines.append("    bib:arxivId %s ;" % _ttl_string(p.arxiv_id))
        if p.doi:
            lines.append("    bib:doi %s ;" % _ttl_string(p.doi))
        if p.snapshot_url:
            lines.append("    bib:snapshotUrl %s ;" % _ttl_string(p.snapshot_url))
        lines.append("    bib:sourceKind %s ;" % _ttl_string(p.source_kind))
        cited = sorted(p.cites.to_list(), key = lambda c: c.key)
        if cited:
            cite_iris = " , ".join(["bib:" + c.key for c in cited])
            lines.append("    cito:cites %s ;" % cite_iris)
        # End the resource (Turtle requires `.`).
        # Strip the trailing `;` from the prior line and emit `.`.
        last = lines[-1]
        if last.endswith(" ;"):
            lines[-1] = last[:-2] + " ."
        lines.append("")
    return "\n".join(lines)

def _ttl_string(s):
    """Escape a string for Turtle literal output."""
    escaped = s.replace("\\", "\\\\").replace("\"", "\\\"")
    return "\"" + escaped + "\""

def _research_graph_impl(ctx):
    """Roots are `cited_tex_paper` targets. Walk their citation
    closures (the TexPaperWithCitationsInfo depset already contains
    direct + transitive papers) and dedupe by key.
    """
    # Collect every paper reachable from each root. Three contribution
    # paths per root:
    #   (a) `TexPaperWithCitationsInfo.citations` for cited_tex_paper roots
    #   (already includes transitive cites assembled by _assemble_bib);
    #   (b) `PaperCitationInfo`-typed roots — the root itself; and
    #   (c) `PaperCitationInfo.cites` — the root's transitive citations.
    transitive_depsets = []
    for root in ctx.attr.roots:
        if TexPaperWithCitationsInfo in root:
            transitive_depsets.append(root[TexPaperWithCitationsInfo].citations)
        if PaperCitationInfo in root:
            info = root[PaperCitationInfo]
            transitive_depsets.append(depset([info]))
            transitive_depsets.append(info.cites)
    all_papers = depset(transitive = transitive_depsets)

    # Dedup by key — the same paper can be reachable via multiple roots.
    seen = {}
    for p in all_papers.to_list():
        seen[p.key] = p
    papers = sorted(seen.values(), key = lambda p: p.key)

    # We need a regular File output, so write the TTL via
    # ctx.actions.write (synchronous, no subprocess).
    out = ctx.actions.declare_file(ctx.label.name + ".ttl")
    ctx.actions.write(out, _emit_turtle(papers))

    edge_count = 0
    for p in papers:
        edge_count = edge_count + len(p.cites.to_list())

    return [
        DefaultInfo(files = depset([out])),
        ResearchGraphInfo(
            ttl = out,
            papers = depset(papers),
            edge_count = edge_count,
        ),
    ]

research_graph = rule(
    implementation = _research_graph_impl,
    attrs = {
        "roots": attr.label_list(
            mandatory = True,
            doc = "List of `cited_tex_paper` (or `bibtex_entry`) targets " +
                  "to start the citation closure from. Each root's " +
                  "transitive citations contribute nodes + edges. " +
                  "Deduplication is by bibtex key.",
        ),
    },
    provides = [ResearchGraphInfo],
    doc = "Compute the (paper, cites, paper) RDF graph over the " +
          "citation closure of one or more papers; emit it as Turtle.",
)
