"""Public API for rules_markdown.

```starlark
load("@rules_markdown//markdown:defs.bzl", "markdown_fragment", "markdown_document")
```
"""

load(":aspect.bzl", _markdown_link_aspect = "markdown_link_aspect")
load(":document.bzl", _markdown_document = "markdown_document")
load(":fragment.bzl", _markdown_fragment = "markdown_fragment")
load(":providers.bzl", _MarkdownDocInfo = "MarkdownDocInfo", _MarkdownFragmentInfo = "MarkdownFragmentInfo")

markdown_fragment = _markdown_fragment
markdown_document = _markdown_document
markdown_link_aspect = _markdown_link_aspect
MarkdownFragmentInfo = _MarkdownFragmentInfo
MarkdownDocInfo = _MarkdownDocInfo
