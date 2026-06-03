"""MCP server rules — declare MCP servers as agentic-ide data.

Two layers:

1. `mcp_server(name, def_ttl)` — wrap a hand-authored `aide:McpServer`
   Turtle graph as data. The flavor (network / binary / bazel-target)
   is expressed in the TTL.

2. The **host** rules — `mcp_bazel_server`, `mcp_network_server`, and the
   opt-in package-manager hosts (`mcp_npm_server` / `mcp_pypi_server` /
   `mcp_oci_server`, in `rules/hosts/`). These *generate* the resolved
   `aide:McpServer` TTL from attrs, so a server's launcher is a pinned
   Bazel target and the projection renders it as `bazel run <label>`.
   Only `mcp_network_server` (a remote endpoint) stays a URL.

```python
load("@rules_agentic_ide//rules:defs.bzl", "mcp_bazel_server", "mcp_network_server", "agent_bundle")

# A first-party server: any runnable bazel target.
mcp_bazel_server(name = "studio", target = "//packages/studio-dev-mcp:mcp")

# A remote endpoint — no local launch.
mcp_network_server(name = "grafana", url = "http://localhost:8000/mcp")

agent_bundle(
    name = "agents",
    members = [":studio", ":grafana"],
    projections = ["@rules_agentic_ide//rdf/projections:claude_code/mcp.rq"],
)
```
"""

load("@rules_rdf//rdf:providers.bzl", "RdfDatasetInfo")
load(":providers.bzl", "McpServerInfo")

# ---- mcp_server: wrap hand-authored TTL ------------------------------------

def _mcp_server_impl(ctx):
    ttl = depset(ctx.files.def_ttl)
    return [
        DefaultInfo(files = ttl),
        McpServerInfo(name = ctx.label.name, ttl = ttl),
        RdfDatasetInfo(files = ttl, transitive_files = ttl, in_format = "turtle"),
    ]

mcp_server = rule(
    implementation = _mcp_server_impl,
    attrs = {
        "def_ttl": attr.label_list(
            allow_files = [".ttl"],
            mandatory = True,
            doc = "Hand-authored aide:McpServer graph(s) (Turtle); flavor is in the TTL.",
        ),
    },
    provides = [McpServerInfo, RdfDatasetInfo],
    doc = "An MCP server declared from hand-authored Turtle.",
)

# ---- _emit_mcp_server: generate resolved aide:McpServer TTL -----------------

_NS = "https://fastverk.dev/ontology/agentic_ide/projection#"

def _ttl_str(s):
    """Escape a string for a Turtle double-quoted literal."""
    return s.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n")

def _emit_mcp_server_impl(ctx):
    name = ctx.attr.server_name or ctx.label.name
    out = ctx.actions.declare_file(ctx.label.name + ".ttl")
    subj = "<%sserver/%s>" % (_NS, name)
    lines = [
        "@prefix aide: <%s> ." % _NS,
        "",
        "%s a aide:McpServer ;" % subj,
        '    aide:defName "%s" ;' % _ttl_str(name),
    ]
    flavor = ctx.attr.flavor
    if flavor == "bazel":
        lines.append("    aide:mcpFlavor aide:BazelTarget ;")
        lines.append("    aide:transport aide:Stdio ;")
        lines.append('    aide:bazelLabel "%s"' % _ttl_str(ctx.attr.bazel_label))
    elif flavor == "network":
        transport = ctx.attr.transport or "http"
        tcap = "Http" if transport == "http" else ("Sse" if transport == "sse" else "Stdio")
        lines.append("    aide:mcpFlavor aide:Network ;")
        lines.append("    aide:transport aide:%s ;" % tcap)
        lines.append('    aide:url "%s"' % _ttl_str(ctx.attr.url))
    elif flavor == "binary":
        lines.append("    aide:mcpFlavor aide:Binary ;")
        lines.append("    aide:transport aide:Stdio ;")
        lines.append('    aide:command "%s"' % _ttl_str(ctx.attr.command))
    else:
        fail("_emit_mcp_server: unknown flavor %r" % flavor)

    # Ordered args (bazel/binary flavors): aide:arg [ aide:value ..; aide:order n ].
    for i, a in enumerate(ctx.attr.args):
        lines[-1] = lines[-1] + " ;"
        lines.append('    aide:arg [ aide:value "%s" ; aide:order %d ]' % (_ttl_str(a), i))

    # env (binary/bazel) and headers (network) as key/value entries.
    for k, v in ctx.attr.env.items():
        lines[-1] = lines[-1] + " ;"
        lines.append('    aide:envVar [ aide:key "%s" ; aide:value "%s" ]' % (_ttl_str(k), _ttl_str(v)))
    for k, v in ctx.attr.headers.items():
        lines[-1] = lines[-1] + " ;"
        lines.append('    aide:header [ aide:key "%s" ; aide:value "%s" ]' % (_ttl_str(k), _ttl_str(v)))

    lines[-1] = lines[-1] + " ."
    lines.append("")
    ctx.actions.write(out, "\n".join(lines))

    ttl = depset([out])
    return [
        DefaultInfo(files = ttl),
        McpServerInfo(name = name, ttl = ttl),
        RdfDatasetInfo(files = ttl, transitive_files = ttl, in_format = "turtle"),
    ]

