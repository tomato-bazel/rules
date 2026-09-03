"""`bibtex_entry(name, bibtex, …)` and the typed sugar rules
(`arxiv_paper`, `doi_paper`, `manual_citation`).

Each rule takes an inline bibtex string, writes it to `<name>.bib`,
and emits `PaperCitationInfo` with the provenance fields filled in.
The `cites` attribute is the manual declaration of which other
citations this paper directly references; the research-graph
aspect walks it to compute the transitive closure.

```python
load("@rules_bibtex//bib:defs.bzl",
     "bibtex_entry", "arxiv_paper", "doi_paper", "manual_citation")

arxiv_paper(
    name = "lewis2020rag",
    arxiv_id = "2005.11401v4",
    doi = "10.5555/3495724.3496517",
    bibtex = '''
@inproceedings{lewis2020rag,
  title = {Retrieval-Augmented Generation for Knowledge-Intensive NLP Tasks},
  author = {Lewis, Patrick and others},
  booktitle = {NeurIPS},
  year = {2020},
  eprint = {2005.11401v4},
  archivePrefix = {arXiv},
}''',
    cites = [":vaswani2017attention", ":guu2020realm"],
)

doi_paper(
    name = "banarescu2013amr",
    doi = "10.18653/v1/W13-2322",
    bibtex = '''@inproceedings{banarescu2013amr,
  title = {Abstract Meaning Representation for Sembanking},
  author = {Banarescu, Laura and others},
  booktitle = {LAW@ACL},
  year = {2013},
}''',
)

manual_citation(
    name = "mcp2024",
    snapshot_url = "https://modelcontextprotocol.io/specification/2024-11-05",
    bibtex = '''@misc{mcp2024,
  title = {Model Context Protocol},
  author = {{Anthropic}},
  year = {2024},
  url = {https://modelcontextprotocol.io/specification/2024-11-05},
}''',
)
```
"""

load(":providers.bzl", "PaperCitationInfo")

_VALID_KEY_CHARS = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_"

def _bibtex_entry_impl(ctx):
    # Extract the bibtex key from the inline string if not given.
    # First non-whitespace char after `@<type>{` is the key, ending
    # at the first comma.
    key = ctx.attr.key if ctx.attr.key else _extract_key_or_default(
        ctx.attr.bibtex,
        ctx.label.name,
    )

    # Sanity: the citation key must match the Bazel target name when
    # not overridden. Mismatched keys cause `\cite{<target_name>}` to
    # miss the bib entry silently.
    if not ctx.attr.key and key != ctx.label.name:
        fail(
            "%s: bibtex citation key %r does not match the target " %
            (ctx.label, key) +
            "name %r. Either rename the target or set `key = %r`." %
            (ctx.label.name, key),
        )

    out = ctx.actions.declare_file(ctx.label.name + ".bib")
    ctx.actions.write(out, ctx.attr.bibtex.strip() + "\n")

    transitive_cites = depset(
        direct = [dep[PaperCitationInfo] for dep in ctx.attr.cites],
        transitive = [dep[PaperCitationInfo].cites for dep in ctx.attr.cites],
    )

    return [
        DefaultInfo(files = depset([out])),
        PaperCitationInfo(
            key = key,
            bibtex = out,
            source_kind = ctx.attr.source_kind,
            arxiv_id = ctx.attr.arxiv_id,
            doi = ctx.attr.doi,
            snapshot_url = ctx.attr.snapshot_url,
            cites = transitive_cites,
        ),
    ]

def _extract_key_or_default(bibtex_str, default):
    """Pull the key from `@type{key,` in an inline bibtex string.

    Returns `default` if the inline string is malformed or empty
    enough that a key isn't recoverable. Build will surface bibtex
    parse errors downstream when the .bib feeds into the LaTeX build.
    """
    s = bibtex_str.strip()
    if not s.startswith("@"):
        return default
    brace = s.find("{")
    if brace < 0:
        return default
    rest = s[brace + 1:]
    end = -1
    for i in range(len(rest)):
        c = rest[i]
        if c == "," or c == "}" or c == "\n" or c == " ":
            end = i
            break
    if end < 0:
        return default
    candidate = rest[:end].strip()
    for c in candidate.elems():
        if c not in _VALID_KEY_CHARS:
            return default
    return candidate or default

