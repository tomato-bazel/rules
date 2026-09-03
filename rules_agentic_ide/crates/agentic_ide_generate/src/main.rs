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
    /// Drift gate: render and diff content hashes against
    /// .agents/generated.lock without writing. Exits non-zero if the
    /// generated files are out of date (graph edit or version bump not
    /// regenerated). Intended for CI.
    #[arg(long)]
    check: bool,
}

fn main() -> Result<()> {
    let cli = Cli::parse();
    // `bazel run` sets BUILD_WORKSPACE_DIRECTORY to the invoking repo so
    // generated files land in the working tree, not the sandbox.
    let repo_root = cli
        .out
        .or_else(|| std::env::var_os("BUILD_WORKSPACE_DIRECTORY").map(PathBuf::from))
        .unwrap_or_else(|| PathBuf::from("."));

    if cli.check {
        return run_check(&cli.filespec, &repo_root);
    }

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

/// Drift gate: compare freshly-rendered hashes to .agents/generated.lock.
/// Prints the drift and exits non-zero if anything is stale.
fn run_check(filespec: &std::path::Path, repo_root: &std::path::Path) -> Result<()> {
    let drift = agentic_ide_projection::check(filespec, repo_root)
        .context("checking generated-file drift")?;
    for p in &drift.added {
        println!("added    {p}");
    }
    for p in &drift.changed {
        println!("changed  {p}");
    }
    for p in &drift.removed {
        println!("removed  {p}");
    }
    if drift.is_clean() {
        eprintln!("generated files are up to date with .agents/generated.lock");
        Ok(())
    } else {
        eprintln!(
            "drift: {} added, {} changed, {} removed — run `generate` and commit .agents/generated.lock",
            drift.added.len(),
            drift.changed.len(),
            drift.removed.len()
        );
        std::process::exit(1);
    }
}
