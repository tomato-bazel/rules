//! ssh-tui-server: a thin SSH front-end that spawns a configured
//! login binary under a PTY and bridges the SSH channel to it.
//!
//! Design constraints we picked deliberately:
//!
//! - **One binary, one purpose.** No shell, no SCP/SFTP, no exec
//!   commands except the configured `--login-binary`. Anything the
//!   client tries (ForceCommand-bypass, port forwarding, agent
//!   forwarding) is refused.
//! - **Public-key auth only.** No passwords, no keyboard-interactive,
//!   no host-based. Keys are read from a plain OpenSSH-format
//!   authorized_keys file at startup.
//! - **Host key persistence.** A long-lived ed25519 host key is
//!   read/generated at the path given by `--host-key`. The first run
//!   creates one; subsequent runs reuse it so clients don't see a
//!   host-key-changed warning on reconnect.
//! - **PTY-only.** Sessions without `pty-req` are refused. A NOC TUI
//!   has no use for non-TTY shells.
//!
//! This is enough to drive a `bazel run //…:noc-tui` workflow today;
//! agent forwarding, port forwarding, and SFTP are explicit no-gos for
//! the foreseeable future.

use anyhow::{anyhow, Context as _, Result};
use async_trait::async_trait;
use clap::Parser;
use portable_pty::{CommandBuilder, PtyPair, PtySize};
use russh::keys::key::{KeyPair, PublicKey};
use russh::keys::PublicKeyBase64;
use russh::server::{Auth, Handler, Msg, Server as _, Session};
use russh::{Channel, ChannelId, CryptoVec, MethodSet};
use std::collections::HashMap;
use std::io::Read;
use std::path::{Path, PathBuf};
use std::sync::Arc;
use tokio::sync::{mpsc, Mutex};
use tracing_subscriber::EnvFilter;

#[derive(Parser, Debug)]
#[command(name = "ssh-tui-server", about = "russh-based TUI launcher")]
struct Args {
    /// Bind address, e.g. 0.0.0.0:22.
    #[arg(long, default_value = "0.0.0.0:22")]
    listen: String,

    /// Persisted ed25519 host key. Generated on first start if absent.
    #[arg(long, default_value = "/var/lib/ssh-tui/host_key")]
    host_key: PathBuf,

    /// OpenSSH-format authorized_keys file (one pubkey per line).
    /// Missing or empty file is allowed when --github-users is set.
    #[arg(long, default_value = "/var/lib/ssh-tui/authorized_keys")]
    authorized_keys: PathBuf,

    /// Comma-separated GitHub usernames whose public SSH keys
    /// (fetched from https://github.com/<user>.keys at startup)
    /// are appended to the accepted set. Use this when you want
    /// SSH access governed by org membership / personal account
    /// instead of a hand-maintained file. Env: GITHUB_USERS.
    #[arg(long, value_delimiter = ',', env = "GITHUB_USERS")]
    github_users: Vec<String>,

    /// Path to the login binary. Spawned under a PTY for every
    /// successful session.
    #[arg(long)]
    login_binary: PathBuf,

    /// Additional positional args passed to the login binary after
    /// `--`. e.g.
    ///   ssh-tui-server --login-binary /app/botnoc -- --org-addr ...
    #[arg(last = true)]
    login_args: Vec<String>,
}

#[tokio::main]
async fn main() -> Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(
            EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::new("info")),
        )
        .init();

    let args = Args::parse();

    let host_key = load_or_create_host_key(&args.host_key)?;
    let mut authorized_keys = if args.authorized_keys.exists() {
        load_authorized_keys(&args.authorized_keys)?
    } else if args.github_users.is_empty() {
        return Err(anyhow!(
            "no authorized_keys file at {} and no --github-users; refusing to start",
            args.authorized_keys.display()
        ));
    } else {
        tracing::info!(
            path = %args.authorized_keys.display(),
            "no authorized_keys file present; relying on --github-users",
        );
        Vec::new()
    };
    let file_count = authorized_keys.len();
    let mut github_count = 0;
    for user in &args.github_users {
        let fetched = fetch_github_keys(user).await.with_context(|| {
            format!("fetch SSH pubkeys for GitHub user {user}")
        })?;
        github_count += fetched.len();
        authorized_keys.extend(fetched);
    }
    if authorized_keys.is_empty() {
        return Err(anyhow!(
            "authorized_keys file + GitHub fetch produced 0 valid pubkeys; refusing to start",
        ));
    }
    tracing::info!(
        listen = %args.listen,
        host_key = %args.host_key.display(),
        authorized_keys = %args.authorized_keys.display(),
        login_binary = %args.login_binary.display(),
        login_args = ?args.login_args,
        github_users = ?args.github_users,
        accepted_keys = authorized_keys.len(),
        accepted_keys_from_file = file_count,
        accepted_keys_from_github = github_count,
        "ssh-tui-server ready",
    );

    let config = russh::server::Config {
        inactivity_timeout: Some(std::time::Duration::from_secs(3600)),
        auth_rejection_time: std::time::Duration::from_secs(2),
        methods: MethodSet::PUBLICKEY,
        keys: vec![host_key],
        ..Default::default()
    };

    let mut server = AppServer {
        authorized_keys: Arc::new(authorized_keys),
        login_binary: args.login_binary,
        login_args: args.login_args,
    };
    server
        .run_on_address(Arc::new(config), args.listen.as_str())
        .await
        .map_err(|e| anyhow!("server loop: {e}"))?;
    Ok(())
}

