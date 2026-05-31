"""Provider types for the rules_beam public API.

The data-providing rule (`beam_pipeline_binary`) emits `BeamPipelineInfo`;
runner-specific deployment rules (`beam_dataflow_template`,
`beam_flink_application`, `beam_spark_application`) consume it. The
pipeline artifact — a fat jar — is universal across runners; deployers
add runner-specific metadata + staging.

Naming follows the rules_jena / rules_rdf convention: provider names
are package-prefixed (`BeamXInfo`) so an unwrapped import is unambiguous
next to other ecosystem providers.
"""

BeamPipelineInfo = provider(
    doc = "A built Beam-Java pipeline artifact. Consumed by deployers " +
          "that stage it for a specific runner (Dataflow / Flink / Spark) " +
          "or by a local DirectRunner test driver.",
    fields = {
        "deploy_jar": "File: the fat (deploy) jar containing the pipeline " +
                      "main class + all transitive deps. Universal across " +
                      "runners — the same jar is what Dataflow / Flink / " +
                      "Spark all consume.",
        "main_class": "str: fully-qualified Java main class of the pipeline " +
                      "(e.g. `com.example.MyPipeline`).",
        "native_binaries": "depset[File]: native binaries bundled inside " +
                           "the jar as classpath resources at " +
                           "`/native/<basename>`. Pipelines that shell to " +
                           "a sidecar (Rust binary, Python script, etc.) " +
                           "extract them at `@Setup` time.",
        "default_options": "list[str]: default PipelineOptions arguments " +
                           "applied when the pipeline is invoked without " +
                           "an explicit override (e.g. `--maxNumWorkers=4`).",
    },
)

BeamRunnerInfo = provider(
    doc = "Configuration for a specific Beam runner. Consumed via the " +
          "runner-toolchain types so deployers can resolve which Beam " +
          "runner Maven dependency to put on the classpath (the runner " +
          "library, not the pipeline itself).",
    fields = {
        "runner_class": "str: fully-qualified PipelineOptions runner class " +
                        "(e.g. `org.apache.beam.runners.direct.DirectRunner`).",
        "runner_label": "Label: a `java_library` containing the runner's " +
                        "Maven artifact; merged into the pipeline's deploy " +
                        "jar when this runner is selected.",
    },
)
