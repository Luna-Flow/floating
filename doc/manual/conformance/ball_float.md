# ball_float conformance

## Claim

The current strict ITF1788 gate executes 4,656/4,656 selected cases with no failed, unsupported, or diagnostic rows. This is a claim about the pinned corpus revision, selected operation phases, and runner precision—not a claim of complete IEEE 1788 implementation.

## Clause traceability

IEEE Std 1788-2015 (set-based flavor) for `ball_float`. Status is `conforming` when the operation exists and the cited evidence exercises it, `partial` when part of the clause is missing or evidence is thin (the cell says which), `not implemented` and `not applicable` otherwise. Evidence without a corpus name is a unit test in the repository; "no external corpus" marks operations that no independent oracle checks.

| Clause | API | Evidence | Status |
| --- | --- | --- | --- |
| §4.2 set-based interval arithmetic flavor | `BallFloat`, `BallFloatDecorated` | ITF1788 strict gate (4,656 cases) | conforming for the selected phases |
| §4.2.2 compressed decorated interval arithmetic | none | none | not implemented |
| §9.1, §10.5.3 forward-mode arithmetic and elementary functions | `add`, `sub`, `mul`, `div`, `reciprocal`, `square`, `sqrt_interval`, `fma`, `pown`, `pow_interval`, `rootn`, `exp_interval`, `exp2_interval`, `exp10_interval`, `expm1_interval`, `ln_interval`, `log2_interval`, `log10_interval`, `log1p_interval`, `sin_interval`, `cos_interval`, `tan_interval`, `asin_interval`, `acos_interval`, `atan_interval`, `atan2_interval`, `sinh_interval`, `cosh_interval`, `tanh_interval`, `asinh_interval`, `acosh_interval`, `atanh_interval` | ITF1788 phases: add/sub/mul/div 539, elementary core 107, exp/log 131, general power 1,428, trigonometric 176, `atan2` 375, hyperbolic 107, inverse trigonometric 61, FMA 567, integer power 174 | conforming (valid enclosures; tightness is not promised, see [Implementation-defined choices](../verification.md#implementation-defined-choices)) |
| §10.5.4 reverse-mode elementary functions | none | none | not implemented (issue [#21](https://github.com/Luna-Flow/floating/issues/21)) |
| §10.5.5 two-output division | none | none | not implemented |
| §9.2, §10.5.6 cancellative addition and subtraction | `cancel_plus`, `cancel_minus` | ITF1788 cancellation phase (242 cases) | conforming |
| §9.3, §10.5.7 set operations | `intersection`, `convex_hull` | ITF1788 sets phase (20 cases) | conforming |
| §9.8, §10.5.8 constructors | `from_bounds`, `new`, `exact`, `from_int`, `from_double`, `from_float` | ITF1788 sets phase; `src/ball_float/ieee1788_arithmetic_wbtest.mbt` | partial (no text-to-interval constructor) |
| §9.4, §10.5.9 numeric functions of intervals | `lower_bound`, `upper_bound`, `midpoint`, `radius`, `width`, `magnitude`, `mignitude` | ITF1788 numeric observations phase (124 cases) | conforming |
| §9.5, §10.5.10 boolean functions of intervals | `is_empty`, `is_entire`, `is_singleton`, `is_common_interval`, `contains`, `set_equal`, `subset`, `interior`, `disjoint`, `less`, `precedes`, `strictly_less`, `strictly_precedes`, `overlap_state` | ITF1788 relations phase (567 cases); `src/ball_float/ieee1788_relations_wbtest.mbt` | conforming |
| §10.6.2 slope functions | none | none | not implemented |
| §10.6.4 extended interval comparisons | `definitely_lt`, `definitely_le`, `definitely_gt`, `maybe_eq` | `src/ball_float/ieee1788_relations_wbtest.mbt` | partial |
| §9.6, §11 decoration system | `Decoration`, `BallFloatDecorated`, `decoration`, `is_nai` | ITF1788 phases above (every selected case checks the decoration) | conforming for the selected phases; decorated `rootn` with a negative degree can keep a decoration above `trv` (see the [design page](../design/ball_float.md#known-limitations)) |
| §9.7, §12.11 interval and number literals | none | none | not implemented (issue [#21](https://github.com/Luna-Flow/floating/issues/21)) |
| §12.10 accuracy of operations | all `*_interval` operations | ITF1788 strict gate checks containment, not tightness | valid accuracy only; no tightest-result claim beyond the arithmetic operations |
| §12.6 754-conformance of the interval types | endpoints are `BinFloat` | see the `bin_float` clause table | not claimed as a Level 2 type claim |

## Semantic oracle

Expected results are compared by set meaning: endpoint containment, set relations, boolean relations, overlap states, numeric observations, and decorations use operation-specific comparators. A conservative interval may be valid when the contract permits widening; an enclosure that excludes an exact result is never valid.

## Supported phases

The strict matrix covers sets, relations, observations, cancellation, add/subtract/multiply/divide, elementary core, exponential/logarithmic functions, general power, trigonometric functions, `atan2`, hyperbolic functions, inverse trigonometric functions, FMA, integer power, and extrema. Phase operation sets are disjoint so a row is never counted twice.

## Decorations and fallbacks

Empty, Entire, and decorated NaI are separate states. Elementary kernels use directed dyadic certificates. When range reduction cannot be certified, `sin`/`cos` return `[-1,1]` and `tan` returns Entire; that preserves inclusion but does not promise tightness. A passing gate does not cover inputs outside the corpus: the remaining defects listed under [Known limitations](../design/ball_float.md#known-limitations) (the decoration of `rootn` with a negative degree) are not exercised by the selected cases.

## Exclusions

Reverse interval operations, every decoration rule outside the selected phases, arbitrary endpoint formats, and unpinned upstream revisions remain outside the claim.

## Reproduction

```sh
just conformance smoke interval
just conformance fetch interval itf1788
just gate interval 8
```

See [the interval data guide](../../../testdata/interval/README.md) for provenance, phase counts, strict-mode behavior, and failure triage.
