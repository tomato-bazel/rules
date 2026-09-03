//! The generated-files manifest (`.agents/generated.lock`).
//!
//! Generated config files are gitignored derived artifacts, so a framework
//! version bump would otherwise change them with no diff to review. The
//! manifest is the review surface: a committed content-hash snapshot
//! (`agentic_ide.v1.GeneratedManifest`, on-disk as textproto). `generate`
//! rewrites it; `generate --check` diffs the freshly-rendered hashes
//! against it, so drift — whether from a graph edit or a version bump —
//! shows up as a reviewable lock diff and a CI gate.

use std::collections::BTreeMap;

use crate::serialize::GeneratedFile;

/// path -> sha256 (sorted, deterministic).
#[derive(Debug, Default, Clone, PartialEq, Eq)]
pub struct Manifest {
    pub entries: BTreeMap<String, String>,
}

/// What `--check` found relative to the committed manifest.
#[derive(Debug, Default)]
pub struct Drift {
    pub added: Vec<String>,
    pub removed: Vec<String>,
    pub changed: Vec<String>,
}

impl Drift {
    pub fn is_clean(&self) -> bool {
        self.added.is_empty() && self.removed.is_empty() && self.changed.is_empty()
    }
}

impl Manifest {
    pub fn from_files(files: &[GeneratedFile]) -> Self {
        let entries = files
            .iter()
            .map(|f| (f.path.clone(), f.sha256.clone()))
            .collect();
        Manifest { entries }
    }

    /// On-disk textproto form of `agentic_ide.v1.GeneratedManifest`.
    /// Deterministic (sorted), one `entries { … }` per line for clean diffs.
    pub fn to_textproto(&self) -> String {
        let mut s = String::new();
        s.push_str("# agentic_ide.v1.GeneratedManifest — generated; do not edit.\n");
        s.push_str("# Content hashes of the projected files; `generate --check` diffs against this.\n");
        for (path, sha) in &self.entries {
            s.push_str(&format!(
                "entries {{ path: {} sha256: \"{}\" }}\n",
                quote(path),
                sha
            ));
        }
        s
    }

    /// Parse the textproto form (tolerant line scan — every `entries { … }`).
    pub fn parse_textproto(text: &str) -> Self {
        let mut entries = BTreeMap::new();
        for line in text.lines() {
            let line = line.trim();
            if !line.starts_with("entries") {
                continue;
            }
            if let (Some(p), Some(s)) = (field(line, "path:"), field(line, "sha256:")) {
                entries.insert(p, s);
            }
        }
        Manifest { entries }
    }

    /// `self` is the freshly-rendered manifest; `prev` the committed one.
    pub fn diff(&self, prev: &Manifest) -> Drift {
        let mut d = Drift::default();
        for (path, sha) in &self.entries {
            match prev.entries.get(path) {
                None => d.added.push(path.clone()),
                Some(old) if old != sha => d.changed.push(path.clone()),
                _ => {}
            }
        }
        for path in prev.entries.keys() {
            if !self.entries.contains_key(path) {
                d.removed.push(path.clone());
            }
        }
        d
    }
}

/// Extract a textproto `<field> "<value>"` token from a line.
fn field(line: &str, key: &str) -> Option<String> {
    let after = line.split(key).nth(1)?;
    let start = after.find('"')? + 1;
    let rest = &after[start..];
    let end = rest.find('"')?;
    Some(rest[..end].to_string())
}

/// Minimal proto string quoting (paths can't contain quotes/newlines in
/// practice, but be safe).
fn quote(s: &str) -> String {
    let mut q = String::with_capacity(s.len() + 2);
    q.push('"');
    for c in s.chars() {
        match c {
            '"' => q.push_str("\\\""),
            '\\' => q.push_str("\\\\"),
            _ => q.push(c),
        }
    }
    q.push('"');
    q
}
