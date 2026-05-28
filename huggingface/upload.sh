#!/usr/bin/env bash
# hf_upload.push — push a local directory to a HuggingFace Hub repo.
#
# Ensures the repo exists (creating it with the requested privacy if
# missing), then uploads the directory contents. Idempotent: HF
# upload is a sync that overwrites changed files.
#
# Args (positional, injected by the macro):
#   $1 — repo id (e.g. fastverk/agora-parser-qwen2.5-1.5b)
#   $2 — repo type (model | dataset)
#   $3 — private flag ("1" private, "0" public)
#   $4 — default local dir (relative to workspace root)
#
# A `bazel run :<name>.push -- <local_dir>` extra arg overrides $4.
#
# Requires the `hf` CLI (huggingface_hub[cli]) on PATH and HF_TOKEN
# in the environment (or a prior `hf auth login`).

set -uo pipefail

if [[ $# -lt 4 ]]; then
    echo "fatal: upload.sh requires REPO, REPO_TYPE, PRIVATE, LOCAL_DIR" >&2
    exit 2
fi
REPO="$1"; REPO_TYPE="$2"; PRIVATE="$3"; LOCAL_DIR="$4"
shift 4
# Optional runtime override of the local dir.
if [[ $# -ge 1 && -n "$1" ]]; then
    LOCAL_DIR="$1"
fi

# Resolve the local dir against the user's workspace, not the
# runfiles tree.
cd "${BUILD_WORKSPACE_DIRECTORY:-$(pwd)}"

# Prefer `hf`; fall back to the legacy `huggingface-cli`.
HF_BIN=""
if command -v hf >/dev/null 2>&1; then
    HF_BIN="hf"
elif command -v huggingface-cli >/dev/null 2>&1; then
    HF_BIN="huggingface-cli"
else
    echo "fatal: neither 'hf' nor 'huggingface-cli' on PATH." >&2
    echo "       pip install 'huggingface_hub[cli]'" >&2
    exit 3
fi

if [[ -z "${HF_TOKEN:-}" ]]; then
    echo "warning: HF_TOKEN not set; relying on a prior 'hf auth login'" >&2
fi

if [[ ! -d "$LOCAL_DIR" ]]; then
    echo "fatal: local dir '$LOCAL_DIR' not found (run the export step first?)" >&2
    exit 3
fi

echo "===> ensuring repo $REPO ($REPO_TYPE) exists" >&2
CREATE_ARGS=(repo create "$REPO" --repo-type "$REPO_TYPE" --exist-ok)
if [[ "$PRIVATE" == "1" ]]; then
    CREATE_ARGS+=(--private)
fi
# `hf repo create` is best-effort: --exist-ok makes a re-run a no-op.
"$HF_BIN" "${CREATE_ARGS[@]}" || {
    echo "warning: repo create returned non-zero (may already exist); continuing" >&2
}

echo "===> uploading $LOCAL_DIR -> $REPO" >&2
exec "$HF_BIN" upload --repo-type "$REPO_TYPE" "$REPO" "$LOCAL_DIR" .
