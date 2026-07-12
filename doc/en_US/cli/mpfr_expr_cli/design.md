# `cli/mpfr_expr_cli` Design

This adapter detects the committed sqrt versus integer-power corpus grammar,
delegates parsing and execution to `frontend/mpfr_expr`, and renders text or
JSON. It accepts one file and disables sharding because these pinned datasets
are small. Detection is a transport concern, not a numerical heuristic.
