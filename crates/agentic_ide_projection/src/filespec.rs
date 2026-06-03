//! Minimal N-Triples reader + the `OutputFile` model.
//!
//! The projection CONSTRUCT queries emit an `aide:OutputFile` graph (the
//! "filespec") describing each file to write. We consume it as
//! N-Triples — line-oriented and trivial to parse, so the serializer
//! needs no RDF crate. Bodies are referenced (a path or inline string),
//! never the file content itself.

use std::collections::BTreeMap;

use anyhow::{bail, Result};

/// The `aide:` projection namespace.
const NS: &str = "https://fastverk.dev/ontology/agentic_ide/projection#";
const RDF_TYPE: &str = "http://www.w3.org/1999/02/22-rdf-syntax-ns#type";

fn aide(local: &str) -> String {
    format!("{NS}{local}")
}

#[derive(Debug, Clone, PartialEq)]
enum Term {
    Iri(String),
    Blank(String),
    Lit(String),
}

/// Serialization of a projected file. The serializer branches only on
/// this — never on the originating definition type.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum FileFormat {
    /// Markdown body with a leading YAML frontmatter block.
    MarkdownYaml,
    /// A JSON document (e.g. .mcp.json, settings.json).
    Json,
    /// Cursor `.mdc` (frontmatter + body).
    Mdc,
    /// An unrecognized `aide:FileFormat` IRI.
    Other(String),
}

impl FileFormat {
    fn from_iri(iri: &str) -> Self {
        match iri.strip_prefix(NS) {
            Some("MarkdownYaml") => FileFormat::MarkdownYaml,
            Some("Json") => FileFormat::Json,
            Some("Mdc") => FileFormat::Mdc,
            _ => FileFormat::Other(iri.to_string()),
        }
    }
}

/// A frontmatter value: a scalar, an ordered list, or a nested map.
/// Real IDE configs nest (e.g. a skill's `metadata: { allowed_tools:
/// [read_file, …] }`), so the model is recursive.
#[derive(Debug, Clone)]
pub enum FmValue {
    Scalar(String),
    List(Vec<String>),
    Map(Vec<FrontmatterEntry>),
}

/// One ordered frontmatter entry.
#[derive(Debug, Clone)]
pub struct FrontmatterEntry {
    pub key: String,
    pub order: i64,
    pub value: FmValue,
}

/// Where a file's body comes from.
#[derive(Debug, Clone)]
pub enum Body {
    /// A checked-in markdown file, repo-relative (read at serialize time).
    Path(String),
    /// A literal body (used for thin shims).
    Inline(String),
    /// No body — frontmatter / structured content only.
    None,
}

/// One ordered fragment of a multi-body output file (e.g. CLAUDE.md built
/// from a root ruleset + N topic rules). Concatenated by `aide:order`.
#[derive(Debug, Clone)]
pub struct BodyFragment {
    pub order: i64,
    /// Optional markdown heading inserted before the fragment body.
    pub header: Option<String>,
    /// Repo-relative path to the fragment body.
    pub body_path: String,
}

/// The structured shape of an `aide:Json` output file (vs. a free-form
/// body). The serializer builds the JSON from the graph, not a string.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum JsonShape {
    /// An MCP server config (.mcp.json) — aggregates `aide:mcpEntry` servers.
    McpConfig,
    /// A Claude settings file (.claude/settings.json) — permissions allow
    /// list + additional directories.
    Settings,
    Other(String),
}

impl JsonShape {
    fn from_iri(iri: &str) -> Self {
        match iri.strip_prefix(NS) {
            Some("McpConfig") => JsonShape::McpConfig,
            Some("SettingsConfig") => JsonShape::Settings,
            _ => JsonShape::Other(iri.to_string()),
        }
    }
}

/// How an MCP server is launched / reached.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum McpFlavor {
    /// External network service (url + headers).
    Network,
    /// External binary (command + args + env).
    Binary,
    /// Hermetic server backed by an upstream bazel target.
    BazelTarget,
    Other(String),
}

impl McpFlavor {
    fn from_iri(iri: &str) -> Self {
        match iri.strip_prefix(NS) {
            Some("Network") => McpFlavor::Network,
            Some("Binary") => McpFlavor::Binary,
            Some("BazelTarget") => McpFlavor::BazelTarget,
            _ => McpFlavor::Other(iri.to_string()),
        }
    }
}

