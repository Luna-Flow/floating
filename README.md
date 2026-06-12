# FLOATING

[![img](https://img.shields.io/badge/Maintainer-KCN--judu-violet)](https://github.com/KCN-judu) [![img](https://img.shields.io/badge/License-Apache%202.0-blue)](https://github.com/Luna-Flow/floating/blob/main/LICENSE) ![img](https://img.shields.io/badge/State-active-success)

## v0.3.0 - Result Wrapper and Checked Composition Baseline

This documentation tracks the current repository baseline for **`v0.3.0`**.
It describes the implementation that exists in this branch today.

### Package Positioning

- **`def`**: `floating`-local support such as `Sign`, `PartialOrder`, and the narrow `Floating` trait, plus compatibility reexports for arithmetic-boundary types.
- **`bin_float`**: Arbitrary-precision binary floating-point values represented by significand, base-2 exponent, and working precision.
- **`decimal`**: Arbitrary-precision decimal floating-point values represented by coefficient, base-10 exponent, and working precision.
- **`ball_float`**: Interval/ball arithmetic values represented by outward-rounded bounds, built on top of `bin_float`.
- **`bin_float_result`**: `Result[BinFloat, ArithmeticError]` wrapped as a closed numeric object for checked composition.
- **`decimal_result`**: `Result[Decimal, ArithmeticError]` wrapped as a closed numeric object for checked composition.
- **`ball_float_result`**: `Result[BallFloat, ArithmeticError]` wrapped as a closed interval object for checked composition.
- **`internal`**: Shared normalization, integer-factor removal, rounding, and decimal parsing helpers.
- **`consistency`**: Repository tests covering normalization, conversion, arithmetic, and cross-package semantic alignment.

### What Defines v0.3.0

- **Capability-boundary integration**: `floating` now depends on `Luna-Flow/arithmetic` for shared arithmetic boundary types and checked capability traits.
- **Shared floating support**: `def` keeps `Sign`, `PartialOrder`, and the repository-wide `Floating` trait while reexporting arithmetic-boundary types for compatibility.
- **Two scalar arbitrary-precision representations**: `bin_float` and `decimal` expose constructors, normalization, precision control, formatting/parsing, comparison, and basic arithmetic.
- **Ball arithmetic baseline**: `ball_float` supports exact embedding, overlap/containment predicates, outward-rounded interval arithmetic, checked integer power, and whole-real fallback for division by zero-containing divisors.
- **Result-wrapped endomorphism layer**: `bin_float_result`, `decimal_result`, and `ball_float_result` lift checked arithmetic into `Self -> Self` and `(Self, Self) -> Self` composition over wrapped `Result` values.
- **Cross-representation conversion**: `decimal` converts to and from `bin_float`; `ball_float` embeds exact `bin_float` values.
- **Correctness-first tests**: the repository includes whitebox tests for normalization, arithmetic, conversion behavior, and interval-enclosure edge cases.
- **Modern Moon package metadata**: the repository uses `moon.mod` as the canonical module manifest.

### API Guidance

- **`Floating` is intentionally small**: it covers classification, sign, precision, precision retuning, and normalization rather than every numeric operation.
- **Checked operations come from `arithmetic`**: `BinFloat` and `Decimal` implement checked scalar traits such as `SqrtChecked`, `DivChecked`, `CompareChecked`, `PowNatChecked`, `PowIntChecked`, and `ParseChecked` where valid.
- **`BallFloat` stays enclosure-first**: it implements enclosure relations plus checked division and checked integer power, but it does not pretend to be a totally ordered scalar.
- **Result wrappers stay closed under composition**: each `*_result` package provides `ok`, `err`, `from_result`, `result`, `map`, `bind`, `flat_map`, and lifted numeric operations returning the same wrapper type.
- **Observer APIs stay separate from endomorphisms**: operations such as checked comparison still naturally return non-`Self` values and are not forced into the closed wrapper algebra.
- **Normalization is part of the contract**: public constructors normalize finite values to canonical internal forms.
- **Precision changes are explicit**: use `with_precision(..., mode)` to request a different working precision.
- **Ball semantics are enclosure-oriented**: `ball_float` exposes overlap and containment style relations rather than pretending all values are totally ordered.
- **Enclosure correctness beats narrowness**: interval results may widen around branch cuts or ambiguous domains rather than returning an unsound narrow band.
- **`BallFloatResult` preserves enclosure fallback semantics**: division by an interval containing zero remains a whole-real enclosure, while invalid wrapper construction is represented as `Err`.
- **Repository docs describe the current code**: if an API is not present in this branch, it is not part of this release baseline.

### Key Features

- **Arbitrary-precision binary values**: normalized finite values, `nan`, `inf`, comparison, `ulp`, checked arithmetic helpers, `sqrt`, and `pow_int`.
- **Arbitrary-precision decimal values**: string parsing, normalized display, precision-aware arithmetic, binary conversion, and checked arithmetic helpers.
- **Ball arithmetic baseline**: exact balls, interval bounds, `contains`, `overlaps`, `separated_from`, `definitely_lt`, `definitely_le`, `maybe_eq`, and outward-rounded interval arithmetic.
- **Checked composition wrappers**: closed `Result`-wrapped arithmetic for binary, decimal, and ball values with explicit short-circuiting error propagation.
- **No upper-layer mathematics in this pass**: no transcendental layer, calculus, matrices, complex numbers, symbolic APIs, or special functions are reintroduced here.
- **Shared rounding helpers**: internal support for factor stripping, decimal parsing, and rounding to requested precision.
- **Consistency tests**: cross-package tests verify normalization, exact dyadic behavior, decimal parsing, binary-decimal conversion, checked error paths, and ball enclosure correctness.

### Quick Start

```moonbit
let x = @bin_float.BinFloat::make(3N, -1, 32)
let y = @bin_float.BinFloat::make(5N, -1, 32)
let sum = x + y

let dec = @decimal.Decimal::from_string("12.34", precision=32).unwrap()
let as_bin = dec.to_bin_float(precision=32)

let exact_ball = @ball_float.BallFloat::exact(as_bin)
let other_ball = @ball_float.BallFloat::from_bounds(
  @bin_float.BinFloat::make(3N, 0, 32),
  @bin_float.BinFloat::make(7N, 0, 32),
  precision=32,
)

inspect(sum.to_string(), content="1p2")
inspect(exact_ball.contains(as_bin).to_string(), content="true")
inspect(other_ball.definitely_lt(@ball_float.BallFloat::from_int(10, precision=32)).to_string(), content="true")

let checked =
  @decimal_result.DecimalResult::parse("9.0", precision=32)
    .sqrt()
    .div(@decimal_result.DecimalResult::from_int(3, precision=32))

inspect(checked.result().unwrap().to_string(), content="1")
```

### Documentation

We provide documentation in multiple languages:

- 🇺🇸 **English** (`doc/en_US`)
- 🇨🇳 **简体中文** (`doc/zh_CN`)
- 🇯🇵 **日本語** (`doc/ja_JP`)

Package documentation:

- [English docs](./doc/en_US/README.md)
- [简体中文文档](./doc/zh_CN)
- [日本語ドキュメント](./doc/ja_JP)

Localized README files:

- 🇺🇸 [README.md](./README.md)
- 🇨🇳 [README.md](./doc/zh_CN/README.md)
- 🇯🇵 [README.md](./doc/ja_JP/README.md)

## Development

Useful local commands:

```bash
moon fmt
moon check
moon test
moon test --enable-coverage
```

The repository test baseline currently lives in `src/consistency` and is run by `moon test`.

## Release Checklist

Before triggering the publish workflow:

1. Bump `moon.mod` to the intended release version.
2. Update `README.md` and localized docs so they match the current repository state.
3. Run `moon check` and `moon test`.
4. Trigger `publish-package`; it reads the release version directly from `moon.mod`.

If the workflow reports a duplicate version, the package manager already contains that version and a new version bump is required.

Contribution guidance is available in [CONTRIBUTING.md](./CONTRIBUTING.md).
