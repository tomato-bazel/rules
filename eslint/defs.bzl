"""eslint_test — lint sources with a workspace's own @npm eslint.

eslint is a Node tool whose binary + plugin/config closure live in the
consumer's `pnpm-lock.yaml`, so this ruleset deliberately does NOT fetch
eslint: the consumer passes its own aspect_rules_js-linked eslint binary,
the same way `rules_storybook` takes a `storybook_bin`. The macro emits a
`lint`-tagged `sh_test` that runs that binary over `srcs` against `config`.

    load("@npm//:eslint/package_json.bzl", eslint_bin = "bin")
    load("@rules_eslint//eslint:defs.bzl", "eslint_test")

    eslint_bin.eslint_binary(name = "eslint")

    eslint_test(
        name = "lint",
        srcs = glob(["**/*.ts", "**/*.tsx"]),
        eslint_bin = ":eslint",
        config = "//:eslint.config.mjs",
    )

CI runs every such target via `bazel test //... --test_tag_filters=lint`.
"""

load("@rules_shell//shell:sh_test.bzl", "sh_test")

def eslint_test(name, srcs, eslint_bin, config, tags = None, **kwargs):
    """Lint `srcs` with the consumer-supplied @npm eslint binary.

    Args:
      name: target name.
      srcs: source files to lint (`.ts`/`.tsx`/`.js`/...).
      eslint_bin: an executable eslint target — typically the
        `eslint_binary` produced by `@npm//:eslint/package_json.bzl`'s
        `bin` factory.
      config: the flat eslint config file (e.g. `//:eslint.config.mjs`),
        passed to eslint via `--config`.
      tags: extra tags; `lint` is always added so test filters can select it.
      **kwargs: forwarded to the underlying `sh_test` (visibility, size, …).
    """
    sh_test(
        name = name,
        srcs = ["@rules_eslint//eslint/private:run_eslint.sh"],
        data = srcs + [
            eslint_bin,
            config,
            "@bazel_tools//tools/bash/runfiles",
        ],
        # argv: <eslint_bin> <config> <src>...
        # The binary + config are runfiles rlocation paths (resolved by the
        # launcher); the sources are forwarded verbatim and resolved by
        # eslint against $PWD, which Bazel sets to the runfiles root.
        args = [
            "$(rlocationpath %s)" % eslint_bin,
            "$(rlocationpath %s)" % config,
        ] + ["$(rootpath %s)" % s for s in srcs],
        tags = list(set(["lint"] + (tags or []))),
        **kwargs
    )
