# FLOATING

[![Maintainer](https://img.shields.io/badge/Maintainer-KCN--judu-violet)](https://github.com/KCN-judu) [![License](https://img.shields.io/badge/License-Apache--2.0-blue)](./LICENSE) ![State](https://img.shields.io/badge/State-active-success)

## v0.6.1 - IEEE/GDA Decimal Semantic Split

This README describes the **`v0.6.1`** release.
Earlier release notes live in [CHANGELOG.md](./CHANGELOG.md).

`floating` provides arbitrary-precision binary, decimal, and interval arithmetic
for MoonBit. Its APIs make precision, rounding, exceptional values, checked
failure, and enclosure semantics explicit.

### Package Map

- **Core vocabulary**: `def` defines the shared `Floating` contract and reexports
  arithmetic boundary types. `internal` owns implementation helpers and is not a
  stable application-facing contract.
- **Numeric values**: `bin_float`, `decimal`, `decimal_gda`, and `ball_float`
  provide binary, IEEE decimal, GDA decimal, and outward-rounded interval
  representations. `bin_float` also
  exposes IEEE 754 contexts, status flags, and binary16/32/64/128 interchange.
- **IEEE/GDA decimal split**: `decimal` owns IEEE contexts and per-operation
  flags; `decimal_gda` owns GDA sticky status, traps, signals, and defined trap
  results. Their public values are intentionally distinct.
- **IEEE intervals**: `ball_float` provides bare Empty/Entire set semantics,
  tight arithmetic, certified elementary enclosures, and
  `BallFloatDecorated` with decorations and NaI. The pinned ITF1788 runner
  gates its declared arithmetic and elementary phases strictly.
- **Checked composition**: `bin_float_checked` and `ball_float_checked` retain
  `Result[..., ArithmeticError]`. `decimal_checked` keeps an IEEE context,
  defined result, and accumulated flags; `decimal_gda_checked` threads sticky
  GDA context and stops on traps until recovery is explicit.
- **Semantic projection**: `semantic` maps concrete values and arithmetic errors
  into representation-independent exact rationals, infinities, NaN, intervals,
  and semantic errors.
- **Expression infrastructure**: `numeric_expr` supplies a private expression IR
  with callback-driven evaluation. The `frontend` package tree contains the GDA,
  TestFloat, MPFR, and ITL parsers/runners; `cli` provides their shared native
  command-line entry point.
- **Verification**: `consistency` contains cross-package and API-audit tests.

### What Defines v0.6.1

- `Decimal` preserves quantum when parsing and exposes explicit `normalized()` /
  `reduce_ctx()` operations when canonical cohort form is wanted.
- `DecimalContext` carries positive precision, IEEE rounding, exponent bounds,
  clamp, and selectable before/after tininess. IEEE operations return
  `(Decimal, DecimalFlags)`.
- `decimal_gda` exposes independent `GdaContext`, `GdaFlags`, trap sets, and
  `GdaOutcome`, including sticky status and defined results for traps.
- `decimal_checked` and `decimal_gda_checked` preserve those distinct state
  models in closed pipelines instead of flattening both into `ArithmeticError`.
- Decimal operations cover arithmetic, FMA, integer division, remainder,
  quantize/rescale, total comparison, logical digits, adjacent values,
  elementary functions, integral conversion, and context-aware formatting.
- `DecimalInterchange` supports decimal32, decimal64, and decimal128 hexadecimal
  interchange encodings with explicit status flags.
- Signed zero, quiet/signaling NaN, NaN payloads, infinity, normal/subnormal
  classification, and GDA class names are observable parts of the Decimal API.
- `BinFloat` preserves signed zero and NaN state, and its contextual add/sub/
  mul/div/sqrt operations derive IEEE flags from exact dyadic/rational results
  before bounded-format encoding.
- The native `gda_expr` pipeline parses `.decTest` files once, executes
  deterministic shards, and reports executable, skipped, unsupported, legacy,
  diagnostic, passed, and failed cases.
- Binary and ball arithmetic continue to use the checked-capability model. Ball
  arithmetic uses tight outward-rounded endpoint enclosures; `BallContext`
  supplies binary32/binary64 exponent bounds and status flags.

### Binary Coefficient Kernel

The binary and ball stacks now use a non-negative `BinCoeff` plus an
independent sign. Non-JS targets store coefficients in an inline/limb kernel;
the JS target uses a hidden host `bigint` adapter with the same public API.
`Decimal` and `Semantic` intentionally retain their existing `BigInt`
boundaries.

| Old binary API | New API |
| --- | --- |
| `BinFloat::from_bigint(n)` | `BinFloat::from_coefficient(c, negative=...)` |
| `BinFloat::make(n, e, p)` | `BinFloat::make(c, e, p, negative=...)` |
| `BinFloat::significand()` | `BinFloat::coefficient()` |
| `BallFloat::from_bigint(n)` | `BallFloat::from_coefficient(c, negative=...)` |
| `BinaryInterchange::from_bits(n, format)` / `bits() -> BigInt` | `from_bits(c, format)` / `bits() -> BinCoeff` |
| checked `from_bigint(n)` | checked `from_coefficient(c, negative=...)` |

Construct coefficients explicitly with `BinCoeff::from_uint64`, `parse`, or
`from_bytes_be`; do not depend on `BigInt` literals at the binary API boundary.

### Verified GDA Conformance

- Current `official` corpus: 144 files, **64,986 / 64,986 legal executable cases
  passed**, 0 failed, 0 unsupported, and 0 legacy-condition cases. The remaining
  141 rows are the corpus's `#` placeholder/non-scalar invalid inputs and are
  intentionally excluded from executable semantics.
- Legacy `official0` corpus: 32 files, **16,124 / 16,124 legal executable cases
  passed**, 0 failed; its excluded rows are the same `#` placeholder class.

This is a complete conformance claim for the legal scalar rows represented by
the pinned official corpora. The runner reports `#` rows separately so invalid
interchange placeholders cannot be confused with implemented GDA behavior.

### Verified IEEE Decimal Interchange

The independent `testdata/decimal/ieee` corpus covers decimal32/64/128 DPD and
BID fixed-width interchange, special values, flags, and core arithmetic rows.
Its manifest records IEEE encoding and independent exact-arithmetic provenance;
the exhaustive DPD fixture checks all 1,024 declets. `just gate decimal` runs this
gate on native, Wasm, Wasm-GC, and JavaScript; LLVM is intentionally excluded.
The gate also executes a 42-row excerpt from the pinned `dd*`/`dq*` decTest
concrete-format files as supplementary diagnostics. decTest is GDA, beta, and
non-exhaustive; it is not a complete IEEE oracle or a compliance claim.

### Verified Binary Conformance

- Berkeley TestFloat 3e level 1, all binary16/32/64/128 contextual add/sub/
  mul/div/sqrt combinations, five rounding directions, and both tininess modes:
  **7,461,360 / 7,461,360** passed.
- GNU MPFR 4.2.2 `sqrt` data: **1,055 / 1,055** executable rows passed.

The checked claim is intentionally restricted to that pinned finite matrix;
it does not claim all IEEE 754 operations. See the
[BinFloat conformance guide](./testdata/bin_float/README.md).

### API Guidance

- Prefer `*_ctx` Decimal methods when flags and decimal-context behavior matter.
  Convenience operators do not expose status flags.
- Treat `DecimalFlags` as accumulated status: use `combine` when composing
  operations and `has_error` when checking hard-error conditions.
- Use `decimal_checked` to retain IEEE defined results and accumulate flags.
  Use `decimal_gda_checked` to thread sticky status and short-circuit traps
  without discarding their defined results.
- Do not use scalar total-order assumptions for `BallFloat`; use containment,
  overlap, separation, and definite comparison predicates.
- `numeric_expr` defines syntax only. Frontends own parsing and source policy;
  backends own literal and operation semantics.
- `frontend/gda_expr` is both a public parser/runner API and repository
  conformance infrastructure. Its only excluded official-corpus rows are `#`
  placeholder/non-scalar invalid inputs; legal GDA rows are executable and
  conformant.

### Installation

```sh
moon add Luna-Flow/floating@0.6.1
```

Import only the packages an application needs:

```moonbit nocheck
import {
  "Luna-Flow/floating/bin_float"
  "Luna-Flow/floating/decimal"
  "Luna-Flow/floating/decimal_gda"
  "Luna-Flow/floating/ball_float"
  "Luna-Flow/floating/decimal_checked"
  "Luna-Flow/floating/decimal_gda_checked"
}
```

### Quick Start

```moonbit check
///|
test "floating basic workflow" {
  let x = @bin_float.BinFloat::make(
    @bin_float.BinCoeff::from_uint64(3UL),
    -1,
    32,
  )
  let y = @bin_float.BinFloat::make(
    @bin_float.BinCoeff::from_uint64(5UL),
    -1,
    32,
  )
  inspect((x + y).to_string(), content="1p2")

  let ctx = @decimal.DecimalContext::decimal64()
  let (dec, parse_flags) = @decimal.Decimal::from_string_ctx("12.3400", ctx)
  inspect(parse_flags.has_error(), content="false")
  inspect(dec.same_quantum(@decimal.Decimal::from_string("0.0000").unwrap()), content="true")

  let ball = @ball_float.BallFloat::exact(dec.to_bin_float(precision=32))
  inspect(ball.contains(ball.center()), content="true")

  let checked = @decimal_checked.DecimalChecked::parse("9", ctx)
    .sqrt()
    .div(@decimal.Decimal::from_int(3, precision=ctx.precision()))
  inspect(checked.value().to_string(), content="1")
  inspect(checked.flags().has_error(), content="false")

  let gda_checked = @decimal_gda_checked.GdaDecimalChecked::parse(
    "9",
    @decimal_gda.GdaContext::decimal64(),
  ).sqrt()
  inspect(gda_checked.value().to_string(), content="3")
  inspect(gda_checked.is_trapped(), content="false")
}
```

### Documentation

- [English](./doc/en_US/README.md)
- [简体中文](./doc/zh_CN/README.md)
- [日本語](./doc/ja_JP/README.md)
- [Getting started](./doc/en_US/getting_started.md)
- [Numeric semantics](./doc/en_US/numeric_semantics.md)
- [Architecture](./doc/en_US/architecture.md)
- [Verification](./doc/en_US/verification.md)
- [Documentation standard](./doc/en_US/doc_standard.md)
- [Binary conformance](./doc/en_US/bin_float/conformance.md) and [performance](./doc/en_US/bin_float/performance.md)
- [IEEE decimal conformance](./doc/en_US/decimal/conformance.md) and [performance](./doc/en_US/decimal/performance.md)
- [GDA decimal conformance](./doc/en_US/decimal_gda/conformance.md)
- [Interval conformance](./doc/en_US/ball_float/conformance.md)
- [Decimal conformance workflow](./testdata/decimal/README.md)
- [BinFloat conformance workflow](./testdata/bin_float/README.md)
- [Release history](./CHANGELOG.md)

## Development

All user-facing conformance workflows use one parameterized `just` entry point:

```sh
just conformance smoke decimal_gda
just conformance plan decimal
just conformance run decimal --run-target native --run-target wasm --run-target wasm-gc --run-target js
just conformance smoke binary
just conformance smoke interval --strict-supported
just conformance build binary
```

Parameterized builds use isolated target directories and backend-named outputs
such as `testfloat-conformance.exe` and `mpfr-conformance.exe`, so different
backend jobs can build concurrently without overwriting one another.

`just conformance` selects an action and backend. `just gate` selects a complete
repository or backend gate and accepts an optional worker count. `just bench`
selects one of the independent performance workflows.

```sh
just fmt
just conformance smoke decimal_gda
just conformance fetch decimal_gda official
just conformance plan decimal_gda --jobs 8
just pr 8
just gate decimal 8
just gate decimal_gda 8
just gate binary 8
just gate interval 8
just ci 8
just conformance smoke binary
just conformance fetch binary
just conformance run binary --level 1 --tininess after --tininess before
just conformance smoke interval
just conformance fetch interval itf1788
just conformance run interval --phase sets --phase relations --strict-supported
just bench decimal --target native
```

The `smoke` action runs a checked-in fixture without a download. Gate scopes
`decimal`, `decimal_gda`, `binary`, and `interval` run the corresponding
authoritative suites. IEEE Decimal uses `decimal`; GDA decTest uses
`decimal_gda`.
`just pr` runs the fast pull-request gate:
all-target checks, native MoonBit tests, Python tooling tests, and the four
committed smoke suites. `just ci` is the complete long gate with generated
interface validation, all-target MoonBit tests, and all four conformance
suites. See
[the conformance data guide](./testdata/decimal/README.md) for case filters,
phases, sharding, strict mode, JSON output, and failure triage.

The interval commands run the committed smoke corpus or the pinned Apache-2.0
ITF1788 corpus. See [the interval data guide](./testdata/interval/README.md) for
the current strict phase boundary.

The binary commands run the committed smoke fixture or the SHA-256-pinned
TestFloat/MPFR gate through native MoonBit interpreters. See
[the binary data guide](./testdata/bin_float/README.md) for the declared
operation and corpus boundary.

Coverage reports are local generated artifacts. Run MoonBit tests with
`--enable-coverage` when needed; `_coverage/` and `coverage_summary.txt` remain
ignored and are not maintained as versioned audit evidence.

## Release Checklist

1. Set the release version in `moon.mod`.
2. Align the root and localized current-baseline documentation.
3. Record the release in `CHANGELOG.md`.
4. Run `just ci`.
5. Trigger the `publish-package` workflow; it reads the version from `moon.mod`.

See [CONTRIBUTING.md](./CONTRIBUTING.md) for contribution guidance.
