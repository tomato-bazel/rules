//! `agentic-ide-generate` — the PUBLIC projection CLI.
//!
//! Materializes per-IDE agent-config files from an `aide:OutputFile`
//! N-Triples filespec (the output of the projection CONSTRUCT queries).
//! Depends only on `agentic_ide_projection` — no private deps — so it is
//! the public repo's sole user-facing binary. The private repo keeps the
//! full `agentic-ide` CLI (harvest / consolidate / mcp serve / …).

use std::path::PathBuf;

use agentic_ide_projection::Status;
use anyhow::{Context, Result};
use clap::Parser;

#[derive(Parser, Debug)]
#[command(
    name = "agentic-ide-generate",
    version,
    about = "Project the agent-config knowledge graph into per-IDE files."
)]
struct Cli {
    /// N-Triples filespec produced by a projection `sparql_query` target
    /// (an `aide:OutputFile` graph).
    #[arg(long)]
    filespec: PathBuf,
    /// Repo root to write into / resolve body paths against. Defaults to
    /// $BUILD_WORKSPACE_DIRECTORY (set by `bazel run`) else the cwd.
    #[arg(long, short = 'o')]
    out: Option<PathBuf>,
    /// Report what would change without writing anything.
    #[arg(long)]
    dry_run: bool,
}

fn main() -> Result<()> {
    let cli = Cli::parse();
    // `bazel run` sets BUILD_WORKSPACE_DIRECTORY to the invoking repo so
    // generated files land in the working tree, not the sandbox.
    let repo_root = cli
        .out
        .or_else(|| std::env::var_os("BUILD_WORKSPACE_DIRECTORY").map(PathBuf::from))
        .unwrap_or_else(|| PathBuf::from("."));

    let results = agentic_ide_projection::generate(&cli.filespec, &repo_root, cli.dry_run)
        .context("projecting agent-config files")?;

    let (mut created, mut changed, mut unchanged) = (0, 0, 0);
    for f in &results {
        let tag = match f.status {
            Status::Created => {
                created += 1;
                "create"
            }
            Status::Changed => {
                changed += 1;
                "update"
            }
            Status::Unchanged => {
                unchanged += 1;
                "noop  "
            }
        };
        println!("{tag}  {}", f.path);
    }
    eprintln!(
        "{} {} file(s) under {} ({created} created, {changed} changed, {unchanged} unchanged){}",
        if cli.dry_run { "would write" } else { "wrote" },
        results.len(),
        repo_root.display(),
        if cli.dry_run { " [dry-run]" } else { "" }
    );
    Ok(())
}
