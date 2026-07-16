# `decimal_gda` API

`decimal_gda` は `0.7.1` の General Decimal Arithmetic Specification 1.70 surface
です。Value、context、flags、traps、signals、outcomes は `decimal` の
IEEE-oriented type と別です。

Implementation も独立しています。`Decimal` は persistent
`Small(UInt64) | Limbs(base-10^9)` coefficient を所有し、`GdaContext` は policy/state
を直接保持し、decimal32/64/128 concrete interchange は DPD-only です。この package
と production frontend は `decimal` を import しません。

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

GDA package operation の `sqrt`、`exp`、`ln`、`log10` は context の一般 rounding 設定に
関係なく、仕様で定められた half-even mathematical-function rule で finalize
します。`power` と通常 arithmetic は official decTest の複数 rounding vector が
示すとおり `GdaContext::rounding` に従います。

Context constructor/accessor は次の通りです。

| API | 意味 |
| --- | --- |
| `basic`、`default` | precision 9、half-up、non-extended。Clamped、DivisionByZero、InvalidOperation、Overflow、Underflow trap を有効化 |
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

1.70 の標準 signal は Clamped、DivisionByZero、InvalidOperation、Overflow、
Underflow、Subnormal、Inexact、Rounded です。`ConversionSyntax`、
`DivisionImpossible`、`DivisionUndefined`、`InvalidContext` は詳細な condition
diagnostic として保持しますが、すべて `InvalidOperation` を signal します。
`LostDigits` は legacy non-extended arithmetic 用です。したがって
`InvalidOperation` trap はこれらすべての invalid condition を捕捉します。

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
Trigonometric、inverse-trigonometric、`atan2`、hyperbolic、`hypot`、pi-scaled
function は GDA operation ではないため、この package では意図的に利用できません。

Pinned `official` corpus の legal executable scalar 64,986 行と `official0` の legal
16,124 行は全件 pass します。Diagnostic `#` placeholder/non-scalar row を値にせず、
unbounded future directive/resource size を約束しません。

## 完全な公開インターフェース

次の snapshot は `0.7.1` の完全な生成 package interface です。公開宣言が名前と signature の基準で、前の説明は挙動別に整理しています。

