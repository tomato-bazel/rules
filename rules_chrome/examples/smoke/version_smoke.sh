#!/usr/bin/env bash
# Smoke check: the given binary exits 0 on `--version` and prints something.
set -euo pipefail

BIN="$1"
if [[ ! -x "$BIN" ]]; then
  echo "version_smoke: binary not executable: $BIN" >&2
  exit 2
fi

# Linux CI runners don't ship libnss3 etc. by default — without these,
# chrome's --version call still works (it doesn't touch the renderer)
# but if we ever extend this to a real launch, the workflow file needs
# to apt-get those libs first.
out="$("$BIN" --version)"
echo "$out"
[[ -n "$out" ]] || { echo "version_smoke: empty --version output" >&2; exit 3; }
