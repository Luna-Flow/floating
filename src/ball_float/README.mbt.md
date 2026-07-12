# `ball_float`

`ball_float` is the stable outward-rounded interval surface. `BallFloat` uses
lower/upper endpoints, `BallContext` applies directed rounding, and
`BallFloatDecorated` adds IEEE 1788 decorations and NaI. Empty, Entire, and NaI
are distinct states; interval relations are not scalar total order.

Public arithmetic includes set construction, containment/overlap relations,
add/subtract/multiply/divide, FMA, integer and general power, exp/log/sqrt, and
sin/cos/tan with certified fallbacks. `*_ctx` returns `BallFlags` when status is
needed. Reverse interval operations remain unsupported and tightness is not
guaranteed when a safe fallback is required.
