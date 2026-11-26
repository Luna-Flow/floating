# `interval`

`interval` is the stable outward-rounded interval surface. `Interval` uses
lower/upper endpoints, `IntervalContext` applies directed rounding, and
`DecoratedInterval` adds IEEE 1788 decorations and NaI. Empty, Entire, and NaI
are distinct states; interval relations are not scalar total order.

Public arithmetic includes set construction, containment/overlap relations,
add/subtract/multiply/divide, FMA, integer and general power, exp/log/sqrt, and
sin/cos/tan with certified fallbacks. `apply_ctx` returns `IntervalFlags` when status is
needed. The reverse operations `mul_rev`, `mul_rev_to_pair`, `sqr_rev`,
`abs_rev`, `pown_rev`, `pow_rev1`, `pow_rev2`, `sin_rev`, `cos_rev`, `tan_rev`,
`cosh_rev`, `atan2_rev1` and `atan2_rev2` are public. Tightness is not
guaranteed when a safe fallback is required.
