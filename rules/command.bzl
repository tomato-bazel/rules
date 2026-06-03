"""`agent_command(name, def_ttl, body)` — declare one authored slash
command / prompt definition as an agentic-ide data primitive.

Provider-only: no Bazel actions, no parsed-form artifacts. The
`def_ttl` files (the authored aide:Command graph) remain the source
of truth; the per-IDE projection CONSTRUCT queries reshape them into
output filespecs.

Every `agent_command` ALSO emits `RdfDatasetInfo` (the abstract
provider from rules_rdf) so it's a drop-in dataset for any rules_rdf
rule — the authored TTL composes straight into a canonical graph that
`sparql_query` / `agent_bundle` run against:

```python
load("@rules_agentic_ide//rules:defs.bzl", "agent_command", "agent_bundle")

agent_command(
    name = "review",
    def_ttl = ["review.ttl"],
    body = [".agents/commands/review.md"],
)

agent_bundle(  # works: resolves the authored graph via RdfDatasetInfo
    name = "commands",
    graph = ":review",
    projections = ["@rules_agentic_ide//rdf/projections:claude_code/commands.rq"],
)
```
"""

load("@rules_rdf//rdf:providers.bzl", "RdfDatasetInfo")
load(":providers.bzl", "AgentCommandInfo")

def _agent_command_impl(ctx):
    ttl = depset(ctx.files.def_ttl)
    body = depset(ctx.files.body)
    return [
        DefaultInfo(files = depset(ctx.files.def_ttl + ctx.files.body)),
        AgentCommandInfo(
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

agent_command = rule(
    implementation = _agent_command_impl,
    attrs = {
        "def_ttl": attr.label_list(
            allow_files = [".ttl"],
            mandatory = True,
            doc = "The authored aide:Command definition graph (Turtle).",
        ),
        "body": attr.label_list(
            allow_files = [".md", ".mdc"],
            doc = "Markdown body files the definition references via " +
                  "aide:bodyPath. Carried through DefaultInfo so the " +
                  "serializer can resolve bodies at generate time.",
        ),
    },
    provides = [AgentCommandInfo, RdfDatasetInfo],
    doc = "An authored slash command / prompt definition declared as Bazel data.",
)
