"""Helpers used by `schema_to_starlark`-generated rule code.

Kept in a separate file (rather than inlined per generated `.bzl`) so
the codegen output stays small and any helper fix benefits every
consumer at once. Generated `.bzl` files load from this module:

    load("@rules_jsonschema//runtime:helpers.bzl", "strip_empty", "parse_json_or_none")
"""

def strip_empty(d):
    """Drop dict entries whose values are absent / zero / empty.

    ⛔ Do not use this where a `false` is meaningful: it cannot express one, and the
    failure is silent. See [`strip_unset`].

    Matches the JSON `omitempty` convention so generated shards stay
    terse — Bazel `attr.*` zero values (0, False, "", [], {}) shouldn't
    serialise as explicit overrides. Distinguishing "user set to 0"
    from "user didn't set" isn't possible at the Starlark layer, so
    we conflate them: every typed schema field that wants to mean
    something non-default ships a non-zero/-empty value.

    ⚠ That last sentence is FALSE for anything routed through
    [`parse_json_or_none`], which already returns `None` for an unset attr — so
    `None` and `False` were distinguishable all along. It is retained because it
    documents what this function still does.

    Args:
      d: the property payload to filter.

    Returns:
      `d` without absent, zero or empty entries.

    Deprecated:
      Generated code now emits [`strip_unset`], which drops only values the caller
      never set. This is kept because previously generated `.bzl` loads it by name,
      and because dropping `[]`/`{}` is defensible for hand-written callers.
    """
    out = {}
    for k, v in d.items():
        if v == None:
            continue
        t = type(v)
        if t == "list" and len(v) == 0:
            continue
        if t == "dict" and len(v) == 0:
            continue
        if t == "string" and v == "":
            continue
        if t == "int" and v == 0:
            continue
        if t == "bool" and v == False:
            continue
        out[k] = v
    return out

def strip_unset(d):
    """Drop dict entries the caller never set — and ONLY those.

    ⛔ THE DIFFERENCE FROM [`strip_empty`] IS A CORRECTNESS ONE, NOT A STYLE ONE.
    `strip_empty` also drops `False`, `0`, `[]` and `{}`, which makes an explicitly
    requested `false` indistinguishable from an omission. That fails OPEN whenever the
    schema's own default is truthy: `AWS::EKS::Cluster`'s
    `ResourcesVpcConfig.EndpointPublicAccess` defaults **true**, so "private endpoint
    only" is exactly the shape that silently renders as a public endpoint. See
    tomato-bazel/rules_cloudformation#2, where it was measured.

    ⭐ AND THE INFORMATION WAS NEVER ACTUALLY LOST. Every generated attr is a STRING;
    a `bool`, `int`, `list` or `dict` can only appear in the payload because
    [`parse_json_or_none`] decoded one — and that function already returns `None` for
    an unset attr. So `None` means "not set" and `False` means "set to false", and
    they were distinguishable all along. `strip_empty`'s docstring says the opposite;
    that claim is wrong for anything routed through `parse_json_or_none`.

    ⚠ `""` is still dropped, and that one IS genuinely ambiguous: an unset
    `attr.string` and one set to the empty string are the same value at this layer.
    Expressing an intentional empty string needs a sentinel default at codegen, which
    is a larger change than this.

    Args:
      d: the property payload to filter.

    Returns:
      `d` without the entries the caller never set.
    """
    out = {}
    for k, v in d.items():
        if v == None:
            continue
        if type(v) == "string" and v == "":
            continue
        out[k] = v
    return out

def parse_json_or_none(s):
    """Return `None` for empty input, otherwise `json.decode(s)`.

    Used for typed schema attrs whose value is a structured object
    or array. Generated rule callers pass `json.encode({...})` (or
    leave the attr empty); the generated impl invokes this to expand
    the encoded payload back into a Starlark dict/list that gets
    merged into the shard.
    """
    if not s:
        return None
    return json.decode(s)
