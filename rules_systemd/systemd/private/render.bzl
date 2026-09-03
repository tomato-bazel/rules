"""INI rendering helpers shared by the unit rules.

systemd unit files are INI-style: `[Section]` headers followed by
`Key=Value` lines. A directive may legally repeat (e.g. multiple
`ExecStartPre=` or `Environment=`), so a list value renders as one line
per element; a string value renders as a single line. `None`/`""`
entries are dropped, and a section with no surviving keys is omitted
entirely. Insertion order is preserved (Starlark dicts/lists are
ordered) so the output reads the way a hand-written unit would.
"""

def join(xs):
    """Space-join a string_list into one directive value, or None if empty."""
    return " ".join([x for x in xs if x]) if xs else None

def dict_pairs(d):
    """Turn an attr.string_dict into ordered (key, value) pairs for an extra block."""
    return [(k, d[k]) for k in d]

def _emit(lines, key, value):
    if value == None:
        return
    if type(value) == "list":
        for v in value:
            if v != None and v != "":
                lines.append("{}={}".format(key, v))
    elif value != "":
        lines.append("{}={}".format(key, value))

def render_sections(sections):
    """Render an ordered list of (section_name, [(key, value), ...]) to INI text.

    Args:
      sections: ordered list of (section_name, pairs) tuples, where
        pairs is a list of (key, value). `value` is a str (single
        line), a list (one repeated line per element), or None
        (dropped). Empty sections are skipped.

    Returns:
      The rendered INI text, always ending in a trailing newline.
    """
    out = []
    first = True
    for section, pairs in sections:
        body = []
        for key, value in pairs:
            _emit(body, key, value)
        if not body:
            continue
        if not first:
            out.append("")
        first = False
        out.append("[{}]".format(section))
        out.extend(body)
    return "\n".join(out) + "\n"
