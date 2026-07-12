# `cli/testfloat_expr_cli` Design

This adapter validates one vector file plus function, rounding, tininess, and
shard options, then delegates to `frontend/testfloat_expr`. It serializes stable
summary fields and exit status. It does not infer vector semantics from file
names or generate TestFloat cases.
