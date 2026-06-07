# Correctness Audit Ledger

This ledger tracks the current `0.2.0` implementation against explicit semantic contracts.

Status labels:

- `Verified`
- `Verified with approximation boundary`
- `Known limitation`

## `@def`

| API | Contract | Implementation Anchor | Verification | Status |
| --- | --- | --- | --- | --- |
| `Sign` / `FpClass` / `RoundingMode` | Shared semantic enums used consistently across packages. | `src/def/types.mbt` | `def predicates classify finite nan and enclosing zero consistently`; package-level code inspection. | Verified |
| `Floating` | Shared capability surface is classification, sign, precision, retuning, normalization only. | `src/def/types.mbt` | Cross-package compile usage and audit test coverage through helper predicates. | Verified |
| `is_finite` / `is_nan` / `is_infinite` / `is_zero` | Predicates are class/sign based; `is_zero` rejects NaN and accepts zero-sign enclosures. | `src/def/types.mbt` | `def predicates classify finite nan and enclosing zero consistently`; legacy NaN regression in `core_wbtest`. | Verified |

## `@internal`

| API | Contract | Implementation Anchor | Verification | Status |
| --- | --- | --- | --- | --- |
| `bigint_zero` / `bigint_one` / `abs_bigint` / `sign_of_bigint` | Canonical integer helpers. | `src/internal/core.mbt` | Used transitively by all numeric packages; sign behavior checked in predicate and normalization tests. | Verified |
| `pow2` / `pow5` / `pow10` / `digits10` | Exact positive-power helpers and decimal digit counting. | `src/internal/core.mbt` | Construction and conversion tests across `bin_float` and `decimal`; parser/normalization tests. | Verified |
| `remove_factor2` / `remove_factor10` | Strip removable radix factors and preserve represented value. | `src/internal/core.mbt` | `bin_float normalizes powers of two`; `decimal make and display normalize trailing zeros`. | Verified |
| `round_positive_div` / `round_shift` / `compare_abs` | Directed and tie-aware rounding on non-negative magnitudes; absolute comparison only. | `src/internal/core.mbt` | `internal rounding helpers honor tie and directed modes`. | Verified |
| `split_decimal_string` | Accept plain/scientific decimal syntax and reject malformed input. | `src/internal/core.mbt` | `internal decimal parser accepts scientific notation and rejects malformed strings`; `decimal parses and normalizes`. | Verified |

## `@bin_float`

| API | Contract | Implementation Anchor | Verification | Status |
| --- | --- | --- | --- | --- |
| `make` / `zero` / `one` / `from_int` / `from_bigint` | Finite constructors normalize to canonical binary form. | `src/bin_float/bin_float.mbt` | `bin_float normalizes powers of two`; `bin_float arithmetic stays exact on small dyadics`. | Verified |
| `inf` / `nan` / `classify` / `sign` / `precision` | Special values keep class and stored precision semantics. | `src/bin_float/bin_float.mbt` | predicate tests, compare tests, arithmetic special-case inspection. | Verified |
| `significand` / `exponent2` / `normalized` / `is_zero` | Expose normalized finite representation and zero classification. | `src/bin_float/bin_float.mbt` | normalization tests, predicate tests, audit review. | Verified |
| `with_precision` / `ulp` | Precision retuning follows requested rounding; `ulp` reports representation-local spacing. | `src/bin_float/bin_float.mbt` | `bin_float with_precision rounds and ulp tracks spacing`. | Verified |
| `add` / `sub` / `mul` / `div` | Exact on small dyadics when representable; propagate special values per implementation. | `src/bin_float/bin_float.mbt` | `bin_float arithmetic stays exact on small dyadics`; existing conversion and special-value tests. | Verified with approximation boundary |
| `compare` | Total order for ordered values only; rejects NaN. | `src/bin_float/bin_float.mbt` | `bin_float compare orders finite and infinities`; source inspection for NaN abort branch. | Verified |

## `@decimal`

| API | Contract | Implementation Anchor | Verification | Status |
| --- | --- | --- | --- | --- |
| `make` / `zero` / `one` / `from_int` / `from_bigint` / `from_string` | Decimal constructors normalize trailing zeros and parse accepted textual forms. | `src/decimal/decimal.mbt` | `decimal parses and normalizes`; `decimal make and display normalize trailing zeros`; parser tests. | Verified |
| `inf` / `nan` / `classify` / `sign` / `precision` | Special-value and sign semantics mirror package contract. | `src/decimal/decimal.mbt` | predicate tests and arithmetic special-case inspection. | Verified |
| `coefficient` / `exponent10` / `is_zero` / `normalized` / `with_precision` | Expose canonical decimal representation and precision-retuned finite forms. | `src/decimal/decimal.mbt` | normalization/display tests and audit review. | Verified |
| `neg` / `abs` / `add` / `sub` / `mul` / `div` | Decimal arithmetic is exact when representable under current precision, otherwise rounded by package rules. | `src/decimal/decimal.mbt` | `decimal arithmetic and display`; conversion-driven regression checks. | Verified with approximation boundary |
| `to_bin_float` / `from_bin_float` | Binary conversion is exact for dyadic-compatible direction and approximate for non-dyadic decimal-to-binary. | `src/decimal/decimal.mbt` | `decimal binary conversion preserves dyadics exactly`; `decimal to bin conversion handles non-dyadic values`; `bin to decimal conversion is exact for finite values`. | Verified with approximation boundary |

## `@ball_float`

| API | Contract | Implementation Anchor | Verification | Status |
| --- | --- | --- | --- | --- |
| `new` | Quantizes center and radius while preserving the original enclosure after center rounding. | `src/ball_float/ball_float.mbt` | `ball_float new preserves an input endpoint after center rounding`. | Verified |
| `exact` | Embeds a finite `BinFloat` as a ball that still contains the source value after precision reduction. | `src/ball_float/ball_float.mbt` | `ball_float exact widens when lowering precision`. | Verified |
| `from_decimal` | Builds a binary enclosure around a finite decimal source. | `src/ball_float/ball_float.mbt` | existing `ball_float from_decimal keeps low precision enclosure`. | Verified with approximation boundary |
| `center` / `radius` / `precision` / `classify` / `sign` / `normalized` / `with_precision` | Expose stored enclosure, finite classification, sign-by-enclosure, and containment-preserving retuning/normalization. | `src/ball_float/ball_float.mbt` | `def predicates classify finite nan and enclosing zero consistently`; `ball_float sign and overlap relations remain enclosure based`; exact-widen regression. | Verified |
| `contains` / `overlaps` / `separated_from` / `definitely_lt` / `definitely_gt` / `maybe_overlap` | Relation APIs operate on interval semantics, not scalar total order. | `src/ball_float/ball_float.mbt` | `ball_float overlap detects separated balls`; `ball_float sign and overlap relations remain enclosure based`; exact containment tests. | Verified |
| `add` / `sub` / `mul` / `div` | Arithmetic returns balls that enclose the corresponding real result and widens for output rounding. Division rejects denominator balls that contain zero. | `src/ball_float/ball_float.mbt` | `ball_float multiplication keeps exact scalar result inside zero-radius inputs`; `ball_float division keeps exact scalar result inside zero-radius inputs`; source inspection for zero-denominator abort branch. | Verified with approximation boundary |
