"""Two repository rules for GitHub-release-based content.

* `github_binary_repository` — fetch a per-platform binary release
  asset (the `releases/download/<tag>/<asset>` URL shape used by
  most CLI projects: mdbook, bun, ripgrep, jq, …).

* `github_source_repository` — fetch a source tarball from a tag
  (the `archive/refs/tags/<tag>.tar.gz` URL shape, used when a
  project doesn't publish prebuilt release assets — e.g.,
  libpg_query — or when you want to build the source yourself).

Both rules:

  - Construct the release tag from a template (`v{version}`,
    `bun-v{version}`, `{version}`, etc.).
  - Verify integrity via sha256.
  - Write the consumer-supplied BUILD overlay (inline or label).

Consumers that need a Bazel toolchain wrapping the downloaded binary
declare it inside `build_file_content` — `rules_github` deliberately
doesn't ship its own toolchain rule because toolchain providers vary
per-tool (each downstream rules_* repo has its own
`ToolToolchainInfo` provider shape).
"""

load("//github/private:platforms.bzl", "detect_platform")

# -----------------------------------------------------------------------------
# github_binary_repository — per-platform release-asset binary.
# -----------------------------------------------------------------------------

def _github_binary_repo_impl(rctx):
    platform = rctx.attr.platform if rctx.attr.platform else detect_platform(rctx)

    alias = rctx.attr.platform_aliases.get(platform, platform)
    sha = rctx.attr.platform_shas.get(platform, "")

    if not sha and not rctx.attr.allow_unverified:
        fail(("rules_github: github_binary_repository {name}: no sha256 " +
              "pinned for host platform {p}. Add an entry to platform_shas " +
              "or set allow_unverified = True.").format(
            name = rctx.name,
            p = platform,
        ))
    if not sha:
        # buildifier: disable=print
        print("rules_github: WARNING — downloading {name}@{v} for {p} unverified".format(
            name = rctx.name,
            v = rctx.attr.version,
            p = platform,
        ))

    tag = rctx.attr.tag_format.format(version = rctx.attr.version)
    asset = rctx.attr.asset_template.format(
        version = rctx.attr.version,
        platform = alias,
    )
    strip = rctx.attr.strip_prefix_template.format(
        version = rctx.attr.version,
        platform = alias,
    )
    url = "https://github.com/{repo}/releases/download/{tag}/{asset}".format(
        repo = rctx.attr.repo,
        tag = tag,
        asset = asset,
    )

    rctx.download_and_extract(
        url = url,
        sha256 = sha,
        stripPrefix = strip,
    )

    _write_build_overlay(rctx)

github_binary_repository = repository_rule(
    implementation = _github_binary_repo_impl,
    attrs = {
        "repo": attr.string(
            mandatory = True,
            doc = "GitHub repo as `owner/name` (e.g. `oven-sh/bun`).",
        ),
        "version": attr.string(
            mandatory = True,
            doc = "Upstream version string (no leading `v`, no tag prefix).",
        ),
        "tag_format": attr.string(
            default = "v{version}",
            doc = "Release tag pattern. `{version}` is substituted. " +
                  "Examples: `v{version}` (default; mdbook, most tools), " +
                  "`bun-v{version}` (bun), `{version}` (libpg_query: " +
                  "`17-6.2.2` IS the tag).",
        ),
        "asset_template": attr.string(
            mandatory = True,
            doc = "Asset filename pattern. `{version}` + `{platform}` " +
                  "substituted. The platform substitution uses the " +
                  "alias from `platform_aliases` for the detected host.",
        ),
        "strip_prefix_template": attr.string(
            default = "",
            doc = "Optional strip-prefix pattern with `{version}` + " +
                  "`{platform}` substitution. Defaults to empty (binary " +
                  "at archive root).",
        ),
        "platform_aliases": attr.string_dict(
            default = {},
            doc = "Canonical-platform → project-specific-platform mapping. " +
                  "Canonical keys: `darwin_aarch64`, `darwin_x86_64`, " +
                  "`linux_x86_64`, `linux_aarch64`, `windows_x86_64`. " +
                  "Project values follow whatever the upstream release " +
                  "uses (`aarch64-apple-darwin`, `darwin-aarch64`, etc.). " +
                  "Missing key = canonical name used verbatim.",
        ),
        "platform_shas": attr.string_dict(
            default = {},
            doc = "Canonical-platform → sha256 hex. Lookup keys match " +
                  "`platform_aliases`. Missing entry for the host platform " +
                  "fails the build unless `allow_unverified = True`.",
        ),
        "allow_unverified": attr.bool(
            default = False,
            doc = "If True, missing sha256 for the host platform downgrades " +
                  "to a warning + unverified download. Useful for bumping " +
                  "to a new version before computing pins.",
        ),
        "platform": attr.string(
            default = "",
            doc = "Override host-platform detection. Empty = auto-detect.",
        ),
        "build_file_content": attr.string(
            default = "",
            doc = "Inline BUILD.bazel content for the generated repo. " +
                  "Either this OR `build_file` must be set.",
        ),
        "build_file": attr.label(
            allow_single_file = True,
            doc = "BUILD.bazel content as a label. Alternative to " +
                  "`build_file_content`.",
        ),
    },
    doc = "Fetch a per-platform binary release asset from a GitHub release.",
)

