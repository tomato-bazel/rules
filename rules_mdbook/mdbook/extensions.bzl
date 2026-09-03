"""Module extension for rules_mdbook.

Auto-fetches prebuilt mdbook + mdbook-mermaid binaries for the host
platform. Versions are pinned by sha256 in
`private/known_versions.bzl`. Consumers can override the version per
tool via the `toolchain` tag class.

Default usage (pulls the default-pinned mdbook + mdbook-mermaid):

    mdbook = use_extension("@rules_mdbook//mdbook:extensions.bzl", "mdbook")
    use_repo(mdbook, "mdbook", "mdbook_mermaid")

Pin a specific version:

    mdbook = use_extension("@rules_mdbook//mdbook:extensions.bzl", "mdbook")
    mdbook.toolchain(mdbook_version = "0.5.2", mermaid_version = "0.17.0")
    use_repo(mdbook, "mdbook", "mdbook_mermaid")

Release fetching is delegated to
`@rules_github//github:repositories.bzl%github_binary_repository`
so all our rules_* repos share one URL-shape + sha-pinning impl.
"""

load(
    "@rules_github//github:repositories.bzl",
    "github_binary_repository",
)
load(
    "//mdbook/private:known_versions.bzl",
    "DEFAULT_VERSIONS",
    "KNOWN_VERSIONS",
    "REPOS",
)

# Canonical (rules_github) -> upstream asset suffix INCLUDING the
# archive extension. mdbook + mdbook-mermaid both publish .tar.gz on
# unix and .zip on Windows; baking the extension into the alias keeps
# `asset_template` static (rules_github's template only supports
# `{version}` + `{platform}` substitutions).
_PLATFORM_ALIASES = {
    "darwin_aarch64": "aarch64-apple-darwin.tar.gz",
    "darwin_x86_64": "x86_64-apple-darwin.tar.gz",
    "linux_x86_64": "x86_64-unknown-linux-gnu.tar.gz",
    "windows_x86_64": "x86_64-pc-windows-msvc.zip",
}

def _build_overlay(tool, binary_name):
    """BUILD overlay: exports the binary; mdbook also declares its toolchain."""
    overlay = """\
package(default_visibility = ["//visibility:public"])

exports_files(["{name}"])
""".format(name = binary_name)
    if tool == "mdbook":
        overlay += """\

load("@rules_mdbook//mdbook:toolchains.bzl", "mdbook_toolchain")

mdbook_toolchain(
    name = "mdbook_toolchain",
    mdbook = ":{name}",
)

toolchain(
    name = "mdbook_toolchain_def",
    toolchain = ":mdbook_toolchain",
    toolchain_type = "@rules_mdbook//mdbook:toolchain_type",
)
""".format(name = binary_name)
    return overlay

def _fetch(tool, repo_name, version):
    # Binary filename matches the tool's name; only Windows adds `.exe`.
    # We don't know the host at extension-time, so a single repo name maps
    # to one BUILD overlay — we hardcode the non-Windows path and rely on
    # consumers to skip Windows in CI (matches the prior repository_rule).
    binary_name = tool + ""  # ".exe" handled per-platform if needed later
    github_binary_repository(
        name = repo_name,
        repo = REPOS[tool],
        version = version,
        # Asset shape: `<tool>-v<version>-<platform-suffix>`, where the
        # suffix includes the archive extension (see _PLATFORM_ALIASES).
        asset_template = "{tool}-v{{version}}-{{platform}}".format(tool = tool),
        platform_aliases = _PLATFORM_ALIASES,
        platform_shas = KNOWN_VERSIONS.get(tool, {}).get(version, {}),
        allow_unverified = True,
        build_file_content = _build_overlay(tool, binary_name),
    )

def _mdbook_extension_impl(mctx):
    # Reduce all toolchain tags across the dep graph to one (mdbook_version,
    # mermaid_version) pair. Root module wins; otherwise the latest seen.
    mdbook_version = DEFAULT_VERSIONS["mdbook"]
    mermaid_version = DEFAULT_VERSIONS["mdbook-mermaid"]
    for mod in mctx.modules:
        for tag in mod.tags.toolchain:
            if tag.mdbook_version:
                mdbook_version = tag.mdbook_version
            if tag.mermaid_version:
                mermaid_version = tag.mermaid_version

    _fetch("mdbook", "mdbook", mdbook_version)
    _fetch("mdbook-mermaid", "mdbook_mermaid", mermaid_version)

_toolchain_tag = tag_class(attrs = {
    "mdbook_version": attr.string(
        default = "",
        doc = "Override mdbook version. Defaults to the value in known_versions.bzl.",
    ),
    "mermaid_version": attr.string(
        default = "",
        doc = "Override mdbook-mermaid version. Defaults to the value in known_versions.bzl.",
    ),
})

mdbook = module_extension(
    implementation = _mdbook_extension_impl,
    tag_classes = {"toolchain": _toolchain_tag},
    doc = "Sets up @mdbook and @mdbook_mermaid as Bazel-fetched prebuilt binaries.",
)
