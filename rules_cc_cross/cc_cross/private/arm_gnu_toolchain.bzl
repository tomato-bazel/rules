"""Repo rule that materializes one ARM GNU Toolchain install.

The rule:
  1. Resolves the host (os, cpu) from `repository_ctx.os`.
  2. Downloads the matching arm.com tarball for the requested
     (version, target).
  3. Drops a BUILD.bazel into the resulting repo that exposes:
       - filegroup `:all_files` (the entire install)
       - cc_toolchain_config `:cc_toolchain_config`
       - cc_toolchain `:cc_toolchain`
       - toolchain `:<target>_toolchain` (registerable)
"""

load(
    "//cc_cross/private:known_versions.bzl",
    "HOST_KEYS",
    "KNOWN_ARM_GNU_VERSIONS",
    "arm_gnu_strip_prefix",
    "arm_gnu_url",
)

_TARGET_CPU = {
    "aarch64-none-elf": "aarch64",
}

def _resolve_host(rctx):
    os = rctx.os.name.lower()
    cpu = rctx.os.arch.lower()
    # repository_ctx.os.arch reports "arm64" on macOS and "amd64" on
    # some Linux distros. Normalize to (aarch64, x86_64).
    if cpu in ("arm64",):
        cpu = "aarch64"
    if cpu in ("amd64", "x86-64"):
        cpu = "x86_64"
    key = (os, cpu)
    if key not in HOST_KEYS:
        fail(("rules_cc_cross: unsupported host ({}, {}). " +
              "Known: {}.").format(os, cpu, sorted(HOST_KEYS.keys())))
    return HOST_KEYS[key]

def _arm_gnu_toolchain_impl(rctx):
    host_segment = _resolve_host(rctx)
    version = rctx.attr.version
    target = rctx.attr.target

    if version not in KNOWN_ARM_GNU_VERSIONS:
        fail("arm_gnu_toolchain: unknown version " + version)
    sha = rctx.attr.integrity or KNOWN_ARM_GNU_VERSIONS[version].get(host_segment, "")

    url = arm_gnu_url(version, host_segment, target)
    strip = arm_gnu_strip_prefix(version, host_segment, target)

    download_args = {
        "url": [url],
        "stripPrefix": strip,
    }
    if sha:
        download_args["sha256"] = sha
    rctx.download_and_extract(**download_args)

    target_cpu = _TARGET_CPU[target]
    tool_prefix = target + "-"
    sysroot = target

    rctx.template(
        "BUILD.bazel",
        Label("//cc_cross/private:arm_gnu.BUILD.tpl"),
        substitutions = {
            "{target}": target,
            "{target_underscored}": target.replace("-", "_"),
            "{target_cpu}": target_cpu,
            "{tool_prefix}": tool_prefix,
            "{sysroot}": sysroot,
        },
        executable = False,
    )

arm_gnu_toolchain = repository_rule(
    implementation = _arm_gnu_toolchain_impl,
    attrs = {
        "version": attr.string(mandatory = True),
        "target": attr.string(
            mandatory = True,
            values = list(_TARGET_CPU.keys()),
        ),
        "integrity": attr.string(
            default = "",
            doc = "Optional sha256 override. Empty falls back to " +
                  "known_versions.bzl (which today is also empty).",
        ),
    },
    doc = "Downloads one (host, target) ARM GNU Toolchain install.",
)
