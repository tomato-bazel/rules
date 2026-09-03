"""Unit tests for the payload-stripping helpers.

⛔ The load-bearing case is `false_survives_strip_unset`. A top-level property set to
`false` that renders as ABSENT is not a cosmetic bug: whenever the schema's own default
is truthy, the omission means the OPPOSITE of what was written, and it fails open.
`AWS::EKS::Cluster.ResourcesVpcConfig.EndpointPublicAccess` defaults **true**, so
"private endpoint only" is exactly this shape. Measured in
tomato-bazel/rules_cloudformation#2.
"""

load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")

# buildifier: disable=deprecated-function
#
# ⚠ `strip_empty` is imported ON PURPOSE. Pinning that it STILL drops `false` is the
# point of `_strip_empty_still_drops_false` — without it, generated code that continues
# to load the old helper could change meaning without anyone choosing that.
load(":helpers.bzl", "parse_json_or_none", "strip_empty", "strip_unset")

def _false_survives_strip_unset(ctx):
    env = unittest.begin(ctx)

    # The exact shape from rules_cloudformation#2: an attr written as "false".
    payload = strip_unset({"EmptyOnDelete": parse_json_or_none("false")})
    asserts.true(
        env,
        "EmptyOnDelete" in payload,
        "an explicit false must survive; dropping it renders the schema default instead",
    )
    asserts.equals(env, False, payload["EmptyOnDelete"])

    # Zero and empty containers are equally explicit.
    kept = strip_unset({
        "Zero": parse_json_or_none("0"),
        "EmptyList": parse_json_or_none("[]"),
        "EmptyObject": parse_json_or_none("{}"),
    })
    asserts.equals(env, [0, [], {}], [kept["Zero"], kept["EmptyList"], kept["EmptyObject"]])

    return unittest.end(env)

def _unset_is_still_dropped(ctx):
    env = unittest.begin(ctx)

    # An attr the caller never set arrives as "" and decodes to None.
    payload = strip_unset({"Untouched": parse_json_or_none(""), "Set": "value"})
    asserts.equals(env, ["Set"], payload.keys())

    # ⚠ An empty STRING is still conflated with unset, and that is documented rather
    # than fixed: at this layer an unset `attr.string` and one set to "" are the same
    # value. Pinned so the limitation is visible rather than discovered.
    asserts.equals(env, {}, strip_unset({"EmptyString": ""}))

    return unittest.end(env)

def _strip_empty_still_drops_false(ctx):
    env = unittest.begin(ctx)

    # The old behaviour is retained deliberately for existing callers. If this ever
    # starts passing a `false` through, generated code that still loads `strip_empty`
    # changed meaning without anyone choosing that.
    asserts.equals(env, {}, strip_empty({"EmptyOnDelete": False}))
    asserts.equals(env, {}, strip_empty({"Zero": 0}))

    return unittest.end(env)

false_survives_strip_unset_test = unittest.make(_false_survives_strip_unset)
unset_is_still_dropped_test = unittest.make(_unset_is_still_dropped)
strip_empty_still_drops_false_test = unittest.make(_strip_empty_still_drops_false)

def helpers_test_suite(name):
    """Register the helper unit tests.

    Args:
      name: the test_suite target name.
    """
    unittest.suite(
        name,
        false_survives_strip_unset_test,
        unset_is_still_dropped_test,
        strip_empty_still_drops_false_test,
    )
