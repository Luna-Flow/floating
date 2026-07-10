# Changelog

All notable repository-release changes are tracked here. The main
[README.md](./README.md) describes the current baseline; historical release
notes live in this file.

## 0.4.1 - 2026-07-11

### Fixed

- Refreshed the published package README and current-baseline entry points so
  Mooncakes displays the 0.4 release documentation and installation version.
- Recorded verified full-corpus results for both the current and legacy GDA
  suites: 81,110 executable cases passed with zero failures.

## 0.4.0 - 2026-07-11

Feature baseline for Decimal contexts and GDA conformance.

### Added

- Added `DecimalContext`, `DecimalFlags`, decimal-specific rounding modes, and
  context-aware arithmetic, classification, formatting, unary, extrema,
  adjacent-value, logical-digit, quantize/rescale, and elementary operations.
- Added decimal32, decimal64, and decimal128 interchange encoding through
  `DecimalInterchange` and `DecimalInterchangeFormat`.
- Added signed-zero, quiet/signaling NaN, payload, total-order, quantum, normal,
  and subnormal Decimal observers.
- Added `numeric_expr`, a private expression representation with callback-driven
  evaluation and source spans.
- Added `gda_expr` and `gda_expr_cli` for runtime parsing and execution of GDA
  `.decTest` documents, deterministic sharding, case filtering, structured
  summaries, and native CLI execution.
- Added `semantic`, which projects concrete numeric values and arithmetic errors
  into representation-independent scalar, interval, and error values.
- Added pinned external conformance-corpus metadata, a checked-in smoke fixture,
  staged interpreter tooling, and focused CI coverage.

### Changed

- Decimal parsing can preserve exponent/quantum; canonicalization is now an
  explicit `normalized()` or context reduction step.
- Repository validation now separates the focused CI white-box gate from the
  full local/release GDA conformance gate.
- Documentation now follows the package-oriented, current-baseline structure of
  `linear-algebra`, with aligned English, Chinese, and Japanese file sets.

## 0.3.0 - 2026-06-12

### Highlights

- Added `bin_float_result`, `decimal_result`, and `ball_float_result` as closed
  checked-composition wrappers around concrete numeric values.
- Added the first semantic projection layer.
- Integrated shared checked arithmetic capabilities from `Luna-Flow/arithmetic`
  and shared algebraic abstractions from `Luna-Flow/luna-generic`.
- Narrowed `Floating` to classification, sign, precision, precision retuning,
  and normalization; arithmetic capabilities remain separate.

## 0.2.0 - 2026-06-07

### Highlights

- Introduced the shared arithmetic capability boundary.
- Added the first explicit dependency on `Luna-Flow/arithmetic`.

## 0.1.1 - 2026-06-07

### Highlights

- Added the initial ecosystem dependencies needed by the floating-point types.
- Prepared the first maintenance release of the original API line.

## 0.1.0 - 2026-06-06

### Highlights

- Established the MoonBit module and the first arbitrary-precision binary,
  decimal, and ball arithmetic packages.
