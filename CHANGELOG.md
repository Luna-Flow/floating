# Changelog

All notable repository-release changes are tracked here. The main
[README.md](./README.md) describes the current baseline; historical release
notes live in this file.

## 0.8.0 - 2026-09-06

### Added

- Added `AddContextual`, `SubContextual`, `MulContextual`, `DivContextual`,
  `AbsContextual`, `SqrtContextual`, and `ExpContextual` implementations for
  `BinFloat`, so the binary stack participates in the contextual trait surface
  already provided by the decimal stacks.
- Exposed `to_string` as an explicit public method on `BinFloat`, `BinCoeff`,
  `Decimal` (IEEE and GDA), `BallFloat`, `BallFloatDecorated`, and `Decoration`
  through `extend` declarations.

### Changed

- Raised the `Luna-Flow/arithmetic` dependency to `0.5.0`, whose
  `ArithmeticContext` carries exponent bounds and clamping.
- Changed `BinaryContext::from_arithmetic_context`, and the IEEE and GDA
  `DecimalContext::from_arithmetic_context`, to propagate `e_min`, `e_max`, and
  `clamp` from the arithmetic context instead of discarding them. Contextual and
  checked operations that previously ran unbounded now honour the caller's
  exponent range.
- Changed `BinaryContext::new` and `BinaryContext::try_new` to accept a
  one-sided exponent bound. `try_new` now fails only when `e_min` exceeds
  `e_max`; passing `e_min` or `e_max` alone previously aborted or returned an
  error.
- Changed the decimal `PowNatChecked` and `PowIntChecked` implementations to
  derive their context from the supplied arithmetic context instead of fixed
  `+/-999_999` exponent bounds.
- Renamed `BinCoeff::to_string(radix~)` to `BinCoeff::to_radix_string(Int)` so
  that `BinCoeff::to_string` denotes the `Show` implementation, consistent with
  the other numeric types. Callers that passed a radix must use the new name;
  radix-10 callers are unaffected.
- Declared `Show::to_string` explicitly with `extend` instead of relying on the
  implicit promotion of `impl Show` methods, which the MoonBit 0.10.4 toolchain
  deprecated. The repository now checks clean under `moon check --deny-warn` on
  all five backends.

### Fixed

- Fixed the native link failure of the `cli` conformance dispatcher by reading
  process arguments through `moonbitlang/core/env` instead of
  `moonbitlang/x/sys`. The `x` intrinsic still lowers to the pre-rename runtime
  symbol `moonbit_get_cli_args`, which the current split `libruntime.a` no
  longer exports; `@env.args` uses the current `moonbit_rt_get_cli_args`.

### Verified

- Passed the complete `just pr` gate: format, localized documentation, native
  check and test, IEEE 754 smoke 6,897/6,897, binary smoke 2,271/2,271, GDA
  TestFloat 3e 60/60, and interval smoke 10/10.
- Passed `moon check --deny-warn --target all` and `moon test src/bin_float
  --target all` across wasm, wasm-gc, js, and native.
- Retained the 0.7.1 performance and semantic audit unchanged; this release
  contains no new numerical measurements.

## 0.7.1 - 2026-07-16

### Changed

- Audited and retained the decimal GDA coefficient fast paths, IEEE decimal
  exact/bounded division paths, binary exact-top arithmetic paths, and interval
  endpoint dispatch introduced after the 0.7.0 release.
- Added a directed-rounding and monotonicity proof boundary to the interval
  design: every endpoint candidate is rounded outward, and negative-half-axis
  integer powers use the correct reversed endpoint order.
- Kept target-specific crossover tuning as implementation evidence only; noisy
  or non-monotonic observations are not promoted into public performance claims.
- Added package-level GDA and interval performance entry points and aligned the
  decimal performance instructions with the current Maremark runner.

### Fixed

- Removed stale decimal baseline and threshold commands from the published
  performance documentation and corrected the localized release-date record.
- Corrected `BallFloat::pown` for even powers on negative intervals and for even
  negative powers on the negative half-axis. The previous optimization could
  construct an interval with a lower bound above its upper bound or lose one
  outward-rounded ulp across zero.
- Completed the GDA half-power-of-ten coefficient comparison used by the
  optimized rounding path and covered its exact, below-half, and above-half
  boundaries.

### Verified

- Passed the native IEEE 1788 strict aggregate at 4,656/4,656 after the
  interval regression fix, including 174/174 integer-power cases.
- Passed the pinned binary, IEEE decimal, and GDA suites: 7,464,503 binary
  cases, 15,763 IEEE decimal cases, 64,986 current GDA cases, and 16,124
  legacy GDA cases.
- Completed native Maremark `all` and `auto-tune` artifacts; auto-tune output
  is retained as calibration evidence and is not treated as a universal
  crossover guarantee.
- Added a localized performance audit and semantic-proof matrix for the
  `en_US`, `zh_CN`, and `ja_JP` documentation trees.

## 0.7.0 - 2026-07-15

### Added

- Added a shared certified dyadic/interval kernel and bounded Ziv refinement
  for `BinFloat`, `Decimal`, and `BallFloat`; acceptance requires both enclosure
  endpoints to round to the same target value and flags.
- Added the complete 0.7.0 elementary families, pi-scaled functions, contextual
  and `try_*` entry points, and checked mirrors without extending the GDA
  surface beyond `exp`, `ln`, `log10`, `power`, and `sqrt`.
