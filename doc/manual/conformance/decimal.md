# decimal conformance

## Contract split

`decimal` is the IEEE 754 arithmetic and interchange surface. General Decimal Arithmetic sticky status and traps belong to `decimal_gda`; passing the GDA corpus does not by itself establish the IEEE claim.

## Independent IEEE corpus

The committed IEEE corpus covers decimal32/64/128 DPD and BID interchange, canonical and non-canonical encodings, special values, flags, total order, and core arithmetic. The DPD fixture exhaustively checks all 1,024 declets.

## Oracle layers

Mandatory operation vectors use exact integer/rational construction and the documented DPD/BID bridge. Elementary families use independent high-precision or interval oracles when available. Values or encoded bits and IEEE flags are recorded independently so a numerically plausible result cannot hide a flag error.

The committed elementary layer contains 2,784 certified rows. MPFR 4.2.2
produces directed 768-bit dyadic endpoints; exact integer conversion rounds
both endpoints into decimal32/64/128 under every `DecimalRoundingMode`, and the
generator rejects a row unless result and flags are unique. Native, Wasm,
Wasm-GC, and JavaScript each pass 2,975/2,975 tests after these rows are
materialized; the full gate is 15,839/15,839. RDFP and Arb remain optional
secondary routes and are not counted when unavailable.

IEEE 754-2019 §9.2 saturation regressions for `Decimal::tanh_ctx` and
`Decimal::expm1_ctx` are in
`src/decimal/elementary_extensions_wbtest.mbt`. They check positive and
negative `tanh`, negative `expm1`, all eight `DecimalRoundingMode` values,
both clamp settings, both extended settings, and exact `Rounded`/`Inexact`
flags. The certified pre-loop bound selects a same-side representative within
the proved gap and passes it through the normal context finalizer, which
supplies tininess, overflow and clamp flags. These targeted cases are separate
from the committed MPFR row count. `decimal_gda` currently exposes neither
operation, so this entry makes no GDA conformance claim.

## Clause traceability

IEEE Std 754-2019 for `decimal` (decimal32/64/128 and arbitrary precision). Status is `conforming` when the operation exists and the cited evidence exercises it, `partial` when part of the clause is missing or evidence is thin (the cell says which), `not implemented` and `not applicable` otherwise. Evidence without a corpus name is a unit test in the repository; "no external corpus" marks operations that no independent oracle checks.

