# ball_float conformance

## Claim

The current strict ITF1788 gate executes 6,632/6,632 selected cases with no failed, unsupported, or diagnostic rows. This is a claim about the pinned corpus revision, selected operation phases, and runner precision—not a claim of complete IEEE 1788 implementation.

## Clause traceability

IEEE Std 1788-2015 (set-based flavor) for `ball_float`. Status is `conforming` when the operation exists and the cited evidence exercises it, `partial` when part of the clause is missing or evidence is thin (the cell says which), `not implemented` and `not applicable` otherwise. `Level` is `required` for clauses the standard states with "shall", `recommended` for those it states with "should" (and for the optional parts), `optional` for features a flavor may leave out. Evidence without a corpus name is a unit test in the repository; "no external corpus" marks operations that no independent oracle checks.

| Clause | Level | API | Evidence | Status |
| --- | --- | --- | --- | --- |
| §4.2 set-based interval arithmetic flavor | required | `BallFloat`, `BallFloatDecorated` | ITF1788 strict gate (6,632 cases) | conforming for the selected phases |
| §4.2.2 compressed decorated interval arithmetic | optional | none | none | not implemented |
| §9.1, §10.5.3 forward-mode arithmetic and elementary functions | required | `add`, `sub`, `mul`, `div`, `recip`, `sqr`, `sqrt`, `fma`, `pown`, `pow`, `rootn`, `exp`, `exp2`, `exp10`, `expm1`, `ln`, `log2`, `log10`, `log1p`, `sin`, `cos`, `tan`, `asin`, `acos`, `atan`, `atan2`, `sinh`, `cosh`, `tanh`, `asinh`, `acosh`, `atanh` | ITF1788 phases: add/sub/mul/div 539, elementary core 107, exp/log 131, general power 1,428, trigonometric 176, `atan2` 375, hyperbolic 107, inverse trigonometric 61, FMA 567, integer power 174 | partial: the integer functions of Table 9.1 are not provided ([#257](https://github.com/Luna-Flow/floating/issues/257)); tightness per operation is in [Accuracy of operations](#accuracy-of-operations) |
| §10.5.4 reverse-mode elementary functions | required | `mul_rev`, `sqr_rev`, `abs_rev`, `pown_rev`, `cosh_rev`, `sin_rev`, `cos_rev`, `tan_rev`, `pow_rev1`, `pow_rev2`, `atan2_rev1`, `atan2_rev2` | ITF1788 multiplicative-reverse (`mulRev`, `mulRevTen`), algebraic-reverse (`sqrRev`, `absRev`, `pownRev`, `coshRev`) trigonometric-reverse (`sinRev`, `cosRev`, `tanRev`, and the `Bin` forms) power-reverse-1 (`powRev1`) and power-reverse-2 (`powRev2`) phases, and the generated `atan2-reverse` phase (`atan2Rev1`, `atan2Rev2`: our own cases, 16,260, from `tools/itl_atan2_reverse_oracle.py`, validated by the forward definition; the ITF1788 corpus has none); `library/src/ball_float/mul_rev_wbtest.mbt`, `algebraic_reverse_wbtest.mbt`, `trig_reverse_wbtest.mbt`, `trig_reverse_reference_wbtest.mbt`, `pow_reverse_wbtest.mbt`, `pow_reverse_reference_wbtest.mbt`, `pow_reverse2_wbtest.mbt`, `pow_reverse2_reference_wbtest.mbt`, `atan2_reverse_wbtest.mbt`, `atan2_reverse_reference_wbtest.mbt` | conforming (every reverse function of Table 10.1; the evidence for `atan2Rev1` and `atan2Rev2` is generated, see the design page; issue [#230](https://github.com/Luna-Flow/floating/issues/230)) |
| §10.5.5, §12.12.3 two-output division | required | `mul_rev_to_pair` | ITF1788 multiplicative-reverse phase (`mulRevToPair`, bare and decorated); `library/src/ball_float/mul_rev_wbtest.mbt` | conforming |
| §9.2, §10.5.6 cancellative addition and subtraction | required | `cancel_plus`, `cancel_minus` | ITF1788 cancellation phase (242 cases) | conforming |
| §9.3, §10.5.7 set operations | required | `intersection`, `convex_hull` | ITF1788 sets phase (20 cases) | conforming |
| §9.8, §10.5.8 constructors | required | `from_bounds`, `new`, `exact`, `from_int`, `from_double`, `from_float` | ITF1788 sets phase; `library/src/ball_float/ieee1788_arithmetic_wbtest.mbt` | conforming (`textToInterval` is `from_string`; `exactToInterval` is clause 13.4, below) |
| §9.4, §10.5.9 numeric functions of intervals | required | `lower_bound`, `upper_bound`, `midpoint`, `radius`, `width`, `magnitude`, `mignitude` | ITF1788 numeric observations phase (124 cases; it compares by value, so it says nothing about the sign of a zero); `library/src/ball_float/zero_sign_wbtest.mbt`: the sign of a zero from each function, expected values written out from 12.12.8 | conforming |
| §9.5, §10.5.10 boolean functions of intervals | required | `is_empty`, `is_entire`, `is_singleton`, `is_common_interval`, `is_member`, `==` (`equal`), `subset`, `interior`, `disjoint`, `less`, `precedes`, `strict_less`, `strict_precedes`, `overlap` | ITF1788 relations phase (567 cases); `library/src/ball_float/ieee1788_relations_wbtest.mbt` | conforming |
| §10.6.2 slope functions | recommended | none | none | not implemented |
| §10.6.4 extended interval comparisons | recommended | the `DefinitelyLt`, `DefinitelyLe`, `MaybeEq` and `Overlaps` trait implementations | `library/src/ball_float/ieee1788_relations_wbtest.mbt` | partial |
| §9.6, §11 decoration system | required | `Decoration`, `BallFloatDecorated`, `decoration`, `is_nai` | ITF1788 phases above (every selected case checks the decoration) | conforming for the selected phases; decorated `rootn` with a negative degree can keep a decoration above `trv` (see the [design page](../design/ball_float.md#known-limitations)) |
| §9.7, §12.11, §12.12.7, §13.2 interval and number literals, text input | required | `BallFloat::from_string`, `BallFloatDecorated::from_string`, `BallFloatResult::from_string` | `library/src/ball_float/interval_literal_wbtest.mbt`: the vectors of Tables 9.4 and 12.1, the rejected strings of 9.7.4 and 12.11.4 with the rule named, and a table of 9,919 literals (every form, up to five precisions, exponent fields of 19 to 40 digits, the largest finite number, the first value above it, `EMAX + 1`, the smallest subnormal and the first underflow, `_ill` and NaI literals) whose expected bounds and rejection reasons are written by the independent oracle `tools/interval_literal_oracle.py` | conforming for input; the output (13.3) and the exact text (13.4) are not implemented yet (issue [#21](https://github.com/Luna-Flow/floating/issues/21)) |
| §13.3 interval text output (`intervalToText`) | required | `Show` (`to_string`, `output`) for `BallFloat` and `BallFloatDecorated`; `to_ball_string` is the midpoint-radius view | `library/src/ball_float/interval_text_oracle_wbtest.mbt`: 2,570 intervals (precisions 2 to 1,024, both ends of the exponent range, zero bounds of either sign) whose expected `Show` text and exact text are written by the independent oracle `tools/interval_text_oracle.py` (exact fractions, containment checked there); `interval_text_wbtest.mbt`: written-out texts and 1,500 random intervals read back by `from_string` (consistency only) | conforming for the inf-sup representation; see [Text output](#text-output-and-the-cs-table) for the representations (`cs`) |
| §13.4 exact text (`intervalToExact`, `exactToInterval`) | required | `to_exact_string`, `from_exact_string` for `BallFloat` and `BallFloatDecorated`; the text is read exactly at the bit count of its bounds and never widened (an interval with an end wider than its precision, such as an end of `new` or `cancel_minus`, comes back identical) | `interval_text_oracle_wbtest.mbt`: the exact text of the 2,570 rows, 400 intervals with ends of 1 to 8 bits more than the precision, and 1,620 exact texts (fractional mantissas, leading and trailing zeros, upper case, `0x.8p1`, bounds wider than the precision, both ends of the exponent range and one step beyond, reversed and decimal bounds) read by `from_exact_string` with the verdict and the result written by the oracle (1,406 accepted, 214 refused); `interval_text_wbtest.mbt`: written-out cases | conforming |
| §12.10 accuracy of operations | required | every interval operation | [Accuracy of operations](#accuracy-of-operations): tightness and range per operation; the ITF1788 strict gate compares both endpoints with the corpus's tightest binary64 result | conforming for the provided operations |
| §12.6 754-conformance of the interval types | required | endpoints are `BinFloat` | see the `bin_float` clause table | not implemented (not claimed in 0.12; additive, see [issue 232](https://github.com/Luna-Flow/floating/issues/232): the format of an interval will be an optional `e_max?` with the implementation range as default, and it is not part of `==` or `compare` (only `identical` may look at it)) |

## Text output and the cs table

Clause 13.3 gives `intervalToText` a representation parameter `cs`. What
`ball_float` offers for each:

| representation | function | status |
| --- | --- | --- |
| inf-sup `[l, u]`, bounds as decimal numbers rounded outward | `to_string` (`Show`) | implemented; `[empty]` and `[entire]` for the special values, a decoration after `_` |
| exact text, bounds as hexadecimal numbers (13.4) | `to_exact_string` | implemented; `from_exact_string` recovers the datum |
| uncertain form `m?r` (midpoint and radius in units of the last digit) | none | not planned: the inf-sup form carries the same interval and `from_string` reads both |
| midpoint-radius view `m +/- r` | `to_ball_string` | not a literal of the standard: the binary midpoint and half-width, for reading |

A bound whose binary exponent is beyond 4096 in magnitude is written in
hexadecimal by `to_string`: a decimal expansion would need a power of ten of
that size. The hexadecimal bound is exact and is a valid literal, so the text
still contains the value.

## Accuracy of operations

This is the tightness documentation that §12.10.3 requires, for the inf-sup type
with `p`-bit `BinFloat` endpoints and the binary64 exponent range
(`BallContext::new(precision=p, e_max=1023)`; `p = 53` is the binary64 inf-sup type
of the ITF1788 corpus). *Tightest* means the result is the hull of the exact range in that type
(§12.10.1, (27)); *valid* means it contains the exact range ((26)). No operation
claims the intermediate *accurate* mode. Every operation returns Empty for an
Empty input. The ITF1788 phases cited below compare both endpoints for equality
with the corpus's tightest binary64 result, so a passing phase is tightness
evidence for every case it runs, not only containment.

| Operations | Tightness | Range | Evidence |
| --- | --- | --- | --- |
| `neg`, `add`, `sub`, `mul`, `div`, `recip`, `sqr`, `sqrt`, `fma` | tightest | all inputs | outward rounding of the exact hull ([design](../design/ball_float.md#correctness-and-invariants)); ITF1788 add/sub/mul/div (539), elementary core (107), FMA (567) |
| `abs`, `min`, `max` | tightest | all inputs | design; ITF1788 elementary core and extrema |
| `pown` | tightest | all inputs except a degree below −4096 with 0 inside the input, which gives Entire (valid) | design; ITF1788 integer power (174) |
| `intersection`, `convex_hull` | tightest | all inputs | ITF1788 sets |
| `cancel_plus`, `cancel_minus` | as §12.12.5 requires | all inputs | ITF1788 cancellation (242) |
| `sin`, `cos`, `tan`, `atan`, `atan2`, `pow` | tightest when the endpoint evaluation is certified; valid otherwise | certified unless an endpoint magnitude reaches 2^(max(65536, 4p)+1) (trigonometric reduction) or the refinement budget of 12 work precisions runs out; then `sin`/`cos` give [−1, 1], `tan` Entire, `atan` [−π/2, π/2], `atan2` [−π, π], `pow` [0, +∞), and the `try_*` forms report the failure | design; ITF1788 trigonometric (176), `atan2` (375), general power (1,428), inverse trigonometric (61) |
| `exp`, `exp2`, `exp10`, `ln`, `log2`, `log10`, `asin`, `acos` | tightest when the endpoint evaluation is certified; valid otherwise | certified unless the work budget of the `bin_float` kernel runs out; then `exp`, `exp2`, `exp10` give [0, +∞), the logarithms Entire, `asin` [−π/2, π/2], `acos` [0, π], and the `try_*` forms report the failure | design; ITF1788 exponential/logarithmic (131), inverse trigonometric (61) |
| `sinh`, `cosh`, `tanh`, `asinh`, `acosh`, `atanh` | tightest when the endpoint evaluation is certified; valid otherwise | certified unless the work budget of the `bin_float` kernel runs out; then `sinh`, `asinh`, `atanh` give Entire, `tanh` [−1, 1], `cosh` [1, +∞), `acosh` [0, +∞), and the `try_*` forms report the failure | design; ITF1788 hyperbolic (107) |
| `expm1`, `log1p`, `sinpi`, `cospi`, `tanpi`, `hypot` | tightest when certified; valid otherwise | as for the certified functions above; `expm1` falls back to [−1, +∞), `log1p` to Entire | design; package tests only, no ITF1788 cases |
| `rootn` | tightest when certified; valid otherwise | as for the certified functions above; the fallback is [0, +∞) for an even degree and Entire for an odd one | design; package tests only |

## Corpus values wider than the exact result

IEEE 1788-2015 12.12.4 asks the reverse-mode operations for an enclosure of the Level 1
value, not for the tightest one (the tightest-or-accurate requirement of 12.10 is stated
for the forward operations). Six statements of `libieeep1788_tests_rev.itl`, and their
six decorated copies in the `_dec_` test cases, expect a value that is valid but one or
two units wider than the exact hull in binary64. `ball_float` returns the exact hull, so the
gate does not hold those cases to the corpus value: `testdata/interval/interpreter_refinements.json`
records, for each, the corpus value and the exact value, and the gate requires the result to
equal the exact value, which must lie inside the corpus value. The gate summary reports these
cases on a line of their own. Every other case keeps exact equality with the corpus. The exact
values are computed by `tools/itl_trig_reverse_oracle.py`, which evaluates `asin`, `acos`, `atan`
and $\pi$ with Python's `decimal` and shares no code with `ball_float`; it also confirms that the
other 124 trigonometric reverse statements equal the exact hull.

| Statement | Corpus value | Exact hull | Corpus excess |
| --- | --- | --- | --- |
| `sinRevBin [0x1.FFFFFFFFFFFFFp-1, 1] [1.57, 1.58]` | `[0x1.921fb50442d18p+0, 0x1.921fb58442d1ap+0]` | `[0x1.921fb50442d18p+0, 0x1.921fb58442d19p+0]` | upper end, 1 unit |
| `cosRevBin [-1, -1] [3.14, 3.15]` (the point $\pi$) | `[0x1.921fb54442d18p+1, 0x1.921fb54442d1ap+1]` | `[0x1.921fb54442d18p+1, 0x1.921fb54442d19p+1]` | upper end, 1 unit |
| `cosRevBin [-1, -0x1.FFFFFFFFFFFFFp-1] [3.14, 3.15]` | `[0x1.921fb52442d18p+1, 0x1.921fb56442d1ap+1]` | `[0x1.921fb52442d18p+1, 0x1.921fb56442d19p+1]` | upper end, 1 unit |
| `cosRevBin [-1, -0x1.FFFFFFFFFFFFFp-1] [-3.15, -3.14]` | `[-0x1.921fb56442d1ap+1, -0x1.921fb52442d18p+1]` | `[-0x1.921fb56442d19p+1, -0x1.921fb52442d18p+1]` | lower end, 1 unit |
| `tanRevBin [0x1.D02967C31CDB4p+53, 0x1.D02967C31CDB5p+53] [-1.5708, 1.5708]` | `[-0x1.921fb54442d1bp+0, 0x1.921fb54442d19p+0]` | `[-0x1.921fb54442d19p+0, 0x1.921fb54442d19p+0]` | lower end, 2 units |
| `tanRevBin [0x1.72CECE675D1FCp-52, 0x1.72CECE675D1FDp-52] [-3.15, 3.15]` | `[-0x1.921fb54442d19p+1, 0x1.921fb54442d1ap+1]` | `[-0x1.921fb54442d18p+1, 0x1.921fb54442d1ap+1]` | lower end, 1 unit |

Whether to report the six values to the corpus's authors is left to the maintainer.

## Semantic oracle

Expected results are compared by set meaning: endpoint containment, set relations, boolean relations, overlap states, numeric observations, and decorations use operation-specific comparators. A conservative interval may be valid when the contract permits widening; an enclosure that excludes an exact result is never valid.

## Supported phases

The strict matrix covers sets, relations, observations, cancellation, add/subtract/multiply/divide, elementary core, exponential/logarithmic functions, general power, trigonometric functions, `atan2`, hyperbolic functions, inverse trigonometric functions, FMA, integer power, extrema, the integer functions, reverse multiplication (`mulRev`, `mulRevTen`, `mulRevToPair`), the algebraic reverse functions (`sqrRev`, `absRev`, `pownRev`, `coshRev`), the trigonometric reverse functions (`sinRev`, `cosRev`, `tanRev`), `powRev1` and `powRev2` (the generated `atan2Rev1` and `atan2Rev2` cases are a phase of their own and are not part of the ITF1788 count). Phase operation sets are disjoint so a row is never counted twice.

## Decorations and fallbacks

Empty, Entire, and decorated NaI are separate states. Elementary kernels use directed dyadic certificates. When range reduction cannot be certified, `sin`/`cos` return `[-1,1]` and `tan` returns Entire; that preserves inclusion but does not promise tightness. A passing gate does not cover inputs outside the corpus: the remaining defects listed under [Known limitations](../design/ball_float.md#known-limitations) (the decoration of `rootn` with a negative degree) are not exercised by the selected cases.

## Exclusions

Reverse interval operations other than `mulRev`, `mulRevToPair`, `sqrRev`, `absRev`, `pownRev`, `coshRev`, `sinRev`, `cosRev`, `tanRev`, `powRev1`, `powRev2`, `atan2Rev1` and `atan2Rev2`, every decoration rule outside the selected phases, arbitrary endpoint formats, and unpinned upstream revisions remain outside the claim.

## Reproduction

```sh
just conformance smoke interval
just conformance fetch interval itf1788
just gate interval 8
```

See [the interval data guide](../../../testdata/interval/README.md) for provenance, phase counts, strict-mode behavior, and failure triage.
