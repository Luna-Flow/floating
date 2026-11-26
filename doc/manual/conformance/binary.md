# binary conformance

The `floating` programming environment conforms to IEEE 754-2019 in radix two, through its
`binary` package: binary16, binary32, binary64, and binary128 are each a supported arithmetic
format and a supported interchange format, the condition of IEEE 754-2019 3.1.2. This page
records finite results for named corpora, inputs, and contexts, together with the cases they
do not cover.

## Normative and research sources

- IEEE, *IEEE Standard for Floating-Point Arithmetic*, IEEE 754-2019:
  interchange formats, rounding-direction attributes, NaNs, infinities, signed zeros,
  exceptions, and tininess detection.
- S. Fousse, G. Hanrot, V. Lefèvre, P. Pélissier, and P. Zimmermann,
[MPFR: A Multiple-Precision Binary Floating-Point Library with Correct
  Rounding](https://doi.org/10.1145/1236463.1236468), ACM TOMS 33(2), 2007. MPFR supplies the
  exact-result-then-one-rounding model used for arbitrary precisions.
- John Hauser's Berkeley [SoftFloat](https://www.jhauser.us/arithmetic/SoftFloat.html)
  and [TestFloat](https://www.jhauser.us/arithmetic/TestFloat.html), release 3e, provide
  independently generated IEEE result and flag vectors.

## Mathematical model

A finite, nonzero `Binary` denotes the dyadic real

$$(-1)^s c 2^q,$$

where $s$ is 1 for a negative value and 0 otherwise, $c$ is the non-negative `coefficient`
represented by `BinCoeff`, and $q$ is its `exponent2`. The finite coefficient is normalized
by removing factors of two.
The sign of zero remains observable. Infinity, qNaN, sNaN, NaN payload, and NaN sign are
explicit states rather than sentinel finite values.

For `add_ctx`, `sub_ctx`, `mul_ctx`, `div_ctx`, `sqrt_ctx`, and `pown_ctx`, the contextual
operations follow this sequence:

1. Resolve IEEE special cases before finite arithmetic.
2. Compute the exact finite result. Addition, subtraction, and multiplication use exact
dyadic arithmetic; division uses an exact integer quotient/remainder decision; square root
uses an exact integer square root and an exact comparison with the rounding midpoint. Integer
powers certify a directed enclosure with a Ziv loop and use the exact power if certification
does not succeed.
3. Round the exact result once, in the requested direction, directly to the coarser of the
precision grid and the subnormal grid of the exponent range. This avoids double rounding;
overflow is decided from the rounded value.
4. Derive `BinaryFlags` from the mathematical result: inexact, underflow, overflow,
division-by-zero, and invalid-operation.

This order matters. For example, binary16 `0x0400 * 0x3BFF` produces `0x0400` with `inexact | underflow`.
After-rounding tininess is determined from the precision-rounded unbounded value, not only
from the final normal interchange encoding.

The corpus interpreter calls the public contextual operations. It does not branch on test
identifiers, test values, or corpus format.

## Interchange and context

`BinaryInterchange` decodes and encodes IEEE binary16, binary32, binary64, and binary128 bit
patterns. `BinaryContext` carries precision, rounding direction, paired exponent limits, and
before- or after-rounding tininess detection. Encoding and contextual arithmetic return
status flags. Ordinary operators use a nearest-even context determined by their precision
alone and intentionally do not expose those flags.

In the TestFloat adapter, results are compared by class only when the expected result is a
NaN. Non-NaN encoded bits and all exception bits must match exactly. The class comparison
reflects IEEE's permitted choice of a newly generated NaN payload. The implementation itself
preserves the selected input NaN's sign and payload and quiets signaling NaNs.

## Clause traceability

This table maps IEEE 754-2019 clauses, cited by bare number, to the `binary` API and to the
evidence that supports each status. A row is `conforming` when the operation exists and the
cited evidence exercises it. It is `partial` when part of the clause is missing or the
evidence is thin (the cell says which); `not implemented` and `not applicable` have their
ordinary meanings. The `Level` column is `required` for clauses stated with “shall”,
`recommended` for those stated with “should” and for the optional parts, and `optional` for
features a format may omit. Evidence without a corpus name is a unit test in the repository;
“no external corpus” marks operations that no independent oracle checks.

| Clause | Level | API | Evidence | Status |
| --- | --- | --- | --- | --- |
| 3.3 to 3.6 binary16/32/64/128 interchange formats | required | `Binary::to_interchange`, `BinaryInterchange::from_bits` | TestFloat gate; `library/src/binary/ieee754_wbtest.mbt` | conforming |
| 3.7 extendable precisions | recommended | `BinaryContext::new` (precision alone) | MPFR elementary fixture; `library/src/binary/exponent_range_wbtest.mbt` | conforming |
| 4.3 rounding-direction attributes | required | `BinaryRoundingMode` | TestFloat gate (five directions) | conforming; no other mode exists |
| 5.3.1 addition, subtraction, multiplication, division, squareRoot | required | `add_ctx`, `sub_ctx`, `mul_ctx`, `div_ctx`, `sqrt_ctx` | TestFloat gate (7,461,360 vectors); `library/src/binary/ieee754_wbtest.mbt` | conforming |
| 5.3.1 fusedMultiplyAdd | required | `fma_ctx` | TestFloat gate (245,329,920 mulAdd vectors); `library/src/binary/fma_wbtest.mbt` | conforming |
| 5.3.1 remainder | required | `remainder_ctx` | TestFloat gate (rem); `library/src/binary/remainder_wbtest.mbt` | conforming |
| 5.3.1, 5.9 roundToIntegral (five directions, exact) | required | `to_integral_value_ctx`, `to_integral_exact_ctx`, `floor`, `ceil`, `trunc`, `round`, `round_ties_to_even` | TestFloat gate (roundToInt, exact and inexact); `library/src/binary/integral_wbtest.mbt` | conforming |
| 5.3.1 nextUp, nextDown | required | `next_up_ctx`, `next_down_ctx` | `library/src/binary/next_wbtest.mbt` (no external corpus) | conforming |
| 5.3.1 scaleB, logB | required | `scaleb_ctx`, `logb_ctx` | `library/src/binary/scale_wbtest.mbt` (no external corpus) | conforming |
| 5.4.1 convertFromInt | required | `Binary::from_int`, `Binary::from_coefficient` with `BinCoeff::from_uint64` | `library/src/binary/order_wbtest.mbt` (no external corpus) | conforming |
| 5.4.1, 5.8 convertToInteger (exact and inexact) | required | `to_int_ctx`, `to_int64_ctx`, `to_uint_ctx`, `to_uint64_ctx` | TestFloat gate (32- and 64-bit conversions); `library/src/binary/to_integer_wbtest.mbt` | conforming |
| 5.4.2 convertFormat | required | `convert_format`, `apply_ctx`, `with_precision`, `to_interchange` | TestFloat conversion matrix and package tests; see [convertFormat evidence](#convertformat-evidence) | conforming |
| 5.5 copy, negate, abs, copySign | required | `neg`, `abs`, `copy_sign` | `library/src/binary/order_wbtest.mbt` | conforming |
| 5.6, 5.11 comparison predicates, quiet and signaling | required | Predicate set in Tables 5.1 and 5.2; see [comparison-predicate evidence](#comparison-predicate-evidence) | Predicate and TestFloat checks; see [comparison-predicate evidence](#comparison-predicate-evidence) | conforming |
| 5.7 class and sign predicates | required | `class_of`, `is_normal`, `is_subnormal`, `is_finite`, `is_infinite`, `is_nan`, `classify`, `is_sign_minus`, `is_zero`, `is_signaling_nan` | Class and contextual-trait tests; see [class-predicate evidence](#class-predicate-evidence) | conforming |
| 5.10 totalOrder, totalOrderMag | required | `total_order`, `total_order_mag`, `total_order_compare` | `library/src/binary/order_wbtest.mbt` (no external corpus) | conforming |
| 5.12 decimal character conversion, both directions | required | `from_string_ctx`, `to_decimal_string_ctx`, `to_shortest_string` | MPFR `mpfr_strtofr` corpus (3,699 rows) and `mpfr_get_str` corpus (2,688 rows); `library/src/binary/decimal_string_wbtest.mbt` | conforming |
| 5.12 hexadecimal character conversion | required | `from_hex`, `from_hex_ctx`, `to_hex` | Grammar, round-trip, and rational-arithmetic tests; see [hexadecimal-conversion evidence](#hexadecimal-conversion-evidence) | conforming |
| 6.1 to 6.3 infinities, NaNs, sign bit | required | every `*_ctx` operation | TestFloat gate (a NaN result is compared by class only); `library/src/binary/compare_nan_wbtest.mbt` | conforming; payload choice in [Implementation-defined choices](../verification.md#implementation-defined-choices) |
| 7.2 to 7.6 exceptions and default handling | required | `BinaryFlags` returned by every `*_ctx` operation | TestFloat gate (exact flag bits, both tininess modes) | conforming |
| 7.5 tininess detection | required | `TininessDetection` | TestFloat gate (before and after rounding); the exact-subnormal and range-limit cases of `exp2`, `pow` and `pown` in [mathematical-function evidence](#mathematical-function-evidence) | conforming |
| 8 alternate exception handling | recommended | none | none | not implemented (flags are values; no traps, no resumption) |
| 9.2 recommended mathematical functions | recommended | The functions listed in [mathematical-function evidence](#mathematical-function-evidence), in contextual (`*_ctx`) and `try_*_ctx` forms | MPFR fixture and targeted tests; see [mathematical-function evidence](#mathematical-function-evidence) | conforming |
| 9.3 dynamic mode operations | recommended (required only where a language defines dynamic modes) | none (contexts are explicit values) | none | not implemented by design |
| 9.4 reduction operations | recommended | none | none | not implemented |
| 9.5 augmented arithmetic | recommended | none | none | not implemented |
| 9.6 minimum, maximum and magnitude variants | recommended | none (`Binary::min_num` and `Binary::max_num` are plain helpers) | none | not implemented |
| 9.7 NaN payload operations | recommended | `nan_payload`, `quiet_nan(payload~)`, `signaling_nan(payload~)` | `library/src/binary/order_wbtest.mbt`; no getPayload/setPayload pair | partial |

### convertFormat evidence

TestFloat covers `f16`, `f32`, `f64`, and `f128` converted to every other format: 52,632
level-1 vectors with five rounding directions and both tininess rules for narrowing pairs.
Package tests are `library/src/binary/convert_format_wbtest.mbt` and
`library/src/binary/ieee754_wbtest.mbt`.

### Comparison-predicate evidence

The API comprises `compare_quiet`, `compare_signaling`, `compare_quiet_equal`,
`compare_signaling_equal`, `compare_quiet_less`, `compare_signaling_less`,
`compare_quiet_less_equal`, `compare_signaling_less_equal`, `compare_quiet_unordered`, and
the fifteen predicates in `order_predicates.mbt`, 22 in all, as listed in Tables 5.1 and
5.2. `library/src/binary/order_predicates_wbtest.mbt` tests every predicate against every
relation, value, and flags. The TestFloat gate covers eq, le, lt, eq_signaling, le_quiet,
and lt_quiet; `library/src/binary/order_wbtest.mbt` provides additional package tests.

### Class-predicate evidence

`library/src/binary/class_of_wbtest.mbt` tests all ten classes in binary16, binary32,
binary64, and binary128, including the smallest and largest subnormal and normal values in
both signs. `library/src/binary/contextual_traits_wbtest.mbt` covers contextual traits.

### Hexadecimal-conversion evidence

`library/src/binary/hex_grammar_wbtest.mbt` tests every production of the IEEE 754-2019 5.12.3 grammar
and the 5.12.1 words, accepted and rejected, through both entry points, and checks a 4,000-value
round trip. The `from_hex_ctx` tests contain 5,095 rows across all five rounding directions,
both tininess rules, binary16, binary32, binary64, binary128, two toy formats, and the
implementation range. They cover midpoints, subnormals, and the overflow threshold against
exact rational arithmetic in `library/src/binary/hex_ctx_wbtest.mbt` and
`hex_ctx_rows_wbtest.mbt`; `tools/generate_hex_ctx_rows.py` generates the rows.

### Mathematical-function evidence

IEEE 754-2019 9.2 functions covered are `exp`, `exp2`, `exp10`, `expm1`, `exp2m1`,
`exp10m1`, `ln`, `log2`, `log10`, `log1p`, `log2p1`, `log10p1`, `hypot`, `rsqrt`, `rootn`,
`pown`, `compound`, `pow`, `powr`, `sin`, `cos`, `tan`, `sinpi`, `cospi`, `tanpi`, `asin`,
`acos`, `atan`, `atan2`, `asinpi`, `acospi`, `atanpi`, `atan2pi`, `sinh`, `cosh`, `tanh`,
`asinh`, `acosh`, and `atanh`, through their `*_ctx` and `try_*_ctx` forms. The MPFR
elementary fixture (1,740 rows) is the corpus evidence. The package tests include
`library/src/binary/elementary_certified_wbtest.mbt` and
`library/src/binary/tanh_saturation_issue185_wbtest.mbt`.

Tests of range-limit decisions cover exact subnormal powers of two for `exp2` and `pow`,
`pown` tininess, the `expm1` overflow window, and all elementary exponentials against an
independent reference. The tests are `library/src/binary/exp2_subnormal_wbtest.mbt`,
`pow_exact_subnormal_wbtest.mbt`, `pown_subnormal_tininess_wbtest.mbt`,
`expm1_overflow_window_wbtest.mbt`, and `underflow_siblings_wbtest.mbt`.

The `exp2m1`, `exp10m1`, `log2p1`, and `log10p1` tests cover special values of IEEE 754-2019 9.2.1, exact
cases, and thresholds in `library/src/binary/pm1_functions_wbtest.mbt`. The `rsqrt`,
`compound`, and `powr` tests cover special values of IEEE 754-2019 9.2.1, exact cases, the tiny-argument
rule, and agreement with `pow` in `library/src/binary/rsqrt_compound_powr_wbtest.mbt`. The
`asinpi`, `acospi`, `atanpi`, and `atan2pi` tests cover special values and exact constants
of IEEE 754-2019 9.2.1; anchors at ±1/2 and ±1 for huge, tiny, and extreme-ratio arguments; tiny arguments
at the implementation subnormal limit; and agreement with the result at p + 150. They are in
`library/src/binary/pi_inverse_wbtest.mbt`. The corresponding range-boundary sweep uses six contexts. It covers underflow thresholds,
the anchors ±1/2 and ±1 for huge and tiny arguments and extreme ratios, and inputs next to
±1. `atan2pi` rows whose operands differ by more than 100,000 binades are not oracle rows
(MPFR is too slow). Seeded random and targeted boundary campaigns are listed in the corpus
table.

## Declared corpus and results

The full pinned gate is defined in
[`testdata/binary/README.md`](../../../testdata/binary/README.md). The table records each
source, its scope, and the passed rows.

| Source | Scope | Result |
| --- | --- | --- |
| TestFloat 3e level 1, seed 1 | 4 formats × 5 arithmetic operations × 5 rounding directions × 2 tininess modes | 7,461,360 / 7,461,360 |
| TestFloat 3e level 1, seed 1 | 4 formats × mulAdd (5 directions × 2 tininess modes), rem, roundToInt and four integer conversions (5 directions × exact/inexact variants), six comparison predicates | 246,766,512 / 246,766,512 |
| MPFR 4.2.2 `tests/data/sqrt` | all executable hexadecimal sqrt rows | 1,055 / 1,055 |
| MPFR 4.2.2 `pow_si` fixture | 4 precisions × 4 supported roundings × 6 inputs | 96 / 96 |
| MPFR 4.2.2 elementary fixture | 29 operations × 3 precisions × 5 roundings × 4 fixed-seed inputs | 1,740 / 1,740 |
| MPFR 4.2.2 `mpfr_strtofr` fixture | decimal text to binary: 5 precisions (11 to 200 bits) × 5 roundings × random, long-mantissa, huge-exponent, exact-halfway and one-unit-off-halfway literals, plus range limits and signed zeros | 3,699 / 3,699 |
| MPFR 4.2.2 `mpfr_get_str` fixture | binary to decimal: 2,448 fixed-digit rows (5 precisions × 5 roundings × 10 digit counts × up to 12 fixed-seed values per cell, exponents up to ±20,000) and 240 shortest round-trip digit-count rows | 2,688 / 2,688 |
| Optional MPFR elementary stress, seed 20260715 | at least 100,000 cases per three-operation-or-larger family | 966,744 / 966,744 |
| Seeded random elementary (`elem`), seeds 20261118 and 20261201 | 29 functions, contexts given by the precision alone, precisions 2 to 700, all rounding directions | 2,000,000 / 2,000,000 |
| Range-boundary sweep (`tools/range_boundary_rows.py`) | `exp`, `exp2`, `exp10`, `expm1`, `pow`, `pown`, `rootn` on the underflow and overflow thresholds, precisions 2 to 300, six contexts, both tininess rules | 1,269,554 / 1,269,554 |
| Seeded random elementary (`elem2`: `exp2m1`, `exp10m1`, `log2p1`, `log10p1`), seed 20261118 | contexts given by the precision alone, precisions 2 to 700, all rounding directions; 1,000,000 cases on native, 100,000 on Wasm, JavaScript and Wasm-GC | 1,300,000 / 1,300,000 |
| Range-boundary sweep of `exp2m1`, `exp10m1`, `log2p1`, and `log10p1` | precisions 2 to 300, six contexts, overflow, saturation and tiny-result thresholds | 303,108 / 303,108 |
| Seeded random elementary (`elem3`: `rsqrt`, `compound`, `powr`), seed 20261118 | contexts given by the precision alone, precisions 2 to 700, all rounding directions; 1,000,000 cases on native, 100,000 on Wasm, JavaScript and Wasm-GC | 1,300,000 / 1,300,000 |
| Range-boundary sweep of `rsqrt`, `compound`, and `powr` | precisions 2 to 300, six contexts, overflow and tiny-result thresholds; the `compound` rows use the exact rational in place of `mpfr_compound_si` (see the oracle defect in `verification.md`) | 718,824 / 718,824 |
| Seeded random elementary (`elem4`: `asinpi`, `acospi`, `atanpi`, `atan2pi`), seed 20261118 | contexts given by the precision alone, precisions 2 to 700, all rounding directions; 1,000,000 cases on native, 100,000 on Wasm, JavaScript and Wasm-GC | 1,300,000 / 1,300,000 |
| Range-boundary sweep of `asinpi`, `acospi`, `atanpi`, and `atan2pi` | precisions 2 to 300, six contexts; see mathematical-function evidence | 1,654,315 / 1,654,315 |
| Committed smoke | TestFloat, sqrt, `pow_si`, elementary, `strtofr` and decimal output witnesses | 8,514 / 8,514 |
| TestFloat 3e level 2 | binary16, all declared operations/directions/tininess modes | 50,205,600 / 50,205,600 |

Two table rows are optional and are not included in the result claim of this page:

- The TestFloat level-2 result is for binary16. It is additional streaming stress evidence,
  not a claim for the much larger binary32, binary64, and binary128 level-2 suites. The
  runner streams level 2 in verified bounded chunks, and level 2 is an optional stress
  suite.
- The 966,744-row MPFR run is optional generated stress evidence; the 1,740-row hash-pinned fixture remains the reproducible release boundary.

The archives, files, and digests are pinned in
[`testdata/binary/corpora.json`](../../../testdata/binary/corpora.json).

## Scope of the claim

The finite claim covers these contextual operations and inputs:

- add, subtract, multiply, divide, square root, fused multiply-add, remainder,
and roundToIntegral (plain and exact);
- signed and unsigned 32- and 64-bit convertToInteger (plain and exact);
- convertFormat among the four interchange formats, as specified by
IEEE 754-2019 5.4.2;
- quiet and signaling equal, less, and less-or-equal predicates for the four
interchange formats and the stated rounding directions and tininess rules;
- the 29 operations in the MPFR elementary fixture (28 functions from IEEE
754-2019 9.2 and `sqrt`) at 24, 53, and 113 bits under all five rounding directions; and
- the other 11 functions in the 9.2 row, through the seeded random and
range-boundary rows above.

Invalid integer conversions are compared by flags only: SoftFloat returns platform-specific
sentinels where the API returns `None`. The page makes no TestFloat conformance claim for
min/max (not implemented as the operations of IEEE 754-2019 9.6), total ordering,
nextUp/nextDown, or scaleB/logB; package tests cover total ordering, nextUp/nextDown,
and scaleB/logB. TestFloat has no
decimal-character corpus, so `convertFromDecimalCharacter` and `convertToDecimalCharacter`
are checked against the MPFR `mpfr_strtofr` and `mpfr_get_str` fixtures (3,699 and 2,688
rows) and by package tests. The finite evidence does not cover every IEEE 754 operation or
every real input.

The elementary generator implements nearest-away through MPFR's required
`mpfr_round_nearest_away_begin/end` protocol. It never passes the explicitly forbidden
`MPFR_RNDNA` value to a general elementary function.

The fixed-seed elementary inputs are dyadic multiples of $2^{-8}$ with magnitude at most 16
and lie inside each function's domain. `pow` takes a positive base and an exponent in $[-3,
3]$; `rootn` takes an odd degree from 3 to 7; `atan2` never takes two zeros; and `tanpi`
takes no integral or half-integral argument. A zero input is $+0$. The 1,740-row fixture
therefore does not exercise tiny or huge arguments, $-0$, infinities, NaNs, negative bases
of `pow`, negative degrees of `rootn`, or the poles and signed zeros of the IEEE
special-case tables. Exact results such as $4^{3/2}$ occur only by chance. The package's
unit tests cover those special-value cases against the special-value tables in the
[API reference](../api/binary.md#elementary-functions); they are outside this finite claim. The seeded random and
range-boundary rows above do exercise tiny and huge arguments and the overflow and underflow
thresholds.

## Stability of the evidence

The pinned matrix is the release evidence boundary. Adding a new operation requires a new
corpus contract and an independent oracle. Run `just conformance smoke binary` for the
checked-in gate and `just gate binary` for the full pinned gate.
