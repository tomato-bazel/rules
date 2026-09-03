# Graph migrations (major-version codemods)

When an `aide:` ontology change is **breaking** (a property renamed or
removed — a major version bump), the framework ships a migration here that
mechanically rewrites a consumer's `.agents/graph/*.ttl` from the old shape
to the new. The consumer applies it once when adopting the new major, then
reviews the resulting `.ttl` + `generated.lock` diff like any change.

## Discipline

- **Additive changes need no migration** (new property/host = minor bump);
  the old graph still validates and projects.
- **Deprecate before removing**: mark the outgoing term `owl:deprecated true`
  for a full major; `validate` warns (severity `sh:Warning`) but still
  passes, so a minor bump never breaks a consumer.
- **Remove only on a major**, paired with a migration here.

## Naming

`<from>-to-<to>.rq` — a SPARQL `UPDATE` (e.g. `0.x-to-1.0.rq`). One file per
breaking transition; the consumer applies the chain from their pinned
version to the target.

## Applying a migration

```sh
# Apply the codemod to the authored graph (Jena ARQ `update`).
bazel run @rules_jena//jena/update:jena_update -- \
    --update=migrations/0.x-to-1.0.rq \
    --data=.agents/graph/skills.ttl --out=.agents/graph/skills.ttl
# then: bazel test //.agents:validate && regenerate && review the diffs
```

See [`template.rq`](template.rq) for the codemod shape.
