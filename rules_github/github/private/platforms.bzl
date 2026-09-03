"""Host-platform detection for `github_binary_repository`.

Returns a canonical platform identifier string used as the dict
key for `platform_aliases` + `platform_shas` (the per-platform
attributes on `github_binary_repository`).

Canonical identifiers:

    darwin_aarch64    macOS Apple Silicon
    darwin_x86_64     macOS Intel
    linux_x86_64      Linux 64-bit
    linux_aarch64     Linux ARM64
    windows_x86_64    Windows 64-bit

Matches the canonical naming used in `fastverk/rules_lean`'s
`known_lean_versions.bzl`. Project-specific naming (e.g.,
mdbook's Rust-target `aarch64-apple-darwin`, bun's
`darwin-aarch64`) is mapped from the canonical via the
`platform_aliases` attribute on each rule call.
"""

def detect_platform(rctx):
    """Return the canonical platform identifier for the host that's
    fetching this repository.

    Args:
      rctx: a `repository_ctx`.

    Returns:
      String — one of the canonical identifiers above.

    Fails if the host platform is not one we recognize.
    """
    os = rctx.os.name.lower()
    arch = rctx.os.arch.lower()
    if "linux" in os and arch in ("x86_64", "amd64"):
        return "linux_x86_64"
    if "linux" in os and arch in ("aarch64", "arm64"):
        return "linux_aarch64"
    if ("mac" in os or "darwin" in os) and arch in ("aarch64", "arm64"):
        return "darwin_aarch64"
    if ("mac" in os or "darwin" in os) and arch in ("x86_64", "amd64"):
        return "darwin_x86_64"
    if "windows" in os and arch in ("x86_64", "amd64"):
        return "windows_x86_64"
    fail("rules_github: unsupported host os={os} arch={arch}".format(os = os, arch = arch))
