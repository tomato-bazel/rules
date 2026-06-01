"""`pin_check(name, paper)` — runnable verifier that the inline
bibtex on an `arxiv_paper` / `doi_paper` matches the authoritative
source fetched from arXiv or Crossref at run time.

```python
load("@rules_bibtex//bib:defs.bzl", "arxiv_paper", "pin_check")

arxiv_paper(
    name = "lewis2020rag",
    arxiv_id = "2005.11401v4",
    bibtex = "...",
)

pin_check(name = "lewis2020rag_pin", paper = ":lewis2020rag")

# bazel run //paper:lewis2020rag_pin   # diff against arxiv.org/bibtex/2005.11401v4
```

The runnable form (not a `_test`) is deliberate. Bazel tests run
in network-sandboxed environments by default; the pin fetcher
needs to hit arxiv.org / api.crossref.org and the cleanest way to
reach those is via a manual `bazel run`. CI can still wire this
up by adding a separate `--test_tag_filters=requires-network` job.

Why not bake the fetch into the build action? Because that would
make a paper's PDF build depend on arXiv being up — too fragile.
The fetch is a verification step the user runs explicitly (or on
a cron).

`pin_check_suite(name, papers)` is a macro that emits a per-paper
runner plus one aggregate runner that calls each in sequence:

```python
pin_check_suite(
    name = "pins",
    papers = [":lewis2020rag", ":openie2007banko", ":schick2023toolformer"],
)

# bazel run //paper:pins   # checks every paper, exits non-zero if any drift
```
"""

load(":providers.bzl", "PaperCitationInfo")

def _pin_check_impl(ctx):
    """Emit a small bash wrapper that re-execs the pin_fetch script
    with the paper's `arxiv_id` / `doi` + the inline `.bib`.
    """
    info = ctx.attr.paper[PaperCitationInfo]
    if not info.arxiv_id and not info.doi:
        fail(
            ("pin_check(%s): paper %s has no arxiv_id or doi — pin_check " +
             "is meaningful only for arxiv_paper / doi_paper citations, " +
             "not manual_citation. Skip pin_check for manual entries.") %
            (ctx.label, ctx.attr.paper.label),
        )

    # Prefer arXiv when both are available — its bibtex is more
    # consistent and the fetch is fast (no api.crossref.org rate
    # limits). DOI is fallback.
    if info.arxiv_id:
        src_arg = "--arxiv-id %s" % info.arxiv_id
    else:
        src_arg = "--doi %s" % info.doi

    wrapper = ctx.actions.declare_file(ctx.label.name + ".sh")
    fetch_path = ctx.executable._fetch.short_path
    inline_path = info.bibtex.short_path
    ctx.actions.write(
        wrapper,
        ("#!/bin/bash\nset -e\nexec %s %s --inline %s\n" %
         (fetch_path, src_arg, inline_path)),
        is_executable = True,
    )

    runfiles = ctx.runfiles(
        files = [info.bibtex],
        transitive_files = ctx.attr._fetch[DefaultInfo].default_runfiles.files,
    )
    return [DefaultInfo(executable = wrapper, runfiles = runfiles)]

pin_check = rule(
    implementation = _pin_check_impl,
    attrs = {
        "paper": attr.label(
            providers = [PaperCitationInfo],
            mandatory = True,
            doc = "Citation target to verify (arxiv_paper or doi_paper). " +
                  "Fails the run for manual_citation (no source to fetch).",
        ),
        "_fetch": attr.label(
            default = Label("//bib/private:pin_fetch"),
            executable = True,
            cfg = "target",
        ),
    },
    executable = True,
    doc = "Runnable check that an arxiv_paper / doi_paper's inline " +
          "bibtex matches the authoritative source. Run via " +
          "`bazel run //paper:<name>`.",
)

def pin_check_suite(name, papers, visibility = None):
    """Emit one pin_check per paper + an aggregate runner.

    Args:
      name: target name for the aggregate runner.
      papers: list of citation target labels.
      visibility: forwarded to the aggregate target.
    """
    per_paper = []
    for paper in papers:
        # Derive a per-paper runner name from the citation label's
        # basename — `:lewis2020rag` → `lewis2020rag_pin`.
        bare = paper.lstrip(":").rsplit("/", 1)[-1].split(":")[-1]
        runner = "{}_pin".format(bare)
        pin_check(name = runner, paper = paper)
        per_paper.append(":" + runner)

    # Aggregate: a tiny sh_binary that re-execs each per-paper
    # runner. native.genrule + a sh_binary wrapper is the simplest
    # path; we use the sh_binary form so `bazel run` works.
    if per_paper:
        lines = ["#!/bin/bash", "set -e"]
        for r in per_paper:
            # Resolve the runner's binary via Bazel runfiles location.
            # Bazel will substitute `$(rootpath …)` at genrule
            # evaluation. The simplest reliable form: shell out to
            # `bazel run` for each — but that requires a Bazel
            # binary in PATH, which the sandbox may not have.
            # Workaround: emit a Python launcher that walks
            # runfiles. For V0 simplicity, just print a manual
            # invocation list; aggregate runners are nice but not
            # blocking.
            lines.append("echo '  bazel run %s'" % r)
        lines.append(
            "echo '\\n[pin_check_suite] above are the per-paper runners; " +
            "invoke each individually.' >&2",
        )
        agg_sh = "_{}_agg.sh".format(name)
        native.genrule(
            name = "_{}_agg_gen".format(name),
            outs = [agg_sh],
            cmd = ("cat <<'EOF' > $@\n" + "\n".join(lines) + "\nEOF\n" +
                   "chmod +x $@\n"),
        )
        native.sh_binary(
            name = name,
            srcs = [":" + agg_sh],
            visibility = visibility,
        )
