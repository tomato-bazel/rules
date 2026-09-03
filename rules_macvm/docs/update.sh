#!/usr/bin/env bash
# Regenerate docs/*.md from stardoc output. Run after changing rule
# docstrings. Invoked via `bazel run //docs:update`.
set -euo pipefail

if [[ -z "${BUILD_WORKSPACE_DIRECTORY:-}" ]]; then
  echo "error: must be invoked via 'bazel run //docs:update'" >&2
  exit 1
fi

RUNFILES_DIR="${RUNFILES_DIR:-$0.runfiles}"

for name in vm_defs vm_providers vm_toolchains vfkit image; do
  gen="$(find "$RUNFILES_DIR" -name "${name}.md.generated" -print -quit)"
  cp "$gen" "$BUILD_WORKSPACE_DIRECTORY/docs/${name}.md"
done

echo "docs/{vm_defs,vm_providers,vm_toolchains,vfkit,image}.md regenerated."
