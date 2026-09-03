"""Provider types for the rules_puml public API.

V0 ships two:
- `PumlSourceInfo` — a collected `.puml` source set, optionally with
  an explicit ordering used at compose time.
- `PumlDiagramInfo` — a rendered diagram artifact (SVG / PNG / PDF
  output file plus its format).

V1 will add per-construct providers (`PumlActorInfo`,
`PumlComponentInfo`, …) generated from the PlantUML grammar in the
same way rules_cloudformation generates its provider set from the
CFN spec.

Names use the `PumlXInfo` package-prefixed convention so an unwrapped
`PumlDiagramInfo` import is unambiguous next to other ecosystem
providers (`JenaModelInfo`, `BeamPipelineInfo`, ...).
"""

PumlSourceInfo = provider(
    doc = "A collection of `.puml` source files contributed by a " +
          "target. Consumed by `puml_diagram` (renders the union as " +
          "one diagram) and by future typed-AST rules.",
    fields = {
        "srcs": "depset[File]: `.puml` files in declaration order. " +
                "Declaration order is the compose order at render " +
                "time, so a library can put a preamble fragment " +
                "(`@startuml`, skinparam settings) first and a " +
                "closer (`@enduml`) last.",
    },
)

PumlDiagramInfo = provider(
    doc = "A rendered PlantUML diagram. The `output` is a single " +
          "image file in the format named by `output_format`.",
    fields = {
        "output": "File: the rendered diagram (SVG / PNG today).",
        "output_format": "str: `svg`, `png`. Future versions may add " +
                         "`pdf` via an external SVG→PDF conversion " +
                         "step.",
    },
)
