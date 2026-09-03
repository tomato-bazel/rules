"""Providers for rules_markdown."""

MarkdownFragmentInfo = provider(
    doc = "A markdown fragment + its metadata, gathered transitively by " +
          "markdown_link_aspect. Each contribution is a hashable struct so it " +
          "can ride a depset.",
    fields = {
        "fragments": "depset of struct(frag_id, md_file, title, level, weight, handle, tags).",
    },
)

MarkdownDocInfo = provider(
    doc = "A rendered markdown document — exposed so a doc can be embedded, " +
          "link-checked, or published without re-rendering.",
    fields = {
        "md": "File: the rendered document.",
        "anchor_index": "File: JSON map of deep-link handle -> final in-doc anchor slug.",
        "fragments": "depset of the fragment structs that composed it.",
    },
)
