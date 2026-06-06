# FLOATING

[![img](https://img.shields.io/badge/Maintainer-KCN--judu-violet)](https://github.com/KCN-judu) [![img](https://img.shields.io/badge/License-MIT-blue)](https://github.com/Luna-Flow/floating/blob/main/LICENSE) ![img](https://img.shields.io/badge/State-active-success)

## v0.1.0 - Initial Package Baseline

This documentation tracks the current repository baseline for **`v0.1.0`**.
It describes the implementation that exists in this branch today.

### Package Positioning

- **`def`**: Shared floating-point classifications, rounding modes, and the core `Floating` trait.
- **`bin_float`**: Arbitrary-precision binary floating-point values represented by significand, base-2 exponent, and working precision.
- **`decimal`**: Arbitrary-precision decimal floating-point values represented by coefficient, base-10 exponent, and working precision.
- **`ball_float`**: Ball arithmetic values represented as `center +/- radius`, built on top of `bin_float`.
- **`internal`**: Shared normalization, integer-factor removal, rounding, and decimal parsing helpers.
- **`consistency`**: Repository tests covering normalization, conversion, arithmetic, and cross-package semantic alignment.

### What Defines v0.1.0

- **Shared trait baseline**: `def` provides `FpClass`, `Sign`, `RoundingMode`, and the repository-wide `Floating` trait.
- **Two arbitrary-precision floating representations**: `bin_float` and `decimal` each expose constructors, normalization, precision control, arithmetic, special values, and shared arithmetic traits.
- **Ball arithmetic baseline**: `ball_float` supports exact embedding, overlap tests, containment, interval comparison, and enclosure arithmetic.
- **Cross-representation conversion**: `decimal` can convert to and from `bin_float`; `ball_float` can embed exact `bin_float` values and approximate `decimal` values.
- **Transcendental baseline**: binary, decimal, and ball values expose constants, exponential/logarithmic functions, trigonometric functions, inverse trigonometric functions, hyperbolic functions, and inverse hyperbolic functions through the shared arithmetic interfaces.
- **Correctness-first tests**: the repository includes whitebox tests for normalization, arithmetic, conversion behavior, and interval-enclosure edge cases.
- **Modern Moon package metadata**: the repository uses `moon.mod` as the canonical module manifest.

### API Guidance

- **`Floating` is intentionally small**: it covers classification, sign, precision, precision retuning, and normalization rather than every numeric operation.
- **Normalization is part of the contract**: public constructors normalize finite values to canonical internal forms.
- **Precision changes are explicit**: use `with_precision(..., mode)` to request a different working precision.
- **Ball semantics are enclosure-oriented**: `ball_float` exposes overlap and containment style relations rather than pretending all values are totally ordered.
- **Enclosure correctness beats narrowness**: interval results may widen around branch cuts or ambiguous domains rather than returning an unsound narrow band.
- **Repository docs describe the current code**: if an API is not present in this branch, it is not part of this release baseline.

### Key Features

- **Arbitrary-precision binary values**: normalized finite values, `nan`, `inf`, comparison, `ulp`, integer rounding helpers, constants, and transcendental functions.
- **Arbitrary-precision decimal values**: string parsing, normalized display, precision-aware arithmetic, binary conversion, and shared arithmetic traits for constants and transcendental functions.
- **Ball arithmetic baseline**: exact balls, decimal embedding, interval bounds, `contains`, `overlaps`, `separated_from`, `definitely_lt`, `definitely_gt`, `pow`, and interval transcendental functions.
- **Shared rounding helpers**: internal support for factor stripping, decimal parsing, and rounding to requested precision.
- **Consistency tests**: cross-package tests verify normalization, exact dyadic behavior, decimal parsing, binary-decimal conversion, transcendental smoke cases, and ball containment semantics near branch cuts and domain boundaries.

### Quick Start

```moonbit
let x = @bin_float.BinFloat::make(3N, -1, 32)
let y = @bin_float.BinFloat::make(5N, -1, 32)
let sum = x + y

let dec = @decimal.Decimal::from_string("12.34", precision=32).unwrap()
let as_bin = dec.to_bin_float(precision=32)

let exact_ball = @ball_float.BallFloat::exact(as_bin)
let loose_ball = @ball_float.BallFloat::from_decimal(dec, precision=32)

inspect(sum.to_string(), content="1p2")
inspect(exact_ball.contains(as_bin).to_string(), content="true")
inspect(loose_ball.overlaps(exact_ball).to_string(), content="true")
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
