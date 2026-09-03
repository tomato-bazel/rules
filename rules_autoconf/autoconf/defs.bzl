"""User-facing rules for rules_autoconf.

The Bazel-native equivalents of common autoconf AC_* primitives. Each
rule emits a single result file that other rules (notably
`config_header`) consume — so probe results compose into a graph, not
into shell-script global state.

The probes use Python tools that shell out to the host C compiler. The
host compiler choice is the `CC` env var (defaults to `cc`). v0.1 does
NOT use Bazel's `@bazel_tools//tools/cpp` C toolchain — it relies on
whatever `cc` resolves to on the host. v0.2+ will integrate the proper
Bazel C toolchain for full hermeticity.

Available rules:
  cc_check_header     — autoconf's AC_CHECK_HEADER
  cc_check_function   — autoconf's AC_CHECK_FUNC (link test)
  cc_check_symbol     — autoconf's AC_CHECK_DECL / AC_CHECK_TYPE
  config_header       — autoconf's AC_CONFIG_HEADERS (renders config.h
                        from a template + define dict + probe results)
"""

ProbeResultInfo = provider(
    doc = "A compile-test probe result.",
    fields = {
        "result_file": "File: contains '1' if the feature is present, '0' otherwise.",
        "define_name": "string: the macro name this probe defines when present (e.g. \"HAVE_STRLCPY\").",
    },
)

def _probe_impl(ctx, *, mode, header, symbol, libs, define_name):
    result = ctx.actions.declare_file(ctx.label.name + ".result")
    log = ctx.actions.declare_file(ctx.label.name + ".log")

    args = ctx.actions.args()
    args.add("--mode", mode)
    if header:
        args.add("--header", header)
    if symbol:
        args.add("--symbol", symbol)
    for lib in libs:
        args.add("--lib", lib)
    args.add("--out", result)
    args.add("--logfile", log)

    ctx.actions.run(
        executable = ctx.executable._probe,
        arguments = [args],
        outputs = [result, log],
        mnemonic = "AutoconfProbe",
        progress_message = "Probing %s for %s" % (mode, symbol or header),
        # Probes run against the host compiler; not sandbox-deterministic by
        # design (the whole point is to discover host capabilities).
        use_default_shell_env = True,
    )

    return [
        DefaultInfo(files = depset([result, log])),
        ProbeResultInfo(result_file = result, define_name = define_name),
    ]

def _cc_check_header_impl(ctx):
    header = ctx.attr.header
    define_name = ctx.attr.define_name or _default_define_name("HAVE_", header)
    return _probe_impl(
        ctx,
        mode = "header",
        header = header,
        symbol = None,
        libs = [],
        define_name = define_name,
    )

def _default_define_name(prefix, raw):
    sanitized = ""
    for c in raw.elems():
        if c.isalnum():
            sanitized += c.upper()
        else:
            sanitized += "_"
    return prefix + sanitized

cc_check_header = rule(
    implementation = _cc_check_header_impl,
    attrs = {
        "header": attr.string(
            mandatory = True,
            doc = "Header to probe (e.g. \"string.h\", \"sys/socket.h\").",
        ),
        "define_name": attr.string(
            default = "",
            doc = "Override the macro name. Defaults to `HAVE_<HEADER>` " +
                  "(uppercased, non-alphanumeric -> underscore).",
        ),
        "_probe": attr.label(
            default = "//autoconf/private:probe",
            executable = True,
            cfg = "exec",
        ),
    },
    provides = [ProbeResultInfo],
    doc = "Probe whether a C header is includable. Bazel-native equivalent of autoconf's AC_CHECK_HEADER.",
)

def _cc_check_function_impl(ctx):
    function = ctx.attr.function
    define_name = ctx.attr.define_name or _default_define_name("HAVE_", function)
    return _probe_impl(
        ctx,
        mode = "function",
        header = ctx.attr.header or None,
        symbol = function,
        libs = ctx.attr.libraries,
        define_name = define_name,
    )

