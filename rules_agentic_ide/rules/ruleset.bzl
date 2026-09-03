"""`agent_ruleset(name, def_ttl, body)` — declare one authored ruleset
definition as an agentic-ide data primitive.

A ruleset is the CLAUDE.md / AGENTS.md / .cursorrules /
copilot-instructions style repo-wide doc. Provider-only: no Bazel
actions, no parsed-form artifacts. The `def_ttl` files (the authored
aide:Ruleset graph) remain the source of truth; the per-IDE projection
CONSTRUCT queries (claude_code/rulesets.rq, …) reshape them into output
filespecs.

Every `agent_ruleset` ALSO emits `RdfDatasetInfo` (the abstract
provider from rules_rdf) so it's a drop-in dataset for any rules_rdf
rule — the authored TTL composes straight into a canonical graph that
`sparql_query` / `agent_bundle` run against:

```python
load("@rules_agentic_ide//rules:defs.bzl", "agent_ruleset", "agent_bundle")

agent_ruleset(
    name = "engineering",
    def_ttl = ["engineering.ttl"],
    body = [".agents/rulesets/engineering.md"],
)

agent_bundle(  # works: resolves the authored graph via RdfDatasetInfo
    name = "rulesets",
    graph = ":engineering",
    projections = ["@rules_agentic_ide//rdf/projections:claude_code/rulesets.rq"],
)
```
"""

load("@rules_rdf//rdf:providers.bzl", "RdfDatasetInfo")
load(":providers.bzl", "AgentRulesetInfo")

def _agent_ruleset_impl(ctx):
    ttl = depset(ctx.files.def_ttl)
    body = depset(ctx.files.body)
    return [
        DefaultInfo(files = depset(ctx.files.def_ttl + ctx.files.body)),
        AgentRulesetInfo(
            name = ctx.label.name,
            ttl = ttl,
            body_files = body,
        ),
        # Drop-in compatibility with rules_rdf rules. The authored TTL is
        # both the dataset's own files and (no deps) its closure, so the
        # graph composes into sparql_query / agent_bundle unchanged.
        RdfDatasetInfo(
            files = ttl,
            transitive_files = ttl,
            in_format = "turtle",
        ),
    ]

agent_ruleset = rule(
    implementation = _agent_ruleset_impl,
    attrs = {
        "def_ttl": attr.label_list(
            allow_files = [".ttl"],
            mandatory = True,
            doc = "The authored aide:Ruleset definition graph (Turtle).",
        ),
        "body": attr.label_list(
            allow_files = [".md", ".mdc"],
            doc = "Markdown body files the definition references via " +
                  "aide:bodyPath. Carried through DefaultInfo so the " +
                  "serializer can resolve bodies at generate time.",
        ),
    },
    provides = [AgentRulesetInfo, RdfDatasetInfo],
    doc = "An authored ruleset definition declared as Bazel data.",
)
