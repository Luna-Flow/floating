# `frontend/itl_expr` Design

The package parses the ITF1788 line language into typed cases, then dispatches
supported operations to `BallFloat` and `BallFloatDecorated`. Expected interval,
boolean, overlap, numeric, and decoration results use operation-specific
comparators. Summaries are folded through the shared conformance model.

Unsupported operation, arity, or expected-value forms remain explicit
dispositions. The package does not claim full IEEE 1788 support, read files, or
choose strict phases; `testdata/interval/README.md` and tooling define the gate.
