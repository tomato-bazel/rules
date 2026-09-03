"""`beam_pipeline_binary(name, main_class, srcs, deps, ...)` — build a
Beam-Java pipeline as a fat (deploy) jar consumable by any runner.

The universal output across runners. Dataflow consumes it via Flex
template launchers; AWS Managed Service for Apache Flink takes it as
the application jar; Spark on EMR Serverless mounts it on the driver
classpath. The same artifact, different deployers downstream.

```python
load("@rules_beam//beam:defs.bzl", "beam_pipeline_binary")

beam_pipeline_binary(
    name = "corpus_pipeline",
    srcs = ["MyPipeline.java"],
    main_class = "com.example.MyPipeline",
    deps = [
        "@maven//:org_apache_beam_beam_sdks_java_core",
        "@maven//:org_apache_beam_beam_runners_direct_java",
    ],
    native_binaries = [
        "//crates/agora_bgp_sidecar:agora-bgp-sidecar",
    ],
)
```

Produces:
- `:corpus_pipeline` — the `java_binary` (runnable locally).
- `:corpus_pipeline_deploy.jar` — the fat jar (single file with all
  transitive deps shaded). The artifact deployers consume.
- A `BeamPipelineInfo` provider on a separate `:corpus_pipeline_info`
  target so deployers (`beam_dataflow_template`, etc.) can resolve it
  without depending on the java_binary directly.

`native_binaries` are bundled into the jar as classpath resources at
`/native/<basename>`. The pipeline's `@Setup` extracts them to `/tmp/`,
marks them executable, and opens stdin/stdout subprocesses — the
canonical "ship a Rust sidecar inside a Java jar" pattern.
"""

load("@rules_java//java:defs.bzl", "java_binary")
load(":providers.bzl", "BeamPipelineInfo")

def _beam_pipeline_info_impl(ctx):
    return [BeamPipelineInfo(
        deploy_jar = ctx.file.deploy_jar,
        main_class = ctx.attr.main_class,
        native_binaries = depset(ctx.files.native_binaries),
        default_options = ctx.attr.default_options,
    )]

_beam_pipeline_info = rule(
    implementation = _beam_pipeline_info_impl,
    attrs = {
        "deploy_jar": attr.label(allow_single_file = [".jar"], mandatory = True),
        "main_class": attr.string(mandatory = True),
        "native_binaries": attr.label_list(allow_files = True),
        "default_options": attr.string_list(),
    },
    provides = [BeamPipelineInfo],
    doc = "Wraps a java_binary's _deploy.jar in BeamPipelineInfo for " +
          "consumption by runner-specific deployers.",
)

def beam_pipeline_binary(
        name,
        main_class,
        srcs = None,
        deps = None,
        resources = None,
        data = None,
        native_binaries = None,
        default_options = None,
        visibility = None):
    """Bazel-idiomatic Beam pipeline build.

    Args:
      name: target name.
      main_class: fully-qualified Java main class of the pipeline.
      srcs: Java source files implementing the pipeline.
      deps: java_library / Maven labels. Must include the Beam SDK and
        any runner the pipeline references directly. Runner-specific
        Maven deps (e.g. beam-runners-google-cloud-dataflow-java) are
        added by the deployer macros when the pipeline is staged for
        that runner.
      resources: classpath resources (configs, prompt templates, etc.).
      data: runtime data files resolved via Bazel runfiles. Use for
        binaries the pipeline shells to (sidecars, helper tools) when
        running locally on DirectRunner. NOTE: data is NOT included in
        the fat jar — cloud runners (Dataflow, Flink, Spark) won't have
        access to it. Use `native_binaries` instead for cloud-runnable
        sidecars.
      native_binaries: targets producing native executables to bundle
        in the fat jar at `/native/<basename>`. The pipeline extracts
        + execs them at runtime. Cloud-runner compatible.
      default_options: PipelineOptions args passed verbatim by deployers
        when the pipeline runs (e.g. `["--streaming", "--maxNumWorkers=4"]`).
      visibility: forwarded to the produced targets.
    """
    native_binaries = native_binaries or []
    resources = resources or []

    # The native binaries ride inside the jar as classpath resources.
    # `resource_strip_prefix` is unset here because Bazel emits the
    # binaries under their package path; we re-anchor them via a
    # genrule that stages each under `/native/<basename>`. The genrule
    # produces a flat directory the java_binary picks up via `data` +
    # `resources` of a wrapper java_library.
    bundled_resources = list(resources)
    if native_binaries:
        staged_name = "_{}_native".format(name)
        cmds = []
        outs = []
        for i, bin in enumerate(native_binaries):
            out = "{}/native/{}".format(staged_name, _basename(bin))
            outs.append(out)
            cmds.append("mkdir -p $(RULEDIR)/{}/native && cp $(location {}) $(RULEDIR)/{}".format(
                staged_name,
                bin,
                out,
            ))
        native.genrule(
            name = staged_name,
            srcs = native_binaries,
            outs = outs,
            cmd = " && ".join(cmds),
        )
        bundled_resources.extend([":" + staged_name])

    java_binary(
        name = name,
        srcs = srcs,
        main_class = main_class,
        deps = deps,
        resources = bundled_resources,
        resource_strip_prefix = "_{}_native".format(name) if native_binaries else None,
        data = data,
        visibility = visibility,
    )

    # Wrap the produced _deploy.jar in BeamPipelineInfo for deployers.
    _beam_pipeline_info(
        name = name + "_info",
        deploy_jar = ":" + name + "_deploy.jar",
        main_class = main_class,
        native_binaries = native_binaries,
        default_options = default_options or [],
        visibility = visibility,
    )

def _basename(label):
    """Naive basename: last `/`-segment of the label, or the label name."""
    s = str(label)
    if "/" in s:
        s = s.rsplit("/", 1)[-1]
    if ":" in s:
        s = s.rsplit(":", 1)[-1]
    return s
