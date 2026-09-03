"""Public API surface for rules_puml.

```python
load("@rules_puml//puml:defs.bzl",
     "puml_diagram", "puml_library",
     "PumlSourceInfo", "PumlDiagramInfo")
```

V0 ships file-level macros: render one `.puml`, compose several
fragments through a library. V1 will add per-construct typed rules
(`puml_actor`, `puml_component`, …) generated from the PlantUML
grammar in `polyglot_ast`; both V0 and V1 consumers share the
underlying renderer (`//puml/private/plantuml`) and the same provider
types.
"""

load(":diagram.bzl", _puml_diagram = "puml_diagram")
load(":library.bzl", _puml_library = "puml_library")
load(
    ":providers.bzl",
    _PumlDiagramInfo = "PumlDiagramInfo",
    _PumlSourceInfo = "PumlSourceInfo",
)

puml_diagram = _puml_diagram
puml_library = _puml_library

PumlSourceInfo = _PumlSourceInfo
PumlDiagramInfo = _PumlDiagramInfo
