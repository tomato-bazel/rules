"""The `helm` module extension — fetches the hermetic helm CLI.

Creates the `@helm` repo (host-platform helm binary). rules_helm's MODULE.bazel
`use_repo`s it; the rules reach it through the `//helm:helm_bin` alias, so
consumers never name `@helm` directly.
"""

load("//helm:repositories.bzl", "helm_repository")

def _helm_impl(_mctx):
    helm_repository(name = "helm")

helm = module_extension(
    implementation = _helm_impl,
    doc = "Downloads the pinned helm CLI for the host platform.",
)
