"""`puml_diagram(name, src | libs, output_format)` — render a single
PlantUML diagram.

Two input shapes, mutually exclusive:
- `src` — a single `.puml` source file. The common case for a
  one-off diagram.
- `libs` — a list of `puml_library` targets whose sources are
  concatenated (declaration order) and rendered as one diagram.
  Used to compose a system diagram out of typed fragments.

```python
load("@rules_puml//puml:defs.bzl", "puml_diagram", "puml_library")

# One-shot diagram from a single source.
puml_diagram(
    name = "pipeline",
    src = "pipeline.puml",
    output_format = "svg",
)

# Composed diagram: preamble + components + interactions, rendered as one.
puml_library(name = "preamble", srcs = ["skinparam.puml"])
puml_library(name = "components", srcs = ["actors.puml", "boxes.puml"])
puml_library(name = "interactions", srcs = ["flows.puml"])

puml_diagram(
    name = "system",
    libs = [":preamble", ":components", ":interactions"],
    output_format = "svg",
)
```

The macro composes a private `_<name>_assemble` genrule (concatenates
the puml sources) with a typed `_puml_diagram_render` rule that
invokes the PlantUML JAR via `ctx.actions.run`. The two-step shape
matches the rules_cloudformation pattern: input fragments stay
declarative, the rendered artifact is a downstream consumer.
"""

load(":providers.bzl", "PumlDiagramInfo", "PumlSourceInfo")

_VALID_FORMATS = ["svg", "png"]

# Map PlantUML CLI `-t<fmt>` switches.
_PUML_FLAG = {
    "svg": "-tsvg",
    "png": "-tpng",
}

def _puml_diagram_render_impl(ctx):
    if ctx.attr.output_format not in _VALID_FORMATS:
        fail(
            "puml_diagram: unsupported output_format %r (valid: %s)." %
            (ctx.attr.output_format, sorted(_VALID_FORMATS)),
        )

    src = ctx.file.src
    out = ctx.actions.declare_file(ctx.attr.basename + "." + ctx.attr.output_format)

    # PlantUML writes `<input_stem>.<ext>` inside the directory it's
    # given via `-o` — there's no way to name the output file. So we
    # let it write `<input_stem>.<ext>` into our action's working dir
    # and then move it to the declared output. Using `run_shell` so
    # the rename happens in the same action (and inside the sandbox).
    in_stem = src.basename.rsplit(".", 1)[0]
    fmt_flag = _PUML_FLAG[ctx.attr.output_format]
    fmt_ext = ctx.attr.output_format
    # Render into a per-action scratch dir alongside the declared
    # output, then rename the produced `<stem>.<ext>` to the declared
    # path. PlantUML's `-o` resolves the dir relative to the SOURCE
    # file (not the cwd), which Bazel's relative paths interact with
    # in surprising ways; staging through a scratch under cwd and
    # moving is the simplest robust shape.
    cmd = (
        'set -e; mkdir -p "$2"; "$1" {flag} -o "$(pwd)/$2" "$3"; ' +
        'mv "$2/{stem}.{ext}" "$4"'
    ).format(flag = fmt_flag, stem = in_stem, ext = fmt_ext)

    scratch_dir = "_puml_render_" + ctx.label.name
    ctx.actions.run_shell(
        command = cmd,
        arguments = [
            ctx.executable._tool.path,
            scratch_dir,
            src.path,
            out.path,
        ],
        tools = [ctx.executable._tool],
        inputs = [src],
        outputs = [out],
        mnemonic = "PumlRender",
        progress_message = "puml render %s (%s)" % (
            ctx.label,
            ctx.attr.output_format,
        ),
    )

    return [
        DefaultInfo(files = depset([out])),
        PumlDiagramInfo(
            output = out,
            output_format = ctx.attr.output_format,
        ),
    ]

_puml_diagram_render = rule(
    implementation = _puml_diagram_render_impl,
    attrs = {
        "src": attr.label(
            allow_single_file = [".puml", ".plantuml", ".pu", ".uml"],
            mandatory = True,
            doc = "Composed `.puml` source. For the macro form the " +
                  "macro synthesizes this from `libs` via a private " +
                  "genrule; consumers calling the rule directly pass " +
                  "a hand-authored file.",
        ),
        "output_format": attr.string(
            default = "svg",
            values = _VALID_FORMATS,
            doc = "Render format. SVG is the LaTeX-friendly default " +
                  "(consumers either use the `svg` package or " +
                  "pre-convert to PDF). PNG is the rasterized form.",
        ),
        "basename": attr.string(
            mandatory = True,
            doc = "Output basename (without extension). The macro " +
                  "sets this to the macro's `name` so the rendered " +
                  "file is `<name>.<format>`.",
        ),
        "_tool": attr.label(
            default = Label("//puml/private/plantuml:plantuml"),
            executable = True,
            cfg = "exec",
        ),
    },
    provides = [PumlDiagramInfo],
    doc = "Internal: invokes the PlantUML JAR on a composed `.puml` " +
          "source. Most consumers want the `puml_diagram` macro, " +
          "which assembles `libs` and forwards to this rule.",
)

def puml_diagram(name, src = None, libs = None, output_format = "svg", visibility = None):
    """Render a PlantUML diagram from a single source or composed libraries.

    Args:
      name: target name. The rendered file is `<name>.<output_format>`.
      src: a single `.puml` source label. Mutually exclusive with `libs`.
      libs: a list of `puml_library` labels whose sources concatenate
        (declaration order) into one diagram. Mutually exclusive
        with `src`.
      output_format: `svg` (default) or `png`.
      visibility: forwarded to the rendered target.
    """
    if (src == None) == (libs == None or len(libs) == 0):
        fail(
            "puml_diagram(%r): exactly one of `src` or non-empty " %
            name + "`libs` must be supplied.",
        )

    if src != None:
        composed = src
    else:
        composed_name = "_{}_composed".format(name)
        _puml_compose(
            name = composed_name,
            libs = libs,
        )
        composed = ":" + composed_name

    _puml_diagram_render(
        name = name,
        src = composed,
        output_format = output_format,
        basename = name,
        visibility = visibility,
    )

def _puml_compose_impl(ctx):
    """Concatenate sources from every `puml_library` in `libs`.

    Output: `<name>.puml`. The composed source is what
    `_puml_diagram_render` consumes. Declaration order is preserved
    (so a `preamble` library can ship `@startuml` and a closer
    library can ship `@enduml`).
    """
    files = []
    for lib in ctx.attr.libs:
        info = lib[PumlSourceInfo]
        files.extend(info.srcs.to_list())

    out = ctx.actions.declare_file(ctx.label.name + ".puml")
    ctx.actions.run_shell(
        command = "cat \"$@\" > " + out.path,
        arguments = [f.path for f in files],
        inputs = files,
        outputs = [out],
        mnemonic = "PumlCompose",
        progress_message = "puml compose %s (%d fragments)" % (
            ctx.label,
            len(files),
        ),
    )
    return [DefaultInfo(files = depset([out]))]

_puml_compose = rule(
    implementation = _puml_compose_impl,
    attrs = {
        "libs": attr.label_list(
            providers = [PumlSourceInfo],
            mandatory = True,
            doc = "`puml_library` targets to concatenate.",
        ),
    },
    doc = "Internal: concatenate the `.puml` sources from a list of " +
          "`puml_library` targets into a single composed source.",
)
