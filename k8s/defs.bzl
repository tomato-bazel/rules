"""Public API for the manifest half of rules_k8s.

    load("@rules_k8s//k8s:defs.bzl", "k8s_bundle", "k8s_validate")
"""

load("//k8s:providers.bzl", _K8sBundleInfo = "K8sBundleInfo", _K8sObjectInfo = "K8sObjectInfo")
load("//k8s/private:bundle.bzl", _k8s_bundle = "k8s_bundle", _k8s_object = "k8s_object")
load("//k8s/private:diff.bzl", _k8s_diff = "k8s_diff")
load("//k8s/private:schemas.bzl", _k8s_schemas_aspect = "k8s_schemas_aspect")
load("//k8s/private:validate.bzl", _k8s_validate = "k8s_validate")

k8s_object = _k8s_object
k8s_bundle = _k8s_bundle
k8s_validate = _k8s_validate
k8s_diff = _k8s_diff

K8sObjectInfo = _K8sObjectInfo
K8sBundleInfo = _K8sBundleInfo

# Exported so a rule outside rules_k8s can collect CRD schemas the same way
# k8s_validate does.
k8s_schemas_aspect = _k8s_schemas_aspect
