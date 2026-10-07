# `semantic` Design

## Responsibility And Algorithm

`semantic` projects representation-specific values into a small exact domain:
reduced `ExactRational`, signed infinity, NaN, closed intervals, and semantic
errors. Finite binary values map by powers of two; finite decimals map by powers
of ten; interval endpoints map independently. Checked adapters translate
`ArithmeticError` into `SemanticError` without throwing or performing IO.

## Boundary

Projection is intentionally lossy for representation metadata: precision,
quantum/cohort, signed zero, NaN payload/signaling state, decorations, and
context flags are not preserved. The package compares or serializes mathematical
meaning; it is not a replacement for concrete arithmetic and defines no
rounding, parsing, interchange, or interval-tightening algorithms.
