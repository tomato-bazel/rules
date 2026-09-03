"""User-facing XSD rules (the `rules_xsd` seed).

Two rules, deliberately shaped like rules_rdf's `rdf_dataset` + `rdf_validate_test`
so the whole package lifts into a standalone `rules_xsd` ruleset once the shape
settles (legislative-kg §11):

  * `xsd_schema(name, srcs, deps)` — declare an XSD plus the schemas it imports
    (as other `xsd_schema` targets). Produces `XsdInfo` carrying the transitive
    import closure, the XSD analog of an `rdf_dataset` closure.

  * `xsd_validate_test(name, schema, xml)` — assert an XML instance validates
    against an `XsdInfo`'s schema (resolving every `<xsd:import>` from the local
    closure, never the network). The first correct-by-construction gate.

```python
load("//xsd:defs.bzl", "xsd_schema", "xsd_validate_test")

xsd_schema(name = "xml_ns", srcs = ["@uslm_schema//:xml.xsd"])
xsd_schema(name = "uslm",   srcs = ["@uslm_schema//:USLM-1.0.15.xsd"], deps = [":xml_ns", ...])

xsd_validate_test(name = "slice_valid", schema = ":uslm", xml = "//data:usc_t26_slice.xml")
```

Next step (the `owl:imports`-strict-manifest analog): an aspect that parses each
schema's `<xsd:import namespace=…>` and fails unless every imported namespace is
covered by a declared `dep`'s `targetNamespace` — a closure-completeness gate.
For the first cut, `deps` are explicit and the validator fails loudly if a needed
namespace is absent from the closure.
"""

load(":providers.bzl", "XsdInfo")

def _xsd_schema_impl(ctx):
    direct = ctx.files.srcs
    if not direct:
        fail("xsd_schema: `srcs` must list at least one .xsd file.")
    root = ctx.file.root if ctx.file.root else direct[0]
    transitive = depset(
        direct = direct,
        transitive = [d[XsdInfo].transitive_files for d in ctx.attr.deps],
    )
    return [
        DefaultInfo(files = depset(direct)),
        XsdInfo(schema_root = root, transitive_files = transitive),
    ]

xsd_schema = rule(
    implementation = _xsd_schema_impl,
    attrs = {
        "srcs": attr.label_list(
            allow_files = [".xsd"],
            mandatory = True,
            doc = "This schema's own .xsd file(s).",
        ),
        "root": attr.label(
            allow_single_file = [".xsd"],
            doc = "Entry-point schema to validate / generate against " +
                  "(defaults to `srcs[0]`).",
        ),
        "deps": attr.label_list(
            providers = [XsdInfo],
            doc = "Imported schemas (other `xsd_schema` targets); their " +
                  "closures fold into this one's `transitive_files`.",
        ),
    },
    provides = [XsdInfo],
    doc = "Declare an XSD schema + its transitive import closure.",
)

def _xsd_validate_test_impl(ctx):
    info = ctx.attr.schema[XsdInfo]
    validator = ctx.executable._validator
    closure = info.transitive_files.to_list()

    runner = ctx.actions.declare_file(ctx.label.name + ".sh")
    ctx.actions.write(
        output = runner,
        is_executable = True,
        content = """#!/usr/bin/env bash
set -euo pipefail
RUNFILES_DIR="${{RUNFILES_DIR:-$0.runfiles}}"
WS_NAME="{ws}"

resolve() {{
    local sp="$1"
    if [[ "$sp" == ../* ]]; then
        printf '%s' "$RUNFILES_DIR/${{sp#../}}"
    else
        printf '%s' "$RUNFILES_DIR/$WS_NAME/$sp"
    fi
}}

VALIDATOR="$(resolve "{validator_sp}")"
ROOT="$(resolve "{root_sp}")"
XML="$(resolve "{xml_sp}")"
CLOSURE=""
{closure_lines}

exec "$VALIDATOR" --root="$ROOT" --xml="$XML" --closure="$CLOSURE"
""".format(
            ws = ctx.workspace_name,
            validator_sp = validator.short_path,
            root_sp = info.schema_root.short_path,
            xml_sp = ctx.file.xml.short_path,
            closure_lines = "\n".join([
                'CLOSURE="${CLOSURE:+$CLOSURE,}$(resolve "%s")"' % f.short_path
                for f in closure
            ]),
        ),
    )

    runfiles = ctx.runfiles(files = [validator, ctx.file.xml] + closure)
    runfiles = runfiles.merge(ctx.attr._validator[DefaultInfo].default_runfiles)
    return [DefaultInfo(executable = runner, runfiles = runfiles)]

xsd_validate_test = rule(
    implementation = _xsd_validate_test_impl,
    test = True,
    attrs = {
        "schema": attr.label(
            providers = [XsdInfo],
            mandatory = True,
            doc = "The `xsd_schema` to validate against (its closure resolves imports).",
        ),
        "xml": attr.label(
            allow_single_file = [".xml"],
            mandatory = True,
            doc = "The XML instance to validate.",
        ),
        "_validator": attr.label(
            default = Label("//xsd:xsd_validate"),
            executable = True,
            cfg = "exec",
        ),
    },
    doc = "Assert an XML instance validates against an XSD closure (offline).",
)

def _xsd_to_vocab_impl(ctx):
    info = ctx.attr.schema[XsdInfo]
    out = ctx.actions.declare_file(ctx.label.name + ".ttl")
    args = ctx.actions.args()
    args.add(info.schema_root, format = "--root=%s")
    args.add(out, format = "--out=%s")
    if ctx.attr.namespace:
        args.add(ctx.attr.namespace, format = "--namespace=%s")
    ctx.actions.run(
        executable = ctx.executable._generator,
        arguments = [args],
        inputs = [info.schema_root],
        outputs = [out],
        mnemonic = "XsdToVocab",
        progress_message = "xsd_to_vocab %s" % ctx.label,
    )
    return [DefaultInfo(files = depset([out]))]

xsd_to_vocab = rule(
    implementation = _xsd_to_vocab_impl,
    attrs = {
        "schema": attr.label(
            providers = [XsdInfo],
            mandatory = True,
            doc = "The `xsd_schema` whose root is translated to an RDF/OWL vocabulary.",
        ),
        "namespace": attr.string(
            doc = "Ontology namespace IRI for the generated terms " +
                  "(defaults to the schema's targetNamespace + '#').",
        ),
        "_generator": attr.label(
            default = Label("//xsd:xsd_to_vocab"),
            executable = True,
            cfg = "exec",
        ),
    },
    doc = "Generate a Turtle RDF/OWL vocabulary from an XSD — the 'XSD -> RDF, " +
          "first instance'. Feed the output to jena_schemagen for typed views.",
)
