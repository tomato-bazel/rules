package main

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func write(t *testing.T, dir, name, content string) string {
	t.Helper()
	p := filepath.Join(dir, name)
	if err := os.WriteFile(p, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
	return p
}

const appYAML = `apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: my-operator
  namespace: argocd
spec:
  source:
    targetRevision: 0.1.0-abc
`

func TestParseAndCollect(t *testing.T) {
	dir := t.TempDir()
	src := write(t, dir, "app.yaml", appYAML)
	out := filepath.Join(dir, "bundle")

	objs, err := parseAll([]string{src})
	if err != nil {
		t.Fatalf("parseAll: %v", err)
	}
	if len(objs) != 1 {
		t.Fatalf("got %d objects, want 1", len(objs))
	}
	if got, want := objs[0].obj.key(), "argoproj.io/Application/argocd/my-operator"; got != want {
		t.Errorf("key = %q, want %q", got, want)
	}
	if err := collect(objs, out); err != nil {
		t.Fatalf("collect: %v", err)
	}
	got, err := os.ReadFile(filepath.Join(out, "argoproj.io_application_argocd_my-operator.yaml"))
	if err != nil {
		t.Fatalf("expected the object at its identity-derived name: %v", err)
	}
	// The bundle must place manifests, never rewrite them. If this ever
	// round-trips through a YAML marshaller it will reorder keys and drop
	// comments — silently rewriting the operator's public API surface.
	if !strings.Contains(string(got), "targetRevision: 0.1.0-abc") {
		t.Errorf("source bytes were not preserved verbatim:\n%s", got)
	}
}

// TestDuplicateIsAnError is the reason k8s_bundle exists rather than a filegroup.
// Two manifests with the same identity are not two objects: applying both keeps
// whichever came last, and which that is depends on ordering.
func TestDuplicateIsAnError(t *testing.T) {
	dir := t.TempDir()
	a := write(t, dir, "a.yaml", appYAML)
	b := write(t, dir, "b.yaml", appYAML)

	objs, err := parseAll([]string{a, b})
	if err != nil {
		t.Fatal(err)
	}
	err = collect(objs, filepath.Join(dir, "out"))
	if err == nil {
		t.Fatal("want an error for two objects with the same group/Kind/namespace/name, got nil")
	}
	if !strings.Contains(err.Error(), "duplicate object") {
		t.Errorf("error = %v, want it to name the duplicate", err)
	}
}

// TestSameNameDifferentVersionCollides pins a subtle one: Kubernetes identity
// excludes the API version. Foo/v1 and Foo/v1beta1 with the same name are the
// SAME object, so shipping both is a conflict, not a pair.
func TestSameNameDifferentVersionCollides(t *testing.T) {
	dir := t.TempDir()
	v1 := write(t, dir, "v1.yaml", "apiVersion: x.dev/v1\nkind: Foo\nmetadata:\n  name: n\n")
	beta := write(t, dir, "beta.yaml", "apiVersion: x.dev/v1beta1\nkind: Foo\nmetadata:\n  name: n\n")

	objs, err := parseAll([]string{v1, beta})
	if err != nil {
		t.Fatal(err)
	}
	if err := collect(objs, filepath.Join(dir, "out")); err == nil {
		t.Fatal("want a conflict: identity excludes the version, so these are the same object")
	}
}

// TestMultiDoc: a manifest may hold many objects, and each is its own object.
// Namespace and cluster-scoped ones must not collide just by sharing a name.
func TestMultiDoc(t *testing.T) {
	dir := t.TempDir()
	src := write(t, dir, "multi.yaml", `apiVersion: v1
kind: ServiceAccount
metadata:
  name: op
  namespace: ns
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: op
`)
	objs, err := parseAll([]string{src})
	if err != nil {
		t.Fatalf("parseAll: %v", err)
	}
	if len(objs) != 2 {
		t.Fatalf("got %d objects, want 2", len(objs))
	}
	// A core object ("v1") is in the empty group — what Kubernetes calls it too.
	if got, want := objs[0].obj.key(), "/ServiceAccount/ns/op"; got != want {
		t.Errorf("key = %q, want %q", got, want)
	}
	if err := collect(objs, filepath.Join(dir, "out")); err != nil {
		t.Errorf("same name, different Kind/scope must not collide: %v", err)
	}
}

// TestEmptyAndCommentDocsSkipped: a trailing `---` or a comment block is not an
// object. Failing on those would reject valid manifests.
func TestEmptyAndCommentDocsSkipped(t *testing.T) {
	dir := t.TempDir()
	src := write(t, dir, "x.yaml", "# just a comment\n---\n"+appYAML+"---\n")
	objs, err := parseAll([]string{src})
	if err != nil {
		t.Fatalf("parseAll: %v", err)
	}
	if len(objs) != 1 {
		t.Fatalf("got %d objects, want 1 (comment and trailing --- are not objects)", len(objs))
	}
}

func TestMissingNameIsAnError(t *testing.T) {
	dir := t.TempDir()
	src := write(t, dir, "x.yaml", "apiVersion: v1\nkind: ConfigMap\n")
	if _, err := parseAll([]string{src}); err == nil {
		t.Fatal("want an error for an object with no metadata.name")
	}
}

func TestVerifyExpectations(t *testing.T) {
	dir := t.TempDir()
	src := write(t, dir, "app.yaml", appYAML)
	objs, err := parseAll([]string{src})
	if err != nil {
		t.Fatal(err)
	}
	if err := verifyAll(objs, "Application", "argoproj.io/v1alpha1"); err != nil {
		t.Errorf("matching expectations should pass: %v", err)
	}
	if err := verifyAll(objs, "Deployment", ""); err == nil {
		t.Error("want an error when the declared kind disagrees with the file")
	}
	if err := verifyAll(objs, "", "apps/v1"); err == nil {
		t.Error("want an error when the declared apiVersion disagrees with the file")
	}
}

// The regression tests for two silent-drop bugs the hand-rolled splitter had.
// Both exited 0 with the object simply gone. The old splitDocs tests were
// VACUOUS — swapping splitDocs for a naive bytes.Split(b, []byte("\n---\n"))
// left the whole suite green, because no fixture contained these shapes.

// TestInlineDocumentIsNotSilentlyDropped: `--- {inline}` put the content ON the
// separator line. The hand-rolled splitter `continue`d, discarding the line and
// everything on it — a Secret could vanish from the bundle with exit 0.
// apimachinery rejects this shape, which is the right answer: loud beats lost.
func TestInlineDocumentIsNotSilentlyDropped(t *testing.T) {
	dir := t.TempDir()
	src := write(t, dir, "inline.yaml", `apiVersion: v1
kind: ConfigMap
metadata:
  name: cm
  namespace: ns
--- {apiVersion: v1, kind: Secret, metadata: {name: sec, namespace: ns}}
`)
	objs, err := parseAll([]string{src})
	if err != nil {
		return // Rejected outright — acceptable, and not silent.
	}
	// If it parsed, the Secret must be there. What must never happen is a clean
	// exit with the object missing.
	var kinds []string
	for _, o := range objs {
		kinds = append(kinds, o.obj.Kind)
	}
	if !contains(kinds, "Secret") {
		t.Fatalf("the Secret was SILENTLY DROPPED: got %v. A manifest vanished with no error — "+
			"the exact failure this tool exists to prevent.", kinds)
	}
}

// TestSeparatorWithTrailingTab: `---\t`. The hand-rolled splitter trimmed only
// \r and \n, so the tab made the line != "---" and the separator went unseen —
// both documents fused into one and the second object vanished. kubectl applies
// both, so a bundle that disagrees with the applier is wrong by definition.
func TestSeparatorWithTrailingTab(t *testing.T) {
	dir := t.TempDir()
	src := write(t, dir, "tab.yaml", "apiVersion: v1\nkind: ConfigMap\nmetadata:\n  name: first\n  namespace: ns\n---\t\napiVersion: v1\nkind: ConfigMap\nmetadata:\n  name: second\n  namespace: ns\n")
	objs, err := parseAll([]string{src})
	if err != nil {
		t.Fatalf("parseAll: %v", err)
	}
	if len(objs) != 2 {
		var names []string
		for _, o := range objs {
			names = append(names, o.obj.Metadata.Name)
		}
		t.Fatalf("got %d objects %v, want 2 — a trailing tab on the separator hid a document", len(objs), names)
	}
}

// TestSeparatorInsideBlockScalar: the inverse risk — over-splitting. A `---`
// inside a block scalar is CONTENT, not a separator (YAML requires block content
// to be indented deeper, and a separator to be at column 0). Splitting here would
// corrupt the manifest.
func TestSeparatorInsideBlockScalar(t *testing.T) {
	dir := t.TempDir()
	src := write(t, dir, "block.yaml", `apiVersion: v1
kind: ConfigMap
metadata:
  name: cm
  namespace: ns
data:
  notes: |
    intro
    ---
    outro
`)
	objs, err := parseAll([]string{src})
	if err != nil {
		t.Fatalf("parseAll: %v", err)
	}
	if len(objs) != 1 {
		t.Fatalf("got %d objects, want 1 — a --- inside a block scalar is content, not a separator", len(objs))
	}
	if !bytes.Contains(objs[0].raw, []byte("outro")) {
		t.Error("the block scalar was truncated at the ---")
	}
}

func contains(hay []string, needle string) bool {
	for _, h := range hay {
		if h == needle {
			return true
		}
	}
	return false
}
