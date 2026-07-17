// Command k8s-bundle collects Kubernetes manifests into a conflict-checked
// directory, and verifies individual manifests.
//
// Identity (group/version/kind, name, namespace) is resolved HERE rather than in
// Starlark because Starlark cannot read files: a rule that merely adopts a
// checked-in YAML has no way to know its Kind at analysis time. So the providers
// carry files, and this tool is where duplicate detection and the listing happen.
// rules_cloudformation's stack aggregator makes the same trade for the same
// reason.
//
// Two modes:
//
//	bundle: -out DIR -listing FILE @params   collect, conflict-check, emit
//	verify: -verify -marker FILE [-expect-kind K] [-expect-api-version V] FILE...
package main

import (
	"bufio"
	"bytes"
	"flag"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"sort"
	"strings"

	utilyaml "k8s.io/apimachinery/pkg/util/yaml"
	"sigs.k8s.io/yaml"

	"github.com/tomato-bazel/rules_k8s/internal/params"
)

// object is the identifying head of a manifest. Everything else is passed
// through verbatim — this tool must never rewrite a manifest's content, only
// place it.
type object struct {
	APIVersion string `json:"apiVersion"`
	Kind       string `json:"kind"`
	Metadata   struct {
		Name      string `json:"name"`
		Namespace string `json:"namespace"`
	} `json:"metadata"`
}

// parsed pairs an object's identity with the exact bytes it came from.
type parsed struct {
	obj      object
	raw      []byte
	src      string
	docIndex int
}

// group returns the API group, i.e. apiVersion minus the version. Core objects
// ("v1") are in the empty group, which is what Kubernetes itself calls it.
func (o object) group() string {
	if i := strings.Index(o.APIVersion, "/"); i >= 0 {
		return o.APIVersion[:i]
	}
	return ""
}

// key is the identity Kubernetes itself enforces uniqueness on. Note it excludes
// the VERSION: two manifests declaring the same Kind at v1 and v1beta1 with the
// same name are the same object, and applying both is a conflict, not a pair.
func (o object) key() string {
	return fmt.Sprintf("%s/%s/%s/%s", o.group(), o.Kind, o.Metadata.Namespace, o.Metadata.Name)
}

// filename is the object's stable on-disk name in the bundle. Derived from
// identity rather than from the source filename so the bundle's layout is a
// function of its contents — two inputs that collide in identity also collide
// here, and sorting is meaningful.
func (o object) filename() string {
	parts := []string{}
	if g := o.group(); g != "" {
		parts = append(parts, g)
	}
	parts = append(parts, strings.ToLower(o.Kind))
	if o.Metadata.Namespace != "" {
		parts = append(parts, o.Metadata.Namespace)
	}
	parts = append(parts, o.Metadata.Name)
	return strings.Join(parts, "_") + ".yaml"
}

func main() {
	if err := run(); err != nil {
		fmt.Fprintf(os.Stderr, "k8s-bundle: %v\n", err)
		os.Exit(1)
	}
}

func run() error {
	var (
		outDir     = flag.String("out", "", "Directory to collect manifests into (a declared Bazel output).")
		listing    = flag.String("listing", "", "Write a sorted `<group>/<Kind>/<ns>/<name>` index here, for golden tests.")
		verify     = flag.Bool("verify", false, "Verify mode: assert each input's identity instead of collecting.")
		marker     = flag.String("marker", "", "Verify mode: the (empty) success marker to write.")
		expectKind = flag.String("expect-kind", "", "Verify mode: every object must be this Kind.")
		expectAPI  = flag.String("expect-api-version", "", "Verify mode: every object must be this apiVersion.")
	)
	flag.Parse()

	args, err := params.Expand(flag.Args())
	if err != nil {
		return err
	}
	if len(args) == 0 {
		// An empty bundle is almost always a glob that matched nothing. Emitting
		// an empty directory would let a validate target pass vacuously.
		return fmt.Errorf("no manifests given")
	}

	objs, err := parseAll(args)
	if err != nil {
		return err
	}
	if len(objs) == 0 {
		return fmt.Errorf("no Kubernetes objects found in %d file(s): every document was empty "+
			"or lacked apiVersion/kind", len(args))
	}

	if *verify {
		if err := verifyAll(objs, *expectKind, *expectAPI); err != nil {
			return err
		}
		// The marker pattern (rules_helm's helm_lint does the same): an empty
		// declared output is what makes a pure check cacheable.
		return os.WriteFile(*marker, nil, 0o644)
	}

	if *outDir == "" {
		return fmt.Errorf("-out is required")
	}
	if err := collect(objs, *outDir); err != nil {
		return err
	}
	if *listing != "" {
		return writeListing(*listing, objs)
	}
	return nil
}

