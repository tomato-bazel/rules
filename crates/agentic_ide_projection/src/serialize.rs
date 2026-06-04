//! Render `OutputFile`s to bytes and write them under a repo root.
//!
//! The mirror image of the harvest parsers: where they read an IDE's
//! on-disk files into the IR, this writes the IR's projection back out.
//! Branches only on `FileFormat`.

use std::path::Path;

use anyhow::{bail, Context, Result};

use super::filespec::{
    Body, FileFormat, FmValue, FrontmatterEntry, JsonShape, McpFlavor, McpServerSpec, OutputFile,
    Transport,
};

/// What materializing a file did (or would do, in a dry run).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Status {
    Created,
    Changed,
    Unchanged,
}

/// One file the projection produced.
#[derive(Debug, Clone)]
pub struct GeneratedFile {
    /// Repo-relative path.
    pub path: String,
    pub status: Status,
    /// Lowercase hex SHA-256 of the rendered content (for the manifest /
    /// drift check). Computed even on a dry run.
    pub sha256: String,
}

/// Render a single output file to its on-disk bytes. `repo_root`
/// resolves `Body::Path` references to the canonical source body.
pub fn render(out: &OutputFile, repo_root: &Path) -> Result<String> {
    match out.format {
        FileFormat::MarkdownYaml | FileFormat::Mdc => render_markdown(out, repo_root),
        FileFormat::Json => render_json(out),
        FileFormat::Other(ref iri) => bail!(
            "unknown aide:FileFormat <{iri}> for {}",
            out.target_path
        ),
    }
}

fn render_json(out: &OutputFile) -> Result<String> {
    match &out.json_shape {
        Some(JsonShape::McpConfig) => render_mcp_config(out),
        Some(JsonShape::Settings) => render_settings(out),
        Some(JsonShape::Other(s)) => bail!(
            "unsupported aide:jsonShape <{s}> for {}",
            out.target_path
        ),
        None => bail!(
            "aide:Json file {} has no aide:jsonShape (don't know how to build it)",
            out.target_path
        ),
    }
}

/// Build a Claude settings file (.claude/settings.json) from the
/// permission allow list + additional directories. Both are normalized
/// (sorted, deduped) by the filespec parser, so output is byte-stable.
fn render_settings(out: &OutputFile) -> Result<String> {
    use serde_json::{Map, Value};

    let arr =
        |items: &[String]| Value::Array(items.iter().map(|s| Value::String(s.clone())).collect());
    let mut perms = Map::new();
    perms.insert("allow".to_string(), arr(&out.settings_allow));
    if !out.settings_dirs.is_empty() {
        perms.insert("additionalDirectories".to_string(), arr(&out.settings_dirs));
    }
    let root = Value::Object({
        let mut m = Map::new();
        m.insert("permissions".to_string(), Value::Object(perms));
        m
    });
    let mut s = serde_json::to_string_pretty(&root)
        .with_context(|| format!("serializing {}", out.target_path))?;
    s.push('\n');
    Ok(s)
}

/// Build an MCP config file (.mcp.json) from the aggregated server
/// entries. Each flavor maps to its on-disk JSON form; `${VAR}` env /
/// header values pass through verbatim (no secret is resolved here).
fn render_mcp_config(out: &OutputFile) -> Result<String> {
    use serde_json::{Map, Value};

    let mut servers = Map::new();
    for s in &out.mcp_servers {
        servers.insert(s.name.clone(), mcp_server_json(s));
    }
    let root = Value::Object({
        let mut m = Map::new();
        m.insert("mcpServers".to_string(), Value::Object(servers));
        m
    });
    let mut s = serde_json::to_string_pretty(&root)
        .with_context(|| format!("serializing {}", out.target_path))?;
    s.push('\n');
    Ok(s)
}

