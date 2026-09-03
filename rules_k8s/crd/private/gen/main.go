// Command k8s-crd-gen runs controller-tools' CRD generator as a library, into a
// directory the caller names.
//
// It exists instead of shelling out to the controller-gen CLI because the CLI
// insists on writing in place relative to `paths=./api/...`, which is the
// opposite of a Bazel action's declared-outputs contract. genall.Runtime is
// public and OutputToDirectory redirects anywhere, so we drive it directly.
//
// Package loading goes through go/packages, which we point at the sibling
// k8s-crd-driver via GOPACKAGESDRIVER (set by the rule). Nothing here touches
// the go command, the module cache, or the network.
//
// Usage:
//
//	k8s-crd-gen -out DIR [-expect-group G] [-listing FILE] PATTERN...
package main

import (
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"sigs.k8s.io/controller-tools/pkg/crd"
	"sigs.k8s.io/controller-tools/pkg/genall"
	"sigs.k8s.io/yaml"
)

func main() {
	if err := run(); err != nil {
		fmt.Fprintf(os.Stderr, "k8s-crd-gen: %v\n", err)
		os.Exit(1)
	}
}

func run() error {
	var (
		outDir      = flag.String("out", "", "Directory to write CRD YAML into (a declared Bazel output).")
		expectGroup = flag.String("expect-group", "", "Fail unless every generated CRD is in this API group.")
		listing     = flag.String("listing", "", "Write a sorted `<group>/<kind>` index here, for golden tests.")
	)
	flag.Parse()

	if *outDir == "" {
		return fmt.Errorf("-out is required")
	}
	roots := flag.Args()
	if len(roots) == 0 {
		return fmt.Errorf("no package patterns given")
	}
	if err := os.MkdirAll(*outDir, 0o755); err != nil {
		return err
	}

	gens := genall.Generators{generator()}
	rt, err := gens.ForRoots(roots...)
	if err != nil {
		// The overwhelmingly likely cause is a driver that couldn't serve the
		// pattern. Say so, because "go command required, not found" from here
		// means GOPACKAGESDRIVER didn't take effect at all.
		return fmt.Errorf("loading roots %v: %w", roots, err)
	}
	rt.OutputRules = genall.OutputRules{Default: genall.OutputToDirectory(*outDir)}

	if hadErrs := rt.Run(); hadErrs {
		// genall has already printed the per-package diagnostics.
		return fmt.Errorf("controller-tools reported errors generating CRDs from %v", roots)
	}

	written, err := readGeneratedCRDs(*outDir)
	if err != nil {
		return err
	}
	if len(written) == 0 {
		// A silent no-op is the worst outcome: a green build that generated
		// nothing, and (paired with write_source_files) a chart whose crds/ gets
		// emptied. Fail instead.
		return fmt.Errorf("no CRDs were generated from %v — the packages have no "+
			"+kubebuilder:object:root types, or the markers were not parsed", roots)
	}
	if err := checkGroup(written, *expectGroup); err != nil {
		return err
	}
	if *listing != "" {
		return writeListing(*listing, written)
	}
	return nil
}

// generator returns the CRD generator. controller-tools takes a *Generator
// interface value, so the concrete type has to be boxed before its address is
// taken.
func generator() *genall.Generator {
	var g genall.Generator = crd.Generator{}
	return &g
}

type generatedCRD struct {
	File  string
	Group string
	Kind  string
}

func readGeneratedCRDs(dir string) ([]generatedCRD, error) {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return nil, err
	}
	var out []generatedCRD
	for _, e := range entries {
		if e.IsDir() || !strings.HasSuffix(e.Name(), ".yaml") {
			continue
		}
		path := filepath.Join(dir, e.Name())
		b, err := os.ReadFile(path)
		if err != nil {
			return nil, err
		}
		// Only the identifying head matters; parsing the full schema here would
		// duplicate work controller-tools already did.
		var doc struct {
			Spec struct {
				Group string `json:"group"`
				Names struct {
					Kind string `json:"kind"`
				} `json:"names"`
			} `json:"spec"`
		}
		if err := yaml.Unmarshal(b, &doc); err != nil {
			return nil, fmt.Errorf("parsing generated %s: %w", e.Name(), err)
		}
		out = append(out, generatedCRD{File: e.Name(), Group: doc.Spec.Group, Kind: doc.Spec.Names.Kind})
	}
	sort.Slice(out, func(i, j int) bool { return out[i].File < out[j].File })
	return out, nil
}

// checkGroup makes k8s_crd_library's `group` attr load-bearing rather than
// decorative. The group string is currently retyped in many places per operator;
// declaring it once and having the build reject a mismatch is the point.
func checkGroup(crds []generatedCRD, want string) error {
	if want == "" {
		return nil
	}
	var bad []string
	for _, c := range crds {
		if c.Group != want {
			bad = append(bad, fmt.Sprintf("%s (%s) is in group %q", c.Kind, c.File, c.Group))
		}
	}
	if len(bad) > 0 {
		return fmt.Errorf("group = %q, but:\n  %s\nEither the +groupName marker moved or the "+
			"rule's `group` attr is stale", want, strings.Join(bad, "\n  "))
	}
	return nil
}

// writeListing emits a stable index of what was generated. Its whole purpose is
// to be golden-tested: a diff_test over this file turns "a Kind silently
// disappeared from the CRD set" into a build failure, which the CRD YAML's own
// bytes would also catch but far less legibly.
func writeListing(path string, crds []generatedCRD) error {
	lines := make([]string, 0, len(crds))
	for _, c := range crds {
		lines = append(lines, fmt.Sprintf("%s/%s\t%s", c.Group, c.Kind, c.File))
	}
	sort.Strings(lines)
	return os.WriteFile(path, []byte(strings.Join(lines, "\n")+"\n"), 0o644)
}
