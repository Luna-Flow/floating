# `cli/itl_expr_cli` Design

This adapter reads ITL files, optionally filters exact operation names, executes
cases through `frontend/itl_expr`, and emits schema-versioned JSON. Strict mode
turns unsupported cases into failure. It has no phase planner, corpus fetcher,
or interval algorithm; phase ownership remains in Python tooling.
