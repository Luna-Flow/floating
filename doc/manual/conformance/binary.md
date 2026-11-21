# binary conformance

This page records the binary floating-point semantic and test boundary of
the current source (the `Unreleased` section of the changelog). It is evidence for a stated, finite corpus; it is not a proof that
any implementation can be correct for every real input.

## Normative and research sources

- IEEE, *IEEE Standard for Floating-Point Arithmetic*, IEEE 754-2019:
  interchange formats, rounding-direction attributes, NaNs/infinities/signed
  zeros, exceptions, and tininess detection.
- S. Fousse, G. Hanrot, V. Lefèvre, P. Pélissier, and P. Zimmermann,
  [MPFR: A Multiple-Precision Binary Floating-Point Library with Correct Rounding](https://doi.org/10.1145/1236463.1236468),
  ACM TOMS 33(2), 2007. MPFR supplies the exact-result-then-one-rounding model
  used for arbitrary precisions.
- John Hauser's Berkeley [SoftFloat](https://www.jhauser.us/arithmetic/SoftFloat.html)
  and [TestFloat](https://www.jhauser.us/arithmetic/TestFloat.html), release
  3e, provide the independently generated IEEE result/flag vectors.

## Mathematical model

A finite nonzero `Binary` denotes the dyadic real

`(-1)^negative * coefficient * 2^exponent2`, where `coefficient` is a
non-negative `BinCoeff`.

The finite coefficient is normalized by removing factors of two, while the
sign of zero remains observable. Infinity, qNaN, sNaN, NaN payload, and NaN
sign are explicit states rather than sentinel finite values.

For `add_ctx`, `sub_ctx`, `mul_ctx`, `div_ctx`, `sqrt_ctx`, and `pown_ctx`:

1. IEEE special cases are resolved before finite arithmetic.
2. Finite addition, subtraction, and multiplication use their exact dyadic
   result; division uses an exact integer quotient/remainder decision; square
   root uses an exact integer square root and an exact comparison with the
   rounding midpoint; integer powers certify a directed enclosure (Ziv loop)
   and fall back to the exact power when certification does not succeed.
3. The exact result is rounded once, in the requested direction, directly to
   the coarser of the precision grid and the subnormal grid of the exponent
   range (no double rounding); overflow is then decided on the rounded value.
4. The returned `BinaryFlags` is derived from that mathematical result:
   inexact, underflow, overflow, division-by-zero, and invalid-operation.

This order matters. For example, binary16 `0x0400 * 0x3BFF` produces
`0x0400` with `inexact | underflow`; after-rounding tininess is determined from
the precision-rounded unbounded value, not merely from the final normal
interchange encoding.

No operation branches on test identifiers, test values, or corpus format.
The corpus interpreter is an adapter around the public contextual operations.

## Interchange and context

`BinaryInterchange` decodes and encodes IEEE binary16, binary32, binary64, and
binary128 bit patterns. `BinaryContext` carries precision, rounding direction,
paired exponent limits, and before/after tininess detection. Encoding and
contextual arithmetic both return status flags; ordinary operators use an
unbounded nearest-even context and intentionally do not expose those flags.

NaN comparisons in the TestFloat adapter are class-based only when an expected
result is NaN. This is not a weakened finite-value comparison: non-NaN encoded
bits and all exception bits must match exactly. It reflects IEEE's permitted
choice of a newly generated NaN payload. The implementation itself preserves
the selected input NaN's sign/payload and quiets signaling NaNs.

## Clause traceability

IEEE Std 754-2019 for `binary`. Status is `conforming` when the operation exists and the cited evidence exercises it, `partial` when part of the clause is missing or evidence is thin (the cell says which), `not implemented` and `not applicable` otherwise. `Level` is `required` for clauses the standard states with "shall", `recommended` for those it states with "should" (and for the optional parts), `optional` for features a flavor may leave out. Evidence without a corpus name is a unit test in the repository; "no external corpus" marks operations that no independent oracle checks.

| Clause | Level | API | Evidence | Status |
| --- | --- | --- | --- | --- |
| §3.3–§3.6 binary16/32/64/128 interchange formats | required | `Binary::to_interchange`, `Binary::from_bits` | TestFloat gate; `library/src/binary/ieee754_wbtest.mbt` | conforming |
| §3.7 extendable precisions | recommended | `BinaryContext::new` (precision alone) | MPFR elementary fixture; `library/src/binary/exponent_range_wbtest.mbt` | conforming |
| §4.3 rounding-direction attributes | required | `BinaryRoundingMode` | TestFloat gate (five directions) | conforming; no other mode exists |
| §5.3.1 addition, subtraction, multiplication, division, squareRoot | required | `add_ctx`, `sub_ctx`, `mul_ctx`, `div_ctx`, `sqrt_ctx` | TestFloat gate (7,461,360 vectors); `library/src/binary/ieee754_wbtest.mbt` | conforming |
| §5.3.1 fusedMultiplyAdd | required | `fma_ctx` | TestFloat gate (245,329,920 mulAdd vectors); `library/src/binary/fma_wbtest.mbt` | conforming |
| §5.3.1 remainder | required | `remainder_ctx` | TestFloat gate (rem); `library/src/binary/remainder_wbtest.mbt` | conforming |
| §5.3.1, §5.9 roundToIntegral (five directions, exact) | required | `to_integral_value_ctx`, `to_integral_exact_ctx`, `floor`, `ceil`, `trunc`, `round`, `round_ties_to_even` | TestFloat gate (roundToInt, exact and inexact); `library/src/binary/integral_wbtest.mbt` | conforming |
| §5.3.1 nextUp, nextDown | required | `next_up_ctx`, `next_down_ctx` | `library/src/binary/next_wbtest.mbt` (no external corpus) | conforming |
| §5.3.1 scaleB, logB | required | `scaleb_ctx`, `logb_ctx` | `library/src/binary/scale_wbtest.mbt` (no external corpus) | conforming |
| §5.4.1 convertFromInt | required | `Binary::from_int`, `Binary::from_uint64` | `library/src/binary/order_wbtest.mbt` (no external corpus) | conforming |
| §5.4.1, §5.8 convertToInteger (exact and inexact) | required | `to_int_ctx`, `to_int64_ctx`, `to_uint_ctx`, `to_uint64_ctx` | TestFloat gate (32- and 64-bit conversions); `library/src/binary/to_integer_wbtest.mbt` | conforming |
| §5.4.2 convertFormat | required | `convert_format`, `apply_ctx`, `with_precision`, `to_interchange` | TestFloat gate (`f16`, `f32`, `f64`, `f128` to every other format, 52,632 vectors at level 1: five rounding modes and both tininess rules for the narrowing pairs); `library/src/binary/convert_format_wbtest.mbt`; `library/src/binary/ieee754_wbtest.mbt` | conforming |
| §5.5 copy, negate, abs, copySign | required | `neg`, `abs`, `copy_sign` | `library/src/binary/order_wbtest.mbt` | conforming |
| §5.6, §5.11 comparison predicates, quiet and signaling | required | `compare_quiet`, `compare_signaling`, `compare_quiet_equal`, `compare_signaling_equal`, `compare_quiet_less`, `compare_signaling_less`, `compare_quiet_less_equal`, `compare_signaling_less_equal`, `compare_quiet_unordered` and the fifteen of `order_predicates.mbt` (22 in all, Tables 5.1 and 5.2) | `library/src/binary/order_predicates_wbtest.mbt` (every predicate against every relation, value and flags); TestFloat gate (eq, le, lt, eq_signaling, le_quiet, lt_quiet); `library/src/binary/order_wbtest.mbt` | conforming |
| §5.7 class and sign predicates | required | `class_of`, `is_normal`, `is_subnormal`, `is_finite`, `is_infinite`, `is_nan`, `classify`, `is_sign_minus`, `is_zero`, `is_signaling_nan` | `library/src/binary/class_of_wbtest.mbt` (all ten classes in binary16, 32, 64 and 128, with the smallest and largest subnormal and normal, both signs); `library/src/binary/contextual_traits_wbtest.mbt` | conforming |
| §5.10 totalOrder, totalOrderMag | required | `total_order`, `total_order_mag`, `total_order_compare` | `library/src/binary/order_wbtest.mbt` (no external corpus) | conforming |
| §5.12 decimal character conversion, both directions | required | `from_string_ctx`, `to_decimal_string_ctx`, `to_shortest_string` | MPFR `mpfr_strtofr` corpus (3,699 rows) and `mpfr_get_str` corpus (2,688 rows); `library/src/binary/decimal_string_wbtest.mbt` | conforming |
| §5.12 hexadecimal character conversion | required | `from_hex`, `from_hex_ctx`, `to_hex` | every production of the §5.12.3 grammar and the §5.12.1 words, accepted and rejected, through both entry points, and a 4,000-value round trip in `library/src/binary/hex_grammar_wbtest.mbt`; 4,554 rows of `from_hex_ctx` (all six rounding directions, both tininess rules, binary16, 32, 64, 128, two toy formats and the implementation range, the midpoints, subnormals and the overflow threshold) against exact rational arithmetic in `library/src/binary/hex_ctx_wbtest.mbt` and `hex_ctx_rows_wbtest.mbt` (generator `tools/generate_hex_ctx_rows.py`) | conforming |
| §6.1–§6.3 infinities, NaNs, sign bit | required | every `*_ctx` operation | TestFloat gate (a NaN result is compared by class only); `library/src/binary/compare_nan_wbtest.mbt` | conforming; payload choice in [Implementation-defined choices](../verification.md#implementation-defined-choices) |
| §7.2–§7.6 exceptions and default handling | required | `BinaryFlags` returned by every `*_ctx` operation | TestFloat gate (exact flag bits, both tininess modes) | conforming |
| §7.5 tininess detection | required | `TininessDetection` | TestFloat gate (before and after rounding); the exact-subnormal and range-limit cases of `exp2`, `pow` and `pown` above | conforming |
| §8 alternate exception handling | recommended | none | none | not implemented (flags are values; no traps, no resumption) |
| §9.2 recommended mathematical functions | recommended | `exp`, `exp2`, `exp10`, `expm1`, `exp2m1`, `exp10m1`, `ln`, `log2`, `log10`, `log1p`, `log2p1`, `log10p1`, `hypot`, `rsqrt`, `rootn`, `pown`, `compound`, `pow`, `powr`, `sin`, `cos`, `tan`, `sinpi`, `cospi`, `tanpi`, `asin`, `acos`, `atan`, `atan2`, `asinpi`, `acospi`, `atanpi`, `atan2pi`, `sinh`, `cosh`, `tanh`, `asinh`, `acosh`, `atanh` (`*_ctx`, `try_*_ctx`) | MPFR elementary fixture (1,740 rows); `library/src/binary/elementary_certified_wbtest.mbt`; `library/src/binary/tanh_saturation_issue185_wbtest.mbt`; underflow and overflow decisions at the range limits (`exp2` and `pow` exact subnormal powers of two, `pown` tininess, `expm1` overflow window, all elementary exponentials against an independent reference): `library/src/binary/exp2_subnormal_wbtest.mbt`, `pow_exact_subnormal_wbtest.mbt`, `pown_subnormal_tininess_wbtest.mbt`, `expm1_overflow_window_wbtest.mbt`, `underflow_siblings_wbtest.mbt`; `exp2m1`, `exp10m1`, `log2p1`, `log10p1` (special values of §9.2.1, exact cases, thresholds): `library/src/binary/pm1_functions_wbtest.mbt`; `rsqrt`, `compound`, `powr` (special values of §9.2.1, exact cases, tiny-argument rule, `pow` agreement): `library/src/binary/rsqrt_compound_powr_wbtest.mbt`; `asinpi`, `acospi`, `atanpi`, `atan2pi` (special values and exact constants of §9.2.1, anchors at ±1/2 and ±1 for huge, tiny and extreme-ratio arguments, tiny arguments at the implementation subnormal limit, agreement with the result at p + 150): `library/src/binary/pi_inverse_wbtest.mbt`; seeded random and targeted boundary campaigns (results below) | conforming |
| §9.3 dynamic mode operations | recommended (required only where a language defines dynamic modes) | none (contexts are explicit values) | none | not implemented by design |
| §9.4 reduction operations | recommended | none | none | not implemented |
| §9.5 augmented arithmetic | recommended | none | none | not implemented |
| §9.6 minimum, maximum and magnitude variants | recommended | none (`Binary::min_num` and `Binary::max_num` are plain helpers) | none | not implemented |
| §9.7 NaN payload operations | recommended | `nan_payload`, `quiet_nan(payload~)`, `signaling_nan(payload~)` | `library/src/binary/order_wbtest.mbt`; no getPayload/setPayload pair | partial |

## Declared corpus and results

The pinned full gate is documented in
[`testdata/binary/README.md`](../../../testdata/binary/README.md).

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
| Seeded random elementary (`elem`), seeds 20261118 and 20261201 | 29 functions, unbounded contexts, precisions 2 to 700, all rounding directions | 2,000,000 / 2,000,000 |
| Range-boundary sweep (`tools/range_boundary_rows.py`) | `exp`, `exp2`, `exp10`, `expm1`, `pow`, `pown`, `rootn` on the underflow and overflow thresholds, precisions 2 to 300, six contexts, both tininess rules | 1,269,554 / 1,269,554 |
| Seeded random elementary (`elem2`: `exp2m1`, `exp10m1`, `log2p1`, `log10p1`), seed 20261118 | unbounded contexts, precisions 2 to 700, all rounding directions; 1,000,000 cases on native, 100,000 on Wasm, JavaScript and Wasm-GC | 1,300,000 / 1,300,000 |
| Range-boundary sweep of the four new functions | precisions 2 to 300, six contexts, overflow, saturation and tiny-result thresholds | 303,108 / 303,108 |
| Seeded random elementary (`elem3`: `rsqrt`, `compound`, `powr`), seed 20261118 | unbounded contexts, precisions 2 to 700, all rounding directions; 1,000,000 cases on native, 100,000 on Wasm, JavaScript and Wasm-GC | 1,300,000 / 1,300,000 |
| Range-boundary sweep of the three new functions | precisions 2 to 300, six contexts, overflow and tiny-result thresholds; the `compound` rows use the exact rational in place of `mpfr_compound_si` (see the oracle defect in `verification.md`) | 718,824 / 718,824 |
| Seeded random elementary (`elem4`: `asinpi`, `acospi`, `atanpi`, `atan2pi`), seed 20261118 | unbounded contexts, precisions 2 to 700, all rounding directions; 1,000,000 cases on native, 100,000 on Wasm, JavaScript and Wasm-GC | 1,300,000 / 1,300,000 |
| Range-boundary sweep of the four functions | precisions 2 to 300, six contexts, underflow thresholds, the anchors ±1/2 and ±1 for huge and tiny arguments and extreme ratios, next to ±1; `atan2pi` rows whose operands differ by more than 100,000 binades are not oracle rows (MPFR is too slow) | 1,654,315 / 1,654,315 |
| Committed smoke | TestFloat, sqrt, `pow_si`, elementary, `strtofr` and decimal output witnesses | 8,514 / 8,514 |
| TestFloat 3e level 2 | binary16, all declared operations/directions/tininess modes | 50,205,600 / 50,205,600 |

The level-2 binary16 result is additional streaming stress evidence, not a
claim for the much larger binary32/64/128 level-2 suites. The archives/files
and digests are pinned in
[`testdata/binary/corpora.json`](../../../testdata/binary/corpora.json).
The runner streams TestFloat level 2 in verified bounded chunks, but level 2
is an optional stress suite and is not included in the result claim above.
The 966,744-row MPFR run is likewise optional generated stress evidence; the
1,740-row hash-pinned fixture remains the reproducible release boundary.

## Scope of the claim

The results cover contextual add, subtract, multiply, divide, square root,
fused multiply-add, remainder, roundToIntegral (plain and exact),
convertToInteger to signed/unsigned 32/64-bit integers (plain and exact), and
the quiet/signaling equal, less, and less-or-equal predicates for the four IEEE
interchange formats and stated rounding/tininess modes, plus the declared
29-function elementary surface at 24, 53, and 113 bits under all five project
rounding modes. Invalid integer conversions are compared by flags only:
SoftFloat returns platform-specific sentinels where the API returns `None`.
They do not claim TestFloat conformance for format-to-format conversions,
min/max, total ordering, nextUp/nextDown, scaleB/logB, or decimal character
conversion (covered by package tests), nor for every IEEE 754 operation or
every real input. The elementary generator implements
nearest-away through MPFR's required `mpfr_round_nearest_away_begin/end`
protocol; it never passes the explicitly forbidden `MPFR_RNDNA` value to a
general elementary function.

The fixed-seed elementary inputs are dyadic multiples of $2^{-8}$ of
magnitude at most 16, inside each function's domain: `pow` takes a positive
base and an exponent in $[-3, 3]$, `rootn` a degree from 2 to 7, `atan2`
never two zeros, and `tanpi` no integral or half-integral argument. A zero
input is $+0$. The matrix therefore does not exercise tiny or huge
arguments, $-0$, infinities, NaNs, negative bases of `pow`, negative degrees
of `rootn`, or the poles and signed zeros of the IEEE special-case tables;
exact results such as $16^{3/4}$ occur only by chance. Those cases are
covered by the package's unit tests against the special-value tables in the
[API reference](../api/binary.md#elementary-functions), not by this
claim.

## Stability of the evidence

The pinned matrix is the release evidence boundary; adding a new operation
requires a new corpus contract and independent oracle. Run
`just conformance smoke binary` for the checked-in gate and `just gate binary`
for the full pinned gate.
