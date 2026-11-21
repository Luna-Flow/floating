# floating

[![Maintainer](https://img.shields.io/badge/Maintainer-KCN--judu-violet)](https://github.com/KCN-judu)
[![License](https://img.shields.io/badge/License-Apache--2.0-blue)](./LICENSE)
![State](https://img.shields.io/badge/State-active-success)

`Luna-Flow/floating` provides arbitrary-precision binary, IEEE decimal, General
Decimal Arithmetic, and certified interval arithmetic for MoonBit. Binary
values follow IEEE 754 at any precision, decimals keep their exponent, and
intervals are rounded outward so that they always contain the exact result.
Precision, rounding, exponent range, special values, status flags, traps and
enclosures are explicit values in every API rather than hidden global state.

## Install

```bash
moon add Luna-Flow/floating@0.11.0
```

The module needs the MoonBit toolchain with `moonc` 0.10.20 or later (verified with `moon 0.1.20261104` and `moonc v0.10.20`; older 0.10 compilers ignore `#derive`). Import
only the packages you use in your `moon.pkg`:

```moonbit nocheck
import {
  "Luna-Flow/floating/bin_float",
  "Luna-Flow/floating/decimal",
  "Luna-Flow/floating/interval",
}
```

## Quick start

```moonbit
///|
test "floating quick start" {
  // One third, correctly rounded to binary64, with its IEEE status.
  let ctx = @bin_float.BinaryContext::binary64()
  let (third, flags) = @bin_float.BinFloat::from_int(1).div_ctx(
    @bin_float.BinFloat::from_int(3),
    ctx,
  )
  inspect(third.to_shortest_string(), content="0.3333333333333333")
  inspect(flags.inexact(), content="true")

  // A decimal keeps the exponent of its literal.
  let (price, _) = @decimal.Decimal::from_string_ctx(
    "12.3400",
    @decimal.DecimalContext::decimal64(),
  )
  inspect(price.exponent10(), content="-4")

  // An interval contains every exact result.
  let one = @interval.Interval::from_int(1, precision=53)
  let enclosure = one.div(@interval.Interval::from_int(3, precision=53))
  inspect(enclosure.contains(third), content="true")
}
```

The three results have different contracts: `third` is one rounded point with
the flags its rounding raised, `price` retains the exponent `-4` of `12.3400`,
and `enclosure` is a set of reals guaranteed to contain $1/3$.

## Packages

| Package | Purpose | Result model |
| --- | --- | --- |
| [`bin_float`](https://github.com/Luna-Flow/floating/blob/main/doc/manual/api/bin_float.md) | arbitrary-precision binary floating point, IEEE 754 binary operations, binary16/32/64/128 interchange | value, or `(value, BinaryFlags)` under a `BinaryContext` |
| [`decimal`](https://github.com/Luna-Flow/floating/blob/main/doc/manual/api/decimal.md) | IEEE 754 decimal arithmetic, decimal32/64/128 DPD and BID interchange | value, or `(value, DecimalFlags)` under a `DecimalContext` |
| [`decimal_gda`](https://github.com/Luna-Flow/floating/blob/main/doc/manual/api/decimal_gda.md) | General Decimal Arithmetic with sticky status and traps | `GdaOutcome` with the defined result and the next context |
| [`interval`](https://github.com/Luna-Flow/floating/blob/main/doc/manual/api/interval.md) | outward-rounded bare and decorated intervals (IEEE 1788) | interval, or `(interval, IntervalFlags)` under an `IntervalContext` |
| [`bin_float_checked`](https://github.com/Luna-Flow/floating/blob/main/doc/manual/api/bin_float_checked.md) | binary pipeline that stops at the first error | `Result[BinFloat, ArithmeticError]` in a wrapper |
| [`decimal_checked`](https://github.com/Luna-Flow/floating/blob/main/doc/manual/api/decimal_checked.md) | IEEE decimal pipeline that accumulates flags | value with latest and accumulated flags |
| [`decimal_gda_checked`](https://github.com/Luna-Flow/floating/blob/main/doc/manual/api/decimal_gda_checked.md) | GDA pipeline that stops at a trap | one threaded `GdaOutcome` |
| [`interval_checked`](https://github.com/Luna-Flow/floating/blob/main/doc/manual/api/interval_checked.md) | interval pipeline that stops at the first error | `Result[Interval, ArithmeticError]` in a wrapper |
| [`def`](https://github.com/Luna-Flow/floating/blob/main/doc/manual/api/def.md) | shared vocabulary: `Sign`, `PartialOrder`, the `Floating` trait | — |

Expression, corpus-frontend, CLI, benchmark and differential-testing packages
are not part of this module: they live in the separate module
`Luna-Flow/floating-tools` of the same repository, next to the library. The
[package map](https://github.com/Luna-Flow/floating/blob/main/doc/manual/index.md) lists every package with its tutorial,
API and design pages; `internal` and `internal/decimal_kernel` stay in this module as
repository infrastructure.

## Documentation

The manual is published at <https://lunaflow.cn/en/floating/> in English,
Chinese and Japanese; its English source is in
[`doc/manual`](https://github.com/Luna-Flow/floating/blob/main/doc/manual/index.md). Good starting points:

- [Getting started](https://github.com/Luna-Flow/floating/blob/main/doc/manual/getting_started.md): choosing a package and
  first programs.
- [Numeric semantics](https://github.com/Luna-Flow/floating/blob/main/doc/manual/numeric_semantics.md): rounding, ulp,
  flags, exponent, signed zero, NaN and enclosures.
- [Architecture](https://github.com/Luna-Flow/floating/blob/main/doc/manual/architecture.md): layers, the numeric core
  pipeline and certified elementary functions.
- [Verification](https://github.com/Luna-Flow/floating/blob/main/doc/manual/verification.md): gates and the scope of every
  conformance claim.

Conformance evidence is finite and pinned: the GDA `official` corpus passes
64,986/64,986 legal executable rows, the binary TestFloat level-1 matrix
254,227,872 vectors, and the strict ITF1788 aggregate 4,656/4,656 cases. Read
the conformance pages before turning a result into a compatibility claim.

## Stability

The public API of every package follows the changelog of each release. `Floating` in
`def` is implemented by the types of this library only; implementing it for a
type outside this module is not supported and not covered by the compatibility
promise, because methods may be added to the trait in a minor release.

## Development

The repository ([Luna-Flow/floating](https://github.com/Luna-Flow/floating)) holds
this module in `library/`, the tools module in `tooling/`, the manual, the pinned
corpora and the gate scripts. The task runner, the gates and the conformance
entry points are described in the
[repository README](https://github.com/Luna-Flow/floating#readme) and in
[CONTRIBUTING](https://github.com/Luna-Flow/floating/blob/main/CONTRIBUTING.md); the corpora are documented under
[`testdata`](https://github.com/Luna-Flow/floating/blob/main/testdata/).

## Contributing

Contributions to correctness, documentation and test coverage are welcome.
Read [CONTRIBUTING](https://github.com/Luna-Flow/floating/blob/main/CONTRIBUTING.md) for the workflow and the
[repository conventions](https://github.com/Luna-Flow/floating/blob/main/doc/manual/conventions.md) for documentation and
API snapshot rules. Release history is in [CHANGELOG](./CHANGELOG.md).

## License

Apache-2.0. See [LICENSE](./LICENSE).
