# bin_float conformance

This page records the `0.9.0` binary floating-point semantic and test
boundary. It is evidence for a stated, finite corpus; it is not a proof that
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

A finite nonzero `BinFloat` denotes the dyadic real

`(-1)^negative * coefficient * 2^exponent2`, where `coefficient` is a
non-negative `BinCoeff`.

The finite coefficient is normalized by removing factors of two, while the
sign of zero remains observable. Infinity, qNaN, sNaN, NaN payload, and NaN
sign are explicit states rather than sentinel finite values.

For `add_ctx`, `sub_ctx`, `mul_ctx`, `div_ctx`, `sqrt_ctx`, and `pow_int_ctx`:

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

IEEE Std 754-2019 for `bin_float`. Status is `conforming` when the operation exists and the cited evidence exercises it, `partial` when part of the clause is missing or evidence is thin (the cell says which), `not implemented` and `not applicable` otherwise. Evidence without a corpus name is a unit test in the repository; "no external corpus" marks operations that no independent oracle checks.

| Clause | API | Evidence | Status |
| --- | --- | --- | --- |
| §3.3–§3.6 binary16/32/64/128 interchange formats | `BinFloat::to_interchange`, `BinFloat::from_bits` | TestFloat gate; `src/bin_float/ieee754_wbtest.mbt` | conforming |
| §3.7 extendable precisions | `BinaryContext::new`, `BinaryContext::unbounded` | MPFR elementary fixture; `src/bin_float/exponent_range_wbtest.mbt` | conforming |
| §4.3 rounding-direction attributes | `BinaryRoundingMode` | TestFloat gate (five directions) | conforming; `RoundAwayFromZero` is an extension |
| §5.3.1 addition, subtraction, multiplication, division, squareRoot | `add_ctx`, `sub_ctx`, `mul_ctx`, `div_ctx`, `sqrt_ctx` | TestFloat gate (7,461,360 vectors); `src/bin_float/ieee754_wbtest.mbt` | conforming |
| §5.3.1 fusedMultiplyAdd | `fma_ctx` | TestFloat gate (245,329,920 mulAdd vectors); `src/bin_float/fma_wbtest.mbt` | conforming |
| §5.3.1 remainder | `remainder_ctx` | TestFloat gate (rem); `src/bin_float/remainder_wbtest.mbt` | conforming |
| §5.3.1, §5.9 roundToIntegral (five directions, exact) | `to_integral_value_ctx`, `to_integral_exact_ctx`, `floor`, `ceil`, `trunc`, `round`, `round_ties_even` | TestFloat gate (roundToInt, exact and inexact); `src/bin_float/integral_wbtest.mbt` | conforming |
| §5.3.1 nextUp, nextDown | `next_up_ctx`, `next_down_ctx` | `src/bin_float/next_wbtest.mbt` (no external corpus) | conforming |
| §5.3.1 scaleB, logB | `scaleb_ctx`, `logb_ctx` | `src/bin_float/scale_wbtest.mbt` (no external corpus) | conforming |
| §5.4.1 convertFromInt | `BinFloat::from_int`, `BinFloat::from_uint64` | `src/bin_float/order_wbtest.mbt` (no external corpus) | conforming |
| §5.4.1, §5.8 convertToInteger (exact and inexact) | `to_int_ctx`, `to_int64_ctx`, `to_uint_ctx`, `to_uint64_ctx` | TestFloat gate (32- and 64-bit conversions); `src/bin_float/to_integer_wbtest.mbt` | conforming |
| §5.4.2 convertFormat | `round_ctx`, `with_precision`, `to_interchange` | `src/bin_float/ieee754_wbtest.mbt`; TestFloat format-to-format conversions are not run | partial |
| §5.5 copy, negate, abs, copySign | `neg`, `abs`, `copy_sign` | `src/bin_float/order_wbtest.mbt` | conforming |
| §5.6, §5.11 comparison predicates, quiet and signaling | `compare_quiet`, `compare_signaling`, `equal_quiet`, `equal_signaling`, `less_quiet`, `less_signaling`, `less_equal_quiet`, `less_equal_signaling`, `unordered_quiet` | TestFloat gate (eq, le, lt, eq_signaling, le_quiet, lt_quiet); `src/bin_float/order_wbtest.mbt` | conforming |
| §5.7 class and sign predicates | `classify`, `is_negative`, `is_zero`, `is_signaling_nan` | `src/bin_float/contextual_traits_wbtest.mbt`; the ten-way `class` of §5.7.2 is not one function | partial |
| §5.10 totalOrder, totalOrderMag | `total_order`, `total_order_mag`, `total_order_compare` | `src/bin_float/order_wbtest.mbt` (no external corpus) | conforming |
| §5.12 decimal character conversion, both directions | `from_string_ctx`, `to_decimal_string_ctx`, `to_shortest_string` | MPFR `mpfr_strtofr` corpus (1,716 rows) and `mpfr_get_str` corpus (3,300 rows); `src/bin_float/decimal_string_wbtest.mbt` | conforming |
| §5.12 hexadecimal character conversion | `from_hex`, `to_hex` | used by every MPFR corpus row; the full grammar of §5.12.3 is not enumerated | partial |
| §6.1–§6.3 infinities, NaNs, sign bit | every `*_ctx` operation | TestFloat gate (a NaN result is compared by class only); `src/bin_float/compare_nan_wbtest.mbt` | conforming; payload choice in [Implementation-defined choices](../verification.md#implementation-defined-choices) |
| §7.2–§7.6 exceptions and default handling | `BinaryFlags` returned by every `*_ctx` operation | TestFloat gate (exact flag bits, both tininess modes) | conforming |
| §7.5 tininess detection | `TininessDetection` | TestFloat gate (before and after rounding) | conforming |
| §8 alternate exception handling | none | none | not implemented (flags are values; no traps, no resumption) |
| §9.2 recommended mathematical functions | `exp`, `exp2`, `exp10`, `expm1`, `ln`, `log2`, `log10`, `log1p`, `hypot`, `rootn`, `pown`, `pow`, `sin`, `cos`, `tan`, `sinpi`, `cospi`, `tanpi`, `asin`, `acos`, `atan`, `atan2`, `sinh`, `cosh`, `tanh`, `asinh`, `acosh`, `atanh` (`*_ctx`, `try_*_ctx`) | MPFR elementary fixture (2,088 rows); `src/bin_float/elementary_certified_wbtest.mbt`; `src/bin_float/tanh_saturation_issue185_wbtest.mbt` | partial: no `rSqrt`, `compound`, `powr`, `asinPi`, `acosPi`, `atanPi`, `atan2Pi`, `exp2m1`, `exp10m1`, `log2p1`, `log10p1` |
| §9.3 dynamic mode operations | none (contexts are explicit values) | none | not implemented by design |
| §9.4 reduction operations | none | none | not implemented |
| §9.5 augmented arithmetic | none | none | not implemented |
| §9.6 minimum, maximum and magnitude variants | none (`BinFloat::min` and `BinFloat::max` are plain helpers) | none | not implemented |
| §9.7 NaN payload operations | `nan_payload`, `quiet_nan(payload~)`, `signaling_nan(payload~)` | `src/bin_float/order_wbtest.mbt`; no getPayload/setPayload pair | partial |

## Declared corpus and results

The pinned full gate is documented in
[`testdata/bin_float/README.md`](../../../testdata/bin_float/README.md).

| Source | Scope | Result |
| --- | --- | --- |
| TestFloat 3e level 1, seed 1 | 4 formats × 5 arithmetic operations × 5 rounding directions × 2 tininess modes | 7,461,360 / 7,461,360 |
| TestFloat 3e level 1, seed 1 | 4 formats × mulAdd (5 directions × 2 tininess modes), rem, roundToInt and four integer conversions (5 directions × exact/inexact variants), six comparison predicates | 246,766,512 / 246,766,512 |
| MPFR 4.2.2 `tests/data/sqrt` | all executable hexadecimal sqrt rows | 1,055 / 1,055 |
| MPFR 4.2.2 `pow_si` fixture | 4 precisions × 5 supported roundings × 6 inputs | 120 / 120 |
| MPFR 4.2.2 elementary fixture | 29 operations × 3 precisions × 6 roundings × 4 fixed-seed inputs | 2,088 / 2,088 |
| MPFR 4.2.2 `mpfr_strtofr` fixture | decimal text to binary: 5 precisions (11 to 200 bits) × 6 roundings × random, long-mantissa, huge-exponent, exact-halfway and one-unit-off-halfway literals, plus range limits and signed zeros | 1,716 / 1,716 |
| MPFR 4.2.2 `mpfr_get_str` fixture | binary to decimal: 5 precisions × 5 roundings × 10 digit counts × fixed-seed values (exponents up to ±20,000), 12 exact ties, and the shortest round-trip digit count of 1,200 values | 3,300 / 3,300 |
| Optional MPFR elementary stress, seed 20260715 | at least 100,000 cases per three-operation-or-larger family | 966,744 / 966,744 |
| Committed smoke | TestFloat, sqrt, `pow_si`, elementary, `strtofr` and decimal output witnesses | 7,467 / 7,467 |
| TestFloat 3e level 2 | binary16, all declared operations/directions/tininess modes | 50,205,600 / 50,205,600 |

The level-2 binary16 result is additional streaming stress evidence, not a
claim for the much larger binary32/64/128 level-2 suites. The archives/files
and digests are pinned in
[`testdata/bin_float/corpora.json`](../../../testdata/bin_float/corpora.json).
The runner streams TestFloat level 2 in verified bounded chunks, but level 2
is an optional stress suite and is not included in the result claim above.
The 966,744-row MPFR run is likewise optional generated stress evidence; the
2,088-row hash-pinned fixture remains the reproducible release boundary.

## Scope of the claim

The results cover contextual add, subtract, multiply, divide, square root,
fused multiply-add, remainder, roundToIntegral (plain and exact),
convertToInteger to signed/unsigned 32/64-bit integers (plain and exact), and
the quiet/signaling equal, less, and less-or-equal predicates for the four IEEE
interchange formats and stated rounding/tininess modes, plus the declared
29-function elementary surface at 24, 53, and 113 bits under all six project
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
[API reference](../api/bin_float.md#elementary-functions), not by this
claim.

## Stability of the evidence

The pinned matrix is the release evidence boundary; adding a new operation
requires a new corpus contract and independent oracle. Run
`just conformance smoke binary` for the checked-in gate and `just gate binary`
for the full pinned gate.
