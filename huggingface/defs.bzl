"""rules_huggingface public API.

```starlark
load(
    "@rules_huggingface//huggingface:defs.bzl",
    "hf_model", "hf_upload", "hf_repo", "hf_download",
)
```

Data-plane macros emit a `bazel run`-able runner per the cluster
verb-suffix convention (mirrors rules_runpod's `.deploy` / `.run`):

* `hf_upload`   → `<name>.push`     — create-if-missing + sync a dir
* `hf_repo`     → `<name>.create`   — create (or no-op reuse) a repo
* `hf_download` → `<name>.download` — materialize a repo/files locally
* `hf_model`    — typed `HfModelInfo` repo reference (no runner)

Every runner drives a hermetic `hf` CLI resolved through
`//huggingface:toolchain_type` — no system `hf` needed.
"""

load(
    "//huggingface/private:endpoints.bzl",
    _hf_inference_endpoint = "hf_inference_endpoint",
)
load(
    "//huggingface/private:rules.bzl",
    _hf_download_rule = "hf_download",
    _hf_model = "hf_model",
    _hf_repo_rule = "hf_repo",
    _hf_upload_rule = "hf_upload",
)

hf_model = _hf_model
hf_inference_endpoint = _hf_inference_endpoint

def hf_upload(name, visibility = None, **kwargs):
    """Push a local directory to a HF Hub repo. Emits `<name>.push`."""
    _hf_upload_rule(name = name + ".push", visibility = visibility, **kwargs)

def hf_repo(name, visibility = None, **kwargs):
    """Create (or no-op reuse) a HF Hub repo. Emits `<name>.create`."""
    _hf_repo_rule(name = name + ".create", visibility = visibility, **kwargs)

def hf_download(name, visibility = None, **kwargs):
    """Materialize a HF Hub repo/files locally. Emits `<name>.download`."""
    _hf_download_rule(name = name + ".download", visibility = visibility, **kwargs)
