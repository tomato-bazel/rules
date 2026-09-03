//! `hf-endpoints` — a typed CLI over the generated HF Inference
//! Endpoints client (`inference_endpoints_client`). Drives the
//! control-plane verbs the `hf_inference_endpoint` rule emits:
//! deploy / pause / resume / scale-to-zero / delete / describe / list.
//!
//! Auth is `HF_TOKEN` (bearer). The base URL defaults to the public
//! Inference Endpoints API and is overridable for testing.

use anyhow::{anyhow, Context, Result};
use clap::{Parser, Subcommand};
use inference_endpoints_client::{types, Client};

const DEFAULT_BASE_URL: &str = "https://api.endpoints.huggingface.cloud";

#[derive(Parser)]
#[command(name = "hf-endpoints", about = "Typed HF Inference Endpoints control plane")]
struct Cli {
    /// HF namespace (user or org) that owns the endpoint.
    #[arg(long, global = true, env = "HF_NAMESPACE")]
    namespace: Option<String>,
    /// API base URL (override for testing).
    #[arg(long, global = true, env = "HF_ENDPOINTS_URL", default_value = DEFAULT_BASE_URL)]
    base_url: String,
    #[command(subcommand)]
    cmd: Cmd,
}

#[derive(Subcommand)]
enum Cmd {
    /// Create the endpoint from a JSON config (an `Endpoint` body).
    Deploy {
        /// Path to the endpoint JSON config.
        #[arg(long)]
        config: String,
    },
    /// Pause a running endpoint.
    Pause {
        #[arg(long)]
        name: String,
    },
    /// Resume a paused endpoint.
    Resume {
        #[arg(long)]
        name: String,
    },
    /// Scale an endpoint to zero replicas.
    ScaleToZero {
        #[arg(long)]
        name: String,
    },
    /// Delete an endpoint permanently.
    Delete {
        #[arg(long)]
        name: String,
    },
    /// Print an endpoint's current state.
    Describe {
        #[arg(long)]
        name: String,
    },
    /// List all endpoints in the namespace.
    List,
}

fn namespace(cli: &Cli) -> Result<&str> {
    cli.namespace
        .as_deref()
        .ok_or_else(|| anyhow!("--namespace (or HF_NAMESPACE) is required"))
}

/// Build an authenticated client: a reqwest client carrying the
/// `Authorization: Bearer <HF_TOKEN>` default header, wrapped by the
/// generated progenitor `Client`.
fn client(base_url: &str) -> Result<Client> {
    let token = std::env::var("HF_TOKEN")
        .context("HF_TOKEN not set in env (needed to authenticate to the Endpoints API)")?;
    let mut headers = reqwest::header::HeaderMap::new();
    let mut auth = reqwest::header::HeaderValue::from_str(&format!("Bearer {token}"))
        .context("building Authorization header")?;
    auth.set_sensitive(true);
    headers.insert(reqwest::header::AUTHORIZATION, auth);
    let http = reqwest::Client::builder()
        .default_headers(headers)
        .build()
        .context("building reqwest client")?;
    Ok(Client::new_with_client(base_url, http))
}

fn print_json<T: serde::Serialize>(v: &T) -> Result<()> {
    println!("{}", serde_json::to_string_pretty(v)?);
    Ok(())
}

#[tokio::main]
async fn main() -> Result<()> {
    let cli = Cli::parse();
    let c = client(&cli.base_url)?;
    match &cli.cmd {
        Cmd::Deploy { config } => {
            let ns = namespace(&cli)?;
            let raw = std::fs::read_to_string(config)
                .with_context(|| format!("reading endpoint config {config}"))?;
            let body: types::Endpoint = serde_json::from_str(&raw)
                .with_context(|| format!("parsing {config} as an Endpoint config"))?;
            let resp = c
                .create_endpoint(ns, &body)
                .await
                .map_err(|e| anyhow!("create_endpoint failed: {e}"))?;
            print_json(&*resp)
        }
        Cmd::Pause { name } => {
            let resp = c
                .pause_endpoint(namespace(&cli)?, name)
                .await
                .map_err(|e| anyhow!("pause_endpoint failed: {e}"))?;
            print_json(&*resp)
        }
        Cmd::Resume { name } => {
            let resp = c
                .resume_endpoint(namespace(&cli)?, name)
                .await
                .map_err(|e| anyhow!("resume_endpoint failed: {e}"))?;
            print_json(&*resp)
        }
        Cmd::ScaleToZero { name } => {
            let resp = c
                .scale_to_zero_endpoint(namespace(&cli)?, name)
                .await
                .map_err(|e| anyhow!("scale_to_zero_endpoint failed: {e}"))?;
            print_json(&*resp)
        }
        Cmd::Delete { name } => {
            c.delete_endpoint(namespace(&cli)?, name)
                .await
                .map_err(|e| anyhow!("delete_endpoint failed: {e}"))?;
            println!("deleted endpoint {name}");
            Ok(())
        }
        Cmd::Describe { name } => {
            let resp = c
                .get_endpoint(namespace(&cli)?, name)
                .await
                .map_err(|e| anyhow!("get_endpoint failed: {e}"))?;
            print_json(&*resp)
        }
        Cmd::List => {
            let resp = c
                .list_endpoint(namespace(&cli)?, None, None, None, None)
                .await
                .map_err(|e| anyhow!("list_endpoint failed: {e}"))?;
            print_json(&*resp)
        }
    }
}