<!-- generated-api-start -->
```moonbit
// Generated using `moon info`, DON'T EDIT IT
package "Luna-Flow/floating/decimal_gda"

import {
  "Luna-Flow/arithmetic",
  "Luna-Flow/floating/bin_float",
  "Luna-Flow/floating/def",
  "Luna-Flow/luna-generic",
  "moonbitlang/core/bigint",
  "moonbitlang/core/debug",
}

// Values
pub fn abs(Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn add(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn apply(Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn class_name(Decimal, GdaContext) -> GdaOutcome[String]

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

pub fn is_normal(Decimal, GdaContext) -> GdaOutcome[Bool]

pub fn is_subnormal(Decimal, GdaContext) -> GdaOutcome[Bool]

pub fn ln(Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn log10(Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn logb(Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn logical_and(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn logical_invert(Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn logical_or(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn logical_xor(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn max(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn max_mag(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn min(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn min_mag(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]

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

pub fn same_quantum(Decimal, Decimal, GdaContext) -> GdaOutcome[Bool]

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
} derive(@debug.Debug)
pub fn Decimal::abs(Self) -> Self
pub fn Decimal::abs_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::add(Self, Self) -> Self
pub fn Decimal::add_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::apply_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::clamp(Self, min~ : Self, max~ : Self) -> Self
pub fn Decimal::clamp_checked(Self, min~ : Self, max~ : Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn Decimal::class_name(Self, DecimalContext) -> String
pub fn Decimal::classify(Self) -> @arithmetic.FpClass
pub fn Decimal::coefficient(Self) -> @bigint.BigInt
pub fn Decimal::compare(Self, Self) -> Int
pub fn Decimal::compare_checked(Self, Self) -> Result[Int, @arithmetic.ArithmeticError]
pub fn Decimal::compare_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::compare_signal_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::compare_total(Self, Self) -> Int
pub fn Decimal::compare_total_ctx(Self, Self, DecimalContext) -> (Int, DecimalFlags)
pub fn Decimal::compare_total_magnitude(Self, Self) -> Int
pub fn Decimal::compare_total_magnitude_ctx(Self, Self, DecimalContext) -> (Int, DecimalFlags)
pub fn Decimal::copy(Self) -> Self
pub fn Decimal::copy_abs(Self) -> Self
pub fn Decimal::copy_negate(Self) -> Self
pub fn Decimal::copy_sign(Self, Self) -> Self
pub fn Decimal::div(Self, Self) -> Self
pub fn Decimal::div_checked(Self, Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn Decimal::div_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::divide_integer(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::exp_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::exponent10(Self) -> Int
pub fn Decimal::fma_ctx(Self, Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::from_bigint(@bigint.BigInt, precision? : Int) -> Self
pub fn Decimal::from_bin_float(@bin_float.BinFloat, precision? : Int) -> Self
pub fn Decimal::from_double(Double, precision? : Int) -> Self
pub fn Decimal::from_float(Float, precision? : Int) -> Self
pub fn Decimal::from_int(Int, precision? : Int) -> Self
pub fn Decimal::from_interchange_hex(String, GdaInterchangeFormat) -> Self?
pub fn Decimal::from_string(String, precision? : Int) -> Self?
pub fn Decimal::from_string_ctx(String, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::get_payload(Self) -> @bigint.BigInt
pub fn Decimal::inf(@def.Sign, precision? : Int) -> Self
pub fn Decimal::is_canonical(Self) -> Bool
pub fn Decimal::is_finite(Self) -> Bool
pub fn Decimal::is_infinite(Self) -> Bool
pub fn Decimal::is_nan(Self) -> Bool
pub fn Decimal::is_negative(Self) -> Bool
pub fn Decimal::is_negative_zero(Self) -> Bool
pub fn Decimal::is_normal(Self, DecimalContext) -> Bool
pub fn Decimal::is_qnan(Self) -> Bool
pub fn Decimal::is_quiet_nan(Self) -> Bool
pub fn Decimal::is_signaling_nan(Self) -> Bool
pub fn Decimal::is_signed(Self) -> Bool
pub fn Decimal::is_snan(Self) -> Bool
pub fn Decimal::is_subnormal(Self, DecimalContext) -> Bool
pub fn Decimal::is_zero(Self) -> Bool
pub fn Decimal::ln_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::log10_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::logb_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::logical_and(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::logical_invert(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::logical_or(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::logical_xor(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::magnitude(Self) -> @bigint.BigInt
pub fn Decimal::make(@bigint.BigInt, Int, Int, mode? : @arithmetic.RoundingMode) -> Self
pub fn Decimal::max(Self, Self) -> Self
pub fn Decimal::max_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::max_mag_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::maximum_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::maximum_mag_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::maximum_magnitude_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::maximum_number_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::maximum_number_mag_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::maximum_number_magnitude_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::min(Self, Self) -> Self
pub fn Decimal::min_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::min_mag_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::minimum_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::minimum_mag_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::minimum_magnitude_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::minimum_number_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::minimum_number_mag_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::minimum_number_magnitude_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::minus_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::mul(Self, Self) -> Self
pub fn Decimal::mul_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::nan(precision? : Int) -> Self
pub fn Decimal::nan_payload(Self) -> @bigint.BigInt
pub fn Decimal::neg(Self) -> Self
pub fn Decimal::negative_zero(precision? : Int) -> Self
pub fn Decimal::next_minus(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::next_plus(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::next_toward(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::normalize_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::normalized(Self) -> Self
pub fn Decimal::one(precision? : Int) -> Self
pub fn Decimal::parse(String, precision? : Int) -> Result[Self, @arithmetic.ArithmeticError]
pub fn Decimal::plus_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::power_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::precision(Self) -> Int
pub fn Decimal::quantize(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::quantum(Self) -> Int
pub fn Decimal::quiet_nan(payload? : @bigint.BigInt, negative? : Bool, precision? : Int) -> Self
pub fn Decimal::reduce_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::remainder(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::remainder_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::remainder_near(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::rescale(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::rotate_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::same_quantum(Self, Self) -> Bool
pub fn Decimal::scaleb_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::set_payload(Self, @bigint.BigInt) -> Self
pub fn Decimal::set_payload_signaling(Self, @bigint.BigInt) -> Self
pub fn Decimal::shift_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::sign(Self) -> @def.Sign
pub fn Decimal::signaling_nan(payload? : @bigint.BigInt, negative? : Bool, precision? : Int) -> Self
pub fn Decimal::sqrt(Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn Decimal::sqrt_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::sub(Self, Self) -> Self
pub fn Decimal::sub_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::to_bin_float(Self, precision? : Int, mode? : @arithmetic.RoundingMode) -> @bin_float.BinFloat
pub fn Decimal::to_eng_string(String, DecimalContext) -> (String, DecimalFlags)
pub fn Decimal::to_integral_exact(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::to_integral_value(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::to_interchange_hex(Self, GdaInterchangeFormat) -> (String, DecimalFlags)
pub fn Decimal::to_sci_string(String, DecimalContext) -> (String, DecimalFlags)
pub fn Decimal::trim(Self) -> Self
pub fn Decimal::try_exp_ctx(Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::try_ln_ctx(Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::try_log10_ctx(Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::try_power_ctx(Self, Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::with_precision(Self, Int, @arithmetic.RoundingMode) -> Self
pub fn Decimal::zero(precision? : Int) -> Self
pub impl @arithmetic.AbsContextual for Decimal
pub impl @arithmetic.AddContextual for Decimal
pub impl @arithmetic.CompareChecked for Decimal
pub impl @arithmetic.DivChecked for Decimal
pub impl @arithmetic.DivContextual for Decimal
pub impl @arithmetic.ExpContextual for Decimal
pub impl @arithmetic.MulContextual for Decimal
pub impl @arithmetic.NumericFormatContextual for Decimal
pub impl @arithmetic.ParseChecked for Decimal
pub impl @arithmetic.PowIntChecked for Decimal
pub impl @arithmetic.PowNatChecked for Decimal
pub impl @arithmetic.SqrtChecked for Decimal
pub impl @arithmetic.SqrtContextual for Decimal
pub impl @arithmetic.SubContextual for Decimal
pub impl @def.Floating for Decimal
pub impl @luna-generic.AddGroup for Decimal
pub impl @luna-generic.AddMonoid for Decimal
pub impl @luna-generic.IntegralHomomorphism for Decimal
pub impl @luna-generic.MulMonoid for Decimal
pub impl @luna-generic.NatHomomorphism for Decimal
pub impl @luna-generic.One for Decimal
pub impl @luna-generic.Ring for Decimal
pub impl @luna-generic.Semiring for Decimal
pub impl @luna-generic.Zero for Decimal
pub impl Add for Decimal
pub impl Compare for Decimal
pub impl Div for Decimal
pub impl Eq for Decimal
pub impl Mul for Decimal
pub impl Neg for Decimal
pub impl Show for Decimal
pub impl Sub for Decimal

pub struct DecimalContext {
  // private fields
} derive(Eq)
pub fn DecimalContext::clamp(Self) -> Bool
pub fn DecimalContext::decimal128() -> Self
pub fn DecimalContext::decimal32() -> Self
pub fn DecimalContext::decimal64() -> Self
pub fn DecimalContext::decimal_rounding(Self) -> DecimalRoundingMode
pub fn DecimalContext::e_max(Self) -> Int
pub fn DecimalContext::e_min(Self) -> Int
pub fn DecimalContext::exact() -> Self
pub fn DecimalContext::extended(Self) -> Bool
pub fn DecimalContext::from_arithmetic_context(@arithmetic.ArithmeticContext) -> Self
pub fn DecimalContext::new(precision? : Int, rounding? : @arithmetic.RoundingMode, decimal_rounding? : DecimalRoundingMode, e_min? : Int, e_max? : Int, clamp? : Bool, extended? : Bool, tininess? : DecimalTininessDetection) -> Self
pub fn DecimalContext::precision(Self) -> Int
pub fn DecimalContext::rounding(Self) -> @arithmetic.RoundingMode
pub fn DecimalContext::tininess(Self) -> DecimalTininessDetection
pub fn DecimalContext::try_new(precision? : Int, rounding? : @arithmetic.RoundingMode, decimal_rounding? : DecimalRoundingMode, e_min? : Int, e_max? : Int, clamp? : Bool, extended? : Bool, tininess? : DecimalTininessDetection) -> Result[Self, @arithmetic.ArithmeticError]
pub fn DecimalContext::with_rounding(Self, @arithmetic.RoundingMode) -> Self
pub fn DecimalContext::with_tininess(Self, DecimalTininessDetection) -> Self

pub struct DecimalFlags {
  inexact : Bool
  rounded : Bool
  lost_digits : Bool
  invalid_operation : Bool
  division_by_zero : Bool
  overflow : Bool
  underflow : Bool
  subnormal : Bool
  clamped : Bool
  conversion_syntax : Bool
  division_impossible : Bool
  division_undefined : Bool
  invalid_context : Bool
} derive(Eq)
pub fn DecimalFlags::combine(Self, Self) -> Self
pub fn DecimalFlags::contains(Self, DecimalSignal) -> Bool
pub fn DecimalFlags::has_error(Self) -> Bool
pub fn DecimalFlags::new() -> Self

pub(all) enum DecimalRoundingMode {
  HalfEven
  HalfUp
  HalfDown
  Down
  Ceiling
  Floor
  Up
  ZeroFiveUp
} derive(Eq)
pub fn DecimalRoundingMode::from_arithmetic(@arithmetic.RoundingMode) -> Self
pub fn DecimalRoundingMode::to_arithmetic(Self) -> @arithmetic.RoundingMode?

pub(all) enum DecimalSignal {
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

pub(all) enum DecimalTininessDetection {
  BeforeRounding
  AfterRounding
} derive(Eq)

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

pub struct GdaInterchange {
  // private fields
}
pub fn GdaInterchange::canonical(Self) -> Self
pub fn GdaInterchange::copy(Self) -> Self
pub fn GdaInterchange::copy_abs(Self) -> Self
pub fn GdaInterchange::copy_negate(Self) -> Self
pub fn GdaInterchange::copy_sign(Self, Self) -> Self
pub fn GdaInterchange::format(Self) -> GdaInterchangeFormat
pub fn GdaInterchange::from_decimal(Decimal, GdaInterchangeFormat) -> (Self, DecimalFlags)
pub fn GdaInterchange::from_hex(String, GdaInterchangeFormat) -> Self?
pub fn GdaInterchange::is_canonical(Self) -> Bool
pub fn GdaInterchange::to_decimal(Self) -> Decimal
pub fn GdaInterchange::to_decimal_ctx(Self) -> (Decimal, DecimalFlags)
pub fn GdaInterchange::to_hex(Self) -> String

pub(all) enum GdaInterchangeFormat {
  Decimal32
  Decimal64
  Decimal128
} derive(Eq)
pub fn GdaInterchangeFormat::context(Self) -> DecimalContext

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
