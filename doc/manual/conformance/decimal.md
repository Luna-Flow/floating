# decimal conformance

`decimal` is the IEEE 754-2019 decimal arithmetic and interchange surface
(`decimal32`, `decimal64`, `decimal128`, and extendable precision). This page
lists the clauses of IEEE 754-2019 with their status and the finite tests and
corpora that check them.

General Decimal Arithmetic Specification 1.70 (GDA 1.70) accumulated flags and
traps belong to `decimal_gda`, while `decimal` exposes per-operation flags
(`DecimalFlags`). Passing the GDA corpus does not by itself establish the IEEE
754-2019 claim.

## Independent IEEE corpus

The committed IEEE corpus covers decimal32, decimal64, and decimal128 DPD and
BID interchange encodings, canonical and non-canonical encodings, special
values, flags, total order, and core arithmetic. The DPD fixture exhaustively
checks all 1,024 declets.

## Oracle layers

Mandatory operation vectors use exact integer and rational construction and the
documented DPD and BID bridge. Elementary families use independent
high-precision or interval oracles when available. Values or encoded bits and
IEEE flags are recorded independently so a numerically plausible result cannot
hide a flag error.

The committed elementary corpus contains 3,060 certified rows. MPFR 4.2.2
produces directed 768-bit dyadic bounds; exact integer conversion rounds both
bounds into decimal32, decimal64, and decimal128 under each of the five
`DecimalRoundingMode` directions, and the generator rejects a row unless result
and flags are unique. Native, Wasm, Wasm-GC, and JavaScript each pass 573/573
public API tests after these rows are materialized (one test per MPFR interval,
holding its 15 rows: a Wasm test module cannot register one test per row). The
full gate, `just gate decimal 3`, is 64,327/64,327: the 23,031 target-independent
checks, the 573 public API tests on each of the four targets, and the 9,691 rows
of the `pi_inverse` table and the 60 rows of the `huge_trig` table on each of
the four targets. RDFP and Arb remain optional secondary routes and are not
counted when unavailable.

| Source | Scope | Result |
| --- | --- | --- |
| MPFR 4.2.2 elementary oracle | 29 operations × 60 rows, 11 operations × 120 rows | 3,060 rows |
| `just gate decimal 3` | target-independent checks and four target runs | 64,327 / 64,327 |

IEEE 754-2019 9.2 saturation regressions for `Decimal::tanh_ctx` and
`Decimal::expm1_ctx` are in `library/src/decimal/elementary_extensions_wbtest.mbt`.
They check positive and negative `tanh`, negative `expm1`, all eight rounding
algorithms (the five directions of `DecimalRoundingMode` and three working
ones), and the exact `Inexact` flag. The certified pre-loop bound selects a
same-side representative within the proved gap and passes it through the normal
context finalizer, which supplies tininess and overflow flags. These targeted
cases are separate from the committed MPFR row count. `decimal_gda` currently
exposes neither operation, so this entry makes no GDA conformance claim.

## Clause traceability

IEEE 754-2019 for `decimal` (decimal32, decimal64, decimal128, and arbitrary
precision), with clauses cited by bare number. Status is `conforming` when the
operation exists and the cited evidence exercises it, `partial` when part of the
clause is missing or evidence is thin (the cell says which), and
`not implemented` or `not applicable` otherwise. `Level` is `required` for
clauses the standard states with "shall", `recommended` for those it states with
"should" and for the optional parts, and `optional` for features a flavor may
leave out. Evidence without a corpus name is a unit test in the repository;
"no external corpus" marks operations that no independent oracle checks.

