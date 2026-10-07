# `ball_float_checked` Design

`BallFloatResult` closes checked interval construction and arithmetic over
`Result[BallFloat, ArithmeticError]`. Invalid bounds, non-finite exact sources,
and checked arithmetic failures enter the error branch; later methods
short-circuit. `bind` may introduce a failure and `map` cannot.

The wrapper neither stores decorations nor `BallFlags`, and it does not add an
interval algorithm. Bare set arithmetic is delegated to `ball_float`; decorated
operations and context status remain explicit APIs there. Conservative interval
results such as Entire are valid successes, not wrapper errors.

Wrapper composition adds `O(1)` work beyond interval arithmetic. Entire remains
success because loss of tightness is not the same as failure to enclose; making
it an error would break valid interval-domain semantics.