/// MCP transport.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Transport {
    Stdio,
    Http,
    Sse,
    Other(String),
}

impl Transport {
    fn from_iri(iri: &str) -> Self {
        match iri.strip_prefix(NS) {
            Some("Stdio") => Transport::Stdio,
            Some("Http") => Transport::Http,
            Some("Sse") => Transport::Sse,
            _ => Transport::Other(iri.to_string()),
        }
    }
}

/// One MCP server entry within a `.mcp.json`.
#[derive(Debug, Clone)]
pub struct McpServerSpec {
    pub name: String,
    pub flavor: McpFlavor,
    pub transport: Option<Transport>,
    pub command: Option<String>,
    /// (order, value), sorted by order.
    pub args: Vec<(i64, String)>,
    /// (key, value), sorted by key.
    pub env: Vec<(String, String)>,
    pub url: Option<String>,
    /// (key, value), sorted by key.
    pub headers: Vec<(String, String)>,
    pub bazel_label: Option<String>,
}

/// A single file to materialize.
#[derive(Debug, Clone)]
pub struct OutputFile {
    pub target_path: String,
    pub format: FileFormat,
    pub frontmatter: Vec<FrontmatterEntry>,
    pub body: Body,
    /// For `FileFormat::Json`, the structured shape to build.
    pub json_shape: Option<JsonShape>,
    /// MCP server entries (when `json_shape == McpConfig`).
    pub mcp_servers: Vec<McpServerSpec>,
    /// `permissions.allow` entries (when `json_shape == Settings`). Sorted.
    pub settings_allow: Vec<String>,
    /// `permissions.additionalDirectories` entries (when Settings). Sorted.
    pub settings_dirs: Vec<String>,
    /// Ordered body fragments; when non-empty, concatenated as the body
    /// (takes precedence over `body`). Sorted by `order`.
    pub body_fragments: Vec<BodyFragment>,
    /// Strip the resolved body's own leading `---…---` frontmatter (the
    /// target format supplies its own).
    pub strip_body_frontmatter: bool,
}

/// Parse an N-Triples filespec into the output files it describes.
pub fn parse_filespec(nt: &str) -> Result<Vec<OutputFile>> {
    // subject key -> [(predicate IRI, object term)]
    let mut spo: BTreeMap<String, Vec<(String, Term)>> = BTreeMap::new();
    for (i, line) in nt.lines().enumerate() {
        let line = line.trim();
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        let (s, p, o) = parse_line(line)
            .ok_or_else(|| anyhow::anyhow!("malformed N-Triples at line {}: {line}", i + 1))?;
        let subj = match s {
            Term::Iri(iri) => iri,
            Term::Blank(b) => format!("_:{b}"),
            Term::Lit(_) => bail!("literal subject at line {}", i + 1),
        };
        let pred = match p {
            Term::Iri(iri) => iri,
            _ => bail!("non-IRI predicate at line {}", i + 1),
        };
        spo.entry(subj).or_default().push((pred, o));
    }

    let output_iri = aide("OutputFile");
    let mut outs = Vec::new();
    for props in spo.values() {
        let is_output = props
            .iter()
            .any(|(p, o)| p == RDF_TYPE && matches!(o, Term::Iri(i) if *i == output_iri));
        if is_output {
            outs.push(build_output(props, &spo)?);
        }
    }
    Ok(outs)
}

