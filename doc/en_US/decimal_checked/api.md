# `decimal_checked` API

`DecimalResult` wraps `Result[Decimal, ArithmeticError]` for closed checked
decimal composition.

## Construction And Observation

- `ok`, `err`, `from_result`, and `result` bridge the raw result boundary.
- `from_int`, `from_bigint`, `from_float`, `from_double`, and `parse` create values.
- `parse` records invalid input as `Err` instead of returning `Option`.

## Composition And Arithmetic

`map`, `bind`, and `flat_map` preserve an existing error without invoking the
callback. `abs`, `neg`, `add`, `sub`, `mul`, `div`, `sqrt`, `pow_nat`,
`pow_int`, `normalized`, `with_precision`, `min`, `max`, and `clamp` return
`DecimalResult`. Standard arithmetic operators delegate to these methods.

Context-and-flags Decimal operations remain on `@decimal.Decimal`; this wrapper
models `ArithmeticError`, not the full GDA status-flag state.
