# `ball_float_checked`

`BallFloatResult` is the stable checked wrapper for interval construction and
scalar composition. Invalid bounds and checked arithmetic failures are errors;
Entire and other conservative enclosures are valid successful values. The
wrapper does not store decorations or `BallFlags`; those remain explicit
`ball_float` concerns.
