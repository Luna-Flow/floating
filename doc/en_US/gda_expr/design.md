# `gda_expr` Design

## Pipeline

The parser turns directive state and case rows into `GdaDocument` values backed
by `numeric_expr`. The executor translates GDA context into `DecimalContext`,
dispatches normalized operation names, and classifies outcomes in `RunSummary`.

## Execution Boundary

The library package contains no corpus download or process scheduling policy.
Python tooling owns pinned corpus installation, staged file assignment,
deterministic native shards, JSON artifacts, and aggregation. `gda_expr_cli`
provides the process boundary without duplicating Decimal semantics.

## Unsupported Cases

Unsupported operations, parser diagnostics, and legacy conditions are kept
separate from executable mismatches. Strict mode can promote unsupported or
legacy rows to a failing gate without misreporting them as wrong numeric answers.
