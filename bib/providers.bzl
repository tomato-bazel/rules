"""Provider types for the rules_bibtex public API.

Three types:

- `PaperCitationInfo` — one citation. Carries the single-entry `.bib`
  file plus its provenance (arXiv id, DOI, snapshot URL, source
  kind) plus the depset of directly-cited papers (for the research
  graph). Emitted by `bibtex_entry`, `arxiv_paper`, `doi_paper`,
  `manual_citation`.

- `TexPaperWithCitationsInfo` — a paper + its full citation graph.
  Emitted by `cited_tex_paper`. The `citations` depset is the
  transitive set of papers reachable from the paper's `bib_deps`
  via the per-citation `cites` attribute, computed by the
  research-graph aspect.

- `ResearchGraphInfo` — the final TTL Turtle file with (paper,
  cites, paper) edges. Emitted by `research_graph(roots = [...])`
  over a list of `cited_tex_paper` targets.

Names use the `XInfo` package-prefixed convention so an unwrapped
import is unambiguous next to other ecosystem providers
(JenaModelInfo, BeamPipelineInfo, PumlDiagramInfo).
"""

PaperCitationInfo = provider(
    doc = "One bibtex citation entry. Carries the single-entry .bib " +
          "file plus provenance + directly-cited papers (depset of " +
          "PaperCitationInfo).",
    fields = {
        "key": "str: the bibtex citation key (matches \\cite{<key>} in .tex).",
        "bibtex": "File: the single-entry .bib file for this citation.",
        "source_kind": "str: provenance — 'arxiv' | 'doi' | 'arxiv+doi' | " +
                       "'manual'. Drives the research-graph aspect's " +
                       "annotation; consumers can use it for filtering " +
                       "(e.g. 'manual' citations may want manual review).",
        "arxiv_id": "str: arXiv identifier (e.g. '2005.11401v4') if " +
                    "known. Empty string when unknown.",
        "doi": "str: DOI (e.g. '10.5555/3495724.3496517') if known. " +
               "Empty string when unknown.",
        "snapshot_url": "str: URL of the snapshotted resource for " +
                        "manual citations. Empty string when N/A.",
        "cites": "depset[PaperCitationInfo]: directly-cited papers. " +
                 "Manually declared in V0; future versions may " +
                 "populate from Crossref reference data.",
    },
)

TexPaperWithCitationsInfo = provider(
    doc = "A LaTeX paper + its assembled bibliography + the transitive " +
          "research-graph closure of its citations.",
    fields = {
        "pdf": "File: rendered paper PDF.",
        "combined_bib": "File: the assembled .bib file (one entry per " +
                        "bib_dep).",
        "citations": "depset[PaperCitationInfo]: every reachable citation " +
                     "from this paper via the cites graph. The 'reachable " +
                     "vs declared' distinction matters: declared (direct) " +
                     "are in the paper's bibliography; reachable (transitive) " +
                     "feed the research_graph aspect.",
    },
)

ResearchGraphInfo = provider(
    doc = "A computed (paper, cites, paper) RDF Turtle graph over the " +
          "research closure of one or more papers. The graph is the V0 " +
          "answer to 'what's the citation footprint of this project?'.",
    fields = {
        "ttl": "File: Turtle-serialized research graph. Uses the " +
               "https://fastverk.dev/bib/ namespace for citation IRIs " +
               "and dcterms / fabio for the predicates.",
        "papers": "depset[PaperCitationInfo]: every paper in the graph.",
        "edge_count": "int | None: total citation edges, if known cheaply.",
    },
)