fn build_output(
    props: &[(String, Term)],
    spo: &BTreeMap<String, Vec<(String, Term)>>,
) -> Result<OutputFile> {
    let mut target_path = String::new();
    let mut format = FileFormat::Other(String::new());
    let mut frontmatter = Vec::new();
    let mut inline: Option<String> = None;
    let mut body_path: Option<String> = None;
    let mut json_shape: Option<JsonShape> = None;
    let mut mcp_servers = Vec::new();
    let mut settings_allow: Vec<String> = Vec::new();
    let mut settings_dirs: Vec<String> = Vec::new();
    let mut body_fragments: Vec<BodyFragment> = Vec::new();
    let mut strip_body_frontmatter = false;

    for (p, o) in props {
        match p.strip_prefix(NS) {
            Some("targetPath") => {
                if let Term::Lit(v) = o {
                    target_path = v.clone();
                }
            }
            Some("fileFormat") => {
                if let Term::Iri(i) = o {
                    format = FileFormat::from_iri(i);
                }
            }
            Some("bodyPath") => {
                if let Term::Lit(v) = o {
                    body_path = Some(v.clone());
                }
            }
            Some("bodyInline") => {
                if let Term::Lit(v) = o {
                    inline = Some(v.clone());
                }
            }
            Some("jsonShape") => {
                if let Term::Iri(i) = o {
                    json_shape = Some(JsonShape::from_iri(i));
                }
            }
            Some("frontmatter") => {
                if let Some(entry_props) = lookup(o, spo) {
                    frontmatter.push(read_entry(entry_props, spo));
                }
            }
            Some("mcpEntry") => {
                if let Some(entry_props) = lookup(o, spo) {
                    mcp_servers.push(read_mcp_entry(entry_props, spo));
                }
            }
            Some("permissionAllow") => {
                if let Term::Lit(v) = o {
                    settings_allow.push(v.clone());
                }
            }
            Some("additionalDirectory") => {
                if let Term::Lit(v) = o {
                    settings_dirs.push(v.clone());
                }
            }
            Some("bodyFragment") => {
                if let Some(fp) = lookup(o, spo) {
                    body_fragments.push(read_fragment(fp));
                }
            }
            Some("stripBodyFrontmatter") => {
                if let Term::Lit(v) = o {
                    strip_body_frontmatter = v == "true";
                }
            }
            _ => {}
        }
    }

    // Inline wins over a path reference; both absent → no body.
    let body = if let Some(s) = inline {
        Body::Inline(s)
    } else if let Some(p) = body_path {
        Body::Path(p)
    } else {
        Body::None
    };

    frontmatter.sort_by_key(|e| e.order);
    mcp_servers.sort_by(|a, b| a.name.cmp(&b.name));
    // Permission lists are sets — normalize to a deterministic (sorted)
    // order so projected settings.json is byte-stable.
    settings_allow.sort();
    settings_allow.dedup();
    settings_dirs.sort();
    settings_dirs.dedup();
    body_fragments.sort_by_key(|f| f.order);
    if target_path.is_empty() {
        bail!("aide:OutputFile is missing aide:targetPath");
    }
    Ok(OutputFile {
        target_path,
        format,
        frontmatter,
        body,
        json_shape,
        mcp_servers,
        settings_allow,
        settings_dirs,
        body_fragments,
        strip_body_frontmatter,
    })
}

/// Resolve a term (blank node or IRI) to its property list in the graph.
fn lookup<'a>(
    o: &Term,
    spo: &'a BTreeMap<String, Vec<(String, Term)>>,
) -> Option<&'a Vec<(String, Term)>> {
    let key = match o {
        Term::Blank(b) => format!("_:{b}"),
        Term::Iri(i) => i.clone(),
        Term::Lit(_) => return None,
    };
    spo.get(&key)
}

fn read_mcp_entry(
    props: &[(String, Term)],
    spo: &BTreeMap<String, Vec<(String, Term)>>,
) -> McpServerSpec {
    let mut name = String::new();
    let mut flavor = McpFlavor::Other(String::new());
    let mut transport = None;
    let mut command = None;
    let mut url = None;
    let mut bazel_label = None;
    let mut args = Vec::new();
    let mut env = Vec::new();
    let mut headers = Vec::new();

    for (p, o) in props {
        match (p.strip_prefix(NS), o) {
            (Some("serverName"), Term::Lit(v)) => name = v.clone(),
            (Some("mcpFlavor"), Term::Iri(i)) => flavor = McpFlavor::from_iri(i),
            (Some("transport"), Term::Iri(i)) => transport = Some(Transport::from_iri(i)),
            (Some("command"), Term::Lit(v)) => command = Some(v.clone()),
            (Some("url"), Term::Lit(v)) => url = Some(v.clone()),
            (Some("bazelLabel"), Term::Lit(v)) => bazel_label = Some(v.clone()),
            (Some("arg"), _) => {
                if let Some(ap) = lookup(o, spo) {
                    let (val, order) = read_arg(ap);
                    args.push((order, val));
                }
            }
            (Some("envVar"), _) => {
                if let Some(ep) = lookup(o, spo) {
                    env.push(read_kv(ep));
                }
            }
            (Some("header"), _) => {
                if let Some(hp) = lookup(o, spo) {
                    headers.push(read_kv(hp));
                }
            }
            _ => {}
        }
    }

    args.sort_by_key(|(order, _)| *order);
    env.sort();
    headers.sort();
    McpServerSpec {
        name,
        flavor,
        transport,
        command,
        args,
        env,
        url,
        headers,
        bazel_label,
    }
}

