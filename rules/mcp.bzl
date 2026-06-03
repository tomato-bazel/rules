"""`mcp_server(name, def_ttl)` — declare authored MCP server
definition(s) as agentic-ide data.

Provider-only: emits `McpServerInfo` + `RdfDatasetInfo`, so the authored
`aide:McpServer` TTL composes straight into the canonical graph the MCP
projection (`claude_code/mcp.rq`, …) runs against. The three flavors —
network (url + headers), binary (command + args + env), and bazel-target
(`aide:bazelLabel` → `bazel run <label>`) — are expressed in the TTL.

```python
load("@rules_agentic_ide//rules:defs.bzl", "mcp_server", "agent_bundle")

mcp_server(name = "linear", def_ttl = ["graph/mcp.ttl"])

agent_bundle(
    name = "agents",
    members = [":linear", ":debugging"],   # union the authored graphs
    projections = ["@rules_agentic_ide//rdf/projections:claude_code/mcp.rq"],
)
```
"""

load("@rules_rdf//rdf:providers.bzl", "RdfDatasetInfo")
load(":providers.bzl", "McpServerInfo")

def _mcp_server_impl(ctx):
    ttl = depset(ctx.files.def_ttl)
    return [
        DefaultInfo(files = ttl),
        McpServerInfo(
            name = ctx.label.name,
            ttl = ttl,
        ),
        # Drop-in dataset for sparql_query / agent_bundle (the union path).
        RdfDatasetInfo(
            files = ttl,
            transitive_files = ttl,
            in_format = "turtle",
        ),
    ]

mcp_server = rule(
    implementation = _mcp_server_impl,
    attrs = {
        "def_ttl": attr.label_list(
            allow_files = [".ttl"],
            mandatory = True,
            doc = "The authored aide:McpServer definition graph (Turtle). " +
                  "May declare one or many servers; the flavor is in the TTL.",
        ),
    },
    provides = [McpServerInfo, RdfDatasetInfo],
    doc = "An authored MCP server definition declared as Bazel data.",
)
