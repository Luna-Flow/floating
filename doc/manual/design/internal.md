# `internal` Design

## Responsibility And Algorithms

`internal` contains shared decimal/semantic implementation helpers: cached
powers of 2/5/10, decimal-string splitting, factor removal, digit counting,
rounding of positive quotients/shifts, `ExactRat`, and `Result` lifting.
Rational construction normalizes the sign and gcd; rounding consumes explicit
quotient/remainder facts and a caller-supplied mode.

## Boundary

The functions are deterministic and effect-free apart from local allocation.
They do not own numeric context, flags, parsing policy beyond lexical decimal
splitting, or public scalar representations. The package is importable in this
module but is not a stable application-facing contract: callers should use
`bin_float`, `decimal`, `ball_float`, or `semantic`.
