# `bin_float_result` Design

## Responsibility

The package solves an endomorphism problem: raw checked methods return
`Result`, which interrupts fluent numeric composition. `BinFloatResult` keeps
both success and failure in a numeric wrapper whose operations return `Self`.

## Boundaries

The wrapper does not hide failure; `result()` restores the ordinary checked
boundary. Observer operations whose natural result is not `BinFloat` are not
forced into this algebra. Error propagation is left-biased and short-circuiting.
