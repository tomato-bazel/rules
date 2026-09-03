// Command crd2jsonschema extracts kubeconform-compatible JSON Schemas from CRDs.
//
// kubeconform validates a manifest against a JSON Schema, but a CRD carries its
// schema as `spec.versions[].schema.openAPIV3Schema` inside a Kubernetes object.
// This lifts each version's schema out into the layout kubeconform's
// `-schema-location` expects:
//
//	<out>/<group>/<kind>_<version>.json      (lowercased)
//
// which matches the template
//
//	<out>/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json
//
// WHAT THIS DOES NOT DO
//
// The extracted schema is structural only. `x-kubernetes-validations` (CEL rules
// like `self == oldSelf`) cannot be evaluated by kubeconform — or by anything at
// build time, since they may reference the PRIOR state of an object that does not
// exist yet. Those rules are dropped here rather than silently half-honored, and
// k8s_validate's docs say so. A green validate means "structurally valid", not
// "the API server will accept this".
package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"sigs.k8s.io/yaml"

	"github.com/tomato-bazel/rules_k8s/internal/params"
)

type crd struct {
	APIVersion string `json:"apiVersion"`
	Kind       string `json:"kind"`
	Spec       struct {
		Group string `json:"group"`
		Names struct {
			Kind string `json:"kind"`
		} `json:"names"`
		Versions []struct {
			Name   string `json:"name"`
			Schema struct {
				OpenAPIV3Schema map[string]any `json:"openAPIV3Schema"`
			} `json:"schema"`
		} `json:"versions"`
	} `json:"spec"`
}

func main() {
	if err := run(); err != nil {
		fmt.Fprintf(os.Stderr, "crd2jsonschema: %v\n", err)
		os.Exit(1)
	}
}

func run() error {
	out := flag.String("out", "", "Directory to write the schema tree into.")
	strict := flag.Bool("strict", false, "Seal object schemas with additionalProperties:false, so an undeclared field is a validation error.")
	flag.Parse()
	if *out == "" {
		return fmt.Errorf("-out is required")
	}
	inputs, err := params.Expand(flag.Args())
	if err != nil {
		return err
	}
	if err := os.MkdirAll(*out, 0o755); err != nil {
		return err
	}

	n := 0
	for _, dir := range inputs {
		files, err := yamlsUnder(dir)
		if err != nil {
			return err
		}
		for _, f := range files {
			written, err := convert(f, *out, *strict)
			if err != nil {
				return fmt.Errorf("%s: %w", f, err)
			}
			n += written
		}
	}
	if n == 0 {
		// Zero schemas would make every k8s_validate pass vacuously — the worst
		// outcome for a validator.
		return fmt.Errorf("no CRD schemas extracted from %v", inputs)
	}
	return nil
}

// yamlsUnder accepts either a file or a directory, because k8s_crd_library emits
// a TreeArtifact while a hand-written CRD is a plain file.
func yamlsUnder(root string) ([]string, error) {
	info, err := os.Stat(root)
	if err != nil {
		return nil, err
	}
	if !info.IsDir() {
		return []string{root}, nil
	}
	var out []string
	err = filepath.WalkDir(root, func(p string, d os.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if !d.IsDir() && (strings.HasSuffix(p, ".yaml") || strings.HasSuffix(p, ".yml")) {
			out = append(out, p)
		}
		return nil
	})
	return out, err
}