/// Read the host key from disk if present, otherwise generate a fresh
/// ed25519 keypair, write it to `path`, and return it. Permissions on
/// the written key file are 0600.
fn load_or_create_host_key(path: &Path) -> Result<KeyPair> {
    if path.is_file() {
        let bytes = std::fs::read(path).with_context(|| format!("read {}", path.display()))?;
        let key = russh::keys::decode_secret_key(
            std::str::from_utf8(&bytes).context("host key not utf-8")?,
            None,
        )
        .map_err(|e| anyhow!("decode host key at {}: {e}", path.display()))?;
        return Ok(key);
    }
    tracing::info!(path = %path.display(), "host key missing; generating fresh ed25519");
    let key = KeyPair::generate_ed25519().ok_or_else(|| anyhow!("ed25519 keygen failed"))?;
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent).ok();
    }
    let mut buf: Vec<u8> = Vec::new();
    russh::keys::encode_pkcs8_pem(&key, &mut buf)
        .map_err(|e| anyhow!("serialize host key: {e}"))?;
    std::fs::write(path, &buf)
        .with_context(|| format!("write host key to {}", path.display()))?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let _ = std::fs::set_permissions(path, std::fs::Permissions::from_mode(0o600));
    }
    Ok(key)
}

/// Parse an OpenSSH-format authorized_keys file. Returns one PublicKey
/// per non-comment, non-empty line. Lines that fail to parse are
/// skipped with a warning — partial-broken file behaves like
/// partial-good rather than refusing all auth.
fn load_authorized_keys(path: &Path) -> Result<Vec<PublicKey>> {
    let body = std::fs::read_to_string(path)
        .with_context(|| format!("read authorized_keys at {}", path.display()))?;
    Ok(parse_authorized_keys_body(&body, &format!("file {}", path.display())))
}

/// Fetch one GitHub user's public SSH keys from
/// `https://github.com/<user>.keys`, parse each line, and return
/// the recognized russh PublicKey values. Unrecognized lines are
/// skipped with a warning so a single malformed entry doesn't
/// reject every other key on the user's account.
async fn fetch_github_keys(user: &str) -> Result<Vec<PublicKey>> {
    let url = format!("https://github.com/{user}.keys");
    let body = reqwest::Client::builder()
        .user_agent("ssh-tui-server")
        .build()
        .context("build reqwest client")?
        .get(&url)
        .send()
        .await
        .with_context(|| format!("GET {url}"))?
        .error_for_status()
        .with_context(|| format!("GET {url} non-2xx"))?
        .text()
        .await
        .context("read body")?;
    let keys = parse_authorized_keys_body(&body, &format!("github:{user}"));
    tracing::info!(
        user = %user,
        keys = keys.len(),
        "fetched GitHub SSH pubkeys",
    );
    Ok(keys)
}

fn parse_authorized_keys_body(body: &str, src: &str) -> Vec<PublicKey> {
    let mut keys = Vec::new();
    for (idx, raw) in body.lines().enumerate() {
        let line = raw.trim();
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        match russh::keys::parse_public_key_base64(line) {
            Ok(k) => keys.push(k),
            Err(_) => {
                let parts: Vec<&str> = line.split_whitespace().collect();
                if parts.len() >= 2 {
                    if let Ok(k) = russh::keys::parse_public_key_base64(parts[1]) {
                        keys.push(k);
                        continue;
                    }
                }
                tracing::warn!(
                    src = %src,
                    line = idx + 1,
                    "skipping unparseable pubkey line",
                );
            }
        }
    }
    keys
}

