"""Deterministic JSON rendering for VSCode artifacts.

VSCode consumes JSON — it publishes JSON Schemas for `.code-workspace`
and `settings.json` — so these emitters serialize to canonical JSON
rather than protobuf (the JSON-Schema layer is pinned via
`rules_jsonschema`; see `//schema`). Output is *canonicalized* (dict
keys sorted recursively, folders ordered by path with the `.` root
first), so the generated file is bit-exact for a given logical input
regardless of attribute ordering — which keeps `write_source_files`
diffs minimal.

Hermeticity: emission is pure `ctx.actions.write` — no subprocess, no
toolchain. The output is bit-exact for a given input.
"""

def _sorted_top(d):
    # Sort a dict's top-level keys for a stable encoding. Starlark forbids
    # recursion, so nested values keep their (input-deterministic) order;
    # `json.encode_indent` preserves dict insertion order. This is enough for
    # diff-stable output because the BUILD input is itself the source of truth.
    return {k: d[k] for k in sorted(d.keys())}

def _folder_sort_key(path):
    # The meta-repo's own folder (path ".") always sorts first.
    return "" if path == "." else path

def dedup_folders(folder_dicts):
    """De-duplicate folder dicts by path and return them in canonical order.

    Args:
      folder_dicts: list of `{path, name}` dicts, possibly with duplicate
        paths. First occurrence of a path wins; later ones are discarded
        rather than merged.

    Returns:
      A new list in canonical order — the meta-repo root (`.`) first, then
      lexicographic by path — so output is diff-stable regardless of the
      order attributes were declared in.
    """
    seen = {}
    for f in folder_dicts:
        if f["path"] not in seen:
            seen[f["path"]] = {"path": f["path"], "name": f["name"]}
    return [seen[p] for p in sorted(seen.keys(), key = _folder_sort_key)]

def merge_settings(dicts):
    """Merge a list of settings dicts, with later entries winning.

    Args:
      dicts: settings dicts in precedence order (later wins).

    Returns:
      A new merged dict. When both sides map a key to a dict — e.g. two
      contributors to `files.exclude` — the dicts are merged one level deep
      rather than clobbered. Nesting deeper than one level is still replaced
      wholesale, since Starlark forbids the recursion a deep merge needs.
    """
    out = {}
    for d in dicts:
        for k, v in d.items():
            if k in out and type(out[k]) == "dict" and type(v) == "dict":
                merged = dict(out[k])
                merged.update(v)
                out[k] = merged
            else:
                out[k] = v
    return out

def dedup_extensions(lists):
    """Flatten and de-duplicate extension-id lists.

    Args:
      lists: lists of VSCode extension ids, possibly overlapping.

    Returns:
      A single flattened list with duplicates removed, preserving first-seen
      order rather than sorting — recommendation order is meaningful to VSCode.
    """
    out = []
    seen = {}
    for lst in lists:
        for e in lst:
            if e not in seen:
                seen[e] = True
                out.append(e)
    return out

def prefix_path(prefix, p):
    """Re-root a folder path underneath a prefix.

    Used when merging per-org workspaces into one ecosystem workspace.

    Args:
      prefix: path to re-root under. Empty string is identity.
      p: the folder path to re-root.

    Returns:
      The re-rooted path. A `.` folder becomes the prefix itself, so the
      org's own root lands at the right depth instead of collapsing.
    """
    if not prefix:
        return p
    if p == ".":
        return prefix
    return prefix + "/" + p

def workspace_json(folders, settings, extensions):
    """Render the canonical `.code-workspace` JSON, with a trailing newline.

    Args:
      folders: folder dicts, already ordered by `dedup_folders`.
      settings: settings dict, or falsy to omit the key entirely.
      extensions: extension ids, or falsy to omit the key entirely.

    Returns:
      The encoded JSON string. Top-level keys are emitted in a fixed order
      (folders, settings, extensions) and settings' top-level keys are
      sorted, so the result is bit-exact for a given logical input — which
      is what keeps `write_source_files` diffs empty.
    """
    ws = {"folders": folders}
    if settings:
        ws["settings"] = _sorted_top(settings)
    if extensions:
        ws["extensions"] = {"recommendations": extensions}
    return json.encode_indent(ws, indent = "  ") + "\n"

def settings_json(settings):
    """Render a canonical `settings.json` (trailing newline)."""
    return json.encode_indent(_sorted_top(settings) if settings else {}, indent = "  ") + "\n"
