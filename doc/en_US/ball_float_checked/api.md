# `ball_float_checked` API

`BallFloatResult` wraps `Result[BallFloat, ArithmeticError]` while preserving
interval semantics.

## Construction And Observation

`ok`, `err`, `from_result`, and `result` bridge raw results. `exact`,
`from_bounds`, `whole`, `from_int`, `from_coefficient`, `from_float`, and
`from_double` construct wrapped intervals. Invalid bounds become `Err`.

`from_coefficient` takes `@bin_float.BinCoeff` plus the independent
`negative?` sign flag; binary checked APIs do not accept `BigInt`.

## Composition And Arithmetic

`map`, `bind`, and `flat_map` short-circuit existing errors. `abs`, `neg`,
`add`, `sub`, `mul`, `div`, `pow_nat`, `pow_int`, `normalized`, and
`with_precision` return `BallFloatResult`; standard arithmetic operators are
implemented.

Division by an interval containing zero follows `BallFloat` semantics and
returns the whole-real enclosure. It is not converted into `Err`.
