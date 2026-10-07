# FLOATING

<!-- historical-performance-baseline: 0.7.1 -->

[![Maintainer](https://img.shields.io/badge/Maintainer-KCN--judu-violet)](https://github.com/KCN-judu)
[![License](https://img.shields.io/badge/License-Apache--2.0-blue)](./LICENSE)
![State](https://img.shields.io/badge/State-active-success)

`Luna-Flow/floating` 0.8.0 provides arbitrary-precision binary, decimal, GDA
decimal, and certified interval arithmetic for MoonBit. Precision, rounding,
special values, status flags, traps, and enclosure semantics are explicit
rather than hidden in process-global state.

## Start Here

- New user: [Getting Started](./doc/manual/getting_started.md)
- Choose a package: [Package Guide](#package-guide)
- Copy a minimal example: [Quick Start](#quick-start)
- Understand algorithms and boundaries: [Architecture](./doc/manual/architecture.md)
- Check numerical claims: [Verification](./doc/manual/verification.md)
- See 0.8.0 changes: [CHANGELOG](./CHANGELOG.md)
- Read the optimization evidence: [0.7.1 audit](./doc/manual/performance_audit.md)
- Read the documentation: [luna-flow.github.io/en/floating](https://luna-flow.github.io/en/floating/)
  (English, 简体中文, 日本語); the English sources live in [`doc/manual`](./doc/manual/index.md)

## Install

```sh
moon add Luna-Flow/floating@0.8.0
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
test "floating 0.8.0 quick start" {
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
| arbitrary-precision dyadic and IEEE binary interchange | `bin_float` | value or `(value, BinaryFlags)` | [API](./doc/manual/api/bin_float.md) · [Tutorial](./doc/manual/tutorial/bin_float.md) · [Design](./doc/manual/design/bin_float.md) |
| IEEE decimal and DPD/BID interchange | `decimal` | value or `(value, DecimalFlags)` | [API](./doc/manual/api/decimal.md) · [Tutorial](./doc/manual/tutorial/decimal.md) · [Design](./doc/manual/design/decimal.md) |
| General Decimal Arithmetic status and traps | `decimal_gda` | `GdaOutcome` with defined result and next context | [API](./doc/manual/api/decimal_gda.md) · [Tutorial](./doc/manual/tutorial/decimal_gda.md) · [Design](./doc/manual/design/decimal_gda.md) · [Performance](./doc/manual/performance/decimal_gda.md) |
| certified real enclosure and IEEE 1788 decorations | `ball_float` | bare/decorated interval, optionally with `BallFlags` | [API](./doc/manual/api/ball_float.md) · [Tutorial](./doc/manual/tutorial/ball_float.md) · [Design](./doc/manual/design/ball_float.md) · [Performance](./doc/manual/performance/ball_float.md) |
| first-error binary pipeline | `bin_float_checked` | `Result[BinFloat, ArithmeticError]` wrapper | [Tutorial](./doc/manual/tutorial/bin_float_checked.md) |
| accumulated IEEE decimal pipeline | `decimal_checked` | value + latest/combined flags + optional certification error | [Tutorial](./doc/manual/tutorial/decimal_checked.md) |
| sticky/trapping GDA pipeline | `decimal_gda_checked` | one threaded `GdaOutcome` | [Tutorial](./doc/manual/tutorial/decimal_gda_checked.md) |
| first-error interval pipeline | `ball_float_checked` | `Result[BallFloat, ArithmeticError]` wrapper | [Tutorial](./doc/manual/tutorial/ball_float_checked.md) |
| representation-independent observation | `semantic` | exact scalar/interval projection | [API](./doc/manual/api/semantic.md) |

Parser, CLI, benchmark, consistency, and `internal/*` packages are repository
infrastructure. See the [full documentation index](./doc/manual/index.md) before
depending on them as application APIs.

## 0.8.0 At A Glance

- `BinFloat`, `Decimal`, and `BallFloat` expose certified elementary-function
  paths with bounded refinement and structured certification failure.
- Binary and decimal coefficient kernels use target-specific, exact-fallback
  dispatch across schoolbook, Karatsuba, Toom-3, NTT, block division, and
  reciprocal algorithms.
- `decimal` and `decimal_gda` are independent state models: IEEE per-operation
  flags are not GDA sticky status/traps.
- `BinFloat` implements the contextual arithmetic traits, so binary, IEEE
  decimal, and GDA decimal all compose through the same `ArithmeticContext`.
- Converting an `ArithmeticContext` into a binary or decimal context now carries
  `e_min`, `e_max`, and `clamp`; contextual operations honour the caller's
  exponent range instead of running unbounded.
- `ball_float` covers the declared strict IEEE 1788 phases with bare/decorated
  intervals, critical-point/pole handling, and conservative total fallbacks.
- Benchmarks moved into the unified `bench/*` Maremark hierarchy with explicit
  crossover and regression analysis.
- The 0.7.1 optimization audit records exact-kernel, directed-rounding, and
  interval-monotonicity proofs for the optimized paths.
- The native benchmark artifact covers all four core suites; non-monotonic
  auto-tune observations remain evidence only until independently replicated.

Detailed claims and exclusions live in package-local evidence pages:

- [Binary conformance](./doc/manual/conformance/bin_float.md) ·
  [performance](./doc/manual/performance/bin_float.md)
- [IEEE decimal conformance](./doc/manual/conformance/decimal.md) ·
  [performance](./doc/manual/performance/decimal.md)
- [GDA decimal conformance](./doc/manual/conformance/decimal_gda.md) ·
  [performance](./doc/manual/performance/decimal_gda.md)
- [Interval conformance](./doc/manual/conformance/ball_float.md) ·
  [performance](./doc/manual/performance/ball_float.md)
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
[Repository conventions](./doc/manual/conventions.md) for documentation and
API snapshot requirements.

## License

Apache-2.0. See [LICENSE](./LICENSE).
