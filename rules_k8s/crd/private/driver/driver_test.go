package main

import (
	"bytes"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"golang.org/x/tools/go/packages"
)

// writePkgJSON writes one package's metadata in the format the aspect emits: a
// stream of JSON objects (NOT an array — WalkFlatPackagesFromJSON decodes with
// decoder.More(), so a top-level array would try to unmarshal into a single
// FlatPackage and fail).
func writePkgJSON(t *testing.T, dir, name string, pkgs ...map[string]any) string {
	t.Helper()
	path := filepath.Join(dir, name)
	var buf bytes.Buffer
	enc := json.NewEncoder(&buf)
	for _, p := range pkgs {
		if err := enc.Encode(p); err != nil {
			t.Fatalf("encoding %s: %v", name, err)
		}
	}
	if err := os.WriteFile(path, buf.Bytes(), 0o644); err != nil {
		t.Fatalf("writing %s: %v", name, err)
	}
	return path
}

func writeGoFile(t *testing.T, dir, name, content string) string {
	t.Helper()
	path := filepath.Join(dir, name)
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatalf("writing %s: %v", name, err)
	}
	return path
}

func writeParams(t *testing.T, dir string, lines []string) string {
	t.Helper()
	path := filepath.Join(dir, "pkg_json.params")
	if err := os.WriteFile(path, []byte(strings.Join(lines, "\n")+"\n"), 0o644); err != nil {
		t.Fatalf("writing params: %v", err)
	}
	return path
}

// runDriver invokes the driver end to end the way go/packages does: patterns on
// argv, a DriverRequest on stdin, a DriverResponse on stdout.
func runDriver(t *testing.T, paramsPath string, patterns []string) (*packages.DriverResponse, error) {
	t.Helper()
	t.Setenv(pkgJSONEnv, paramsPath)

	stdin, stdout := os.Stdin, os.Stdout
	t.Cleanup(func() { os.Stdin, os.Stdout = stdin, stdout })

	inR, inW, err := os.Pipe()
	if err != nil {
		t.Fatal(err)
	}
	req, _ := json.Marshal(packages.DriverRequest{})
	go func() { inW.Write(req); inW.Close() }()
	os.Stdin = inR

	outR, outW, err := os.Pipe()
	if err != nil {
		t.Fatal(err)
	}
	os.Stdout = outW

	runErr := run(patterns)
	outW.Close()

	var out bytes.Buffer
	out.ReadFrom(outR)
	if runErr != nil {
		return nil, runErr
	}

	resp := &packages.DriverResponse{}
	if err := json.Unmarshal(out.Bytes(), resp); err != nil {
		t.Fatalf("driver stdout was not a DriverResponse (%q): %v", out.String(), err)
	}
	return resp, nil
}

// TestDriverServesGraphFromPkgJSON is the core contract: given the files the
// aspect emits, the driver answers a pattern with the package and its imports —
// having consulted nothing else.
func TestDriverServesGraphFromPkgJSON(t *testing.T) {
	dir := t.TempDir()

	apiGo := writeGoFile(t, dir, "widget_types.go", `package v1

import "example.com/dep"

type Widget struct{ _ dep.T }
`)
	depGo := writeGoFile(t, dir, "dep.go", "package dep\n\ntype T struct{}\n")

	apiJSON := writePkgJSON(t, dir, "api.pkg.json", map[string]any{
		"ID":              "@@//api/v1:v1",
		"Name":            "v1",
		"PkgPath":         "example.com/api/v1",
		"GoFiles":         []string{apiGo},
		"CompiledGoFiles": []string{apiGo},
		"Imports":         map[string]string{"example.com/dep": "@@//dep:dep"},
	})
	depJSON := writePkgJSON(t, dir, "dep.pkg.json", map[string]any{
		"ID":              "@@//dep:dep",
		"Name":            "dep",
		"PkgPath":         "example.com/dep",
		"GoFiles":         []string{depGo},
		"CompiledGoFiles": []string{depGo},
	})

	params := writeParams(t, dir, []string{apiJSON, depJSON})
	resp, err := runDriver(t, params, []string{"@@//api/v1:v1"})
	if err != nil {
		t.Fatalf("driver failed: %v", err)
	}

	// The ID round-trips verbatim: it already starts with '@', so Match's
	// canonicalizing prefix (for Bazel >= 6) is a no-op. Real pkg.json IDs are
	// `str(archive.data.label)`, which under bzlmod is this canonical form.
	if got, want := resp.Roots, []string{"@@//api/v1:v1"}; len(got) != 1 || got[0] != want[0] {
		t.Errorf("Roots = %v, want %v", got, want)
	}
	// The dependency must come along, or controller-gen cannot resolve the field
	// type and would silently emit a schema missing that property.
	var names []string
	for _, p := range resp.Packages {
		names = append(names, p.Name)
	}
	if !contains(names, "v1") || !contains(names, "dep") {
		t.Errorf("Packages names = %v, want both v1 and dep", names)
	}
}

