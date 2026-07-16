# `ball_float` Design

`ball_float` is the certified real-enclosure domain of `floating` 0.7.1. It
builds bare and decorated intervals on `BinFloat` endpoints and aligns its
declared operation boundary with IEEE 1788-2015. Correctness is defined first by
set inclusion: a wider interval may be less useful, but an interval that omits a
possible exact result is invalid.

## Design Contract

The package turns a point operation into an enclosure pipeline:

```text
input interval(s)
  -> classify Empty / Entire / finite / unbounded domains
  -> choose monotone endpoint, critical-point, or full endpoint-product rule
  -> evaluate lower bounds toward -infinity
  -> evaluate upper bounds toward +infinity
  -> apply BallContext bounds and flags
  -> optionally propagate IEEE 1788 decoration
```

This pipeline separates the mathematical set rule from endpoint arithmetic.
`bin_float` owns dyadic rounding and certified scalar kernels; `ball_float`
owns which endpoint combinations and domain fallbacks are required to enclose
the image of a set.

## Representation And Invariants

A non-empty bare interval stores a lower endpoint `lo_`, upper endpoint `hi_`,
and precision, with `lo_ <= hi_` and no NaN endpoint. Empty and Entire are
explicit states. `BallFloat::new(center, radius)` is a constructor view; the
stored object is still an endpoint interval.

Constructors and precision changes round `lo_` toward negative infinity and
`hi_` toward positive infinity. Therefore conversion or retuning may widen an
interval but cannot shrink the represented set. `BallFloat::exact(x)` embeds
the exact dyadic value represented by `x`; it does not assert that a prior
decimal-to-binary approximation equals the original decimal real value.

`BallFloatDecorated` combines a bare interval with IEEE 1788 decorations and a
distinct NaI state. Empty is a valid bare set; NaI records an invalid decorated
operation and must not be collapsed into Empty.

## IEEE 1788 Alignment

The standard-facing model keeps set values, decorations, and status separate:

- bare interval operations compute set enclosures;
- decorated operations lower the result decoration to the minimum permitted by
  the operands and operation continuity/domain;
- NaI remains distinct from all bare intervals;
- relations such as subset, interior, overlap, and precedes are set relations,
  not scalar comparison;
- reverse operations remain outside the 0.7.1 support boundary.

The strict pinned ITF1788 run passes 4,656/4,656 selected cases, including
general power, trigonometric, hyperbolic, inverse-trigonometric, and 375
`atan2` cases. `rootn` and extension operations have package-level evidence but
are reported separately when the pinned corpus does not cover them. Passing a
finite corpus does not imply every IEEE 1788 operation or guaranteed tightness.

## Basic Arithmetic Selection

Basic operations select formulas from monotonicity and sign structure:

| Operation | Enclosure rule | Important boundary |
| --- | --- | --- |
| addition | `[a.lo + b.lo, a.hi + b.hi]` with directed rounding | Empty propagates |
| subtraction | `[a.lo - b.hi, a.hi - b.lo]` | endpoint order reverses for the subtrahend |
| multiplication | minimum/maximum of four endpoint products | sign shortcuts may reduce work but not candidates |
| reciprocal/division | reciprocal endpoints when zero is excluded | interior zero crossing yields Entire; one-sided zero may yield a half-infinite interval |
| square/root | monotone pieces plus zero/domain checks | negative-only square-root domain yields Empty |
| intersection/hull | endpoint max/min | disjoint intersection yields Empty |

`BallContext` then rounds both endpoints to its precision/exponent range and
returns `BallFlags` for inexact, overflow, and underflow. Entire is a successful
enclosure rather than a generic error.

## Certified Elementary Functions

Elementary functions use directed dyadic certificates over `BinCoeff`. Each
series or reduction step rounds outward, and an explicit analytic remainder
bound encloses the truncated tail. The implementation uses:

- range reduction plus a bounded exponential series for `exp`;
- power-of-two reduction plus a certified unit-interval series for `ln`;
- certified logarithms and exact shortcuts for `log2`/`log10`;
- Machin-formula bounds for pi, certified quadrant reduction, alternating
  series, and exact critical-point tests for `sin`/`cos`;
