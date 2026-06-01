"""Public API surface for rules_bibtex.

```python
load("@rules_bibtex//bib:defs.bzl",
     # Citation rules
     "bibtex_entry", "arxiv_paper", "doi_paper", "manual_citation",
     # Paper rule
     "cited_tex_paper",
     # Research-graph rule
     "research_graph",
     # Provider types
     "PaperCitationInfo", "TexPaperWithCitationsInfo", "ResearchGraphInfo")
```
"""

load(
    ":citation.bzl",
    _arxiv_paper = "arxiv_paper",
    _bibtex_entry = "bibtex_entry",
    _doi_paper = "doi_paper",
    _manual_citation = "manual_citation",
)
load(":cited_tex_paper.bzl", _cited_tex_paper = "cited_tex_paper")
load(
    ":providers.bzl",
    _PaperCitationInfo = "PaperCitationInfo",
    _ResearchGraphInfo = "ResearchGraphInfo",
    _TexPaperWithCitationsInfo = "TexPaperWithCitationsInfo",
)
load(":research_graph.bzl", _research_graph = "research_graph")

# Re-exported rules / macros.
bibtex_entry = _bibtex_entry
arxiv_paper = _arxiv_paper
doi_paper = _doi_paper
manual_citation = _manual_citation
cited_tex_paper = _cited_tex_paper
research_graph = _research_graph

# Re-exported provider types.
PaperCitationInfo = _PaperCitationInfo
TexPaperWithCitationsInfo = _TexPaperWithCitationsInfo
ResearchGraphInfo = _ResearchGraphInfo
