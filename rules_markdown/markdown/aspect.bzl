"""markdown_link_aspect — collect MarkdownFragmentInfo across the build graph.

A markdown_fragment already exposes its own + transitive closure (its rule
provides MarkdownFragmentInfo). For any *other* target, this aspect gathers the
MarkdownFragmentInfo reachable through its deps/fragments/roots edges — so a
markdown_document can point `roots` at an arbitrary target whose graph contains
fragment declarations. (Same non-conflicting rule+aspect pattern as
rules_vscode's vscode_folder_aspect: the aspect returns nothing when the target
already provides the provider.)
"""

load(":providers.bzl", "MarkdownFragmentInfo")

def _markdown_link_aspect_impl(target, ctx):
    if MarkdownFragmentInfo in target:
        return []
    transitive = []
    for attr_name in ("deps", "fragments", "roots"):
        for d in getattr(ctx.rule.attr, attr_name, None) or []:
            if type(d) == "Target" and MarkdownFragmentInfo in d:
                transitive.append(d[MarkdownFragmentInfo].fragments)
    if not transitive:
        return []
    return [MarkdownFragmentInfo(fragments = depset(transitive = transitive))]

markdown_link_aspect = aspect(
    implementation = _markdown_link_aspect_impl,
    attr_aspects = ["deps", "fragments", "roots"],
    doc = "Walk deps/fragments/roots edges collecting markdown fragment contributions.",
)
