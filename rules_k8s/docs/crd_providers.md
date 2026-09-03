<!-- Generated with Stardoc: http://skydoc.bazel.build -->

Providers for the CRD half of rules_k8s.

<a id="K8sCrdInfo"></a>

## K8sCrdInfo

<pre>
load("@rules_k8s//crd:providers.bzl", "K8sCrdInfo")

K8sCrdInfo(<a href="#K8sCrdInfo-crds">crds</a>, <a href="#K8sCrdInfo-group">group</a>)
</pre>

CRD schemas generated from kubebuilder markers in a Go API package.

Carries the schemas as a directory rather than a file list because the set of
Kinds is not knowable at analysis time — controller-tools discovers it by
type-checking the package, inside the action. Consumers that need per-Kind facts
read the `listing` output group, which the action writes.

**FIELDS**

| Name  | Description |
| :------------- | :------------- |
| <a id="K8sCrdInfo-crds"></a>crds |  File: a TreeArtifact directory of CRD manifests, one `<group>_<plural>.yaml` per Kind.    |
| <a id="K8sCrdInfo-group"></a>group |  str: the API group these CRDs are in, e.g. 'platform.example.com'. Declared on the rule and verified against the generated output, so it cannot rot.    |


<a id="K8sTransitiveSchemasInfo"></a>

## K8sTransitiveSchemasInfo

<pre>
load("@rules_k8s//crd:providers.bzl", "K8sTransitiveSchemasInfo")

K8sTransitiveSchemasInfo(<a href="#K8sTransitiveSchemasInfo-schemas">schemas</a>)
</pre>

Transitive set of CRD schemas, threaded by the `_k8s_schemas` aspect.

Exists so `k8s_validate` can resolve what to validate a manifest against instead
of making every caller hand-list the CRDs — including reaching through
intermediate targets that don't themselves speak k8s (a filegroup, a genrule),
which is the part plain provider-threading can't do.

**FIELDS**

| Name  | Description |
| :------------- | :------------- |
| <a id="K8sTransitiveSchemasInfo-schemas"></a>schemas |  depset[K8sCrdInfo]: every CRD set reachable through `deps`.    |