- Added structured certification-failure details and a unified `bench` package
  hierarchy using Maremark 0.3.0 for kernel, core, checked full-path,
  elementary, hotspot, and auto-tune measurements.

### Changed

- Exhausted certification budgets now fail explicitly instead of accepting
  repeated-approximation results.
- Decimal elementary evaluation now bridges MPFR-directed dyadic enclosures to
  exact decimal endpoint rounding; GDA `sqrt`/`exp`/`ln`/`log10` retain fixed
  HalfEven semantics while `power` follows the active GDA context.
- Aligned the GDA public context surface with Arithmetic Specification 1.70:
  the Basic context uses HalfUp and standard error traps, invalid subconditions
  signal `InvalidOperation`, and decTest execution now traverses
  `GdaContext`/`GdaOutcome` instead of bypassing the public state model.
- BallFloat checked elementary functions now preserve proof failures, while
  unchecked trigonometric functions retain only mathematically conservative
  interval fallbacks. Pi-scaled range reduction operates directly in x-space.
- Native `BinCoeff::square` now enters recursive multiplication at 512 limbs;
  Maremark auto-tune confirms a stable square policy from 8 limbs upward.

### Verified

- Passed the fixed MPFR 4.2.2 binary elementary corpus at 2,088/2,088 and the
  optional generated stress run at 966,744/966,744; only the fixed corpus is
  part of the reproducible release aggregate.
- Passed the Decimal elementary oracle at 2,784/2,784, the complete four-target
  Decimal gate at 15,735/15,735, GDA `official` at 64,986/64,986, and
  `official0` at 16,124/16,124.
- Passed the pinned ITF1788 strict aggregate at 4,656/4,656 with zero
  unsupported selected cases.
- Passed all 12 shared 0.6.1/0.7.0 native performance cells using ten
  alternating paired samples and the Maremark 95% bootstrap/3% release rule.
  New 0.7.0 elementary APIs intentionally have no fabricated 0.6.1 baseline.

## 0.6.1 - 2026-07-14

### Changed

- Reworked `decimal_checked` into an IEEE context-and-flags pipeline and added
  `decimal_gda_checked` for sticky-context composition, trap short-circuiting,
  defined results, and explicit recovery.
- Consolidated public tooling under parameterized `just conformance`, `just
  gate`, and `just bench` commands and removed the backend-specific aliases.

## 0.6.0 - 2026-07-14

### Changed

- Rebuilt the package documentation matrix across English, Simplified Chinese,
  and Japanese. Every package now has API, tutorial, design, and package README
  coverage; numerical cores have explicit conformance and performance evidence
  pages, and superseded research notes have been consolidated.
- Split IEEE tininess policy from GDA status handling; IEEE contexts default to
  after-rounding and expose an explicit before-rounding choice.
- Reject non-positive public precision and reserve zero-precision arithmetic for
  private exact work contexts.
- Added GDA contexts with radix, sticky flags, trap sets, signal precedence, and
  `GdaOutcome` defined results.
- Removed implementation-specific IEEE oracle and full-vector download paths;
  checked-in DPD/BID fixtures are validated from IEEE encoding formulas.

## 0.5.0 - 2026-07-12

### Added

- Added `BinCoeff`, the non-negative public coefficient boundary for binary
  floating-point, IEEE interchange bits, and ball arithmetic. It provides
  explicit integer/byte parsing, arithmetic, bit operations, division, and
  conversion without exposing MoonBit `BigInt`.
- Added a pure inline/limb coefficient kernel for non-JS targets and a hidden
  host `bigint` adapter for JavaScript behind the same `BinCoeff` API.

### Changed

- Reworked contextual integer powers around a single approximation with a
  conservative dyadic error enclosure and exact can-round checks, retaining
  the exact coefficient-power implementation as the permanent fallback.
- Added leading-bit coefficient exponentiation, small addition chains,
  power-of-two and bounded exact-result dispatches, and 120 fixed MPFR 4.2.2
  `pow_si` witnesses without changing the public rounding semantics.
- Changed `BinFloat`, `BinFloatResult`, `BallFloat`, and `BallFloatResult`
  constructors and accessors to use `BinCoeff` plus an independent sign.
- Changed `BinaryInterchange::bits` and `from_bits` to use `BinCoeff`.
- Renamed the checked-composition wrapper packages with the `_checked` suffix
  to align package paths with the checked arithmetic trait naming.
- Kept the existing Decimal and Semantic `BigInt` APIs unchanged; the migration
  applies only to the binary and ball stacks.

### Removed

- Removed binary-stack `from_bigint` constructors, `BinFloat::significand`, and
  the `NatHomomorphism` / `IntegralHomomorphism` implementations whose public
  boundary depended on `BigInt`. Use `from_coefficient`, `coefficient`, and
  explicit `negative?` arguments instead.

## 0.4.1 - 2026-07-11

### Fixed

- Refreshed the published package README and current-baseline entry points so
  Mooncakes displays the 0.4 release documentation and installation version.
- Recorded verified full-corpus results for both the current and legacy GDA
  suites: 81,110 executable cases passed with zero failures.

### Changed

- Moved `Decoration` and `BallFloatDecorated` into the `ball_float` package so
  bare and decorated IEEE 1788 interval APIs share one package boundary.

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
