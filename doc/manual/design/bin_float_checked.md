# `bin_float_checked` Design

`BinFloatResult` is a closed `Result[BinFloat, ArithmeticError]` pipeline.
Constructors validate at the edge; unary methods map successful values; binary
methods short-circuit the left error before the right and invoke checked scalar
operations only when both succeed. `bind` may change success to failure;
`map` cannot. `flat_map` remains only as a deprecated alias.

The package adds no arithmetic algorithm, context flags, IEEE interchange, or
error recovery. It preserves the first checked error and delegates all numeric
semantics to `bin_float`. Its operation set is intentionally limited to the
methods in the generated interface; contextual IEEE pipelines still use the
underlying `(value, flags)` APIs directly.

Each wrapper step is `O(1)` beyond the delegated numeric operation and stores
one `Result`. A separate wrapper was chosen instead of hiding errors inside
`BinFloat` so ordinary values remain usable in algebraic code while checked
pipelines preserve the first failure explicitly.