fn read_arg(props: &[(String, Term)]) -> (String, i64) {
    let mut val = String::new();
    let mut order = i64::MAX;
    for (p, o) in props {
        match (p.strip_prefix(NS), o) {
            (Some("value"), Term::Lit(v)) => val = v.clone(),
            (Some("order"), Term::Lit(v)) => order = v.parse().unwrap_or(i64::MAX),
            _ => {}
        }
    }
    (val, order)
}

fn read_fragment(props: &[(String, Term)]) -> BodyFragment {
    let mut order = i64::MAX;
    let mut header = None;
    let mut body_path = String::new();
    for (p, o) in props {
        match (p.strip_prefix(NS), o) {
            (Some("order"), Term::Lit(v)) => order = v.parse().unwrap_or(i64::MAX),
            (Some("fragmentHeader"), Term::Lit(v)) => header = Some(v.clone()),
            (Some("bodyPath"), Term::Lit(v)) => body_path = v.clone(),
            _ => {}
        }
    }
    BodyFragment {
        order,
        header,
        body_path,
    }
}

fn read_kv(props: &[(String, Term)]) -> (String, String) {
    let mut k = String::new();
    let mut v = String::new();
    for (p, o) in props {
        match (p.strip_prefix(NS), o) {
            (Some("key"), Term::Lit(s)) => k = s.clone(),
            (Some("value"), Term::Lit(s)) => v = s.clone(),
            _ => {}
        }
    }
    (k, v)
}

fn read_entry(
    props: &[(String, Term)],
    spo: &BTreeMap<String, Vec<(String, Term)>>,
) -> FrontmatterEntry {
    let mut key = String::new();
    let mut order = i64::MAX;
    let mut scalar: Option<String> = None;
    let mut list: Vec<(i64, String)> = Vec::new();
    let mut map: Vec<FrontmatterEntry> = Vec::new();
    for (p, o) in props {
        match (p.strip_prefix(NS), o) {
            (Some("key"), Term::Lit(v)) => key = v.clone(),
            (Some("order"), Term::Lit(v)) => order = v.parse().unwrap_or(i64::MAX),
            (Some("value"), Term::Lit(v)) => scalar = Some(v.clone()),
            (Some("listItem"), _) => {
                if let Some(item) = lookup(o, spo) {
                    let (val, ord) = read_arg(item);
                    list.push((ord, val));
                }
            }
            (Some("subEntry"), _) => {
                if let Some(sub) = lookup(o, spo) {
                    map.push(read_entry(sub, spo));
                }
            }
            _ => {}
        }
    }
    // Map wins over list wins over scalar (an entry is one kind).
    let value = if !map.is_empty() {
        map.sort_by_key(|e| e.order);
        FmValue::Map(map)
    } else if !list.is_empty() {
        list.sort_by_key(|(ord, _)| *ord);
        FmValue::List(list.into_iter().map(|(_, v)| v).collect())
    } else {
        FmValue::Scalar(scalar.unwrap_or_default())
    };
    FrontmatterEntry { key, order, value }
}

// ---------- N-Triples line parsing ----------

fn parse_line(line: &str) -> Option<(Term, Term, Term)> {
    let line = line.trim_end();
    let line = line.strip_suffix('.')?.trim_end();
    let mut pos = 0usize;
    let s = read_term(line, &mut pos)?;
    let p = read_term(line, &mut pos)?;
    let o = read_term(line, &mut pos)?;
    Some((s, p, o))
}