- the same reduction plus pole detection for `tan`;
- monotonic endpoint evaluation and domain splitting for inverse/hyperbolic
  functions; and
- `exp(exponent × ln(base))` with guarded outward arithmetic for general
  positive-base power.

The shared certification budget permits 12 refinements and increases work
precision by `max(32, work / 2)`. `try_*` operations expose range-reduction,
resource-limit, or target-rounding failures as structured certification errors.
Total interval operations use conservative set fallbacks when their contract
permits it:

- uncertified or very large `sin`/`cos` returns `[-1, 1]`;
- a `tan` pole or uncertified reduction returns Entire;
- analogous composed operations choose their documented whole-domain bound.

This boundary is intentional. The `try_*` family is appropriate when proof
failure must be observable; the total family is appropriate when a valid but
possibly wide enclosure is more useful than stopping a calculation.

## Critical Points, Poles, And Switching Boundaries

Endpoint evaluation alone is sufficient only for monotone functions. Periodic
functions additionally compute a certified range of quadrant/critical indices.
If that range contains an extremum, the corresponding `-1` or `1` endpoint is
included. If it contains a tangent pole, the result is Entire. The decision is
made in exact/certified index space, not by comparing an approximate remainder
to a heuristic epsilon.

For bounded ordinary arguments, refinement attempts a tight certificate. For
unbounded arguments or arguments whose adjusted binary exponent exceeds the
resource cutoff `max(65,536, 4 × precision)`, the total path switches directly
to the safe range fallback; the `try_*` path returns a resource-limit detail.
This is a proof-resource boundary, not a claim that the mathematical function
is undefined.

## Decorations And Relations

Decorations propagate by the weakest operand/operation grade. Domain clipping
or discontinuity can lower the grade even when the bare enclosure is valid.
Set observers retain their interval meaning:

- `contains` asks whether a point belongs to the set;
- `subset`, `interior`, and `set_equal` compare sets;
- `overlap_state` classifies relative geometry;
- `definitely_lt`/`definitely_gt` prove an order only when all points satisfy it;
- `maybe_eq` reports compatibility rather than equality.

No total scalar order is defined for intervals. Likewise, `Sign::Zero` may mean
that the set crosses zero rather than that it is the singleton `{0}`.

## Optimization And Trade-offs

Basic interval operations perform a constant number of endpoint operations, so
their cost is `O(M(p))` at endpoint precision `p`, with storage for two
`BinFloat` values. Elementary functions add range reduction, bounded series,
and up to 12 refinement steps. Their cost is data-dependent because difficult
rounding cells and large arguments require more proof precision.

The implementation optimizes repeated constants, exact special cases,
monotonicity, and shared trigonometric reduction before increasing precision.
It does not optimize by dropping an endpoint candidate or replacing outward
rounding with nearest rounding. When tightness and resource bounds conflict,
the total API widens and the checked API reports why.

## 0.7.1 Semantic Preservation Proof

For each finite endpoint candidate `y`, downward rounding is a lower
certificate and upward rounding is an upper certificate. The interval code
first selects the mathematical extremum from monotonicity and sign structure,
then applies the matching direction; `quantize_interval` preserves the same
outward relation at the stored precision.

The integer-power proof obligations are explicit: positive odd powers increase,
positive even powers decrease on the negative half-axis, negative odd powers
decrease away from zero, and negative even powers increase on the negative
half-axis. Zero-containing negative powers use the pole/whole-real branches.
The negative-half-axis regression, directed endpoint tests, and strict ITF1788
aggregate verify ordered set inclusion for the declared forward interval
surface. A wider fallback is valid; a reversed or inward-rounded endpoint is
not.

## Evidence Map

- [API reference](./api.md) inventories bare, decorated, context, and `try_*`
  operations.
- [Tutorial](./tutorial.md) demonstrates safe construction, relations,
  elementary functions, and proof-failure policy.
- [Conformance](./conformance.md) defines the exact pinned ITF1788 claim and
  exclusions.
- [`bin_float` design](../bin_float/design.md) owns endpoint kernels and
  coefficient dispatch; [`bin_float` performance](../bin_float/performance.md)
  owns their crossover evidence.
