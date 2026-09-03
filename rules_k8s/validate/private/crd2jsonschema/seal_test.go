package main

import (
	"encoding/json"
	"testing"
)

func parse(t *testing.T, s string) map[string]any {
	t.Helper()
	var m map[string]any
	if err := json.Unmarshal([]byte(s), &m); err != nil {
		t.Fatal(err)
	}
	return m
}

// TestSealObjectsClosesNestedObjects: the point of strict mode. An undeclared
// field is not rejected by the API server, it is PRUNED — silently dropped, with
// the object admitted having lost its meaning. Sealing turns that into a build
// error, and it has to reach nested objects, not just the root.
func TestSealObjectsClosesNestedObjects(t *testing.T) {
	schema := parse(t, `{
	  "type": "object",
	  "properties": {
	    "spec": {
	      "type": "object",
	      "properties": {
	        "source": {
	          "type": "object",
	          "properties": {"targetRevision": {"type": "string"}}
	        }
	      }
	    }
	  }
	}`)
	sealObjects(schema)

	if schema["additionalProperties"] != false {
		t.Error("root was not sealed")
	}
	spec := schema["properties"].(map[string]any)["spec"].(map[string]any)
	if spec["additionalProperties"] != false {
		t.Error("spec was not sealed")
	}
	source := spec["properties"].(map[string]any)["source"].(map[string]any)
	if source["additionalProperties"] != false {
		t.Error("spec.source was not sealed — a typo'd targetRevisionn would slip through")
	}
}

// TestSealObjectsRespectsPreserveUnknownFields is the half that keeps the rule
// usable. controller-gen emits x-kubernetes-preserve-unknown-fields for a
// runtime.RawExtension, and that subtree is SUPPOSED to accept arbitrary keys.
// Sealing it would reject valid manifests — which is how a validator loses its
// users, and how it starts getting switched off.
func TestSealObjectsRespectsPreserveUnknownFields(t *testing.T) {
	schema := parse(t, `{
	  "type": "object",
	  "properties": {
	    "settings": {
	      "type": "object",
	      "x-kubernetes-preserve-unknown-fields": true,
	      "properties": {"known": {"type": "string"}}
	    },
	    "strictPart": {
	      "type": "object",
	      "properties": {"known": {"type": "string"}}
	    }
	  }
	}`)
	sealObjects(schema)

	props := schema["properties"].(map[string]any)
	settings := props["settings"].(map[string]any)
	if _, sealed := settings["additionalProperties"]; sealed {
		t.Error("a preserve-unknown-fields subtree must stay open; sealing it rejects valid manifests")
	}
	strictPart := props["strictPart"].(map[string]any)
	if strictPart["additionalProperties"] != false {
		t.Error("a normal sibling of a preserve-unknown-fields node must still be sealed")
	}
}

// TestSealObjectsReachesArrayItems: an array of objects is the common shape for
// a list of sub-resources; a typo inside one must not slip through.
func TestSealObjectsReachesArrayItems(t *testing.T) {
	schema := parse(t, `{
	  "type": "object",
	  "properties": {
	    "sources": {
	      "type": "array",
	      "items": {
	        "type": "object",
	        "properties": {"repoURL": {"type": "string"}}
	      }
	    }
	  }
	}`)
	sealObjects(schema)

	items := schema["properties"].(map[string]any)["sources"].(map[string]any)["items"].(map[string]any)
	if items["additionalProperties"] != false {
		t.Error("array items were not sealed")
	}
}

// TestSealObjectsLeavesExistingAdditionalPropertiesAlone: a field declaring
// additionalProperties as a SCHEMA (a map with constrained values) must keep it.
// Overwriting it with `false` would reject every valid map.
//
// NOTE the shape: the node has BOTH `properties` and `additionalProperties`. An
// earlier version of this test omitted `properties`, which made it vacuous —
// `hasProps` is false, so sealObjects returns before reaching the `already`
// guard, and the assertion could never fire. It is the guard that needs
// exercising, so the node must reach it.
func TestSealObjectsLeavesExistingAdditionalPropertiesAlone(t *testing.T) {
	schema := parse(t, `{
	  "type": "object",
	  "properties": {
	    "config": {
	      "type": "object",
	      "properties": {"known": {"type": "string"}},
	      "additionalProperties": {"type": "string"}
	    }
	  }
	}`)
	sealObjects(schema)

	config := schema["properties"].(map[string]any)["config"].(map[string]any)
	if config["additionalProperties"] == false {
		t.Fatal("an existing additionalProperties SCHEMA was clobbered with false — " +
			"every valid map value would now be rejected")
	}
	if _, ok := config["additionalProperties"].(map[string]any); !ok {
		t.Errorf("additionalProperties should still be the original schema, got %T", config["additionalProperties"])
	}
}

// TestSealObjectsIsVacuousWithoutProperties pins the reason the test above is
// shaped the way it is: a node with no `properties` is not sealed at all. That is
// correct (there is nothing to constrain), but it means such a node cannot be
// used to test the `already`-guard — which is how the earlier version of that
// test managed to assert nothing.
func TestSealObjectsSkipsNodesWithoutProperties(t *testing.T) {
	schema := parse(t, `{"type": "object", "additionalProperties": {"type": "string"}}`)
	sealObjects(schema)
	if schema["additionalProperties"] == false {
		t.Error("a node with no properties must not be sealed")
	}
}

// TestSealObjectsDoesNotBreakComposition: sealing an allOf/anyOf BRANCH makes it
// reject the sibling branches' fields, so an object valid against the whole
// schema becomes invalid against every branch. Kubernetes structural schemas
// require this shape, so this is not hypothetical.
func TestSealObjectsDoesNotBreakComposition(t *testing.T) {
	for _, key := range []string{"allOf", "anyOf", "oneOf"} {
		schema := parse(t, `{
		  "type": "object",
		  "`+key+`": [
		    {"properties": {"a": {"type": "string"}}},
		    {"properties": {"b": {"type": "string"}}}
		  ]
		}`)
		sealObjects(schema)
		for i, branch := range schema[key].([]any) {
			b := branch.(map[string]any)
			if _, sealed := b["additionalProperties"]; sealed {
				t.Errorf("%s branch %d was sealed — it now rejects the sibling branch's "+
					"fields, so a valid object fails validation", key, i)
			}
		}
	}
}

// TestSealObjectsRespectsEmbeddedResource: an embedded resource carries its own
// apiVersion/kind/metadata that the schema does not declare and the API server
// never prunes. Sealing it rejects valid manifests.
func TestSealObjectsRespectsEmbeddedResource(t *testing.T) {
	schema := parse(t, `{
	  "type": "object",
	  "properties": {
	    "template": {
	      "type": "object",
	      "x-kubernetes-embedded-resource": true,
	      "properties": {"spec": {"type": "object", "properties": {"x": {"type": "string"}}}}
	    }
	  }
	}`)
	sealObjects(schema)

	tmpl := schema["properties"].(map[string]any)["template"].(map[string]any)
	if _, sealed := tmpl["additionalProperties"]; sealed {
		t.Error("an embedded-resource subtree was sealed — its apiVersion/kind/metadata " +
			"would now be rejected, though the API server accepts them")
	}
}
