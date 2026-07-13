# Getting Started

This guide targets `Luna-Flow/floating` **`0.6.0`**. It shows how to select a
package, install the module, construct values, choose an error model, and find
the relevant reference material.

## Choose A Numeric Domain

Choose the representation from the semantics your application needs, not from
the spelling of its input.

| Requirement | Package | Primary value | Result model |
| --- | --- | --- | --- |
| Arbitrary-precision dyadic values or IEEE binary interchange | `bin_float` | `BinFloat` | Value, or `(value, BinaryFlags)` with a context |
| IEEE arbitrary-precision decimal and decimal interchange | `decimal` | `Decimal` | Value, or `(value, DecimalFlags)` with a context |
| General Decimal Arithmetic status and traps | `decimal_gda` | `Decimal` | `GdaOutcome[Decimal]` with next context and raised flags |
| Certified real enclosure | `ball_float` | `BallFloat` / `BallFloatDecorated` | Enclosure, or `(enclosure, BallFlags)` with a context |
| Short-circuit scalar or interval pipeline | `*_checked` | `*Result` | `Result[..., ArithmeticError]` retained inside a wrapper |
| Representation-independent comparison | `semantic` | `SemanticScalar` / `SemanticInterval` | Exact projection, intentionally dropping metadata |

Use `numeric_expr` and `frontend/*` only when building parsers or conformance
tools. `internal/*`, `consistency`, `doc_examples`, and `*_bench` are
maintainer infrastructure rather than application dependencies.

## Install And Import

Add the current release:

```sh
moon add Luna-Flow/floating@0.6.0
```

Import only the package boundaries used by the current MoonBit package:

```moonbit nocheck
import {
  "Luna-Flow/floating/bin_float"
  "Luna-Flow/floating/decimal"
  "Luna-Flow/floating/decimal_gda"
  "Luna-Flow/floating/ball_float"
}
```

Imports name packages, not source files. Files inside one `moon.pkg` are one
compilation unit and do not create submodules.

## Construct Values

Binary coefficients are represented by `BinCoeff`; the sign is independent.
Decimal parsing preserves the input quantum, including significant trailing
zeros. Intervals are normally built from ordered binary endpoints.

```moonbit nocheck
let binary = @bin_float.BinFloat::make(
  @bin_float.BinCoeff::from_uint64(3UL),
  -1,
  53,
)
let decimal = @decimal.Decimal::from_string("12.3400").unwrap()
let interval = @ball_float.BallFloat::from_bounds(
  @bin_float.BinFloat::from_int(1),
  @bin_float.BinFloat::from_int(2),
)
```

`binary` is the exact dyadic value `3 × 2^-1`; `decimal` retains exponent
`-4`; and `interval` denotes every real value from 1 through 2. Call
`normalized()` only when canonical cohort form is intended.

## Select A Context Model

Use ordinary methods for unconstrained arbitrary-precision work. Use `*_ctx`
when precision, exponent limits, rounding, tininess, clamp, or status flags are
part of the result.

```moonbit nocheck
let binary_context = @bin_float.BinaryContext::binary64()
let (binary_sum, binary_flags) = binary.add_ctx(binary, binary_context)

let decimal_context = @decimal.DecimalContext::decimal64()
let (decimal_value, decimal_flags) =
  @decimal.Decimal::from_string_ctx("1.234567890123456789", decimal_context)
```

IEEE contexts are immutable inputs and flags are explicit outputs. Combine
flags when a multi-step calculation needs accumulated status. GDA instead
returns the updated sticky context as part of every `GdaOutcome`.

## Select A Failure Model

The library intentionally exposes several non-equivalent failure channels:

- `Option` is used by simple constructors where invalid input has no additional
  diagnostic contract.
- `Result[T, ArithmeticError]` is used by checked scalar capabilities.
- `BinaryFlags`, `DecimalFlags`, and `BallFlags` report IEEE- or domain-style
  conditions without replacing the returned value.
- `GdaOutcome[T]` always retains the GDA-defined result, even when a configured
  trap fires.
- `Entire`, `Empty`, and `NaI` are interval-domain values, not generic errors.

Do not convert all of these to exceptions or one universal `Result`; doing so
would erase observable numerical semantics.

## Read Results Correctly

- Signed zero, infinity, quiet NaN, signaling NaN, and payloads may be
  observable on scalar representations.
- Ordinary scalar comparison is partial in the presence of NaN; total-order
  APIs are separate operations.
- `BallFloat` has containment and set relations, not a scalar total order.
- An interval result is correct when it encloses the mathematical result;
  tightness is a separate quality property.
- `SemanticScalar` compares mathematical meaning but intentionally loses
  precision, quantum, signed zero, NaN payloads, decorations, and flags.

## Continue Reading

- [Numeric semantics](./numeric_semantics.md) explains precision, rounding,
  status, special values, and interval enclosure.
- [Architecture](./architecture.md) maps stable packages to parsing, execution,
  and verification infrastructure.
- [Verification](./verification.md) lists quick and authoritative gates and the
  exact scope of each conformance claim.
- Package `api.md`, `tutorial.md`, and `design.md` pages provide callable names,
  workflows, and implementation boundaries respectively.
- Core evidence is package-local: [`bin_float`](./bin_float/conformance.md), [`decimal`](./decimal/conformance.md), [`decimal_gda`](./decimal_gda/conformance.md), and [`ball_float`](./ball_float/conformance.md).