_emit_mcp_server = rule(
    implementation = _emit_mcp_server_impl,
    attrs = {
        "server_name": attr.string(doc = "The MCP server key in .mcp.json (defaults to the target name)."),
        "flavor": attr.string(mandatory = True, values = ["bazel", "network", "binary"]),
        "bazel_label": attr.string(doc = "For flavor=bazel: the launcher label → `bazel run <label>`."),
        "url": attr.string(doc = "For flavor=network: the remote endpoint URL."),
        "transport": attr.string(doc = "For flavor=network: http | sse."),
        "command": attr.string(doc = "For flavor=binary: the raw command (non-hermetic escape hatch)."),
        "args": attr.string_list(doc = "Ordered launch args (passthrough, e.g. ${workspaceFolder})."),
        "env": attr.string_dict(doc = "Environment variables."),
        "headers": attr.string_dict(doc = "For flavor=network: HTTP headers."),
    },
    provides = [McpServerInfo, RdfDatasetInfo],
)

# ---- Core host macros (package-manager-agnostic) ---------------------------

def mcp_bazel_server(name, target, args = None, env = None, **kwargs):
    """A first-party MCP server: any runnable bazel target → `bazel run <target>`.

    `target` is taken as-authored (a label string). Package-manager hosts
    (mcp_npm_server etc.) build a launcher and pass its label here.
    """
    _emit_mcp_server(
        name = name,
        server_name = name,
        flavor = "bazel",
        bazel_label = target,
        args = args or [],
        env = env or {},
        **kwargs
    )

def mcp_network_server(name, url, transport = "http", headers = None, **kwargs):
    """A remote HTTP/SSE MCP endpoint — no local launch."""
    _emit_mcp_server(
        name = name,
        server_name = name,
        flavor = "network",
        url = url,
        transport = transport,
        headers = headers or {},
        **kwargs
    )

def mcp_system_server(name, command, args = None, env = None, **kwargs):
    """Escape hatch: a raw system binary on PATH (NON-HERMETIC). Use only
    for servers with no packaged artifact yet; prefer a host that pins."""
    _emit_mcp_server(
        name = name,
        server_name = name,
        flavor = "binary",
        command = command,
        args = args or [],
        env = env or {},
        **kwargs
    )

def mcp_oci_server(name, image, digest, args = None, env = None, docker = "docker", **kwargs):
    """An MCP server in a container, pinned by `digest`, launched via
    `docker run -i --rm <image>@<digest>`. Reproducible (digest is the
    pin); docker is the runtime, so this is pinned-but-not-bazel-hermetic.
    For full bazel-native, pull the image via rules_oci and wrap the
    resulting launcher with `mcp_bazel_server` instead."""
    ref = "{}@{}".format(image, digest)
    _emit_mcp_server(
        name = name,
        server_name = name,
        flavor = "binary",
        command = docker,
        args = ["run", "-i", "--rm", ref] + (args or []),
        env = env or {},
        **kwargs
    )
