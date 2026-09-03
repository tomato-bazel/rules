#!/usr/bin/env bash
# macOS-only: prove the fetched vfkit is the SIGNED binary with the
# Virtualization.framework entitlement, and that Bazel's copy didn't
# break the signature. This is the guard for "native_binary copied the
# Mach-O and invalidated codesigning."
set -euo pipefail

BIN="$1"
[[ -x "$BIN" ]] || { echo "vfkit_signature: not executable: $BIN" >&2; exit 2; }

codesign -v "$BIN" 2>/dev/null \
  || { echo "vfkit_signature: invalid code signature (copy broke it?)" >&2; exit 1; }

codesign -d --entitlements - "$BIN" 2>&1 | tr -d '\0' \
  | grep -q 'com.apple.security.virtualization' \
  || { echo "vfkit_signature: missing com.apple.security.virtualization entitlement" >&2; exit 1; }

"$BIN" --version
echo "vfkit_signature: signature + entitlement OK"
