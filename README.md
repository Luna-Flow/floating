# floating

[![Maintainer](https://img.shields.io/badge/Maintainer-KCN--judu-violet)](https://github.com/KCN-judu)
[![License](https://img.shields.io/badge/License-Apache--2.0-blue)](./LICENSE)
![State](https://img.shields.io/badge/State-active-success)

`Luna-Flow/floating` provides arbitrary-precision binary, IEEE decimal, General
Decimal Arithmetic, and certified interval arithmetic for MoonBit. Binary
values follow IEEE 754 at any precision, decimals keep their quantum, and
intervals are rounded outward so that they always contain the exact result.
Precision, rounding, exponent range, special values, status flags, traps and
enclosures are explicit values in every API rather than hidden global state.

## Install

```sh
moon add Luna-Flow/floating@0.8.0
```

The module needs the MoonBit toolchain 0.10 or later (`moonc` ≥ 0.10). Import
only the packages you use in your `moon.pkg`:

```text
import {
  "Luna-Flow/floating/bin_float",
  "Luna-Flow/floating/decimal",
  "Luna-Flow/floating/ball_float",
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

  // A decimal keeps the quantum of its literal.
  let (price, _) = @decimal.Decimal::from_string_ctx(
    "12.3400",
    @decimal.DecimalContext::decimal64(),
  )
  inspect(price.quantum(), content="-4")

  // An interval contains every exact result.
  let one = @ball_float.BallFloat::from_int(1, precision=53)
  let enclosure = one.div(@ball_float.BallFloat::from_int(3, precision=53))
  inspect(enclosure.contains(third), content="true")
}
```

The three results have different contracts: `third` is one rounded point with
the flags its rounding raised, `price` retains the quantum `-4` of `12.3400`,
and `enclosure` is a set of reals guaranteed to contain $1/3$.

## Packages

| Package | Purpose | Result model |
| --- | --- | --- |
| [`bin_float`](./doc/manual/api/bin_float.md) | arbitrary-precision binary floating point, IEEE 754 binary operations, binary16/32/64/128 interchange | value, or `(value, BinaryFlags)` under a `BinaryContext` |
| [`decimal`](./doc/manual/api/decimal.md) | IEEE 754 decimal arithmetic, decimal32/64/128 DPD and BID interchange | value, or `(value, DecimalFlags)` under a `DecimalContext` |
| [`decimal_gda`](./doc/manual/api/decimal_gda.md) | General Decimal Arithmetic with sticky status and traps | `GdaOutcome` with the defined result and the next context |
| [`ball_float`](./doc/manual/api/ball_float.md) | outward-rounded bare and decorated intervals (IEEE 1788) | interval, or `(interval, BallFlags)` under a `BallContext` |
| [`bin_float_checked`](./doc/manual/api/bin_float_checked.md) | binary pipeline that stops at the first error | `Result[BinFloat, ArithmeticError]` in a wrapper |
| [`decimal_checked`](./doc/manual/api/decimal_checked.md) | IEEE decimal pipeline that accumulates flags | value with latest and accumulated flags |
| [`decimal_gda_checked`](./doc/manual/api/decimal_gda_checked.md) | GDA pipeline that stops at a trap | one threaded `GdaOutcome` |
| [`ball_float_checked`](./doc/manual/api/ball_float_checked.md) | interval pipeline that stops at the first error | `Result[BallFloat, ArithmeticError]` in a wrapper |
| [`def`](./doc/manual/api/def.md) | shared vocabulary: `Sign`, `PartialOrder`, the `Floating` trait | — |
| [`semantic`](./doc/manual/api/semantic.md) | exact projection for comparing values across packages | exact rational, signed infinity or NaN |

Expression, corpus-frontend, CLI, benchmark, consistency and `internal/*`
packages are repository infrastructure. The
[package map](./doc/manual/index.md) lists all of them with their tutorial,
API and design pages.

## Documentation

The manual is published at <https://lunaflow.cn/en/floating/> in English,
Chinese and Japanese; its English source is in
[`doc/manual`](./doc/manual/index.md). Good starting points:

- [Getting started](./doc/manual/getting_started.md): choosing a package and
  first programs.
- [Numeric semantics](./doc/manual/numeric_semantics.md): rounding, ulp,
  flags, quantum, signed zero, NaN and enclosures.
- [Architecture](./doc/manual/architecture.md): layers, the numeric core
  pipeline and certified elementary functions.
- [Verification](./doc/manual/verification.md): gates and the scope of every
  conformance claim.

Conformance evidence is finite and pinned: the GDA `official` corpus passes
64,986/64,986 legal executable rows, the binary TestFloat level-1 matrix
254,227,872 vectors, and the strict ITF1788 aggregate 4,656/4,656 cases. Read
the conformance pages before turning a result into a compatibility claim.

## Development

The repository uses [`just`](https://github.com/casey/just) as its task runner.

```sh
just pr 8                    # pull-request gate
just fmt                     # format MoonBit sources
just docs                    # manual checks and documentation examples
just gate binary 8           # TestFloat and MPFR
just gate decimal 8          # IEEE decimal vectors
just gate decimal_gda 8      # GDA decTest corpora
just gate interval 8         # strict ITF1788
just ci 8                    # everything, before a release
```

Smoke fixtures, plans, pinned corpora, targets and phases go through one entry
point:

```sh
just conformance smoke binary
just conformance run decimal --run-target native --run-target wasm
just conformance run interval --phase trigonometric --strict-supported
```

Corpus provenance and options are described in
[`testdata/bin_float`](./testdata/bin_float/README.md),
[`testdata/decimal`](./testdata/decimal/README.md) and
[`testdata/interval`](./testdata/interval/README.md).

## Contributing

Contributions to correctness, documentation and test coverage are welcome.
Read [CONTRIBUTING](./CONTRIBUTING.md) for the workflow and the
[repository conventions](./doc/manual/conventions.md) for documentation and
API snapshot rules. Release history is in [CHANGELOG](./CHANGELOG.md).

## License

Apache-2.0. See [LICENSE](./LICENSE).
