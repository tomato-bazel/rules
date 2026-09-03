#!/usr/bin/env bash
# Hermetic boot smoke: run a `vm` target built against the mock backend
# and confirm the launcher resolved the VMM + runfiles and "booted". No
# Apple Virtualization.framework required — exercises the whole rule
# pipeline (toolchain/provider resolution, runfiles, arg rendering).
set -euo pipefail

VM="$1"
out="$("$VM")"
echo "$out"

grep -q "mock-vmm: ok" <<<"$out" || { echo "boot_smoke: VMM did not complete" >&2; exit 1; }
grep -q -- "--cpus" <<<"$out" || { echo "boot_smoke: expected --cpus in argv" >&2; exit 1; }
grep -q "rosetta,mountTag=rosetta" <<<"$out" || { echo "boot_smoke: expected rosetta device" >&2; exit 1; }