cc_check_function = rule(
    implementation = _cc_check_function_impl,
    attrs = {
        "function": attr.string(
            mandatory = True,
            doc = "Function to probe (e.g. \"strlcpy\", \"getifaddrs\").",
        ),
        "header": attr.string(
            default = "",
            doc = "Optional header to #include (e.g. \"string.h\"). " +
                  "Some functions need a declaration to compile cleanly.",
        ),
        "libraries": attr.string_list(
            default = [],
            doc = "Libraries to link (each becomes -l<name>).",
        ),
        "define_name": attr.string(
            default = "",
            doc = "Override the macro name. Defaults to `HAVE_<FUNCTION>` " +
                  "(uppercased).",
        ),
        "_probe": attr.label(
            default = "//autoconf/private:probe",
            executable = True,
            cfg = "exec",
        ),
    },
    provides = [ProbeResultInfo],
    doc = "Probe whether a C function is linkable. Bazel-native equivalent of autoconf's AC_CHECK_FUNC.",
)

def _cc_check_symbol_impl(ctx):
    symbol = ctx.attr.symbol
    define_name = ctx.attr.define_name or _default_define_name("HAVE_DECL_", symbol)
    return _probe_impl(
        ctx,
        mode = "symbol",
        header = ctx.attr.header or None,
        symbol = symbol,
        libs = [],
        define_name = define_name,
    )

cc_check_symbol = rule(
    implementation = _cc_check_symbol_impl,
    attrs = {
        "symbol": attr.string(
            mandatory = True,
            doc = "Symbol/identifier to probe. Works for type names, macros, " +
                  "enum members, function declarations.",
        ),
        "header": attr.string(
            default = "",
            doc = "Header to #include to bring the symbol into scope.",
        ),
        "define_name": attr.string(
            default = "",
            doc = "Override the macro name. Defaults to `HAVE_DECL_<SYMBOL>`.",
        ),
        "_probe": attr.label(
            default = "//autoconf/private:probe",
            executable = True,
            cfg = "exec",
        ),
    },
    provides = [ProbeResultInfo],
    doc = "Probe whether a symbol is declared. Bazel-native equivalent of autoconf's AC_CHECK_DECL.",
)

def _config_header_impl(ctx):
    out = ctx.outputs.out

    probe_specs = []
    probe_inputs = []
    for probe in ctx.attr.probes:
        info = probe[ProbeResultInfo]
        probe_specs.append(info.define_name + ":" + info.result_file.path)
        probe_inputs.append(info.result_file)

    args = ctx.actions.args()
    args.add("--template", ctx.file.template)
    args.add("--defines", json.encode(ctx.attr.defines))
    for spec in probe_specs:
        args.add("--probe", spec)
    args.add("--out", out)

    ctx.actions.run(
        executable = ctx.executable._render,
        arguments = [args],
        inputs = [ctx.file.template] + probe_inputs,
        outputs = [out],
        mnemonic = "AutoconfRender",
        progress_message = "Generating %s" % out.short_path,
    )

    return [DefaultInfo(files = depset([out]))]

config_header = rule(
    implementation = _config_header_impl,
    attrs = {
        "template": attr.label(
            mandatory = True,
            allow_single_file = True,
            doc = "The template header (typically `config.h.in`). Lines matching " +
                  "`#undef VAR` are substituted with `#define VAR <value>` when " +
                  "`VAR` is in `defines`. `@VAR@` substitutions are also applied.",
        ),
        "defines": attr.string_dict(
            default = {},
            doc = "Static substitutions. Values become both `#define` bodies " +
                  "(for `#undef VAR` lines) and `@VAR@` substitutions.",
        ),
        "probes": attr.label_list(
            providers = [ProbeResultInfo],
            doc = "Probe targets (cc_check_header / cc_check_function / etc.). " +
                  "Each contributes `<DEFINE_NAME>=1` to `defines` iff the probe " +
                  "result is '1' (autoconf's HAVE_* convention).",
        ),
        "out": attr.output(
            mandatory = True,
            doc = "The rendered config header.",
        ),
        "_render": attr.label(
            default = "//autoconf/private:render",
            executable = True,
            cfg = "exec",
        ),
    },
    doc = "Render an autoconf-style config header from a template + defines + probe results.",
)
