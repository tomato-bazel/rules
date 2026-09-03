#!/usr/bin/env bash
# Fake VMM for rules_macvm tests. Prints the argv it was handed (one per
# line) and exits 0 — vfkit-CLI-compatible enough to exercise the whole
# `vm` launcher path (toolchain resolution, runfiles, file staging, arg
# rendering) with no Apple Virtualization.framework and no real Mac.
set -euo pipefail

echo "mock-vmm: boot"
for a in "$@"; do
  echo "arg: $a"
done
echo "mock-vmm: ok"