#[derive(Clone)]
struct AppServer {
    authorized_keys: Arc<Vec<PublicKey>>,
    login_binary: PathBuf,
    login_args: Vec<String>,
}

impl russh::server::Server for AppServer {
    type Handler = SessionHandler;
    fn new_client(&mut self, addr: Option<std::net::SocketAddr>) -> SessionHandler {
        tracing::info!(?addr, "incoming session");
        SessionHandler {
            authorized_keys: Arc::clone(&self.authorized_keys),
            login_binary: self.login_binary.clone(),
            login_args: self.login_args.clone(),
            authed_key: None,
            channels: Default::default(),
        }
    }
}

/// Per-channel state. `pty_size` carries the most-recent window dims;
/// `writer_tx` is the producer end of the channel data we want to
/// feed into the PTY (closed when the SSH side hangs up).
struct ChannelState {
    pty_pair: Option<PtyPair>,
    pty_size: PtySize,
    writer_tx: Option<mpsc::Sender<Vec<u8>>>,
}

struct SessionHandler {
    authorized_keys: Arc<Vec<PublicKey>>,
    login_binary: PathBuf,
    login_args: Vec<String>,
    authed_key: Option<PublicKey>,
    channels: Arc<Mutex<HashMap<ChannelId, ChannelState>>>,
}

#[async_trait]
impl Handler for SessionHandler {
    type Error = russh::Error;

    async fn auth_publickey(
        &mut self,
        _user: &str,
        public_key: &PublicKey,
    ) -> Result<Auth, Self::Error> {
        let accept = self
            .authorized_keys
            .iter()
            .any(|k| k.public_key_bytes() == public_key.public_key_bytes());
        if accept {
            tracing::info!(fingerprint = %public_key.fingerprint(), "auth ok");
            self.authed_key = Some(public_key.clone());
            Ok(Auth::Accept)
        } else {
            tracing::warn!(fingerprint = %public_key.fingerprint(), "auth refused: not in authorized_keys");
            Ok(Auth::Reject {
                proceed_with_methods: None,
            })
        }
    }

    async fn channel_open_session(
        &mut self,
        channel: Channel<Msg>,
        _session: &mut Session,
    ) -> Result<bool, Self::Error> {
        let mut state = self.channels.lock().await;
        state.insert(
            channel.id(),
            ChannelState {
                pty_pair: None,
                pty_size: PtySize::default(),
                writer_tx: None,
            },
        );
        Ok(true)
    }

    async fn pty_request(
        &mut self,
        channel: ChannelId,
        _term: &str,
        col_width: u32,
        row_height: u32,
        pix_width: u32,
        pix_height: u32,
        _modes: &[(russh::Pty, u32)],
        session: &mut Session,
    ) -> Result<(), Self::Error> {
        let size = PtySize {
            rows: row_height as u16,
            cols: col_width as u16,
            pixel_width: pix_width as u16,
            pixel_height: pix_height as u16,
        };
        let pty_system = portable_pty::native_pty_system();
        let pair = pty_system
            .openpty(size)
            .map_err(|e| russh::Error::IO(std::io::Error::other(format!("openpty: {e}"))))?;
        let mut state = self.channels.lock().await;
        if let Some(s) = state.get_mut(&channel) {
            s.pty_pair = Some(pair);
            s.pty_size = size;
        }
        let _ = session.channel_success(channel);
        Ok(())
    }

    async fn window_change_request(
        &mut self,
        channel: ChannelId,
        col_width: u32,
        row_height: u32,
        pix_width: u32,
        pix_height: u32,
        _session: &mut Session,
    ) -> Result<(), Self::Error> {
        let size = PtySize {
            rows: row_height as u16,
            cols: col_width as u16,
            pixel_width: pix_width as u16,
            pixel_height: pix_height as u16,
        };
        let mut state = self.channels.lock().await;
        if let Some(s) = state.get_mut(&channel) {
            s.pty_size = size;
            if let Some(p) = &s.pty_pair {
                let _ = p.master.resize(size);
            }
        }
        Ok(())
    }

