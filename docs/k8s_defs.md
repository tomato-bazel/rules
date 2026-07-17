<!-- Generated with Stardoc: http://skydoc.bazel.build -->

Public API for the manifest half of rules_k8s.

load("@rules_k8s//k8s:defs.bzl", "k8s_bundle", "k8s_validate")

<a id="k8s_bundle"></a>

## k8s_bundle

<pre>
load("@rules_k8s//k8s:defs.bzl", "k8s_bundle")

k8s_bundle(<a href="#k8s_bundle-name">name</a>, <a href="#k8s_bundle-deps">deps</a>, <a href="#k8s_bundle-srcs">srcs</a>)
</pre>

Collect Kubernetes manifests into one conflict-checked directory.

Fails the build if two manifests declare the same group/Kind/namespace/name.
That is the whole point over a `filegroup`: applying such a pair keeps whichever
came last, and which that is depends on ordering. Note identity excludes the API
VERSION — `Foo/v1` and `Foo/v1beta1` with the same name are the same object.

Manifests are placed, never rewritten: source bytes are copied verbatim, so key
order and comments survive. A bundle that round-tripped YAML through a marshaller
would silently rewrite the API surface it is supposed to be checking.

`deps` composes bundles without needing an aspect; the `_k8s_schemas` aspect is
there to reach CRD schemas through targets that don't speak k8s.

    k8s_bundle(name = "apps", srcs = glob(["argocd/apps/*.yaml"]))
    k8s_bundle(name = "fleet", deps = [":apps", "//op-a:bundle"])

**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="k8s_bundle-name"></a>name |  A unique name for this target.   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="k8s_bundle-deps"></a>deps |  Other bundles, `k8s_object` targets, `k8s_crd_library` targets, or plain file-providing targets.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="k8s_bundle-srcs"></a>srcs |  Manifest files to include directly.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |


<a id="k8s_diff"></a>

## k8s_diff

<pre>
load("@rules_k8s//k8s:defs.bzl", "k8s_diff")

k8s_diff(<a href="#k8s_diff-name">name</a>, <a href="#k8s_diff-bundle">bundle</a>)
</pre>

`bazel run` to diff a bundle against the live cluster. Read-only.

    bazel run //argocd:apps_diff -- --context=my-cluster

Extra arguments after `--` pass through to `kubectl diff`. Exits non-zero when
there is a difference, which is kubectl's own convention.

Uses whatever kubectl is on your PATH — see //kubectl/toolchains.bzl for why
pinning one would be wrong.

**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="k8s_diff-name"></a>name |  A unique name for this target.   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="k8s_diff-bundle"></a>bundle |  The `k8s_bundle` to compare against the cluster.   | <a href="https://bazel.build/concepts/labels">Label</a> | required |  |


<a id="k8s_object"></a>

## k8s_object

<pre>
load("@rules_k8s//k8s:defs.bzl", "k8s_object")

k8s_object(<a href="#k8s_object-name">name</a>, <a href="#k8s_object-srcs">srcs</a>, <a href="#k8s_object-expect_api_version">expect_api_version</a>, <a href="#k8s_object-expect_kind">expect_kind</a>)
</pre>

Adopt checked-in Kubernetes manifests into the build graph.

No codegen and no rewriting — it types the graph so `k8s_bundle` and
`k8s_validate` can consume the files, and optionally asserts that a manifest is
what the BUILD file says it is.

Reach for `k8s_bundle(srcs = ...)` directly unless you want the assertion; this
rule earns its place when a manifest's identity is load-bearing elsewhere.

    k8s_object(
        name = "myresource",
        srcs = ["myresource.yaml"],
        expect_kind = "MyResource",
        expect_api_version = "platform.example.com/v1",
    )

**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="k8s_object-name"></a>name |  A unique name for this target.   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="k8s_object-srcs"></a>srcs |  Manifest files. Each may hold multiple documents.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | required |  |
| <a id="k8s_object-expect_api_version"></a>expect_api_version |  If set, every object in `srcs` must be this apiVersion, or the build fails.   | String | optional |  `""`  |
| <a id="k8s_object-expect_kind"></a>expect_kind |  If set, every object in `srcs` must be this Kind, or the build fails.   | String | optional |  `""`  |


<a id="K8sBundleInfo"></a>

## K8sBundleInfo

<pre>
load("@rules_k8s//k8s:defs.bzl", "K8sBundleInfo")

K8sBundleInfo(<a href="#K8sBundleInfo-dir">dir</a>, <a href="#K8sBundleInfo-files">files</a>)
</pre>

A collected, conflict-checked set of Kubernetes objects.

**FIELDS**

| Name  | Description |
| :------------- | :------------- |
| <a id="K8sBundleInfo-dir"></a>dir |  File: TreeArtifact of the manifests, one file per object, named from its identity.    |
| <a id="K8sBundleInfo-files"></a>files |  depset[File]: the source manifests that composed it.    |


<a id="K8sObjectInfo"></a>

## K8sObjectInfo

<pre>
load("@rules_k8s//k8s:defs.bzl", "K8sObjectInfo")

K8sObjectInfo(<a href="#K8sObjectInfo-files">files</a>)
</pre>

Kubernetes manifests contributed by a target.

Carries files and nothing else. Identity (group/version/kind, name, namespace) is
resolved by the bundle ACTION, not here — Starlark cannot read files, so a rule
that adopts a checked-in manifest has no way to know its Kind at analysis time.
Duplicate detection and the listing therefore live in the tool.
(rules_cloudformation's stack aggregator makes the same trade for the same
reason: it can't load many hundreds of per-kind providers, so it reads the shards.)

**FIELDS**

| Name  | Description |
| :------------- | :------------- |
| <a id="K8sObjectInfo-files"></a>files |  depset[File]: manifest YAMLs. Each may hold multiple documents.    |


<a id="k8s_validate"></a>

## k8s_validate

<pre>
load("@rules_k8s//k8s:defs.bzl", "k8s_validate")

k8s_validate(<a href="#k8s_validate-name">name</a>, <a href="#k8s_validate-kwargs">**kwargs</a>)
</pre>

Validate a `k8s_bundle` against its CRD schemas. See `_k8s_validate_test`.

A macro only because Bazel requires test rule classes to end in `_test`.

**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="k8s_validate-name"></a>name |  <p align="center"> - </p>   |  none |
| <a id="k8s_validate-kwargs"></a>kwargs |  <p align="center"> - </p>   |  none |


<a id="k8s_schemas_aspect"></a>

## k8s_schemas_aspect

<pre>
load("@rules_k8s//k8s:defs.bzl", "k8s_schemas_aspect")

k8s_schemas_aspect()
</pre>

Collect `K8sCrdInfo` from a target and everything reachable via `deps`/`srcs`.

Exists so `k8s_validate` resolves its own schemas instead of making callers
hand-list every CRD set a bundle might contain:

    k8s_bundle(name = "fleet", deps = ["//op-a:bundle", "//op-b:bundle"])
    k8s_validate(name = "fleet_valid", bundle = ":fleet")   # finds both operators' CRDs

Plain provider-threading would cover that much. What needs an aspect is reaching
THROUGH a target that doesn't speak k8s at all — a `filegroup` or `genrule`
wrapping several `k8s_crd_library` targets. Those return neither of our providers,
so nothing would propagate; an aspect visits them anyway.

`srcs` is walked as well as `deps` because a filegroup carries its contents there.

**ASPECT ATTRIBUTES**


| Name | Type |
| :------------- | :------------- |
| deps| String |
| srcs| String |


**ATTRIBUTES**



