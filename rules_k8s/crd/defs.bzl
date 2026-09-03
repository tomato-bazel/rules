"""Public API for the CRD half of rules_k8s.

    load("@rules_k8s//crd:defs.bzl", "k8s_crd_library")
"""

load("//crd:providers.bzl", _K8sCrdInfo = "K8sCrdInfo", _K8sTransitiveSchemasInfo = "K8sTransitiveSchemasInfo")
load("//crd:toolchains.bzl", _K8sCrdToolchainInfo = "K8sCrdToolchainInfo", _k8s_crd_toolchain = "k8s_crd_toolchain")
load("//crd/private:crd_library.bzl", _k8s_crd_library = "k8s_crd_library")

k8s_crd_library = _k8s_crd_library
k8s_crd_toolchain = _k8s_crd_toolchain

K8sCrdInfo = _K8sCrdInfo
K8sTransitiveSchemasInfo = _K8sTransitiveSchemasInfo
K8sCrdToolchainInfo = _K8sCrdToolchainInfo
