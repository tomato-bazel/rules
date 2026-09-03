#!/usr/bin/env bash
# Assert k8s_validate REJECTS a CR that violates its CRD's markers.
#
# Without this, every green k8s_validate is unfalsifiable: a validator wired to
# the wrong schema dir, or handed zero schemas, passes everything silently. This
# is the test that makes the other one mean something.
set -uo pipefail

out="$("$VALIDATOR" 2>&1)"
rc=$?

if [ $rc -eq 0 ]; then
  echo "FAIL: k8s_validate PASSED a Widget with replicas=1000 (Maximum=99) and" >&2
  echo "      mode=Sideways (not in the Enum). The validator is not actually" >&2
  echo "      checking against the CRD schema." >&2
  echo "--- validator output ---" >&2
  echo "$out" >&2
  exit 1
fi

# Fail for the RIGHT reason: a missing schema also exits non-zero, and would let
# this test pass while validating nothing.
if ! grep -qiE "replicas|mode|must be|maximum|enum" <<<"$out"; then
  echo "FAIL: k8s_validate failed, but not because of the schema violation." >&2
  echo "      Expected a complaint about replicas/mode; got:" >&2
  echo "$out" >&2
  exit 1
fi

echo "OK: k8s_validate rejected the invalid Widget:"
echo "$out"
