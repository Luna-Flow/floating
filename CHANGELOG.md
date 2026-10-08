# Changelog

All notable repository-release changes are tracked here. The main
[README.md](./README.md) describes the current baseline; historical release
notes live in this file.

## Unreleased

### Added

- Added the remaining IEEE 754-2019 binary operations to `BinFloat`, each
  correctly rounded under a `BinaryContext` and returning `BinaryFlags`:
  - `fma` and `fma_ctx` (fusedMultiplyAdd), which round `x * y + z` once;
    NaN handling follows SoftFloat 3e.
  - `remainder` and `remainder_ctx` (IEEE remainder, quotient rounded to
    nearest-even), without materializing huge scaled dividends.
  - `to_integral_value_ctx`, `to_integral_exact_ctx`, `floor`, `ceil`,
    `trunc`, `round` (ties away) and `round_ties_even` (roundToIntegral).
  - `to_int_ctx`, `to_int64_ctx`, `to_uint_ctx` and `to_uint64_ctx`
    (convertToInteger, with `exact=true` for convertToIntegerExact); invalid
    conversions return `None` with *invalid*.
  - `next_up_ctx` and `next_down_ctx` (nextUp, nextDown).
  - `scaleb_ctx` and `logb_ctx` (scaleB, logB).
  - `copy_sign`, `total_order`, `total_order_compare` and `total_order_mag`
    (copySign, totalOrder, totalOrderMag), and the comparison predicates
    `compare_quiet`, `compare_signaling`, `equal_quiet`, `equal_signaling`,
    `less_quiet`, `less_signaling`, `less_equal_quiet`,
    `less_equal_signaling` and `unordered_quiet`.
  - `from_string` and `from_string_ctx` (convertFromDecimalCharacter),
    correctly rounded for any precision and exponent, including huge
    exponents decided without expansion.
  - `to_decimal_string_ctx` (convertToDecimalCharacter with a fixed digit
    count) and `to_shortest_string` / `to_shortest_string_ctx` (the fewest
    digits that read back to the same value).
- Added the binary implementation exponent range `binary_implementation_e_min`
  and `binary_implementation_e_max` ($[1 - 2^{30}, 2^{30} - 1]$ for the leading
  bit, as in MPFR) and the precision cap `binary_precision_max` ($2^{28}$
  bits).
- Extended the TestFloat frontend (`TestFloatOperation`, `TestFloatSpec::exact`,
  `TestFloatSpec::parse(..., exact?)`) and the binary gate to mulAdd, rem,
  roundToInt, the four integer conversions and the six comparison predicates:
  `just gate binary` now covers 254,227,872 TestFloat vectors, and the binary
  smoke fixture has 2,451 rows.
- Added a nightly workflow that runs the `quick`, `decimal`, `decimal_gda`,
  `binary` and `interval` gates in parallel with cached, hash-verified corpora
  and uploads each summary.
- Added `tools/check_doc_examples.py`, which compiles and runs the manual's
  MoonBit examples against the current branch. `doc/manual` lives outside `src`
  and its examples use plain `moonbit` fences, which `moon` does not compile, so
  none of them were covered by a gate before; `just docs` now checks 236
  examples across 48 pages.

### Changed

- `BinFloat::compare` and the IEEE and GDA `Decimal::compare` no longer abort
  on NaN. They keep the numeric order for other operands (`-0 == +0`) and
  order every NaN equal to every other NaN and above every number, so
  `Compare`, `<`, `<=` and sorting form a total preorder. IEEE semantics remain
  available through `compare_checked`, the quiet and signaling predicates and
  the total-order functions.
- Results outside the binary implementation exponent range are classified as
  overflow or underflow according to the rounding mode instead of being stored
  with a saturated exponent, and context precision is capped at
  `binary_precision_max`.
- The non-`try` elementary functions of `bin_float`, `decimal` and
  `decimal_gda` return defined results instead of aborting when certification
  fails: binary returns a quiet NaN with *invalid operation*, decimal and GDA
  return their invalid result so that flags and traps apply. `try_*` functions
  still report the failure detail.