    async fn shell_request(
        &mut self,
        channel: ChannelId,
        session: &mut Session,
    ) -> Result<(), Self::Error> {
        // pty_request must have come first; if not, refuse.
        let mut state_guard = self.channels.lock().await;
        let st = match state_guard.get_mut(&channel) {
            Some(s) => s,
            None => return Ok(()),
        };
        let pair = match st.pty_pair.take() {
            Some(p) => p,
            None => {
                tracing::warn!(?channel, "shell-request without prior pty-req; refusing");
                session.channel_failure(channel);
                return Ok(());
            }
        };

        // Spawn login binary under the PTY's slave end.
        let mut cmd = CommandBuilder::new(self.login_binary.as_os_str());
        for a in &self.login_args {
            cmd.arg(a);
        }
        // The login binary expects a TERM; set a sane default.
        cmd.env("TERM", "xterm-256color");
        let mut child = pair
            .slave
            .spawn_command(cmd)
            .map_err(|e| russh::Error::IO(std::io::Error::other(format!("spawn: {e}"))))?;

        // Per-channel: producer/consumer for stdin bytes from SSH → PTY.
        let (tx, mut rx) = mpsc::channel::<Vec<u8>>(64);
        st.writer_tx = Some(tx);

        // Hand over the PTY master to two tasks: reader (PTY → SSH)
        // and writer (SSH → PTY).
        let master = pair.master;
        // master.try_clone_writer gives an owned writer; reader stays on master.
        let mut writer = master
            .take_writer()
            .map_err(|e| russh::Error::IO(std::io::Error::other(format!("take_writer: {e}"))))?;
        // The reader side: we need an OwnedReader; portable-pty's master
        // doesn't impl tokio AsyncRead, so we spawn a blocking task that
        // reads via std::io and forwards to a tokio channel.
        let mut reader = master
            .try_clone_reader()
            .map_err(|e| russh::Error::IO(std::io::Error::other(format!("clone_reader: {e}"))))?;

        let session_handle = session.handle();
        let channel_for_reader = channel;

        // PTY → SSH channel.data
        tokio::task::spawn_blocking(move || {
            let mut buf = [0u8; 4096];
            loop {
                match reader.read(&mut buf) {
                    Ok(0) => break,
                    Ok(n) => {
                        let chunk = buf[..n].to_vec();
                        let handle = session_handle.clone();
                        // Block-on inside the blocking task to push the data.
                        let _ = tokio::runtime::Handle::try_current()
                            .ok()
                            .and_then(|rt| Some(rt.spawn(async move {
                                let _ = handle
                                    .data(channel_for_reader, CryptoVec::from_slice(&chunk))
                                    .await;
                            })));
                    }
                    Err(_) => break,
                }
            }
        });

        // SSH → PTY: drain `rx` (filled by channel.data callback below).
        tokio::spawn(async move {
            while let Some(chunk) = rx.recv().await {
                if writer.write_all(&chunk).is_err() {
                    break;
                }
                let _ = writer.flush();
            }
        });

        // When the child exits, close the SSH channel.
        let session_handle_close = session.handle();
        let channel_close = channel;
        tokio::task::spawn_blocking(move || {
            let _ = child.wait();
            let handle = session_handle_close;
            // Best-effort EOF + close.
            let _ = tokio::runtime::Handle::try_current().ok().map(|rt| {
                rt.spawn(async move {
                    let _ = handle.eof(channel_close).await;
                    let _ = handle.close(channel_close).await;
                });
            });
        });

        session.channel_success(channel);
        Ok(())
    }

    async fn data(
        &mut self,
        channel: ChannelId,
        data: &[u8],
        _session: &mut Session,
    ) -> Result<(), Self::Error> {
        let state = self.channels.lock().await;
        if let Some(s) = state.get(&channel) {
            if let Some(tx) = &s.writer_tx {
                // Best-effort; if the PTY closed, drop the bytes.
                let _ = tx.send(data.to_vec()).await;
            }
        }
        Ok(())
    }

    async fn exec_request(
        &mut self,
        channel: ChannelId,
        _data: &[u8],
        session: &mut Session,
    ) -> Result<(), Self::Error> {
        // We intentionally do not honour exec; only `shell` with a PTY.
        tracing::warn!(?channel, "refusing exec-request: shell-only");
        session.channel_failure(channel);
        Ok(())
    }

    async fn subsystem_request(
        &mut self,
        channel: ChannelId,
        name: &str,
        session: &mut Session,
    ) -> Result<(), Self::Error> {
        tracing::warn!(?channel, name, "refusing subsystem-request: shell-only");
        session.channel_failure(channel);
        Ok(())
    }

    async fn channel_close(
        &mut self,
        channel: ChannelId,
        _session: &mut Session,
    ) -> Result<(), Self::Error> {
        let mut state = self.channels.lock().await;
        state.remove(&channel);
        Ok(())
    }
}
