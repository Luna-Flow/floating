# `decimal_checked` Design

`DecimalResult` provides the same left-to-right closed checked pipeline for
`Decimal`. Parsing and checked scalar operations can introduce
`ArithmeticError`; subsequent transformations short-circuit. `bind` can return
a new failure, while `map` only transforms an existing success.

The wrapper does not carry `DecimalContext` or accumulate `DecimalFlags`, so it
is not a GDA status pipeline. Use `decimal` `*_ctx` methods when cohort,
rounding flags, clamp, or exponent limits matter. The wrapper deliberately
exposes only its generated method set and delegates every numeric algorithm.

Wrapper composition is `O(1)` beyond the Decimal operation. Keeping context and
flags out avoids two competing accumulation models inside one type: callers
choose either short-circuit errors here or explicit `(value, flags)` GDA flow.