// TestPkgNameBackfilled is gotcha #1 and the highest-stakes behavior here.
//
// rules_go's pkg.json does NOT set Name (its _go_archive_to_pkg never populates
// it). controller-tools derives the CRD's VERSION from pkg.Name
// (crd/parser.go: `versionVal := pkg.Name`). So if the backfill regresses, we do
// not get an error — we get a CRD emitted under the wrong apiVersion.
func TestPkgNameBackfilled(t *testing.T) {
	dir := t.TempDir()
	src := writeGoFile(t, dir, "types.go", "package v1alpha1\n\ntype X struct{}\n")

	// Name deliberately absent, exactly as the aspect emits it.
	j := writePkgJSON(t, dir, "api.pkg.json", map[string]any{
		"ID":              "@@//api/v1alpha1:v1alpha1",
		"PkgPath":         "example.com/api/v1alpha1",
		"GoFiles":         []string{src},
		"CompiledGoFiles": []string{src},
	})

	resp, err := runDriver(t, writeParams(t, dir, []string{j}), []string{"@@//api/v1alpha1:v1alpha1"})
	if err != nil {
		t.Fatalf("driver failed: %v", err)
	}
	if len(resp.Packages) != 1 {
		t.Fatalf("got %d packages, want 1", len(resp.Packages))
	}
	if got := resp.Packages[0].Name; got != "v1alpha1" {
		t.Errorf("Name = %q, want %q (parsed from the package clause). "+
			"A regression here silently emits CRDs under the wrong version.", got, "v1alpha1")
	}
}

// TestNoPkgJSONEnvIsAnError: a driver that returns an empty graph instead of
// failing would make controller-gen emit zero CRDs and exit 0 — a green build
// that generated nothing.
func TestNoPkgJSONEnvIsAnError(t *testing.T) {
	t.Setenv(pkgJSONEnv, "")
	if _, err := runDriver(t, "", nil); err == nil {
		t.Fatal("want an error when the pkg.json env var is unset, got nil")
	}
}

// TestUnmatchedPatternIsAnError: same reasoning — asking for a package the
// aspect never collected must fail loudly, not yield an empty response.
func TestUnmatchedPatternIsAnError(t *testing.T) {
	dir := t.TempDir()
	src := writeGoFile(t, dir, "types.go", "package v1\n")
	j := writePkgJSON(t, dir, "api.pkg.json", map[string]any{
		"ID":              "@@//api/v1:v1",
		"PkgPath":         "example.com/api/v1",
		"GoFiles":         []string{src},
		"CompiledGoFiles": []string{src},
	})
	_, err := runDriver(t, writeParams(t, dir, []string{j}), []string{"@@//nope:nope"})
	if err == nil {
		t.Fatal("want an error for a pattern with no matching package, got nil")
	}
	if !strings.Contains(err.Error(), "no roots matched") {
		t.Errorf("error = %v, want it to name the unmatched pattern", err)
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

// TestExecrootResolver pins the placeholder mapping. All three collapse to the
// execroot because we run inside the action whose cwd that is — see paths.go.
// If rules_go ever changes the placeholders, this is where it surfaces.
func TestExecrootResolver(t *testing.T) {
	for _, tc := range []struct{ in, want string }{
		{"__BAZEL_EXECROOT__/bazel-out/darwin/bin/x.go", "bazel-out/darwin/bin/x.go"},
		{"__BAZEL_WORKSPACE__/examples/smoke/api/v1/widget_types.go", "examples/smoke/api/v1/widget_types.go"},
		{"__BAZEL_OUTPUT_BASE__/external/io_k8s_apimachinery/types.go", "external/io_k8s_apimachinery/types.go"},
		{"already/relative.go", "already/relative.go"},
	} {
		if got := execrootResolver(tc.in); got != tc.want {
			t.Errorf("execrootResolver(%q) = %q, want %q", tc.in, got, tc.want)
		}
	}
}

// TestRootWithUnreadableSourceIsAnError is the guard for a vacuous success.
//
// filterSourceFilesForTags discards MatchFile's error, so a file that does not
// exist is treated exactly like one excluded by a build tag: it disappears from
// CompiledGoFiles, and pkg.Name (backfilled by parsing it) disappears with it.
// The driver used to exit 0 with an empty graph, and controller-tools would emit
// nothing — or worse, a CRD under the wrong version, since it derives the version
// from pkg.Name.
//
// len(Roots) == 0 does not catch this: Match() resolves by ID and never touches
// disk, so the root matches fine.
func TestRootWithUnreadableSourceIsAnError(t *testing.T) {
	dir := t.TempDir()
	// A pkg.json naming a file that is not there — exactly what a missing action
	// input looks like to the driver.
	j := writePkgJSON(t, dir, "api.pkg.json", map[string]any{
		"ID":              "@@//api/v1:v1",
		"PkgPath":         "example.com/api/v1",
		"GoFiles":         []string{filepath.Join(dir, "gone.go")},
		"CompiledGoFiles": []string{filepath.Join(dir, "gone.go")},
	})
	_, err := runDriver(t, writeParams(t, dir, []string{j}), []string{"@@//api/v1:v1"})
	if err == nil {
		t.Fatal("want an error when a root's source cannot be read; got a clean exit — " +
			"controller-tools would emit nothing, or a CRD under the wrong version, and the " +
			"build would be green")
	}
	if !strings.Contains(err.Error(), "no source files") && !strings.Contains(err.Error(), "no package name") {
		t.Errorf("error = %v, want it to name the unreadable root", err)
	}
}
