# FLOATING

[![Maintainer](https://img.shields.io/badge/Maintainer-KCN--judu-violet)](https://github.com/KCN-judu)
[![License](https://img.shields.io/badge/License-Apache--2.0-blue)](./LICENSE)
![State](https://img.shields.io/badge/State-active-success)

`Luna-Flow/floating` 0.7.1 provides arbitrary-precision binary, decimal, GDA
decimal, and certified interval arithmetic for MoonBit. Precision, rounding,
special values, status flags, traps, and enclosure semantics are explicit
rather than hidden in process-global state.

## Start Here

- New user: [Getting Started](./doc/en_US/getting_started.md)
- Choose a package: [Package Guide](#package-guide)
- Copy a minimal example: [Quick Start](#quick-start)
- Understand algorithms and boundaries: [Architecture](./doc/en_US/architecture.md)
- Check numerical claims: [Verification](./doc/en_US/verification.md)
- See 0.7.1 changes: [CHANGELOG](./CHANGELOG.md)
- Read the optimization evidence: [0.7.1 audit](./doc/en_US/performance_audit.md)
- Other languages: [简体中文](./doc/zh_CN/README.md) ·
  [日本語](./doc/ja_JP/README.md)

## Install

```sh
moon add Luna-Flow/floating@0.7.1
```

Import only the packages used by the current MoonBit package:

```moonbit nocheck
import {
  "Luna-Flow/floating/bin_float"
  "Luna-Flow/floating/decimal"
  "Luna-Flow/floating/decimal_gda"
  "Luna-Flow/floating/ball_float"
}
```

## Quick Start

```moonbit check
///|
test "floating 0.7.1 quick start" {
  let binary = @bin_float.BinFloat::make(
    @bin_float.BinCoeff::from_uint64(3UL),
    -1,
    53,
  )
  inspect(binary.to_double(), content="1.5")

  let context = @decimal.DecimalContext::decimal64()
  let (decimal, flags) = @decimal.Decimal::from_string_ctx("12.3400", context)
  inspect(decimal.quantum(), content="-4")
  inspect(flags.has_error(), content="false")

  let interval = @ball_float.BallFloat::from_bounds(
    @bin_float.BinFloat::from_int(1, precision=53),
    @bin_float.BinFloat::from_int(2, precision=53),
  )
  inspect(interval.contains(binary), content="true")
}
```

The three values have different contracts: `binary` is one exact dyadic point,
`decimal` retains the input quantum, and `interval` denotes every real value in
`[1, 2]`.

## Package Guide

| Requirement | Package | Result model | Documentation |
| --- | --- | --- | --- |
| arbitrary-precision dyadic and IEEE binary interchange | `bin_float` | value or `(value, BinaryFlags)` | [API](./doc/en_US/bin_float/api.md) · [Tutorial](./doc/en_US/bin_float/tutorial.md) · [Design](./doc/en_US/bin_float/design.md) |
| IEEE decimal and DPD/BID interchange | `decimal` | value or `(value, DecimalFlags)` | [API](./doc/en_US/decimal/api.md) · [Tutorial](./doc/en_US/decimal/tutorial.md) · [Design](./doc/en_US/decimal/design.md) |
| General Decimal Arithmetic status and traps | `decimal_gda` | `GdaOutcome` with defined result and next context | [API](./doc/en_US/decimal_gda/api.md) · [Tutorial](./doc/en_US/decimal_gda/tutorial.md) · [Design](./doc/en_US/decimal_gda/design.md) · [Performance](./doc/en_US/decimal_gda/performance.md) |
| certified real enclosure and IEEE 1788 decorations | `ball_float` | bare/decorated interval, optionally with `BallFlags` | [API](./doc/en_US/ball_float/api.md) · [Tutorial](./doc/en_US/ball_float/tutorial.md) · [Design](./doc/en_US/ball_float/design.md) · [Performance](./doc/en_US/ball_float/performance.md) |
| first-error binary pipeline | `bin_float_checked` | `Result[BinFloat, ArithmeticError]` wrapper | [Tutorial](./doc/en_US/bin_float_checked/tutorial.md) |
| accumulated IEEE decimal pipeline | `decimal_checked` | value + latest/combined flags + optional certification error | [Tutorial](./doc/en_US/decimal_checked/tutorial.md) |
| sticky/trapping GDA pipeline | `decimal_gda_checked` | one threaded `GdaOutcome` | [Tutorial](./doc/en_US/decimal_gda_checked/tutorial.md) |
| first-error interval pipeline | `ball_float_checked` | `Result[BallFloat, ArithmeticError]` wrapper | [Tutorial](./doc/en_US/ball_float_checked/tutorial.md) |
| representation-independent observation | `semantic` | exact scalar/interval projection | [API](./doc/en_US/semantic/api.md) |

Parser, CLI, benchmark, consistency, and `internal/*` packages are repository
infrastructure. See the [full documentation index](./doc/en_US/README.md) before
depending on them as application APIs.

## 0.7.1 At A Glance

- `BinFloat`, `Decimal`, and `BallFloat` expose certified elementary-function
  paths with bounded refinement and structured certification failure.
- Binary and decimal coefficient kernels use target-specific, exact-fallback
  dispatch across schoolbook, Karatsuba, Toom-3, NTT, block division, and
  reciprocal algorithms.
- `decimal` and `decimal_gda` are independent state models: IEEE per-operation
  flags are not GDA sticky status/traps.
- `ball_float` covers the declared strict IEEE 1788 phases with bare/decorated
  intervals, critical-point/pole handling, and conservative total fallbacks.
- Benchmarks moved into the unified `bench/*` Maremark hierarchy with explicit
  crossover and regression analysis.
- The 0.7.1 optimization audit records exact-kernel, directed-rounding, and
  interval-monotonicity proofs for the optimized paths.
- The native benchmark artifact covers all four core suites; non-monotonic
  auto-tune observations remain evidence only until independently replicated.

Detailed claims and exclusions live in package-local evidence pages:

- [Binary conformance](./doc/en_US/bin_float/conformance.md) ·
  [performance](./doc/en_US/bin_float/performance.md)
- [IEEE decimal conformance](./doc/en_US/decimal/conformance.md) ·
  [performance](./doc/en_US/decimal/performance.md)
- [GDA decimal conformance](./doc/en_US/decimal_gda/conformance.md) ·
  [performance](./doc/en_US/decimal_gda/performance.md)
- [Interval conformance](./doc/en_US/ball_float/conformance.md) ·
  [performance](./doc/en_US/ball_float/performance.md)
- [Elementary capability matrix](./testdata/elementary/capability_matrix.json)

Performance thresholds are implementation evidence, not API promises. Passing
a pinned finite corpus does not imply support for every operation or every real
input.

## Development

Run the fast pull-request gate:

```sh
just pr 8
```

Useful focused commands:

```sh
just fmt
just docs
just gate binary 8
just gate decimal 8
just gate decimal_gda 8
just gate interval 8
just bench bin-float --target native
just bench auto-tune --target native
```

Use the parameterized conformance entry point for smoke fixtures, plans, pinned
corpora, targets, and phases:

```sh
just conformance smoke binary
just conformance run decimal --run-target native --run-target wasm
just conformance run interval --phase trigonometric --strict-supported
```

Operational corpus details live under
[`testdata/bin_float`](./testdata/bin_float/README.md),
[`testdata/decimal`](./testdata/decimal/README.md), and
[`testdata/interval`](./testdata/interval/README.md).

Before release, run the complete gate:

```sh
just ci 8
```

See [CONTRIBUTING](./CONTRIBUTING.md) for contribution rules and
[Documentation Standard](./doc/en_US/doc_standard.md) for localization/API
snapshot requirements.

## License

Apache-2.0. See [LICENSE](./LICENSE).
