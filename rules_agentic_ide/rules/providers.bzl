"""Provider types for the agentic-ide thin per-definition rules.

The authoring primitives (`agent_skill`, `agent_ruleset`,
`agent_command`, …) are provider-only — they carry references to
the authored definition TTL + the markdown bodies it points at, no
build actions. The projection machinery (`sparql_query` /
`agent_bundle`) consumes them: every authoring rule ALSO emits the
abstract `RdfDatasetInfo` from rules_rdf, so an `agent_skill` is a
drop-in `rdf_dataset` for any rules_rdf rule and the authored TTL
composes straight into a canonical graph.

The names use the package-prefixed convention (`AgentXInfo`) so an
unwrapped `AgentSkillInfo` import is unambiguous next to the rules_rdf
`RdfDatasetInfo` and the rules_jena `JenaModelInfo`.
"""

AgentSkillInfo = provider(
    doc = "An authored skill definition (aide:Skill). Provider-only " +
          "— the declared files remain the source of truth; the " +
          "per-IDE projection CONSTRUCT queries reshape the TTL into " +
          "output filespecs.",
    fields = {
        "name": "str: the skill's aide:defName (kebab-case id).",
        "ttl": "depset[File]: the authored aide:Skill definition graph.",
        "body_files": "depset[File]: the markdown body files the " +
                      "definition references via aide:bodyPath.",
    },
)

AgentDefinitionInfo = provider(
    doc = "An authored subagent definition (aide:Agent). Provider-only " +
          "— the declared files remain the source of truth; the " +
          "per-IDE projection CONSTRUCT queries reshape the TTL into " +
          "output filespecs.",
    fields = {
        "name": "str: the agent's aide:defName (kebab-case id).",
        "ttl": "depset[File]: the authored aide:Agent definition graph.",
        "body_files": "depset[File]: the markdown body files the " +
                      "definition references via aide:bodyPath.",
    },
)

AgentCommandInfo = provider(
    doc = "An authored slash-command / prompt definition (aide:Command). " +
          "Provider-only — the declared files remain the source of " +
          "truth; the per-IDE projection CONSTRUCT queries reshape the " +
          "TTL into output filespecs.",
    fields = {
        "name": "str: the command's aide:defName (kebab-case id).",
        "ttl": "depset[File]: the authored aide:Command definition graph.",
        "body_files": "depset[File]: the markdown body files the " +
                      "definition references via aide:bodyPath.",
    },
)

AgentRulesetInfo = provider(
    doc = "An authored ruleset definition (aide:Ruleset — CLAUDE.md / " +
          "AGENTS.md / .cursorrules / copilot-instructions). " +
          "Provider-only — the declared files remain the source of " +
          "truth; the per-IDE projection CONSTRUCT queries reshape the " +
          "TTL into output filespecs.",
    fields = {
        "name": "str: the ruleset's aide:defName (kebab-case id).",
        "ttl": "depset[File]: the authored aide:Ruleset definition graph.",
        "body_files": "depset[File]: the markdown body files the " +
                      "definition references via aide:bodyPath.",
    },
)

McpServerInfo = provider(
    doc = "An authored MCP server definition (aide:McpServer). " +
          "Provider-only — the declared files remain the source of " +
          "truth; the MCP projection CONSTRUCT queries reshape the TTL " +
          "into the .mcp.json filespec.",
    fields = {
        "name": "str: the server's aide:defName.",
        "ttl": "depset[File]: the authored aide:McpServer definition graph.",
    },
)
