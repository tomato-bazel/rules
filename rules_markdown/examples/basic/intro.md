`rules_markdown` composes independent markdown fragments into one document —
ordered by weight, with a generated table of contents and resolved
cross-fragment deep links. Each fragment is a Bazel target, so docs assemble
from the build graph the same way code does.
