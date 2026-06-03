"""Public API for the agentic-ide projection rules.

```starlark
load("@rules_agentic_ide//rules:defs.bzl", "agent_bundle", "agent_skill")
```

`agent_bundle` projects a canonical authored graph through per-IDE
SPARQL CONSTRUCT queries and merges the results into one N-Triples
filespec that `agentic-ide generate` materializes into config files.
The thin per-definition rules (`agent_skill` / `agent_ruleset` /
`agent_command` / …) declare one authored definition each as
provider-only Bazel data — they emit both their domain `Agent*Info`
provider and the abstract `RdfDatasetInfo`, so the authored TTL
composes straight into the canonical graph `agent_bundle` runs against.
"""

load(":bundle.bzl", _agent_bundle = "agent_bundle")
load(":skill.bzl", _agent_skill = "agent_skill")
load(":ruleset.bzl", _agent_ruleset = "agent_ruleset")
load(":command.bzl", _agent_command = "agent_command")
load(":mcp.bzl", _mcp_server = "mcp_server")
load(
    ":providers.bzl",
    _AgentCommandInfo = "AgentCommandInfo",
    _AgentDefinitionInfo = "AgentDefinitionInfo",
    _AgentRulesetInfo = "AgentRulesetInfo",
    _AgentSkillInfo = "AgentSkillInfo",
    _McpServerInfo = "McpServerInfo",
)

agent_bundle = _agent_bundle
agent_skill = _agent_skill
agent_ruleset = _agent_ruleset
agent_command = _agent_command
mcp_server = _mcp_server

AgentSkillInfo = _AgentSkillInfo
AgentDefinitionInfo = _AgentDefinitionInfo
AgentCommandInfo = _AgentCommandInfo
AgentRulesetInfo = _AgentRulesetInfo
McpServerInfo = _McpServerInfo
