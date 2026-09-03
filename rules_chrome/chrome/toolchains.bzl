"""Toolchain rule for rules_chrome.

`chrome_toolchain` wraps a Chrome for Testing binary plus the matching
chromedriver as a single Bazel toolchain. Consumers (the `chrome_run`
and `chromedriver_run` rules) resolve chrome through
`@rules_chrome//chrome:toolchain_type`, so users can register custom
chrome builds (locally-built fork, dev/canary channel, …) via
`register_toolchains(...)` without modifying rule attributes.

The module extension at `@rules_chrome//chrome:extensions.bzl`
generates a default toolchain (`@chrome//:chrome_toolchain_def`)
wrapping the prebuilt binaries. Users register it from their
`MODULE.bazel`:

    register_toolchains("@chrome//:chrome_toolchain_def")
"""

ChromeToolchainInfo = provider(
    doc = "The Chrome for Testing binaries, resolved via a toolchain.",
    fields = {
        "chrome": "Target: the chrome executable target (carries its bundle as runfiles).",
        "chromedriver": "Target: the chromedriver executable target. May be None if " +
                        "the toolchain was registered without driver support.",
    },
)

def _chrome_toolchain_impl(ctx):
    return [platform_common.ToolchainInfo(
        chromeinfo = ChromeToolchainInfo(
            chrome = ctx.attr.chrome,
            chromedriver = ctx.attr.chromedriver,
        ),
    )]

chrome_toolchain = rule(
    implementation = _chrome_toolchain_impl,
    attrs = {
        "chrome": attr.label(
            executable = True,
            mandatory = True,
            cfg = "exec",
            doc = "The chrome executable target (its runfiles carry the rest of the bundle).",
        ),
        "chromedriver": attr.label(
            executable = True,
            cfg = "exec",
            doc = "The chromedriver executable target. Optional — leave unset for chrome-only setups.",
        ),
    },
    doc = "Declare a Chrome for Testing binary + chromedriver as a Bazel toolchain.",
)
