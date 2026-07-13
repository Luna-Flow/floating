# `decimal_gda` API

`decimal_gda` は `0.6.0` の General Decimal Arithmetic surface です。Value、context、
flags、traps、signals、outcomes は `decimal` の IEEE-oriented type と別です。

## 値型

Opaque `Decimal` は次を公開します。

- `from_string(source, precision?) -> Decimal?` による context-free construction
- `zero`、`one`、`quiet_nan`、`signaling_nan`
- `is_finite`、`is_infinite`、`is_nan`、`is_qnan`、`is_snan`、`is_zero`、`is_negative`
- `nan_payload` と `Show` formatting

Conversion syntax、rounding、exponent limit、sticky status、trap を観測する場合は
package function `parse(source, context)` を使います。これは `@decimal.Decimal` の
alias ではなく、IEEE/GDA 境界は text または宣言済み interchange format で越えます。

## Context と rounding

`GdaContext::new` は正の `precision`、`GdaRoundingMode`、`e_min`、`e_max`、
`clamp`、`extended`、`GdaTrapSet` を受け取り、非正 precision は abort します。
`try_new` は非正 precision または逆転 exponent bound を `ArithmeticError` で返します。

Rounding mode は `HalfEven`、`HalfUp`、`HalfDown`、`Down`、`Ceiling`、`Floor`、
`Up`、`ZeroFiveUp` です。

Context constructor/accessor は次の通りです。

| API | 意味 |
| --- | --- |
| `basic`、`default` | precision 9、half-even、non-extended GDA context |
| `decimal32`、`decimal64`、`decimal128` | 標準 precision/exponent/clamp preset |
| package `context` | `GdaContext::new` convenience wrapper |
| package `decimal*_context` | standard preset convenience wrapper |
| `radix` | 常に 10 |
| `precision`、`rounding`、`e_min`、`e_max`、`clamp`、`extended` | immutable arithmetic policy |
| `status`、`traps` | current sticky status と enabled trap set |
| `with_traps`、`trap` | trap を変更した新 context |
| `clear_status` | sticky status を消し trap を保持 |
| `reset` | sticky status と trap の両方を消去 |

## Signal、flag、trap

`GdaSignal` は `ConversionSyntax`、`DivisionByZero`、`DivisionImpossible`、
`DivisionUndefined`、`InvalidContext`、`InvalidOperation`、`Overflow`、`Underflow`、
`Subnormal`、`Inexact`、`Rounded`、`Clamped`、`LostDigits` を含みます。

`GdaFlags::none`、`contains`、`combine` は condition set の生成・照会・union、
`GdaTrapSet::none`、`with_signal`、`contains` は immutable trap configuration 用です。

複数 enabled signal が raised された場合の precedence は invalid operation、division
by zero、division undefined、division impossible、invalid context、conversion syntax、
overflow、underflow、subnormal、inexact、rounded、clamped、lost digits です。

## Outcome と state threading

各 context operation は `GdaOutcome[T]` を返します。

```moonbit nocheck
enum GdaOutcome[T] {
  Completed(T, GdaContext, GdaFlags)
  Trapped(GdaSignal, T, GdaContext, GdaFlags)
}
```

両 variant は defined result、sticky status を持つ next context、現在 operation の
raised flags を含みます。`value`、`next_context`、`raised` で match せず共通 field
を取得できます。

Status を蓄積するには `outcome.next_context()` を次の operation に渡します。古い
input context を再利用すると古い status から始まります。Trap は result を捨てません。

## Arithmetic operation

全 function は operand の後に `GdaContext` を取り、`GdaOutcome[...]` を返します。

