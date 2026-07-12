# `bin_float_checked`

`BinFloatResult` is the stable short-circuit composition wrapper around
`Result[BinFloat, ArithmeticError]`. Constructors validate at the boundary;
`map` preserves success, `bind` may introduce an error, and binary operations
retain the first error from left to right.

It adds no IEEE context, flags, interchange, or recovery policy. Use
`bin_float` directly for those concerns and use `BinFloatResult` for pipelines
whose failure channel must remain explicit.