fn read_term(line: &str, pos: &mut usize) -> Option<Term> {
    let bytes = line.as_bytes();
    while *pos < bytes.len() && (bytes[*pos] == b' ' || bytes[*pos] == b'\t') {
        *pos += 1;
    }
    if *pos >= bytes.len() {
        return None;
    }
    let rest = &line[*pos..];
    match bytes[*pos] {
        b'<' => {
            let gt = rest.find('>')?;
            let iri = &rest[1..gt];
            *pos += gt + 1;
            Some(Term::Iri(iri.to_string()))
        }
        b'"' => {
            let (val, consumed) = scan_literal(rest)?;
            *pos += consumed;
            Some(Term::Lit(val))
        }
        b'_' => {
            let end = rest.find([' ', '\t']).unwrap_or(rest.len());
            let tok = &rest[..end];
            *pos += end;
            tok.strip_prefix("_:").map(|l| Term::Blank(l.to_string()))
        }
        _ => None,
    }
}

/// Scan an N-Triples literal at the opening quote of `s`. Returns the
/// unescaped lexical value and the number of bytes consumed (covering
/// the quoted form plus any `^^<datatype>` or `@lang` suffix, both of
/// which we discard — the projection only needs lexical values).
fn scan_literal(s: &str) -> Option<(String, usize)> {
    let mut out = String::new();
    let mut it = s.char_indices();
    if it.next()?.1 != '"' {
        return None;
    }
    let mut closing_end = None;
    while let Some((bi, c)) = it.next() {
        match c {
            '\\' => {
                let e = it.next()?.1;
                match e {
                    'n' => out.push('\n'),
                    't' => out.push('\t'),
                    'r' => out.push('\r'),
                    'b' => out.push('\u{0008}'),
                    'f' => out.push('\u{000C}'),
                    '"' => out.push('"'),
                    '\\' => out.push('\\'),
                    '/' => out.push('/'),
                    'u' => {
                        let mut hex = String::new();
                        for _ in 0..4 {
                            hex.push(it.next()?.1);
                        }
                        out.push(char::from_u32(u32::from_str_radix(&hex, 16).ok()?)?);
                    }
                    'U' => {
                        let mut hex = String::new();
                        for _ in 0..8 {
                            hex.push(it.next()?.1);
                        }
                        out.push(char::from_u32(u32::from_str_radix(&hex, 16).ok()?)?);
                    }
                    _ => return None,
                }
            }
            '"' => {
                closing_end = Some(bi + 1);
                break;
            }
            _ => out.push(c),
        }
    }
    let mut end = closing_end?;
    let rest = &s[end..];
    if let Some(r) = rest.strip_prefix("^^<") {
        end += 3 + r.find('>')? + 1;
    } else if let Some(r) = rest.strip_prefix('@') {
        let tag_len = r
            .find(|ch: char| !(ch.is_ascii_alphanumeric() || ch == '-'))
            .unwrap_or(r.len());
        end += 1 + tag_len;
    }
    Some((out, end))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_skill_filespec() {
        let nt = r#"
_:b0 <https://fastverk.dev/ontology/agentic_ide/projection#key> "name" .
_:b0 <https://fastverk.dev/ontology/agentic_ide/projection#value> "debugging" .
_:b0 <https://fastverk.dev/ontology/agentic_ide/projection#order> "0"^^<http://www.w3.org/2001/XMLSchema#integer> .
<https://x/out> <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> <https://fastverk.dev/ontology/agentic_ide/projection#OutputFile> .
<https://x/out> <https://fastverk.dev/ontology/agentic_ide/projection#targetPath> ".claude/skills/debugging/SKILL.md" .
<https://x/out> <https://fastverk.dev/ontology/agentic_ide/projection#fileFormat> <https://fastverk.dev/ontology/agentic_ide/projection#MarkdownYaml> .
<https://x/out> <https://fastverk.dev/ontology/agentic_ide/projection#bodyPath> ".agents/skills/debugging/SKILL.md" .
<https://x/out> <https://fastverk.dev/ontology/agentic_ide/projection#frontmatter> _:b0 .
"#;
        let files = parse_filespec(nt).unwrap();
        assert_eq!(files.len(), 1);
        let f = &files[0];
        assert_eq!(f.target_path, ".claude/skills/debugging/SKILL.md");
        assert_eq!(f.format, FileFormat::MarkdownYaml);
        assert!(matches!(&f.body, Body::Path(p) if p == ".agents/skills/debugging/SKILL.md"));
        assert_eq!(f.frontmatter.len(), 1);
        assert_eq!(f.frontmatter[0].key, "name");
        assert!(matches!(&f.frontmatter[0].value, FmValue::Scalar(v) if v == "debugging"));
        assert_eq!(f.frontmatter[0].order, 0);
    }
}