# -----------------------------------------------------------------------------
# github_source_repository — source tarball from a tag.
# -----------------------------------------------------------------------------

def _github_source_repo_impl(rctx):
    if rctx.attr.commit and rctx.attr.version:
        fail("rules_github: github_source_repository {name}: set exactly one of `commit` or `version`.".format(
            name = rctx.name,
        ))
    if not rctx.attr.commit and not rctx.attr.version:
        fail("rules_github: github_source_repository {name}: one of `commit` (untagged ref) or `version` (release tag) is required.".format(
            name = rctx.name,
        ))

    sha = rctx.attr.sha256
    ref = rctx.attr.commit if rctx.attr.commit else rctx.attr.version
    if not sha and not rctx.attr.allow_unverified:
        fail("rules_github: github_source_repository {name}: sha256 required (or set allow_unverified = True)".format(
            name = rctx.name,
        ))
    if not sha:
        # buildifier: disable=print
        print("rules_github: WARNING — downloading {name}@{v} unverified".format(
            name = rctx.name,
            v = ref,
        ))

    repo_basename = rctx.attr.repo.split("/")[-1]

    if rctx.attr.commit:
        # Untagged ref: GitHub serves `archive/<sha>.tar.gz`, stripping
        # into `<repo-basename>-<full-sha>/`. Used for research repos
        # without release tags (e.g. HowieHwong/MetaTool).
        url = "https://github.com/{repo}/archive/{commit}.tar.gz".format(
            repo = rctx.attr.repo,
            commit = rctx.attr.commit,
        )
        default_strip = "{name}-{commit}".format(name = repo_basename, commit = rctx.attr.commit)
    else:
        tag = rctx.attr.tag_format.format(version = rctx.attr.version)
        url = "https://github.com/{repo}/archive/refs/tags/{tag}.tar.gz".format(
            repo = rctx.attr.repo,
            tag = tag,
        )
        default_strip = "{name}-{version}".format(name = repo_basename, version = rctx.attr.version)

    if rctx.attr.strip_prefix_template:
        strip = rctx.attr.strip_prefix_template.format(version = rctx.attr.version, commit = rctx.attr.commit)
    else:
        strip = default_strip

    rctx.download_and_extract(
        url = url,
        sha256 = sha,
        stripPrefix = strip,
    )

    _write_build_overlay(rctx)

github_source_repository = repository_rule(
    implementation = _github_source_repo_impl,
    attrs = {
        "repo": attr.string(
            mandatory = True,
            doc = "GitHub repo as `owner/name`.",
        ),
        "version": attr.string(
            doc = "Release-tag version string. Mutually exclusive with " +
                  "`commit`; exactly one is required.",
        ),
        "commit": attr.string(
            doc = "Full commit SHA for an untagged ref. Fetches " +
                  "`archive/<commit>.tar.gz`. Use for repos without " +
                  "release tags. Mutually exclusive with `version`.",
        ),
        "tag_format": attr.string(
            default = "v{version}",
            doc = "Release tag pattern (tag mode only). Same semantics as " +
                  "`github_binary_repository`.",
        ),
        "sha256": attr.string(
            default = "",
            doc = "sha256 of the auto-generated source tarball. Required " +
                  "unless `allow_unverified = True`.",
        ),
        "strip_prefix_template": attr.string(
            default = "",
            doc = "Override strip-prefix pattern (`{version}` / `{commit}` " +
                  "substituted). Default: `<repo-basename>-{version}` for " +
                  "tag mode, `<repo-basename>-{commit}` for commit mode.",
        ),
        "allow_unverified": attr.bool(
            default = False,
            doc = "Skip sha256 requirement; downgrade missing sha to warning.",
        ),
        "build_file_content": attr.string(
            default = "",
            doc = "Inline BUILD.bazel content. Either this OR `build_file` " +
                  "must be set.",
        ),
        "build_file": attr.label(
            allow_single_file = True,
            doc = "BUILD.bazel content as a label.",
        ),
    },
    doc = "Fetch a source tarball from a GitHub release tag.",
)

# -----------------------------------------------------------------------------
# Shared: write the BUILD overlay (inline or label).
# -----------------------------------------------------------------------------

def _write_build_overlay(rctx):
    if rctx.attr.build_file_content and rctx.attr.build_file:
        fail("rules_github: {name}: pass exactly one of `build_file_content` or `build_file`.".format(name = rctx.name))
    if rctx.attr.build_file_content:
        rctx.file("BUILD.bazel", rctx.attr.build_file_content)
    elif rctx.attr.build_file:
        rctx.symlink(rctx.attr.build_file, "BUILD.bazel")
    else:
        fail("rules_github: {name}: must set `build_file_content` or `build_file`.".format(name = rctx.name))
