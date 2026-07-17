module github.com/tomato-bazel/rules_k8s

// The Go deps of the CRD toolchain (the driver + the controller-gen wrapper).
// These are NOT a consumer's deps: rules_go is a dev_dependency in MODULE.bazel
// precisely so a Rust consumer reading a CRD schema never resolves any of this.
//
// EVERY VERSION HERE IS A SCHEMA DECISION, NOT A DEPENDENCY BUMP.
//
// They are pinned to controller-tools v0.16.5's own go.mod, because v0.16.5 is
// what the whole fleet generates with today and this must emit byte-identical
// CRDs. Otherwise adopting rules_k8s silently rewrites every schema — and
// write_source_files would push those rewrites into charts that ArgoCD
// server-side-applies. Before changing any of these, run the byte-diff over all
// every operator (README: "Verifying against stock controller-gen").
//
// Do not run a bare `go mod tidy` and accept the result. Left alone it floats
// k8s.io/apimachinery to v0.35.0-alpha.0 — an alpha — off controller-tools'
// transitive requirements. a real operator's go.mod hit the same trap
// and pins the same way for the same reason.
//
//	upstream sigs.k8s.io/controller-tools v0.16.5 go.mod:
//	  golang.org/x/tools             v0.26.0
//	  k8s.io/apiextensions-apiserver v0.31.2
//	  k8s.io/apimachinery            v0.31.2
//	  sigs.k8s.io/yaml               v1.4.0
go 1.26.0

require (
	golang.org/x/tools v0.26.0
	k8s.io/apimachinery v0.31.2
	sigs.k8s.io/controller-tools v0.16.5
	sigs.k8s.io/yaml v1.4.0
)

require (
	github.com/fxamacker/cbor/v2 v2.9.1 // indirect
	github.com/go-logr/logr v1.4.3 // indirect
	github.com/gobuffalo/flect v1.0.3 // indirect
	github.com/gogo/protobuf v1.3.2 // indirect
	github.com/google/gofuzz v1.2.0 // indirect
	github.com/json-iterator/go v1.1.12 // indirect
	github.com/kr/text v0.2.0 // indirect
	github.com/modern-go/concurrent v0.0.0-20180306012644-bacd9c7ef1dd // indirect
	github.com/modern-go/reflect2 v1.0.3-0.20250322232337-35a7c28c31ee // indirect
	github.com/x448/float16 v0.8.4 // indirect
	golang.org/x/mod v0.25.0 // indirect
	golang.org/x/net v0.40.0 // indirect
	golang.org/x/sync v0.20.0 // indirect
	golang.org/x/text v0.25.0 // indirect
	gopkg.in/check.v1 v1.0.0-20201130134442-10cb98267c6c // indirect
	gopkg.in/inf.v0 v0.9.1 // indirect
	gopkg.in/yaml.v2 v2.4.0 // indirect
	k8s.io/apiextensions-apiserver v0.31.2 // indirect
	k8s.io/klog/v2 v2.140.0 // indirect
	k8s.io/utils v0.0.0-20260319190234-28399d86e0b5 // indirect
	sigs.k8s.io/json v0.0.0-20250730193827-2d320260d730 // indirect
	sigs.k8s.io/structured-merge-diff/v4 v4.4.1 // indirect
)