_bibtex_entry_rule = rule(
    implementation = _bibtex_entry_impl,
    attrs = {
        "bibtex": attr.string(
            mandatory = True,
            doc = "Inline bibtex entry — single `@type{key, …}` block. " +
                  "Stored verbatim into `<name>.bib` (trailing newline " +
                  "normalized). The `key` is extracted from this string " +
                  "and must equal the target name unless `key` overrides.",
        ),
        "key": attr.string(
            default = "",
            doc = "Override the citation key. Default is the target name, " +
                  "which the rule cross-checks against the key in `bibtex`. " +
                  "Override only when the legacy key cannot equal a valid " +
                  "Bazel target name (rare).",
        ),
        "source_kind": attr.string(
            default = "manual",
            values = ["arxiv", "doi", "arxiv+doi", "manual"],
            doc = "Provenance tag — drives research-graph annotation. " +
                  "Set by the typed sugar rules; rarely set directly.",
        ),
        "arxiv_id": attr.string(default = ""),
        "doi": attr.string(default = ""),
        "snapshot_url": attr.string(default = ""),
        "cites": attr.label_list(
            providers = [PaperCitationInfo],
            default = [],
            doc = "Directly-cited papers. The research-graph aspect " +
                  "walks this list across the dep graph to compute " +
                  "the transitive citation closure. Empty by default — " +
                  "papers without declared `cites` are leaves in the " +
                  "research graph.",
        ),
    },
    provides = [PaperCitationInfo],
    doc = "A single bibtex citation, typed as a Bazel target. " +
          "Most consumers use the typed sugar wrappers " +
          "(`arxiv_paper`, `doi_paper`, `manual_citation`); call " +
          "this rule directly only when none of those fits.",
)

def bibtex_entry(name, bibtex, key = "", arxiv_id = "", doi = "", snapshot_url = "", cites = [], visibility = None):
    """Generic bibtex citation. Most consumers want the typed sugar wrappers."""
    source = _infer_source_kind(arxiv_id, doi, snapshot_url)
    _bibtex_entry_rule(
        name = name,
        bibtex = bibtex,
        key = key,
        source_kind = source,
        arxiv_id = arxiv_id,
        doi = doi,
        snapshot_url = snapshot_url,
        cites = cites,
        visibility = visibility,
    )

def _infer_source_kind(arxiv_id, doi, snapshot_url):
    has_arxiv = bool(arxiv_id)
    has_doi = bool(doi)
    if has_arxiv and has_doi:
        return "arxiv+doi"
    if has_arxiv:
        return "arxiv"
    if has_doi:
        return "doi"
    return "manual"

def arxiv_paper(name, arxiv_id, bibtex, doi = "", cites = [], visibility = None):
    """arXiv-pinned citation. `arxiv_id` like `2005.11401v4`."""
    if not arxiv_id:
        fail("arxiv_paper(%r): `arxiv_id` is required." % name)
    bibtex_entry(
        name = name,
        bibtex = bibtex,
        arxiv_id = arxiv_id,
        doi = doi,
        cites = cites,
        visibility = visibility,
    )

def doi_paper(name, doi, bibtex, cites = [], visibility = None):
    """DOI-pinned citation. `doi` like `10.18653/v1/W13-2322`."""
    if not doi:
        fail("doi_paper(%r): `doi` is required." % name)
    bibtex_entry(
        name = name,
        bibtex = bibtex,
        doi = doi,
        cites = cites,
        visibility = visibility,
    )

def manual_citation(name, bibtex, snapshot_url = "", cites = [], visibility = None):
    """Manual citation — for products, specs, websites with no DOI or " +
    arXiv id (Anthropic docs, MCP spec, schema.org, vendor whitepapers).

    `snapshot_url` is informational; future versions of rules_bibtex
    may add a `bazel run :snapshot` step that wayback-archives the
    URL and pins the snapshot SHA.
    """
    bibtex_entry(
        name = name,
        bibtex = bibtex,
        snapshot_url = snapshot_url,
        cites = cites,
        visibility = visibility,
    )
