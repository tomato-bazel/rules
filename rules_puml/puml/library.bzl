"""`puml_library(name, srcs)` — a collection of `.puml` source files.

Provider-only — no build actions. Consumed by `puml_diagram(libs=...)`
which concatenates the sources from every library in declaration
order and renders the union as one diagram. Lets you split a system
diagram into typed pieces (`preamble.puml`, `actors.puml`,
`interactions.puml`) without forcing them through a single source
file.

```python
load("@rules_puml//puml:defs.bzl", "puml_library")

puml_library(
    name = "system_components",
    srcs = ["actors.puml", "boxes.puml"],
)
```
"""

load(":providers.bzl", "PumlSourceInfo")

def _puml_library_impl(ctx):
    return [
        DefaultInfo(files = depset(ctx.files.srcs)),
        PumlSourceInfo(srcs = depset(ctx.files.srcs, order = "preorder")),
    ]

puml_library = rule(
    implementation = _puml_library_impl,
    attrs = {
        "srcs": attr.label_list(
            allow_files = [".puml", ".plantuml", ".pu", ".uml"],
            mandatory = True,
            doc = "`.puml` files in the library. Declaration order " +
                  "is the compose order at render time.",
        ),
    },
    provides = [PumlSourceInfo],
    doc = "A set of `.puml` source files; consumed by `puml_diagram`.",
)
