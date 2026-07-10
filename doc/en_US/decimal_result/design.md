# `decimal_result` Design

## Responsibility

`DecimalResult` is a small checked-composition adapter, not a second Decimal
context system. It lifts operations whose failure vocabulary is
`ArithmeticError` and leaves `(Decimal, DecimalFlags)` APIs untouched.

## Error Flow

The first `Err` short-circuits later operations. `map` cannot introduce a new
error; `bind` and `flat_map` can. `result()` is the explicit exit from the closed
wrapper algebra.