| Clause | Level | API | Evidence | Status |
| --- | --- | --- | --- | --- |
| 3.5 decimal32/64/128 interchange, DPD and BID | required | `Decimal::to_interchange_hex`, `Decimal::from_interchange_hex`, `DecimalInterchange::canonical` | IEEE decimal corpus (`testdata/decimal/ieee/decimal64_dpd.json` and the other five encodings); all 1,024 declets; `library/src/decimal/interchange_wbtest.mbt` | conforming |
| 3.7 extendable precisions | recommended | `DecimalContext::new` (precision up to 999,999,999, `e_max` up to 999,999,999, $e_{\min} = 1 - e_{\max}$; default range $\max(999999, 1000p)$) | `library/src/decimal/context_new_wbtest.mbt`; `library/src/decimal/exponent_range_wbtest.mbt` | conforming |
| 4.3 rounding-direction attributes | required | `DecimalRoundingMode` | IEEE decimal corpus (five directions); `library/src/decimal/subnormal_rounding_wbtest.mbt` | conforming; all five directions of 4.3 (`RoundTiesToEven`, `RoundTiesToAway`, `RoundTowardZero`, `RoundTowardPositive`, `RoundTowardNegative`) and no other |
| 5.2 preferred exponents | required | every `*_ctx` operation, `pow_ctx`, `pown_ctx` | `library/src/decimal/power_preferred_exponent_issue194_wbtest.mbt`, `library/src/decimal/preferred_cohort_issue150_wbtest.mbt` | conforming; `pow(1, ±inf)` has no defined exponent and returns `1` |
| 5.3.1 addition, subtraction, multiplication, division, squareRoot | required | `add_ctx`, `sub_ctx`, `mul_ctx`, `div_ctx`, `sqrt_ctx` | IEEE decimal corpus (authoritative operations); `library/src/decimal/exponent_limits_issue187_wbtest.mbt` | conforming |
| 5.3.1 fusedMultiplyAdd | required | `fma_ctx` | IEEE decimal corpus; `library/src/decimal/exponent_limits_issue187_wbtest.mbt` | conforming |
| 5.3.1 remainder | required | `remainder_ctx` (IEEE remainder; the truncating form is the GDA `remainder`) | `library/src/decimal/remainder_wbtest.mbt` (no external corpus) | conforming |
| 5.3.1 roundToIntegral (all five, exact) | required | `to_integral_value_ctx`, `to_integral_exact_ctx` | `library/src/decimal/to_integral_wbtest.mbt` | conforming |
| 5.3.1 nextUp, nextDown | required | `next_up_ctx`, `next_down_ctx` | `library/src/decimal/exponent_int_limits_wbtest.mbt` | conforming |
| 5.3.1 scaleB, logB | required | `scaleb_ctx`, `logb_ctx` | `library/src/decimal/scaleb_rounding_wbtest.mbt`; `tooling/src/consistency/core_wbtest.mbt` | conforming |
| 5.3.2 quantize | required (shall) | `quantize_ctx` | `library/src/decimal/exponent_int_limits_wbtest.mbt`; `tooling/src/consistency/core_wbtest.mbt` | conforming; a zero result above $e_{\max} - p + 1$ is folded down to a member of the format (`library/src/decimal/zero_fold_issue234_wbtest.mbt`) |
| 5.3.2 quantum | recommended (should) | `quantum_ctx` | `library/src/decimal/quantum_ctx_wbtest.mbt` | conforming; see [quantum details](#quantum-details) |
| 5.7.3 sameQuantum | required (shall) | `same_quantum` | `tooling/src/consistency/core_wbtest.mbt` | conforming: equal exponents; `same_quantum(NaN, NaN)` and `same_quantum(inf, inf)` are true, exactly one NaN or one infinity is false, no exception |
| 5.4.1 convertFromInt | required | `Decimal::from_int`, `Decimal::from_bigint` | `library/src/decimal/preferred_cohort_issue150_wbtest.mbt` | conforming |
| 5.4.1, 5.8 convertToInteger (exact and inexact) | required | `Decimal::to_int_ctx`, `to_int64_ctx`, `to_uint_ctx`, `to_uint64_ctx` | `library/src/decimal/to_integer_wbtest.mbt` | conforming |
| 5.4.2 convertFormat | required | `Decimal::convert_format`, `Decimal::from_binary_ctx`, `Decimal::to_binary_ctx`, `apply_ctx`, `to_binary`, `from_binary` | Format-conversion tests; see [convertFormat evidence](#convertformat-evidence) | conforming |
| 5.5 copy, negate, abs, copySign | required | `copy`, `neg`, `abs`, `copy_sign` | `tooling/src/consistency/api_audit_wbtest.mbt`; `tooling/src/consistency/core_wbtest.mbt` | conforming |
| 5.6, 5.11 comparison, quiet and signaling | required | `compare_quiet`, `compare_signaling`, and the 22 predicates of IEEE 754-2019 Table 5.1 and Table 5.2; see [Comparison-predicate evidence](#comparison-predicate-evidence) | Predicate tests; see [Comparison-predicate evidence](#comparison-predicate-evidence) | conforming |
| 5.7 class, isCanonical, radix | required | `class_of`, `classify`, `is_canonical` | `library/src/decimal/class_of_wbtest.mbt` (all ten classes in decimal32, decimal64, and decimal128); `library/src/decimal/contextual_traits_wbtest.mbt`; `tooling/src/consistency/core_wbtest.mbt` | conforming |
| 5.10 totalOrder, totalOrderMag | required | `Decimal::total_order`, `Decimal::total_order_mag`, `Decimal::total_order_compare` (the same order as a three-way `Int32`) | Total-order corpus and package tests; see [totalOrder evidence](#totalorder-evidence) | conforming |
| 5.12 decimal character conversion (decimal to decimal) | required | `from_string_ctx`, `to_sci_string`, `to_eng_string` | `library/src/decimal/parse_format_wbtest.mbt`; IEEE decimal corpus | conforming |
| 6.1 to 6.3 infinities, NaNs, sign bit | required | every `*_ctx` operation | IEEE decimal corpus; `library/src/decimal/nan_payload_issue151_152_wbtest.mbt` | conforming; payload choice in [Implementation-defined choices](../verification.md#implementation-defined-choices) |
| 7.2 to 7.4, 7.6 invalid operation, division by zero, overflow, inexact | required | `DecimalFlags` returned by every `*_ctx` operation | IEEE decimal corpus (flags recorded independently of values); `library/src/decimal/overflow_rounded_result_issue264_wbtest.mbt` (overflow is judged on the rounded sum, not on an operand) | conforming |
| 7.5 underflow and tininess | required | every `_ctx` operation (tininess is always detected before rounding) | Tininess and underflow tests; see [Underflow and tininess evidence](#underflow-and-tininess-evidence) | conforming (before rounding is the only rule for decimal formats; the after-rounding option was removed in 0.12) |
| 8 alternate exception handling | recommended | none | none | not implemented |
| 9.2 recommended mathematical functions | recommended | The functions listed in [Mathematical-function evidence](#mathematical-function-evidence) | MPFR elementary oracle and package tests; see [Mathematical-function evidence](#mathematical-function-evidence) | conforming |
| 9.2.2 preferred exponents of pow and pown | recommended | `pow_ctx`, `pown_ctx` | Power cohort and exponent tests; see [Power preferred-exponent evidence](#power-preferred-exponent-evidence) | conforming |
| 9.3 dynamic mode operations | recommended (required only where a language defines dynamic modes) | none (contexts are explicit values) | none | not implemented by design |
| 9.4 reduction operations | recommended | none | none | not implemented |
| 9.5 augmented arithmetic | recommended | none (9.5 recommends it for binary formats only; no decimal requirement) | none | not applicable |
| 9.6 minimum and maximum, eight variants | recommended | `minimum_ctx`, `minimum_number_ctx`, `maximum_ctx`, `maximum_number_ctx` and the `*_magnitude_ctx` forms | `library/src/decimal/extrema_ieee_wbtest.mbt` | conforming |
| 9.7 NaN payload operations | recommended | `get_payload`, `set_payload`, `set_payload_signaling` | `library/src/decimal/nan_payload_issue151_152_wbtest.mbt` | conforming |

### quantum details

For a finite operand, `quantum_ctx` returns the number $(0, q, 1)$ with the
exponent $q$ of the operand, zeros included, with preferred exponent $Q(x)$. For
an infinity, it returns $+\infty$ with no exception. NaN operands are handled per
IEEE 754-2019 6.2 (a signaling NaN signals invalid operation). `quantum_ctx`
takes the context and returns the flags, like `logb_ctx`. Before 0.12
`Decimal::quantum` returned the exponent as an `Int32`; that accessor is
`exponent10` ([#719](https://github.com/Luna-Flow/floating/issues/719)).

### convertFormat evidence

`library/src/decimal/convert_format_wbtest.mbt` checks MPFR `mpfr_strtofr` and
`mpfr_get_str` rows and exact rows for every decimal and binary format pair.
Additional tests are in `library/src/decimal/to_binary_rounding_wbtest.mbt` and
`library/src/decimal/binary_zero_wbtest.mbt`.

### Comparison-predicate evidence

The API provides `compare_quiet`, `compare_signaling`, `compare_quiet_equal`,
`compare_signaling_equal`, `compare_quiet_less`, `compare_signaling_less`,
`compare_quiet_less_equal`, `compare_signaling_less_equal`,
`compare_quiet_unordered`, and the fifteen of `compare_predicates.mbt` (24 in
all: the 22 predicates of IEEE 754-2019 Table 5.1 and Table 5.2 and the two
three-way forms `compare_quiet` and `compare_signaling`).
`library/src/decimal/compare_predicates_wbtest.mbt` checks every predicate
against every relation, value, and flags.

### totalOrder evidence

`testdata/decimal/ieee/total_order.json` covers every ordered pair of cohorts,
signed zeros, subnormals, infinities, and quiet and signaling NaNs with payloads
in decimal32, decimal64, and decimal128 (9,408 ordered pairs for each of the two
predicates). Expected results come from a transcription of IEEE 754-2019 5.10
cross-checked with libmpdec and run on four targets in the `DECIMAL: IEEE 754`
gate. NaN payloads order by value, reversed for a negative sign
(implementation-defined by IEEE 754-2019 5.10 d) 5) iii)).
`tooling/src/consistency/core_wbtest.mbt` also checks total order.

### Underflow and tininess evidence

Five package tests check underflow and tininess before rounding:
`library/src/decimal/tininess_default_issue217_wbtest.mbt`,
`library/src/decimal/sqrt_tininess_wbtest.mbt`,
`library/src/decimal/elementary_extensions_wbtest.mbt`,
`library/src/decimal/power_subnormal_underflow_issue268_wbtest.mbt` (an integer
power just below $10^{e_{\min}}$), and
`library/src/decimal/power_subnormal_underflow_issue342_wbtest.mbt` (underflow of
an inexact subnormal integer power).

### Mathematical-function evidence

The IEEE 754-2019 9.2 functions covered are `exp_ctx`, `exp2_ctx`,
`exp10_ctx`, `expm1_ctx`, `exp2m1_ctx`, `exp10m1_ctx`, `ln_ctx`, `log2_ctx`,
`log10_ctx`, `log1p_ctx`, `log2p1_ctx`, `log10p1_ctx`, `hypot_ctx`, `rsqrt_ctx`,
`compound_ctx`, `powr_ctx`, `asinpi_ctx`, `acospi_ctx`, `atanpi_ctx`,
`atan2pi_ctx`, `rootn_ctx`, `pown_ctx`, `pow_ctx`, `sin_ctx`, `cos_ctx`,
`tan_ctx`, `sinpi_ctx`, `cospi_ctx`, `tanpi_ctx`, `asin_ctx`, `acos_ctx`,
`atan_ctx`, `atan2_ctx`, `sinh_ctx`, `cosh_ctx`, `tanh_ctx`, `asinh_ctx`,
`acosh_ctx`, and `atanh_ctx`.

`testdata/decimal/ieee/elementary_mpfr_oracle.json` provides the MPFR-certified
elementary oracle (29 operations × 60 rows and 11 operations × 120 rows = 3,060).
Package tests include `library/src/decimal/elementary_extensions_wbtest.mbt`.
`library/src/decimal/elementary_pm1_wbtest.mbt` and the generated
`library/src/decimal/elementary_pm1_rows_wbtest.mbt`
(`tools/generate_decimal_pm1_rows.py`) test `exp2m1`, `exp10m1`, `log2p1`, and
`log10p1` for special values of IEEE 754-2019 9.2.1, exact cases and preferred
exponent of IEEE 754-2019 9.2.2, clusters, tiny arguments, all eight rounding
algorithms (the five directions and three working ones), and tininess before
rounding.

`library/src/decimal/elementary_rcp_wbtest.mbt` and the generated
`library/src/decimal/elementary_rcp_rows_wbtest.mbt`
(`tools/generate_decimal_rcp_rows.py`) test `rsqrt`, `compound`, and `powr` for
IEEE 754-2019 9.2.1 rows, the two readings of the `powr` list, preferred
exponents, `Int32` minimum, and tiny and extreme arguments.

`library/src/decimal/elementary_pi_inverse_wbtest.mbt` and the generated
`library/src/decimal/elementary_pi_inverse_rows_wbtest.mbt`
(`tools/generate_decimal_pi_inverse_rows.py`) test `asinpi`, `acospi`,
`atanpi`, and `atan2pi`: the clauses of IEEE 754-2019 9.2.1 row by row, exact
Niven values, preferred exponent 0, the anchors next to $\pm 1/2$ and $\pm 1$ in
all eight rounding algorithms on both sides, tiny and extreme operands, and
underflow.

`library/src/decimal/exp_range_wbtest.mbt` and the generated
`library/src/decimal/exp_range_rows_wbtest.mbt`
(`tools/generate_decimal_exp_range_rows.py`) test exponentials at the range
limits: `exp`, `exp2`, and `exp10` beyond the binary exponent range, results
just inside and outside the range, and all five rounding directions. A seeded
random `decimal-*` campaign checks the functions against MPFR
(`doc/manual/verification.md`).

### Power preferred-exponent evidence

Tests for `pow_ctx` and `pown_ctx`:

- `library/src/decimal/power_preferred_exponent_issue194_wbtest.mbt`.
- `library/src/decimal/power_overflow_sign_issue265_wbtest.mbt`: sign of an overflowing power.
- `library/src/decimal/power_inexact_trailing_zeros_issue266_wbtest.mbt`: an inexact power uses the cohort member of least exponent, IEEE 754-2019 5.2.
- `library/src/decimal/power_reciprocal_cohort_issue284_wbtest.mbt`: cohort of exact negative powers, IEEE 754-2019 5.2.
- `library/src/decimal/power_spurious_clamped_issue267_wbtest.mbt`: an integer power is folded down only when the exponent had to be altered.
- `library/src/decimal/power_ten_clamp_issue287_wbtest.mbt`: a power of ten above the top exponent is folded down.
- `library/src/decimal/power_inexact_clamped_issue305_wbtest.mbt`: an inexact result is delivered with precision digits, not folded down.

## Targets

`just gate decimal` runs native, Wasm, Wasm-GC, and JavaScript. LLVM is excluded
because the required local artifacts are not part of the repository.
Target-specific coefficient dispatch must not change value, encoding, or flags.

## Boundaries

The checked matrix is finite and does not claim every IEEE 754-2019
operation, every payload propagation policy, or every possible decimal input.
The supplementary `dd*` and `dq*` decTest rows are diagnostics, not an IEEE
oracle.

`Decimal::parse_checked` routes through `from_string_ctx`; it applies the
ArithmeticContext rounding direction and exponent bounds. This checked API
returns only a value or syntax error, so its `Result` does not expose overflow
or underflow flags.

The matrix passes on the current branch, which has no
[known deviations](../design/decimal.md#known-deviations) left. Passing the gate
is evidence for the covered rows only.

## Reproduction

```bash
just conformance smoke decimal
just gate decimal
just decimal-kernel-ci
```

See [the decimal data guide](../../../testdata/decimal/README.md) for corpus
provenance, vector families, and failure records.
