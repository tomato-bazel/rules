# Changelog

All notable changes to `rules_agentic_ide`. Ontology changes follow the
versioning convention in [docs/upgrading.md](docs/upgrading.md): additive =
minor; deprecate-then-remove (with a migration) = major.

## 0.0.3

Additive — no migration needed.

### Fixed
- **`aide:BazelTarget` MCP flavor now projects `env`.** A bazel-run MCP
  server with `aide:envVar` entries previously dropped them from
  `.mcp.json` (only `Network`/`Binary` rendered `env`). Hermetic
  launchers that need environment (e.g. `AWS_REGION`/`AWS_PROFILE`) now
  carry it through.

## 0.0.2

Additive — no migration needed; a 0.0.1 graph still validates and projects.

### Added
- **MCP host abstraction** — `mcp_bazel_server` / `mcp_network_server` /
  `mcp_oci_server` / `mcp_system_server` (+ `aide:McpHost` vocab). Every
  runnable host projects to `bazel run <launcher>`; only `NetworkHost`
  stays a URL. npm/pypi launcher patterns in [docs/mcp-hosts.md](docs/mcp-hosts.md);
  gateway-daemon design in [docs/mcp-gateway.md](docs/mcp-gateway.md).
- **Settings projection** — `.claude/settings.json` (`aide:SettingsConfig`
  JSON shape + `claude_code/settings.rq`).
- **Multi-body concat** — `aide:bodyFragment` / `aide:fragmentHeader`:
  one `CLAUDE.md` / `copilot-instructions.md` from a root + N topic rules.
- **Per-IDE frontmatter reshape** — `aide:stripBodyFrontmatter` +
  `aide:description`: proper Cursor `.mdc` / Copilot shim frontmatter over
  a frontmatter-free body.
- **Upgrade toolkit**:
  - `generated.lock` manifest (content hashes) + `generate --check` drift gate.
  - `.gitignore` auto-management (`git check-ignore`).
  - SHACL `validate` — `rdf/shapes/aide_shapes.ttl` + the `agent_validate` macro.
  - deprecation/migrate scaffold (`migrations/`).
- **`exports_files`** on `rdf/projections` + `rdf/shapes` so consumers can
  reference the queries/shapes.

## 0.0.1

Initial public release: project a normalized RDF knowledge graph into
per-IDE agent configs (skills / rulesets / MCP) for Claude Code, Copilot,
and Cursor, via per-IDE CONSTRUCT queries + a dependency-light serializer.
