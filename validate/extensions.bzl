"""The module extension that fetches kubeconform."""

load("//validate:repositories.bzl", "kubeconform_repository")

def _kubeconform_ext_impl(_ctx):
    kubeconform_repository(name = "kubeconform")

kubeconform = module_extension(
    implementation = _kubeconform_ext_impl,
    doc = "Fetches the sha256-pinned kubeconform release binary for the host platform.",
)
