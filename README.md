# FLOATING

[![Maintainer](https://img.shields.io/badge/Maintainer-KCN--judu-violet)](https://github.com/KCN-judu) [![License](https://img.shields.io/badge/License-Apache--2.0-blue)](./LICENSE) ![State](https://img.shields.io/badge/State-active-success)

## v0.4.0 - Decimal Context And Conformance Baseline

This README describes the implementation present in the **`v0.4.0`** branch.
Earlier release notes live in [CHANGELOG.md](./CHANGELOG.md).

`floating` provides arbitrary-precision binary, decimal, and interval arithmetic
for MoonBit. Its APIs make precision, rounding, exceptional values, checked
failure, and enclosure semantics explicit.

### Package Map

- **Core vocabulary**: `def` defines the shared `Floating` contract and reexports
  arithmetic boundary types. `internal` owns implementation helpers and is not a
  stable application-facing contract.
- **Numeric values**: `bin_float`, `decimal`, and `ball_float` provide binary,
  decimal, and outward-rounded interval representations.
- **Checked composition**: `bin_float_result`, `decimal_result`, and
  `ball_float_result` keep arithmetic pipelines closed over wrapped
  `Result[..., ArithmeticError]` values.
- **Semantic projection**: `semantic` maps concrete values and arithmetic errors
  into representation-independent exact rationals, infinities, NaN, intervals,
  and semantic errors.
- **Expression infrastructure**: `numeric_expr` supplies a private expression IR
  with callback-driven evaluation. `gda_expr` parses and executes General Decimal
  Arithmetic `.decTest` documents against `decimal`; `gda_expr_cli` is its native
  command-line entry point.
- **Verification**: `consistency` contains cross-package and API-audit tests.

### What Defines v0.4.0

- `Decimal` preserves quantum when parsing and exposes explicit `normalized()` /
  `reduce_ctx()` operations when canonical cohort form is wanted.
- `DecimalContext` carries precision, rounding, exponent bounds, clamp, and
  extended-mode settings. Context operations return `(Decimal, DecimalFlags)`.
- Decimal operations cover arithmetic, FMA, integer division, remainder,
  quantize/rescale, total comparison, logical digits, adjacent values,
  elementary functions, integral conversion, and context-aware formatting.
- `DecimalInterchange` supports decimal32, decimal64, and decimal128 hexadecimal
  interchange encodings with explicit status flags.
- Signed zero, quiet/signaling NaN, NaN payloads, infinity, normal/subnormal
  classification, and GDA class names are observable parts of the Decimal API.
- The native `gda_expr` pipeline parses `.decTest` files once, executes
  deterministic shards, and reports executable, skipped, unsupported, legacy,
  diagnostic, passed, and failed cases.
- Binary and ball arithmetic continue to use the checked-capability model. Ball
  division by an interval containing zero returns a whole-real enclosure.

### API Guidance

- Prefer `*_ctx` Decimal methods when flags and decimal-context behavior matter.
  Convenience operators do not expose status flags.
- Treat `DecimalFlags` as accumulated status: use `combine` when composing
  operations and `has_error` when checking hard-error conditions.
- Use checked scalar operations or the `*_result` packages for pipelines that
  must preserve `ArithmeticError` instead of collapsing failures.
- Do not use scalar total-order assumptions for `BallFloat`; use containment,
  overlap, separation, and definite comparison predicates.
- `numeric_expr` defines syntax only. Frontends own parsing and source policy;
  backends own literal and operation semantics.
- `gda_expr` is both a public parser/runner API and repository conformance
  infrastructure. Unsupported or legacy cases are counted separately from
  executable semantic failures.

### Installation

```sh
moon add Luna-Flow/floating@0.4.0
```

Import only the packages an application needs:

```moonbit nocheck
import {
  "Luna-Flow/floating/bin_float"
  "Luna-Flow/floating/decimal"
  "Luna-Flow/floating/ball_float"
  "Luna-Flow/floating/decimal_result"
}
```

### Quick Start

```moonbit check
///|
test "floating basic workflow" {
  let x = @bin_float.BinFloat::make(3N, -1, 32)
  let y = @bin_float.BinFloat::make(5N, -1, 32)
  inspect((x + y).to_string(), content="1p2")

  let ctx = @decimal.DecimalContext::decimal64()
  let (dec, parse_flags) = @decimal.Decimal::from_string_ctx("12.3400", ctx)
  inspect(parse_flags.has_error(), content="false")
  inspect(dec.same_quantum(@decimal.Decimal::from_string("0.0000").unwrap()), content="true")

  let ball = @ball_float.BallFloat::exact(dec.to_bin_float(precision=32))
  inspect(ball.contains(ball.center()), content="true")

  let checked =
    @decimal_result.DecimalResult::parse("9", precision=32)
    .sqrt()
    .div(@decimal_result.DecimalResult::from_int(3, precision=32))
  inspect(checked.result().unwrap().to_string(), content="1")
}
```

### Documentation

- [English](./doc/en_US/README.md)
- [简体中文](./doc/zh_CN/README.md)
- [日本語](./doc/ja_JP/README.md)
- [Documentation standard](./doc/en_US/doc_standard.md)
- [Decimal conformance workflow](./testdata/decimal/README.md)
- [Release history](./CHANGELOG.md)

## Development

```sh
just fmt
just smoke
just fetch
just plan jobs=8
just pr jobs=8
just ci
```

`just smoke` runs the checked-in conformance fixture without a download.
`just pr` performs all-target checks, refreshes generated interfaces, builds the
native interpreter, and runs the staged official corpus. `just ci` is a focused
white-box gate and is not a substitute for full conformance validation. See
[the conformance data guide](./testdata/decimal/README.md) for case filters,
phases, sharding, strict mode, JSON output, and failure triage.

## Release Checklist

1. Set the release version in `moon.mod`.
2. Align the root and localized current-baseline documentation.
3. Record the release in `CHANGELOG.md`.
4. Run `just pr`.
5. Trigger the `publish-package` workflow; it reads the version from `moon.mod`.

See [CONTRIBUTING.md](./CONTRIBUTING.md) for contribution guidance.