fn mcp_server_json(s: &McpServerSpec) -> serde_json::Value {
    use serde_json::{Map, Value};

    let mut obj = Map::new();
    match &s.flavor {
        McpFlavor::Network => {
            if let Some(t) = transport_str(&s.transport) {
                obj.insert("type".into(), Value::String(t));
            }
            if let Some(u) = &s.url {
                obj.insert("url".into(), Value::String(u.clone()));
            }
            if !s.headers.is_empty() {
                obj.insert("headers".into(), kv_object(&s.headers));
            }
        }
        McpFlavor::Binary => {
            obj.insert("type".into(), Value::String("stdio".into()));
            if let Some(c) = &s.command {
                obj.insert("command".into(), Value::String(c.clone()));
            }
            if !s.args.is_empty() {
                obj.insert(
                    "args".into(),
                    Value::Array(s.args.iter().map(|(_, a)| Value::String(a.clone())).collect()),
                );
            }
            if !s.env.is_empty() {
                obj.insert("env".into(), kv_object(&s.env));
            }
        }
        McpFlavor::BazelTarget => {
            // Hermetic: launch the upstream target via `bazel run <label>`.
            // Any server args pass through after `--` (e.g. ${workspaceFolder}).
            obj.insert("type".into(), Value::String("stdio".into()));
            obj.insert("command".into(), Value::String("bazel".into()));
            let label = s.bazel_label.clone().unwrap_or_default();
            let mut args = vec![Value::String("run".into()), Value::String(label)];
            if !s.args.is_empty() {
                args.push(Value::String("--".into()));
                args.extend(s.args.iter().map(|(_, a)| Value::String(a.clone())));
            }
            obj.insert("args".into(), Value::Array(args));
            if !s.env.is_empty() {
                obj.insert("env".into(), kv_object(&s.env));
            }
        }
        McpFlavor::Other(iri) => {
            obj.insert("_unknownFlavor".into(), Value::String(iri.clone()));
        }
    }
    Value::Object(obj)
}

fn kv_object(pairs: &[(String, String)]) -> serde_json::Value {
    use serde_json::{Map, Value};
    let mut m = Map::new();
    for (k, v) in pairs {
        m.insert(k.clone(), Value::String(v.clone()));
    }
    Value::Object(m)
}

fn transport_str(t: &Option<Transport>) -> Option<String> {
    match t {
        Some(Transport::Http) => Some("http".into()),
        Some(Transport::Sse) => Some("sse".into()),
        Some(Transport::Stdio) => Some("stdio".into()),
        _ => None,
    }
}

/// Emit frontmatter recursively: scalars as `key: value`, lists as
/// `key:` then `  - item`, maps as `key:` then nested entries (2-space
/// indent per level), so nested IDE frontmatter round-trips faithfully.
fn emit_frontmatter(s: &mut String, entries: &[FrontmatterEntry], indent: usize) {
    let pad = "  ".repeat(indent);
    for e in entries {
        match &e.value {
            FmValue::Scalar(v) => {
                s.push_str(&pad);
                s.push_str(&e.key);
                s.push_str(": ");
                s.push_str(&yaml_scalar(v));
                s.push('\n');
            }
            FmValue::List(items) => {
                s.push_str(&pad);
                s.push_str(&e.key);
                s.push_str(":\n");
                for it in items {
                    s.push_str(&pad);
                    s.push_str("  - ");
                    s.push_str(&yaml_scalar(it));
                    s.push('\n');
                }
            }
            FmValue::Map(sub) => {
                s.push_str(&pad);
                s.push_str(&e.key);
                s.push_str(":\n");
                emit_frontmatter(s, sub, indent + 1);
            }
        }
    }
}

fn render_markdown(out: &OutputFile, repo_root: &Path) -> Result<String> {
    let mut s = String::new();
    if !out.frontmatter.is_empty() {
        s.push_str("---\n");
        emit_frontmatter(&mut s, &out.frontmatter, 0);
        s.push_str("---\n");
    }
    // Multi-body: concatenate ordered fragments (optional heading + body),
    // each separated by a blank line. Used for one-file IDEs that have no
    // native multi-rule support (e.g. CLAUDE.md from root + topic rules).
    let body = if !out.body_fragments.is_empty() {
        let mut parts: Vec<String> = Vec::new();
        for f in &out.body_fragments {
            let frag = resolve_body(&Body::Path(f.body_path.clone()), repo_root)
                .with_context(|| format!("resolving fragment for {}", out.target_path))?;
            let mut chunk = String::new();
            if let Some(h) = &f.header {
                chunk.push_str(h);
                chunk.push_str("\n\n");
            }
            chunk.push_str(frag.trim_end_matches('\n'));
            parts.push(chunk);
        }
        parts.join("\n\n")
    } else {
        let raw = resolve_body(&out.body, repo_root)
            .with_context(|| format!("resolving body for {}", out.target_path))?;
        if out.strip_body_frontmatter {
            strip_frontmatter(&raw)
        } else {
            raw
        }
    };
    if !body.is_empty() {
        // Single blank line between frontmatter and body for readability.
        if !out.frontmatter.is_empty() {
            s.push('\n');
        }
        s.push_str(&body);
        if !body.ends_with('\n') {
            s.push('\n');
        }
    }
    Ok(s)
}

