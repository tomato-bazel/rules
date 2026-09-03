"""Public rules_cc_cross surface.

Most consumers only need the `cc_cross` module extension declared in
`extensions.bzl`. The rule re-exports below are convenience aliases
for advanced consumers who want to instantiate toolchains directly
(e.g. in a custom monorepo macro) instead of via `cc_cross.toolchain`.
"""

load(
    "//cc_cross/private:arm_gnu_toolchain.bzl",
    _arm_gnu_toolchain = "arm_gnu_toolchain",
)
load(
    "//cc_cross/private:cc_toolchain_config.bzl",
    _cross_cc_toolchain_config = "cross_cc_toolchain_config",
)

arm_gnu_toolchain = _arm_gnu_toolchain
cross_cc_toolchain_config = _cross_cc_toolchain_config
