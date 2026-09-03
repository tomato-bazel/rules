<!-- Generated with Stardoc: http://skydoc.bazel.build -->

The CRD codegen toolchain: controller-tools plus the driver that feeds it.

<a id="k8s_crd_toolchain"></a>

## k8s_crd_toolchain

<pre>
load("@rules_k8s//crd:toolchains.bzl", "k8s_crd_toolchain")

k8s_crd_toolchain(<a href="#k8s_crd_toolchain-name">name</a>, <a href="#k8s_crd_toolchain-driver">driver</a>, <a href="#k8s_crd_toolchain-gen">gen</a>)
</pre>

Declares a CRD codegen toolchain.

The default implementation (`@rules_k8s//crd:default_k8s_crd_toolchain`) builds
controller-tools from the version pinned in rules_k8s's go.mod. That pin is a
schema decision — see the comment there — so an override should be a deliberate
"we generate with a different controller-tools", not a convenience.

Register with `--extra_toolchains` in .bazelrc, never `register_toolchains()` in
MODULE.bazel: the latter propagates to every consumer, which would drag a Go SDK
into the Rust services that only ever *read* CRD schemas.

**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="k8s_crd_toolchain-name"></a>name |  A unique name for this target.   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="k8s_crd_toolchain-driver"></a>driver |  The go/packages external driver. Must read its package-graph file list from K8S_CRD_DRIVER_PKG_JSON.   | <a href="https://bazel.build/concepts/labels">Label</a> | required |  |
| <a id="k8s_crd_toolchain-gen"></a>gen |  The CRD generator binary. Must accept `-out DIR [-expect-group G] [-listing F] PATTERN...`.   | <a href="https://bazel.build/concepts/labels">Label</a> | required |  |


<a id="K8sCrdToolchainInfo"></a>

## K8sCrdToolchainInfo

<pre>
load("@rules_k8s//crd:toolchains.bzl", "K8sCrdToolchainInfo")

K8sCrdToolchainInfo(<a href="#K8sCrdToolchainInfo-gen">gen</a>, <a href="#K8sCrdToolchainInfo-driver">driver</a>)
</pre>

The tools that turn kubebuilder markers into CRD YAML inside an action.

**FIELDS**

| Name  | Description |
| :------------- | :------------- |
| <a id="K8sCrdToolchainInfo-gen"></a>gen |  FilesToRunProvider: the CRD generator — controller-tools' genall driven as a library, writing to a named directory.    |
| <a id="K8sCrdToolchainInfo-driver"></a>driver |  FilesToRunProvider: the go/packages external driver. `gen` reaches it via GOPACKAGESDRIVER; it is never invoked directly.    |


