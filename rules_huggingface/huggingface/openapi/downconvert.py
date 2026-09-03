#!/usr/bin/env python3
"""Down-convert an OpenAPI 3.1.0 document to 3.0.3 for codegen.

progenitor (via the `openapiv3` crate) only parses 3.0.x. The HF
Inference Endpoints spec is 3.1.0; the sole incompatibilities in it
are JSON-Schema-2020-12 constructs that 3.0 expresses differently:

  * `type: ["X", "null"]`  → `type: "X", nullable: true`
  * `type: "null"`         → `nullable: true` (no `type`)
  * `examples: [v, ...]`   → `example: v`  (3.0 has singular `example`)
  * `const: v`             → `enum: [v]`
  * `oneOf/anyOf: [{}, {$ref}]` → collapse to the single substantive
    member. HF expresses a "nullable $ref" this way; typify otherwise
    emits an enum named after the ref, colliding with the ref's own
    type definition (duplicate-definition build errors).

The HF spec contains only `X + null` type-arrays (no genuine
multi-type unions), so the conversion is lossless for our purposes.
Pure stdlib — runs under the hermetic `hf` python toolchain.

Usage: downconvert.py <in.json> <out.json>
"""

import json
import sys


def _is_trivial(member):
    """A oneOf/anyOf member that carries no type information: the empty
    schema `{}` or a bare null (`{"type": "null"}` / `{"nullable": ...}`)."""
    if not isinstance(member, dict) or not member:
        return True
    if member.get("type") == "null":
        return True
    if set(member.keys()) <= {"nullable"}:
        return True
    return False


def _collapse_union(node, key):
    members = node.get(key)
    if not isinstance(members, list):
        return
    substantive = [m for m in members if not _is_trivial(m)]
    nullable = len(substantive) != len(members)
    if len(substantive) == 1:
        node.pop(key)
        only = substantive[0]
        if "$ref" in only and len(only) == 1:
            # $ref can't carry siblings in 3.0; nullability is handled at
            # the property's `required` list, so drop it here.
            node["$ref"] = only["$ref"]
        else:
            node.update(only)
            if nullable:
                node["nullable"] = True


def convert(node):
    if isinstance(node, dict):
        _collapse_union(node, "oneOf")
        _collapse_union(node, "anyOf")
        t = node.get("type")
        if isinstance(t, list):
            nonnull = [x for x in t if x != "null"]
            if "null" in t:
                node["nullable"] = True
            if len(nonnull) == 1:
                node["type"] = nonnull[0]
            elif len(nonnull) == 0:
                node.pop("type", None)
            else:
                # No multi-type unions exist in the HF spec; fail loudly
                # rather than silently dropping type information.
                raise SystemExit(
                    "multi-type union not representable in 3.0: %r" % (t,)
                )
        elif t == "null":
            node.pop("type", None)
            node["nullable"] = True

        if isinstance(node.get("examples"), list) and "example" not in node:
            if node["examples"]:
                node["example"] = node["examples"][0]
            node.pop("examples", None)

        if "const" in node:
            node["enum"] = [node.pop("const")]

        for v in node.values():
            convert(v)
    elif isinstance(node, list):
        for v in node:
            convert(v)


def main():
    if len(sys.argv) != 3:
        raise SystemExit("usage: downconvert.py <in.json> <out.json>")
    with open(sys.argv[1]) as f:
        doc = json.load(f)
    doc["openapi"] = "3.0.3"
    convert(doc)
    with open(sys.argv[2], "w") as f:
        json.dump(doc, f, indent=2)


if __name__ == "__main__":
    main()
