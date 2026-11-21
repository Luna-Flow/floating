# Generated interval cases

This directory is ours and not part of ITF1788. It holds ITL files whose expected values
are written by an oracle of this repository, for operations that the pinned ITF1788
corpus has no cases for.

| File | Operations | Written by |
| --- | --- | --- |
| `atan2_rev.itl` | `atan2Rev1`, `atan2Rev2` (IEEE 1788-2015 10.5.4, Table 10.1) | `python3 tools/itl_atan2_reverse_oracle.py --write` |

`python3 tools/itl_atan2_reverse_oracle.py --check` recomputes the file, requires it to be
byte-identical (`--write` is byte-stable), and validates every expected hull by the forward
definition of the operation.

## `atan2_rev.itl`

The expected value of each statement is the exact hull in binary64, computed by the oracle
with Python's `decimal` (260 digits) and no `interval` code. The oracle derives the hull
by polar rectangles (monotone images over an angle interval and a factor interval, extremes
at the corners) and then validates it by a second formulation that shares nothing with the
case analysis: the forward definition (`atan2` of a point is monotone and continuous in the
other argument on each side of 0, so a point is a member iff the image of the operand
interval meets `c`; the oracle tests an attained end, points a few geometric steps inside a
piece end, and a spread of points beyond each end of the hull, inside the prior).

The grid: the ends of `c` are -inf, -4, the floats on each side of -pi, -pi/2, 0, pi/2 and
pi, 1, 2, 4 and +inf (17 ends, every ordered pair); the ends of the operand are
-inf, -2, -1, -0.5, 0, 0.5, 1, 2 and +inf (every ordered pair); the prior is Entire for every
combination, and a prior drawn deterministically from eight for one combination in five.
`atan2_rev1_bare` and `atan2_rev2_bare` hold these cases; `atan2_rev1_dec` and
`atan2_rev2_dec` hold every 23rd of them with decorated operands (`_def`) and the result
`_trv` (11.7.1).

The gate runs this file as its own phase, `atan2-reverse` (`directory` in
`interpreter_stages.json`), counted apart from the ITF1788 total.
