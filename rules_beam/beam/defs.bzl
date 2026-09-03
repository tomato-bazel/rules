"""Public API surface for rules_beam.

```python
load("@rules_beam//beam:defs.bzl",
     "beam_pipeline_binary",
     "BeamPipelineInfo", "BeamRunnerInfo")
```

v0.0.1 ships the foundation: provider types + the universal fat-jar
build (`beam_pipeline_binary`). The deployer macros
(`beam_dataflow_template`, `beam_flink_application`,
`beam_spark_application`) land in subsequent versions — each takes the
same `BeamPipelineInfo` and stages it for one cloud runner.

Until those land, consumers can drive the deploy jar via their own
deploy scripts; the artifact + main_class + native_binaries are all
exposed via the `BeamPipelineInfo` provider.
"""

load(":pipeline.bzl", _beam_pipeline_binary = "beam_pipeline_binary")
load(
    ":providers.bzl",
    _BeamPipelineInfo = "BeamPipelineInfo",
    _BeamRunnerInfo = "BeamRunnerInfo",
)

# Re-exported macros.
beam_pipeline_binary = _beam_pipeline_binary

# Re-exported providers.
BeamPipelineInfo = _BeamPipelineInfo
BeamRunnerInfo = _BeamRunnerInfo
