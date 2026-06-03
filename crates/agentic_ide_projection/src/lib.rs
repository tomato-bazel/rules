//! Forward projection: turn the `aide:OutputFile` filespec graph
//! (produced by the per-IDE SPARQL CONSTRUCT queries) into actual
//! on-disk agent-config files. The inverse of the harvest parsers.
//!
//! Pipeline: authored RDF → per-IDE CONSTRUCT (a `sparql_query` bazel
//! target) → N-Triples filespec → [`parse_filespec`] → [`write_all`].
//! The serializer branches only on `aide:fileFormat`, so one code path
//! handles skills, agents, rulesets, and commands alike.

mod filespec;
mod serialize;

pub use filespec::{parse_filespec, Body, FileFormat, FrontmatterEntry, OutputFile};
pub use serialize::{render, write_all, GeneratedFile, Status};

use std::path::Path;

use anyhow::{Context, Result};

/// Parse the N-Triples filespec at `filespec_path` and materialize each
/// described file under `repo_root`. With `dry_run`, nothing is written
/// — the returned list reports what *would* change.
pub fn generate(filespec_path: &Path, repo_root: &Path, dry_run: bool) -> Result<Vec<GeneratedFile>> {
    let nt = std::fs::read_to_string(filespec_path)
        .with_context(|| format!("reading filespec {}", filespec_path.display()))?;
    let mut files = parse_filespec(&nt)
        .with_context(|| format!("parsing filespec {}", filespec_path.display()))?;
    // Deterministic order → stable output and clean diffs.
    files.sort_by(|a, b| a.target_path.cmp(&b.target_path));
    write_all(&files, repo_root, dry_run)
}
