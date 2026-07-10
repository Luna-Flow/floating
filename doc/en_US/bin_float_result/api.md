# `bin_float_result` API

`BinFloatResult` wraps `Result[BinFloat, ArithmeticError]` and keeps checked
binary arithmetic closed over one type.

## Construction And Observation

- `ok`, `err`, and `from_result` wrap existing outcomes.
- `from_int`, `from_bigint`, `from_float`, and `from_double` create successful values.
- `result` exposes the wrapped `Result` at an application boundary.

## Composition

- `map` applies a non-failing `BinFloat -> BinFloat` transform to `Ok` values.
- `bind` and `flat_map` apply a `BinFloat -> BinFloatResult` transform.
- Existing errors short-circuit all composition methods.

## Numeric Operations

`abs`, `neg`, `add`, `sub`, `mul`, `div`, `sqrt`, `pow_nat`, `pow_int`,
`normalized`, `with_precision`, `ulp`, `min`, `max`, and labeled-argument
`clamp` all return `BinFloatResult`. Operators `+`, `-`, `*`, `/`, and unary
`-` delegate to the corresponding methods.
