"""Providers for the generic XSD layer (the `rules_xsd` seed).

`XsdInfo` is the XSD analog of rules_rdf's `RdfDatasetInfo`: a schema plus the
**transitive closure of the schemas it imports**, so a validator (or, later, an
XSD→emitter generator) sees the whole closure with no network access. An XSD is
rarely standalone — USLM-1.0 imports XML, Dublin Core terms, and XHTML — so the
closure is first-class, exactly as RDF graphs carry their `owl:imports` closure.
"""

XsdInfo = provider(
    doc = "A declared XSD schema and its transitive import closure.",
    fields = {
        "schema_root": "File: the entry-point .xsd to validate / generate against.",
        "transitive_files": "depset[File]: schema_root plus the full import " +
                            "closure (this schema's own srcs + every dep's closure).",
    },
)
