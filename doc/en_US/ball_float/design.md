# `ball_float` Design

## Responsibility And Representation

`ball_float` owns bare and decorated real intervals built on `BinFloat`. The
current storage is an outward-rounded lower endpoint `lo_`, upper endpoint
`hi_`, and precision. `BallFloat::new(center, radius)` is a constructor view,
not the storage model. Empty is represented separately from Entire; decorated
NaI is distinct from Empty.

The invariant is `lo <= hi` for non-empty intervals, with no NaN endpoints.
Constructors and precision changes round the lower endpoint toward negative
infinity and the upper endpoint toward positive infinity, so conversion cannot
shrink the represented set.

## Arithmetic Selection

Addition and subtraction use monotone endpoint formulas. Multiplication takes
the minimum and maximum of the four endpoint products. Division uses reciprocal
endpoint formulas when the denominator excludes zero; one-sided zero endpoints
produce half-infinite results, while an interior zero crossing conservatively
produces Entire. `BallContext` then applies directed precision/exponent rounding
and reports `inexact`, `overflow`, and `underflow`.

Elementary functions use directed dyadic interval certificates over `BinCoeff`.
Each arithmetic step rounds outward at a bounded working precision, and an
explicit analytic remainder bound accounts for the truncated series:

- `exp` uses range reduction and a bounded exponential series;
- `ln` uses power-of-two reduction and a certified unit-interval series;
- `log2`/`log10` reuse certified logarithms with exact shortcuts;
- `sin`/`cos` use shared Machin-formula bounds for π, quadrant reduction,
  outward-rounded alternating series, and critical-point detection;
- `tan` additionally rejects intervals crossing a pole;
- general positive-base power evaluates `exp(exponent * ln(base))` with guard
  precision and outward rounding.

The trigonometric kernels double working precision at most eight times. If
argument reduction cannot be certified, `sin`/`cos` return `[-1, 1]` and `tan`
returns Entire. Very large or unbounded trigonometric inputs take the same safe
fallback. These are deliberate enclosure guarantees, not silent scalar guesses.

## Decorations And Relations

Decorations propagate by the minimum input/operation grade. Set relations,
overlap states, cancellation, intersection, and convex hull are interval
operations; no total scalar order is defined. `Sign::Zero` can mean an interval
crosses zero, not only that it is the singleton zero.

## Capability Boundary

The strict ITF1788 gate covers the phases listed in
`testdata/interval/README.md`, including general power and trigonometric
operations; the current pinned run is 4,113/4,113 with zero unsupported cases.
Reverse operations are unsupported. Enclosures are certified, but tightness is
not guaranteed when a conservative fallback is used.

## Complexity And Trade-offs

Basic interval operations perform a constant number of endpoint operations, so
their cost is `O(M(p))`, where `M(p)` is the underlying `BinFloat` coefficient
cost at precision `p`; storage is two endpoint values. Elementary functions use
`O(k)` bounded series terms at `O(p)` working precision, with a bounded number
of precision doublings. Critical-point checks and Entire/`[-1,1]` fallbacks
trade tightness for the non-negotiable inclusion invariant: a wider enclosure
is valid, an enclosure that loses the exact result is not.

## Inclusion Invariant

Every constructor and operation widens outward when necessary; correctness is defined by set inclusion before tightness.

## Elementary Certificates

Range reduction, series bounds, and critical-point checks form the proof object for elementary enclosures.