// parseAll reads every document of every input. A manifest may hold many
// documents; each is an object in its own right.
func parseAll(paths []string) ([]parsed, error) {
	var out []parsed
	for _, p := range paths {
		b, err := os.ReadFile(p)
		if err != nil {
			return nil, err
		}
		docs, err := splitDocs(b)
		if err != nil {
			return nil, fmt.Errorf("%s: %w", p, err)
		}
		for i, doc := range docs {
			if len(bytes.TrimSpace(doc)) == 0 {
				continue
			}
			var o object
			if err := yaml.Unmarshal(doc, &o); err != nil {
				return nil, fmt.Errorf("%s (document %d): %w", p, i, err)
			}
			// A document with no apiVersion/kind isn't an object — most often a
			// stray comment block. Skipping is right; failing would reject valid
			// files.
			if o.APIVersion == "" || o.Kind == "" {
				continue
			}
			if o.Metadata.Name == "" {
				return nil, fmt.Errorf("%s (document %d): %s has no metadata.name", p, i, o.Kind)
			}
			out = append(out, parsed{obj: o, raw: doc, src: p, docIndex: i})
		}
	}
	return out, nil
}

// splitDocs splits a YAML stream into documents using apimachinery's own
// YAMLReader — the splitter kubectl applies with.
//
// This was hand-rolled once, and the hand-rolled version silently DROPPED
// manifests in two cases: `--- {apiVersion: v1, kind: Secret, ...}` (an inline
// document on the separator line) and `---\t` (a trailing tab, since it trimmed
// only \r and \n). Both exited 0 with the object simply missing from the bundle —
// the exact silent loss this tool exists to prevent, and invisible to the golden
// listing test because the listing derives from the same dropped parse.
//
// A bundle that disagrees with the applier's splitter is wrong by definition, so
// use the applier's splitter. It returns raw buffer bytes, which preserves the
// "place, never rewrite" rule (round-tripping through a marshaller would reorder
// keys and drop comments), and it ERRORS on an inline document rather than
// discarding it.
func splitDocs(b []byte) ([][]byte, error) {
	var docs [][]byte
	r := utilyaml.NewYAMLReader(bufio.NewReader(bytes.NewReader(b)))
	for {
		doc, err := r.Read()
		if err == io.EOF {
			return docs, nil
		}
		if err != nil {
			return nil, err
		}
		docs = append(docs, doc)
	}
}

func verifyAll(objs []parsed, expectKind, expectAPI string) error {
	var problems []string
	for _, p := range objs {
		if expectKind != "" && p.obj.Kind != expectKind {
			problems = append(problems, fmt.Sprintf("%s: kind is %q, want %q", p.src, p.obj.Kind, expectKind))
		}
		if expectAPI != "" && p.obj.APIVersion != expectAPI {
			problems = append(problems, fmt.Sprintf("%s: apiVersion is %q, want %q", p.src, p.obj.APIVersion, expectAPI))
		}
	}
	if len(problems) > 0 {
		return fmt.Errorf("manifest does not match its declaration:\n  %s", strings.Join(problems, "\n  "))
	}
	return nil
}

// collect writes each object to the bundle, failing on any identity collision.
//
// The conflict check is the point of the rule. Two manifests with the same
// group/Kind/namespace/name are not two objects — applying the bundle would
// apply one and silently discard the other, and which one wins depends on
// ordering. Better to refuse.
func collect(objs []parsed, outDir string) error {
	if err := os.MkdirAll(outDir, 0o755); err != nil {
		return err
	}
	seen := map[string]parsed{}
	for _, p := range objs {
		k := p.obj.key()
		if prev, dup := seen[k]; dup {
			return fmt.Errorf("duplicate object %s\n  first:  %s (document %d)\n  second: %s (document %d)\n"+
				"Two manifests declare the same group/Kind/namespace/name. Applying both would keep "+
				"whichever came last.", k, prev.src, prev.docIndex, p.src, p.docIndex)
		}
		seen[k] = p
		dst := filepath.Join(outDir, p.obj.filename())
		// Preserve the source bytes exactly, with a leading separator so each
		// file is a well-formed single-document manifest.
		body := append([]byte("---\n"), bytes.TrimLeft(p.raw, "\n")...)
		if err := os.WriteFile(dst, body, 0o644); err != nil {
			return err
		}
	}
	return nil
}

// writeListing emits a stable index of the bundle's contents, for golden tests.
// It is the legible version of "what is in here": a diff over this file names the
// object that appeared or vanished, where a diff over the directory would bury it
// in schema noise.
func writeListing(path string, objs []parsed) error {
	lines := make([]string, 0, len(objs))
	for _, p := range objs {
		lines = append(lines, p.obj.key())
	}
	sort.Strings(lines)
	return os.WriteFile(path, []byte(strings.Join(lines, "\n")+"\n"), 0o644)
}