| Family | Function |
| --- | --- |
| Context application/unary | `apply`、`plus`、`minus`、`abs` |
| Basic arithmetic | `add`、`subtract`、`multiply`、`divide`、`fma` |
| Quotient/remainder | `divide_integer`、`remainder`、`remainder_near` |
| Exponent/quantum | `quantize`、`rescale`、`scaleb`、`reduce` |
| Integral conversion | `to_integral_exact`、`to_integral_value` |
| Elementary | `sqrt`、`exp`、`ln`、`log10`、`power` |
| Adjacent value | `next_plus`、`next_minus`、`next_toward` |
| Logical digit | `logical_and`、`logical_or`、`logical_xor`、`logical_invert` |
| Digit movement | `shift`、`rotate` |
| Comparison | `compare`、`compare_signal`、`compare_total`、`compare_total_magnitude` |

`compare` と `compare_signal` は GDA decimal comparison value、`compare_total` と
`compare_total_magnitude` は outcome 内の `Int` を返します。Total comparison は
representation-aware で、通常の numeric comparison と異なります。

## 境界と保証

この package は GDA integration と `.decTest` behavior 用です。新しい IEEE 754 code
は通常 `decimal` を使い、operation は `(Decimal, DecimalFlags)` を返し context は
sticky status/trap を持ちません。

Pinned `official` corpus の legal executable scalar 64,986 行と `official0` の legal
16,124 行は全件 pass します。Diagnostic `#` placeholder/non-scalar row を値にせず、
unbounded future directive/resource size を約束しません。

## 完全な公開インターフェース

次の snapshot は `0.6.0` の完全な生成 package interface です。公開宣言が名前と signature の基準で、前の説明は挙動別に整理しています。