/// Strip a leading YAML frontmatter block (`---\n…\n---\n`) from a body,
/// so a format that supplies its own frontmatter doesn't nest the source's.
fn strip_frontmatter(body: &str) -> String {
    if let Some(rest) = body.strip_prefix("---\n") {
        if let Some(end) = rest.find("\n---\n") {
            return rest[end + 5..].trim_start_matches('\n').to_string();
        }
        if rest.strip_suffix("\n---").is_some() {
            return String::new(); // entire body was frontmatter
        }
    }
    body.to_string()
}

fn resolve_body(body: &Body, repo_root: &Path) -> Result<String> {
    match body {
        Body::Inline(s) => Ok(s.clone()),
        Body::None => Ok(String::new()),
        Body::Path(p) => {
            let abs = repo_root.join(p);
            std::fs::read_to_string(&abs)
                .with_context(|| format!("reading canonical body {}", abs.display()))
        }
    }
}

/// Emit a YAML scalar — bare when safe, double-quoted (with escaping)
/// when the value could be misparsed. Conservative, so projected
/// frontmatter is stable and unambiguous.
fn yaml_scalar(v: &str) -> String {
    let needs_quote = v.is_empty()
        || v.starts_with(|c: char| {
            matches!(
                c,
                ' ' | '!' | '&' | '*' | '?' | '|' | '>' | '%' | '@' | '`' | '"' | '\'' | '#' | ',' | '[' | ']' | '{' | '}' | '-'
            )
        })
        || v.ends_with(' ')
        || v.contains(": ")
        || v.contains(" #")
        || v.contains('\n')
        || v.contains('"')
        || v.contains(':');
    if !needs_quote {
        return v.to_string();
    }
    let mut q = String::with_capacity(v.len() + 2);
    q.push('"');
    for c in v.chars() {
        match c {
            '"' => q.push_str("\\\""),
            '\\' => q.push_str("\\\\"),
            '\n' => q.push_str("\\n"),
            _ => q.push(c),
        }
    }
    q.push('"');
    q
}

/// Render and (unless `dry_run`) write every output file under
/// `repo_root`. Returns one entry per file with its change status.
pub fn write_all(files: &[OutputFile], repo_root: &Path, dry_run: bool) -> Result<Vec<GeneratedFile>> {
    let mut results = Vec::with_capacity(files.len());
    for out in files {
        let content = render(out, repo_root)?;
        let target = repo_root.join(&out.target_path);
        let status = match std::fs::read_to_string(&target) {
            Ok(existing) if existing == content => Status::Unchanged,
            Ok(_) => Status::Changed,
            Err(_) => Status::Created,
        };
        if !dry_run && status != Status::Unchanged {
            if let Some(parent) = target.parent() {
                std::fs::create_dir_all(parent)
                    .with_context(|| format!("creating {}", parent.display()))?;
            }
            std::fs::write(&target, content.as_bytes())
                .with_context(|| format!("writing {}", target.display()))?;
        }
        results.push(GeneratedFile {
            path: out.target_path.clone(),
            status,
            sha256: sha256_hex(content.as_bytes()),
        });
    }
    Ok(results)
}

/// Lowercase-hex SHA-256 of `bytes`.
pub fn sha256_hex(bytes: &[u8]) -> String {
    use sha2::{Digest, Sha256};
    let digest = Sha256::digest(bytes);
    let mut s = String::with_capacity(64);
    for b in digest {
        s.push_str(&format!("{b:02x}"));
    }
    s
}