- Migrated to the MoonBit 0.10 toolchain. Trait-implementation methods are no
  longer promoted implicitly, so every promoted method is declared with
  `pub extend` and the generated interfaces now list them (`equal`,
  `not_equal`, `op_lt`, `op_le`, `op_gt`, `op_ge`, `output`, `to_repr`, the
  `*_contextual` and `*_checked` methods of `BinFloat`, `Decimal` and
  `BallFloat`, and `Decimal::from_integral` / `from_nat`). Call sites that
  relied on implicit promotion keep working; the public API is otherwise
  unchanged. The tree builds cleanly
  with `--deny-warn` under moonc 0.10.14 (core packages imported explicitly,
  black-box test names qualified) and is formatted with the moonc 0.10.11
  formatter.
- Split the generated IEEE decimal public-API fixture into files of 400 tests,
  which moonc 0.10.14 requires.
- Raised `moonbitlang/x` from 0.4.46 to 0.5.5 and `moonbitlang/async` from
  0.20.1 to 0.22.4.
- Moved the documentation to the gettext layout: English pages in
  `doc/manual` with one `api/`, `tutorial/` and `design/` page per package,
  translations as catalogs in `doc/locale`, and Typst attachments in
  `doc/attachments`. A `Docs` workflow runs `lunadoc check`, and
  `tools/doc_quality.py` checks the new layout.
- Rewrote the documentation (API, tutorial and design pages for every package,
  the overview and the guides) with Chinese and Japanese translations. API
  snapshots use the `mbti` fence, which `tools/doc_quality.py` accepts.
- Ignored local AI-agent state (`.claude/`, `.codex/`, `.cursor/` and similar)
  in `.gitignore`.
- Moved every workflow to the `ubuntu-26.04` runner ahead of the `ubuntu-latest`
  migration that GitHub rolls out between 2026-10-19 and 2026-11-19, and raised
  the actions that still targeted the deprecated Node 20 runtime:
  `actions/checkout` to v7, `actions/cache` to v6, `actions/upload-artifact` to
  v7 and `extractions/setup-just` to v4.

### Fixed

- Fixed `BinFloat::acos`, `acos_ctx` and `try_acos_ctx`, which recursed through
  the certified `asin` bounds until the stack overflowed (SIGSEGV on native, a
  `RangeError` on wasm-gc) for a NaN, an infinity or a finite `|x| > 1`. They
  now match `asin`: a quiet NaN for a NaN input and a domain error otherwise.
- Fixed `just gate <scope>` on a clean checkout: every scope now installs the
  module dependencies first. `moon update` only refreshes the registry index, so
  the first `--frozen` command failed with "`frozen` is set, so the build system
  cannot change the modules directory". This broke the nightly `decimal_gda`
  job, the only nightly scope whose first command is `--frozen`.
- Fixed three tutorial pages that showed `moon add Luna-Flow/floating` without
  the version the other install snippets pin.
- Fixed exponent arithmetic that saturated at the 32-bit limits:
  `2^2e9 * 2^2e9` returned a finite value with no flag, and interval endpoints
  could stop enclosing the exact value.
- Fixed `exp`, `expm1`, `exp2`, `exp10`, `sinh`, `cosh` and `pow`, which could
  fail to certify results whose enclosures overflowed; they now decide
  overflow and underflow from certified bounds on $\log_2$ of the result.
- Fixed `ball_float` endpoint helpers that built exact values beyond the
  exponent range: `exp([1e9, 1e9])` aborted and `exp([-1e9, -1e9])` returned
  `[0, 0]`. Lower endpoints now clamp toward $-\infty$, upper endpoints toward
  $+\infty$, and `exp` of very large arguments returns
  `[max finite, +inf]` or `[0, smallest positive]`.
- Fixed interval addition of operands with a huge exponent gap, which built a
  two-billion-bit coefficient; an addend far below one ulp is replaced by a
  directed sticky term.
- Fixed the decimal certified bridge, which expanded binary endpoints near
  $2^{2^{30}}$ into hundreds of millions of digits (`sinh(1e300)` used several
  GB), and decimal power results far outside the exponent range, which are now
  decided before certification.

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
- Replaced `StringBuilder::new()` with the `StringBuilder()` custom
  constructor, which MoonBit 0.10.11 requires; the previous spelling fails the
  `--deny-warn` publish gate.

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
