"""Runner toolchain types — declared here so deployers can resolve a
concrete runner implementation per-platform / per-flag. Concrete
toolchain implementations land alongside their deployers in subsequent
versions.

Plugin contract (sketch):
- `beam_runner_toolchain_type` resolves to a `BeamRunnerInfo` provider
  that knows the runner class name + the Maven artifact label to add to
  the deploy jar's classpath.
- Built-in runners we plan to wire in v0.0.2+:
  - `beam_direct_runner_toolchain` — local DirectRunner.
  - `beam_dataflow_runner_toolchain` — Google Cloud Dataflow.
  - `beam_flink_runner_toolchain` — Apache Flink (AWS MSF / EMR / EKS).
  - `beam_spark_runner_toolchain` — Apache Spark (AWS EMR Serverless).

The toolchain shape matches the rules_rdf reasoner / serializer /
validator pattern (rules_jena's reasoner-toolchain is the cleanest
in-repo reference).
"""

beam_runner_toolchain_type = "@rules_beam//beam:runner_toolchain_type"
