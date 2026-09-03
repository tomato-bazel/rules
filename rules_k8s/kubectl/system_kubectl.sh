#!/usr/bin/env bash
# The default kubectl "toolchain": whatever the operator already has.
#
# Non-hermetic on purpose — see //kubectl/toolchains.bzl. kubectl must be within
# one minor of the cluster's API server, so the right kubectl is the one the
# person running this already uses for that cluster, not one we pinned.
set -euo pipefail

if ! command -v kubectl >/dev/null 2>&1; then
  cat >&2 <<'MSG'
kubectl not found on PATH.

rules_k8s does not ship a kubectl: it must stay within one minor of your
cluster's API server, so pinning one across a fleet would break more than it
fixes. Install kubectl, or register your own kubectl_toolchain ahead of
@rules_k8s//kubectl:default_kubectl_toolchain.
MSG
  exit 1
fi

exec kubectl "$@"
