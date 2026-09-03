#!/usr/bin/env bash
# rules_eslint test launcher.
#
#   argv[1]  = the @npm eslint binary  (runfiles rlocation path)
#   argv[2]  = the flat eslint config  (runfiles rlocation path)
#   argv[3:] = source files to lint    (paths relative to the runfiles root)
#
# The binary + config are resolved to absolute paths via the bazel runfiles
# library; the sources are forwarded verbatim (eslint resolves them against
# $PWD, which Bazel sets to the runfiles root for the test).

# --- begin runfiles.bash initialization v3 ---
set -uo pipefail
set +e
f=bazel_tools/tools/bash/runfiles/runfiles.bash
# shellcheck disable=SC1090
source "${RUNFILES_DIR:-/dev/null}/$f" 2>/dev/null ||
    source "$(grep -sm1 "^$f " "${RUNFILES_MANIFEST_FILE:-/dev/null}" | cut -f2- -d' ')" 2>/dev/null ||
    source "$0.runfiles/$f" 2>/dev/null ||
    source "$(grep -sm1 "^$f " "$0.runfiles_manifest" | cut -f2- -d' ')" 2>/dev/null ||
    source "$(grep -sm1 "^$f " "$0.exe.runfiles_manifest" | cut -f2- -d' ')" 2>/dev/null ||
    {
        echo >&2 "rules_eslint: cannot find the bazel runfiles library ($f)"
        exit 1
    }
f=
set -e
# --- end runfiles.bash initialization v3 ---

eslint_rlp="$1"
config_rlp="$2"
shift 2

ESLINT="$(rlocation "$eslint_rlp" || true)"
CONFIG="$(rlocation "$config_rlp" || true)"

if [[ -z "${ESLINT:-}" || ! -x "$ESLINT" ]]; then
    echo "rules_eslint: eslint binary not found in runfiles ($eslint_rlp)" >&2
    exit 1
fi
if [[ -z "${CONFIG:-}" ]]; then
    echo "rules_eslint: eslint config not found in runfiles ($config_rlp)" >&2
    exit 1
fi

exec "$ESLINT" --config "$CONFIG" "$@"
