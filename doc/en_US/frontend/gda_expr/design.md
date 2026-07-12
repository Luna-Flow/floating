# `frontend/gda_expr` Design

## Pipeline And Selection

The package parses GDA `.decTest` text into immutable contexts, cases, source
spans, and `numeric_expr` trees. Directive state is snapshotted into each case.
Execution normalizes operation names, classifies the case before evaluation,
maps supported operations to `Decimal` context APIs, and compares both result
cohort and flags. Deterministic sharding selects by stable case position.

## Capability Boundary

Cases are explicitly `Executable`, `Diagnostic`, `Legacy`, or `Unsupported`.
For the pinned official corpora, diagnostics are only `#` placeholder/non-scalar
invalid inputs; legal rows have zero legacy and unsupported classifications and
all pass. The package does not download corpora, read files, spawn processes, or
implement decimal arithmetic. Python tooling owns corpus staging;
`cli/gda_expr_cli` owns filesystem and process exit behavior.