func convert(path, outDir string, strict bool) (int, error) {
	b, err := os.ReadFile(path)
	if err != nil {
		return 0, err
	}
	var c crd
	if err := yaml.Unmarshal(b, &c); err != nil {
		return 0, err
	}
	if c.Kind != "CustomResourceDefinition" {
		// Not every YAML handed to us is a CRD; skipping is correct.
		return 0, nil
	}

	n := 0
	for _, v := range c.Spec.Versions {
		if v.Schema.OpenAPIV3Schema == nil {
			continue
		}
		schema := map[string]any{}
		for k, val := range v.Schema.OpenAPIV3Schema {
			schema[k] = val
		}
		schema["$schema"] = "http://json-schema.org/draft-07/schema#"
		if strict {
			sealObjects(schema)
		}

		dir := filepath.Join(outDir, strings.ToLower(c.Spec.Group))
		if err := os.MkdirAll(dir, 0o755); err != nil {
			return n, err
		}
		// kubeconform looks up <kind>_<version>.json, both lowercased.
		name := fmt.Sprintf("%s_%s.json", strings.ToLower(c.Spec.Names.Kind), strings.ToLower(v.Name))
		enc, err := json.MarshalIndent(schema, "", "  ")
		if err != nil {
			return n, err
		}
		if err := os.WriteFile(filepath.Join(dir, name), append(enc, '\n'), 0o644); err != nil {
			return n, err
		}
		n++
	}
	return n, nil
}


// sealObjects walks a structural schema and sets `additionalProperties: false` on
// every object node — EXCEPT any subtree marked x-kubernetes-preserve-unknown-fields.
//
// Why this is needed at all: kubeconform's `-strict` does not itself forbid
// unknown fields. Upstream, strictness is baked into a separate *set* of schema
// files (hence the `{{.StrictSuffix}}` template variable). A CRD-derived schema
// has no such variant, so without this, `k8s_validate(strict = True)` is a silent
// no-op — it would accept `targetRevisionn: main` without complaint.
//
// Why it is worth doing: this is the same failure as the CRD drift that motivated
// this whole module. The API server PRUNES fields a structural schema doesn't
// declare, so a typo'd field isn't rejected — it's silently dropped, and the
// object is admitted having quietly lost its meaning. Turning that into a build
// error is the entire point of validating in CI.
//
// The exception matters as much as the rule: a subtree marked
// x-kubernetes-preserve-unknown-fields (controller-gen emits it for a
// runtime.RawExtension) is SUPPOSED to accept arbitrary keys. Sealing it would
// reject valid manifests, which is how a validator loses its users.
func sealObjects(node any) {
	switch n := node.(type) {
	case map[string]any:
		// Two kinds of subtree are deliberately open, and sealing either REJECTS
		// VALID MANIFESTS — the way a validator loses its users and gets switched
		// off:
		//
		//  - x-kubernetes-preserve-unknown-fields: controller-gen emits it for a
		//    runtime.RawExtension, which is meant to accept arbitrary keys;
		//  - x-kubernetes-embedded-resource: an embedded object carries its own
		//    apiVersion/kind/metadata, which the API server never prunes and the
		//    schema does not declare.
		for _, open := range []string{
			"x-kubernetes-preserve-unknown-fields",
			"x-kubernetes-embedded-resource",
		} {
			if v, ok := n[open].(bool); ok && v {
				return
			}
		}

		props, hasProps := n["properties"].(map[string]any)
		if hasProps {
			if _, already := n["additionalProperties"]; !already {
				n["additionalProperties"] = false
			}
			for _, v := range props {
				sealObjects(v)
			}
		}
		if items, ok := n["items"]; ok {
			sealObjects(items)
		}
		// additionalProperties can itself be a schema (a map-typed field).
		if ap, ok := n["additionalProperties"].(map[string]any); ok {
			sealObjects(ap)
		}

		// NOT recursing into allOf/anyOf/oneOf. Sealing a composition BRANCH makes
		// that branch reject the sibling branches' fields, so an object valid
		// against the whole schema fails against every branch:
		//
		//     allOf: [ {properties: {a}}, {properties: {b}} ]
		//     {a: "x", b: "y"}  -> valid unsealed, INVALID if each branch is sealed
		//
		// and Kubernetes structural-schema rules positively require that shape.
		// Nor into `not`: sealing inside a negation INVERTS its meaning.
		//
		// The cost is that fields reachable only through a composition branch stay
		// unsealed — strictness is best-effort, and under-sealing merely fails to
		// catch a typo, while over-sealing rejects manifests that are correct.
	case []any:
		for _, v := range n {
			sealObjects(v)
		}
	}
}