<!-- generated-api-start -->
```moonbit
// Generated using `moon info`, DON'T EDIT IT
package "Luna-Flow/floating/decimal_gda"

import {
  "Luna-Flow/arithmetic",
  "moonbitlang/core/bigint",
}

// Values
pub fn abs(Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn add(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn apply(Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn compare(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn compare_signal(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn compare_total(Decimal, Decimal, GdaContext) -> GdaOutcome[Int]

pub fn compare_total_magnitude(Decimal, Decimal, GdaContext) -> GdaOutcome[Int]

pub fn context(precision? : Int, rounding? : GdaRoundingMode, e_min? : Int, e_max? : Int, clamp? : Bool, extended? : Bool) -> GdaContext

pub fn decimal128_context() -> GdaContext

pub fn decimal32_context() -> GdaContext

pub fn decimal64_context() -> GdaContext

pub fn divide(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn divide_integer(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn exp(Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn fma(Decimal, Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn ln(Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn log10(Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn logical_and(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn logical_invert(Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn logical_or(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn logical_xor(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn minus(Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn multiply(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn next_minus(Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn next_plus(Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn next_toward(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn parse(String, GdaContext) -> GdaOutcome[Decimal]

pub fn plus(Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn power(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn quantize(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn reduce(Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn remainder(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn remainder_near(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn rescale(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn rotate(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn scaleb(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn shift(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn sqrt(Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn subtract(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn to_integral_exact(Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn to_integral_value(Decimal, GdaContext) -> GdaOutcome[Decimal]

// Errors

// Types and methods
pub struct Decimal {
  // private fields
} derive(Eq)
pub fn Decimal::from_string(String, precision? : Int) -> Self?
pub fn Decimal::is_finite(Self) -> Bool
pub fn Decimal::is_infinite(Self) -> Bool
pub fn Decimal::is_nan(Self) -> Bool
pub fn Decimal::is_negative(Self) -> Bool
pub fn Decimal::is_qnan(Self) -> Bool
pub fn Decimal::is_snan(Self) -> Bool
pub fn Decimal::is_zero(Self) -> Bool
pub fn Decimal::nan_payload(Self) -> @bigint.BigInt
pub fn Decimal::one(precision? : Int) -> Self
pub fn Decimal::quiet_nan(payload? : @bigint.BigInt, negative? : Bool, precision? : Int) -> Self
pub fn Decimal::signaling_nan(payload? : @bigint.BigInt, negative? : Bool, precision? : Int) -> Self
pub fn Decimal::zero(precision? : Int) -> Self
pub impl Show for Decimal

pub struct GdaContext {
  // private fields
}
pub fn GdaContext::basic() -> Self
pub fn GdaContext::clamp(Self) -> Bool
pub fn GdaContext::clear_status(Self) -> Self
pub fn GdaContext::decimal128() -> Self
pub fn GdaContext::decimal32() -> Self
pub fn GdaContext::decimal64() -> Self
pub fn GdaContext::default() -> Self
pub fn GdaContext::e_max(Self) -> Int
pub fn GdaContext::e_min(Self) -> Int
pub fn GdaContext::extended(Self) -> Bool
pub fn GdaContext::new(precision? : Int, rounding? : GdaRoundingMode, e_min? : Int, e_max? : Int, clamp? : Bool, extended? : Bool, traps? : GdaTrapSet) -> Self
pub fn GdaContext::precision(Self) -> Int
pub fn GdaContext::radix(Self) -> Int
pub fn GdaContext::reset(Self) -> Self
pub fn GdaContext::rounding(Self) -> GdaRoundingMode
pub fn GdaContext::status(Self) -> GdaFlags
pub fn GdaContext::trap(Self, GdaSignal, enabled? : Bool) -> Self
pub fn GdaContext::traps(Self) -> GdaTrapSet
pub fn GdaContext::try_new(precision? : Int, rounding? : GdaRoundingMode, e_min? : Int, e_max? : Int, clamp? : Bool, extended? : Bool, traps? : GdaTrapSet) -> Result[Self, @arithmetic.ArithmeticError]
pub fn GdaContext::with_traps(Self, GdaTrapSet) -> Self

pub struct GdaFlags {
  conversion_syntax : Bool
  division_by_zero : Bool
  division_impossible : Bool
  division_undefined : Bool
  invalid_context : Bool
  invalid_operation : Bool
  overflow : Bool
  underflow : Bool
  subnormal : Bool
  inexact : Bool
  rounded : Bool
  clamped : Bool
  lost_digits : Bool
} derive(Eq)
pub fn GdaFlags::combine(Self, Self) -> Self
pub fn GdaFlags::contains(Self, GdaSignal) -> Bool
pub fn GdaFlags::none() -> Self

pub(all) enum GdaOutcome[T] {
  Completed(T, GdaContext, GdaFlags)
  Trapped(GdaSignal, T, GdaContext, GdaFlags)
}
pub fn[T] GdaOutcome::next_context(Self[T]) -> GdaContext
pub fn[T] GdaOutcome::raised(Self[T]) -> GdaFlags
pub fn[T] GdaOutcome::value(Self[T]) -> T

pub(all) enum GdaRoundingMode {
  HalfEven
  HalfUp
  HalfDown
  Down
  Ceiling
  Floor
  Up
  ZeroFiveUp
} derive(Eq)

pub(all) enum GdaSignal {
  ConversionSyntax
  DivisionByZero
  DivisionImpossible
  DivisionUndefined
  InvalidContext
  InvalidOperation
  Overflow
  Underflow
  Subnormal
  Inexact
  Rounded
  Clamped
  LostDigits
} derive(Eq)

pub struct GdaTrapSet {
  conversion_syntax : Bool
  division_by_zero : Bool
  division_impossible : Bool
  division_undefined : Bool
  invalid_context : Bool
  invalid_operation : Bool
  overflow : Bool
  underflow : Bool
  subnormal : Bool
  inexact : Bool
  rounded : Bool
  clamped : Bool
  lost_digits : Bool
} derive(Eq)
pub fn GdaTrapSet::contains(Self, GdaSignal) -> Bool
pub fn GdaTrapSet::none() -> Self
pub fn GdaTrapSet::with_signal(Self, GdaSignal, enabled? : Bool) -> Self

// Type aliases

// Traits
```
<!-- generated-api-end -->
