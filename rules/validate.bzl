"""`agent_validate` — SHACL-validate a consumer's authored `.agents` graph
against the `aide:` shapes, as a Bazel test.

Thin wrapper over `@rules_rdf//validate:defs.bzl%rdf_validate_test` with
the framework's shapes as the default — so a consumer just points it at
their graph and gets a `bazel test //.agents:validate` gate that fails
loudly (with fix-it messages) on a malformed or version-incompatible
graph, instead of producing broken config downstream.

```python
load("@rules_agentic_ide//rules:defs.bzl", "agent_validate")

agent_validate(name = "validate", graph = ":graph")
```
"""

load("@rules_rdf//validate:defs.bzl", "rdf_validate_test")

# The aide: SHACL shapes shipped by the framework.
DEFAULT_AIDE_SHAPES = "@rules_agentic_ide//rdf/shapes:aide_shapes.ttl"

def agent_validate(name, graph, shapes = None, **kwargs):
    """Validate `graph` (an rdf_dataset / RdfDatasetInfo) against `shapes`
    (default: the framework's aide: shapes). Fails the test on violations."""
    rdf_validate_test(
        name = name,
        dataset = graph,
        shapes = shapes or DEFAULT_AIDE_SHAPES,
        **kwargs
    )