| Clause | API | Evidence | Status |
| --- | --- | --- | --- |
| §3.5 decimal32/64/128 interchange, DPD and BID | `Decimal::to_interchange_hex`, `Decimal::from_interchange_hex`, `Decimal::canonical` | IEEE decimal corpus (`testdata/decimal/ieee/decimal64_dpd.json` and the other five encodings); all 1,024 declets; `src/decimal/interchange_wbtest.mbt` | conforming |
| §3.7 extendable precisions | `DecimalContext::new` (precision up to 999,999,999) | `src/decimal/exponent_range_wbtest.mbt` | conforming |
| §4.3 rounding-direction attributes | `DecimalRoundingMode` | IEEE decimal corpus (five directions); `src/decimal/subnormal_rounding_wbtest.mbt` | conforming; `HalfDown`, `Up` and `ZeroFiveUp` are extensions |
| §5.2 preferred exponents | every `*_ctx` operation, `power_ctx`, `pown_ctx` | `src/decimal/power_preferred_exponent_issue194_wbtest.mbt`, `src/decimal/preferred_cohort_issue150_wbtest.mbt` | conforming; `pow(1, ±inf)` has no defined exponent and returns `1` |
| §5.3.1 addition, subtraction, multiplication, division, squareRoot | `add_ctx`, `sub_ctx`, `mul_ctx`, `div_ctx`, `sqrt_ctx` | IEEE decimal corpus (authoritative operations); `src/decimal/exponent_limits_issue187_wbtest.mbt` | conforming |
| §5.3.1 fusedMultiplyAdd | `fma_ctx` | IEEE decimal corpus; `src/decimal/exponent_limits_issue187_wbtest.mbt` | conforming |
| §5.3.1 remainder | `remainder_ctx` (IEEE remainder; `remainder` and `remainder_near` are the GDA forms) | `src/decimal/remainder_wbtest.mbt` (no external corpus) | conforming |
| §5.3.1 roundToIntegral (all five, exact) | `to_integral_value`, `to_integral_exact` | `src/decimal/to_integral_wbtest.mbt` | conforming |
| §5.3.1 nextUp, nextDown | `next_plus`, `next_minus`, `next_toward` | `src/decimal/exponent_int_limits_wbtest.mbt` | conforming |
| §5.3.1 scaleB, logB | `scaleb_ctx`, `logb_ctx` | `src/decimal/scaleb_rounding_wbtest.mbt`; `src/consistency/core_wbtest.mbt` | conforming |
| §5.3.2 quantize, quantum, sameQuantum | `quantize`, `quantum`, `same_quantum` | `src/decimal/exponent_int_limits_wbtest.mbt`; `src/consistency/core_wbtest.mbt` | conforming; a zero result above `e_max - p + 1` under `clamp` is not folded down |
| §5.4.1 convertFromInt | `Decimal::from_int`, `Decimal::from_bigint` | `src/decimal/preferred_cohort_issue150_wbtest.mbt` | conforming |
| §5.4.1 convertToInteger | none (`to_integral_*` return a `Decimal`) | none | partial |
| §5.4.2 convertFormat | `apply_ctx`, `to_bin_float`, `from_bin_float` | `src/decimal/to_bin_float_rounding_wbtest.mbt`; `src/decimal/bin_float_zero_wbtest.mbt` | partial |
| §5.5 copy, negate, abs, copySign | `copy`, `copy_negate`, `copy_abs`, `copy_sign` | `src/consistency/api_audit_wbtest.mbt`; `src/consistency/core_wbtest.mbt` | conforming |
| §5.6, §5.11 comparison, quiet and signaling | `compare_ctx`, `compare_signal_ctx` | `src/consistency/core_wbtest.mbt` | conforming |
| §5.7 class, isCanonical, radix | `classify`, `class_name`, `is_canonical` | `src/decimal/contextual_traits_wbtest.mbt`; `src/consistency/core_wbtest.mbt` | conforming |
| §5.10 totalOrder, totalOrderMag | `compare_total_ctx`, `compare_total_magnitude_ctx` | `src/consistency/core_wbtest.mbt` | partial |
| §5.12 decimal character conversion (decimal to decimal) | `from_string_ctx`, `to_sci_string`, `to_eng_string` | `src/decimal/parse_format_wbtest.mbt`; IEEE decimal corpus | conforming |
| §6.1–§6.3 infinities, NaNs, sign bit | every `*_ctx` operation | IEEE decimal corpus; `src/decimal/nan_payload_issue151_152_wbtest.mbt` | conforming; payload choice in [Implementation-defined choices](../verification.md#implementation-defined-choices) |
| §7.2–§7.4, §7.6 invalid operation, division by zero, overflow, inexact | `DecimalFlags` returned by every `*_ctx` operation | IEEE decimal corpus (flags recorded independently of values) | conforming |
| §7.5 underflow and tininess | `DecimalTininessDetection`, `DecimalContext::with_tininess` | `src/decimal/tininess_after_rounding_wbtest.mbt`; `src/decimal/sqrt_tininess_wbtest.mbt`; `src/decimal/elementary_extensions_wbtest.mbt` | conforming (the default is before rounding; `AfterRounding` is a non-standard option) |
| §8 alternate exception handling | none | none | not implemented |
| §9.2 recommended mathematical functions | `exp_ctx`, `exp2_ctx`, `exp10_ctx`, `expm1_ctx`, `ln_ctx`, `log2_ctx`, `log10_ctx`, `log1p_ctx`, `hypot_ctx`, `rootn_ctx`, `pown_ctx`, `power_ctx`, `sin_ctx`, `cos_ctx`, `tan_ctx`, `sinpi_ctx`, `cospi_ctx`, `tanpi_ctx`, `asin_ctx`, `acos_ctx`, `atan_ctx`, `atan2_ctx`, `sinh_ctx`, `cosh_ctx`, `tanh_ctx`, `asinh_ctx`, `acosh_ctx`, `atanh_ctx` | MPFR-certified elementary oracle (`testdata/decimal/ieee/elementary_mpfr_oracle.json`, 29 operations × 96 rows = 2,784); `src/decimal/elementary_extensions_wbtest.mbt` | partial: no `rSqrt`, `compound`, `powr`, `asinPi`, `acosPi`, `atanPi`, `atan2Pi`, `exp2m1`, `exp10m1`, `log2p1`, `log10p1` |
| §9.2.2 preferred exponents of pow and pown | `power_ctx`, `pown_ctx` | `src/decimal/power_preferred_exponent_issue194_wbtest.mbt` | conforming |
| §9.3 dynamic mode operations | none (contexts are explicit values) | none | not implemented by design |
| §9.4 reduction operations | none | none | not implemented |
| §9.5 augmented arithmetic | defined for binary formats only | none | not applicable |
| §9.6 minimum and maximum, eight variants | `minimum_ctx`, `minimum_number_ctx`, `maximum_ctx`, `maximum_number_ctx` and the `*_magnitude_ctx` forms | `src/decimal/extrema_ieee_wbtest.mbt` | conforming |
| §9.7 NaN payload operations | `get_payload`, `set_payload`, `set_payload_signaling` | `src/decimal/nan_payload_issue151_152_wbtest.mbt` | conforming |

## Targets

`just gate decimal` runs native, Wasm, Wasm-GC, and JavaScript. LLVM is excluded because the required local artifacts are not part of the repository. Target-specific coefficient dispatch must not change value, encoding, or flags.

## Boundaries

The checked matrix is finite and does not claim every IEEE 754 operation, every payload propagation policy, or every possible decimal input. The supplementary `dd*`/`dq*` decTest rows are diagnostics, not an IEEE oracle.

`Decimal::parse_checked` routes through `from_string_ctx`; it applies the
ArithmeticContext rounding direction and exponent bounds. This checked API
returns only a value or syntax error, so its `Result` does not expose overflow
or underflow flags.

The matrix passes on the current branch, which has no
[known deviations](../design/decimal.md#known-deviations) left. Passing the
gate is evidence for the covered rows only.

## Reproduction

```sh
just conformance smoke decimal
just gate decimal
just decimal-kernel-ci
```

See [the decimal data guide](../../../testdata/decimal/README.md) for corpus provenance, vector families, and failure records.
