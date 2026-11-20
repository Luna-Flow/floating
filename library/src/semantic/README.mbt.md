# `semantic`

`semantic` is a provisional representation-independent boundary. It projects
binary, decimal, and ball values into exact rationals, signed infinity, NaN,
closed intervals, and semantic errors. This is useful for cross-representation
tests, diagnostics, and protocol comparison.

Projection intentionally drops precision, cohort/quantum, signed-zero details,
NaN payload/signaling state, decorations, and context flags. It is not an
arithmetic implementation and should not replace concrete package APIs.
