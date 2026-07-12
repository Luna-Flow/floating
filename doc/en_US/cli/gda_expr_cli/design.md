# `cli/gda_expr_cli` Design

This adapter expands `.decTest` files/directories, parses documents once,
constructs deterministic filter/shard options, renders text or JSON summaries,
and maps failed or strictly unsupported cases to exit status. It does not
implement GDA semantics or download corpora; those belong to
`frontend/gda_expr` and the Python conformance tooling respectively.
