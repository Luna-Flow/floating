# @bin_float.BinFloat

## 安定性

`BinFloat`、`BinCoeff`、binary context/flags、binary16/32/64/128
interchange は `0.6.0` の application API です。limb layout、algorithm threshold、
IEEE 754 全体は安定契約ではありません。

この文書は `0.6.0` API を説明します。数学・テスト境界は
[適合性](./conformance.md) にあります。

## Context、flag、interchange

- `BinaryRoundingMode`：nearest-even、nearest-away、toward-zero、toward-positive、
  toward-negative、away-from-zero。
- `TininessDetection`：before/after rounding。
- `BinaryContext::new`、`try_new`、`unbounded`、`binary16`、`binary32`、`binary64`、`binary128`。
- `BinaryFlags`：5 つの IEEE flag、`combine`、`to_testfloat_bits`。
- `BinaryInterchangeFormat`、`BinaryInterchange::from_hex`、`to_hex`、
  `to_bin_float`、`from_bin_float`、`BinFloat::to_interchange`。

encode API は `(bits, flags)` を返します。

## Constructor と観測

`BinFloat::make`、`zero`、`negative_zero`、`one`、`inf`、`nan`、`quiet_nan`、
`signaling_nan`、`from_int`、`from_coefficient`、`from_float`、`from_double` を使えます。

公開係数型は非負の `BinCoeff` です。`BinCoeff::from_uint64`、`parse`、
`from_bytes_be` で構築し、符号は独立した `negative?` 引数で指定します。
二進/ball API は `BigInt` の境界を公開しません（Decimal と Semantic の既存
`BigInt` API は変更されません）。

`BinCoeff` は `zero`、`one`、`from_uint64`、`parse`、byte 変換、比較、bit
query、加算、`sub_checked`、乗算、平方、`div_rem_checked`、`gcd`、自然数冪、
shift、bitwise operation を公開します。非負型なので、負の結果になり得る減算と
ゼロ除算になり得る除算は checked API です。

## 0.4 からの移行

| 旧 API | 現在の API |
| --- | --- |
| `BinFloat::from_bigint(n)` | `BinFloat::from_coefficient(c, negative=...)` |
| `BinFloat::make(n, e, p)` | `BinFloat::make(c, e, p, negative=...)` |
| `value.significand()` | `value.coefficient()` |
| `BinaryInterchange::from_bits(n, format)` / `bits() -> BigInt` | `from_bits(c, format)` / `bits() -> BinCoeff` |
| `BallFloat::from_bigint(n)` | `BallFloat::from_coefficient(c, negative=...)` |
| checked `from_bigint(n)` | checked `from_coefficient(c, negative=...)` |
| `NatHomomorphism` / `IntegralHomomorphism` | 二進型から削除、明示的 constructor を使用 |

`classify`、`precision`、`sign`、`is_negative`、`is_negative_zero`、
`is_quiet_nan`、`is_signaling_nan`、`nan_payload`、`coefficient`、`exponent2`、
`is_zero`、`normalized`、`with_precision`、`ulp`、`compare`、`min`、`max`、`clamp`、`clamp_checked`
が観測・通常操作を提供します。NaN は順序比較できません。

**算術 operation family**

通常の `+`、`-`、`*`、`/` と `add`、`sub`、`mul`、`div` は無界 nearest-even
context を使い、flag を返しません。IEEE 意味論には `round_ctx`、`add_ctx`、
`sub_ctx`、`mul_ctx`、`div_ctx`、`sqrt_ctx`、`pow_int_ctx` を使い、
`(BinFloat, BinaryFlags)` を受け取ります。

従来の checked helper は `sqrt_bounds_for_precision`、`sqrt_for_precision`、
`compare_checked`、`div_checked`、`sqrt`、`pow_int` です。
## 表現

有限値は独立符号、`BinCoeff`、`exponent2`、precision で表され、零・無限大・NaN は観測可能です。

## Access、正規化、比較

`coefficient`、`exponent2`、`normalized`、`compare` と classification predicate を使います。NaN は通常の全順序に入りません。

## 算術と変換

通常演算は任意精度、context 演算は value と flags、interchange は fixed-width bit encoding を返します。

## Checked 算術 API

checked trait は `ArithmeticError` を明示的に返し、flags は `*_ctx` の責務です。

## Trait 面

`Floating`、checked capability、標準 operator trait を最小の組合せとして公開します。

## 完全な公開インターフェース

次の snapshot は `0.6.0` の完全な生成 package interface です。公開宣言が名前と signature の基準で、前の説明は挙動別に整理しています。

<!-- generated-api-start -->
```moonbit
// Generated using `moon info`, DON'T EDIT IT
package "Luna-Flow/floating/bin_float"

import {
  "Luna-Flow/arithmetic",
  "Luna-Flow/floating/def",
  "moonbitlang/core/debug",
}

// Values
pub fn sqrt_bounds_for_precision(BinFloat, Int) -> Result[(BinFloat, BinFloat), @arithmetic.ArithmeticError]

pub fn sqrt_for_precision(BinFloat, Int) -> Result[BinFloat, @arithmetic.ArithmeticError]

// Errors

// Types and methods
pub struct BinCoeff {
  // private fields
}
pub fn BinCoeff::add(Self, Self) -> Self
pub fn BinCoeff::bit_and(Self, Self) -> Self
pub fn BinCoeff::bit_length(Self) -> Int
pub fn BinCoeff::bit_or(Self, Self) -> Self
pub fn BinCoeff::bit_xor(Self, Self) -> Self
pub fn BinCoeff::compare(Self, Self) -> Int
pub fn BinCoeff::ctz(Self) -> Int
pub fn BinCoeff::div_rem_checked(Self, Self) -> Result[(Self, Self), String]
pub fn BinCoeff::from_bytes_be(BytesView) -> Self
pub fn BinCoeff::from_uint64(UInt64) -> Self
pub fn BinCoeff::gcd(Self, Self) -> Self
pub fn BinCoeff::is_zero(Self) -> Bool
pub fn BinCoeff::mul(Self, Self) -> Self
pub fn BinCoeff::one() -> Self
pub fn BinCoeff::parse(String, radix? : Int) -> Result[Self, String]
pub fn BinCoeff::pow_nat(Self, UInt) -> Self
pub fn BinCoeff::shift_left(Self, Int) -> Self
pub fn BinCoeff::shift_right(Self, Int) -> Self
pub fn BinCoeff::square(Self) -> Self
pub fn BinCoeff::sub_checked(Self, Self) -> Result[Self, String]
pub fn BinCoeff::test_bit(Self, Int) -> Bool
pub fn BinCoeff::to_bytes_be(Self) -> Bytes
pub fn BinCoeff::to_string(Self, radix? : Int) -> String
pub fn BinCoeff::to_uint64(Self) -> UInt64?
pub fn BinCoeff::zero() -> Self
pub impl Add for BinCoeff
pub impl Compare for BinCoeff
pub impl Eq for BinCoeff
pub impl Mul for BinCoeff
pub impl Shl for BinCoeff
pub impl Show for BinCoeff
pub impl Shr for BinCoeff

pub struct BinFloat {
  // private fields
} derive(Eq)
pub fn BinFloat::abs(Self) -> Self
pub fn BinFloat::add(Self, Self) -> Self
pub fn BinFloat::add_ctx(Self, Self, BinaryContext) -> (Self, BinaryFlags)
pub fn BinFloat::clamp(Self, min~ : Self, max~ : Self) -> Self
pub fn BinFloat::clamp_checked(Self, min~ : Self, max~ : Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BinFloat::classify(Self) -> @arithmetic.FpClass
pub fn BinFloat::coefficient(Self) -> BinCoeff
pub fn BinFloat::compare(Self, Self) -> Int
pub fn BinFloat::compare_checked(Self, Self) -> Result[Int, @arithmetic.ArithmeticError]
pub fn BinFloat::div(Self, Self) -> Self
pub fn BinFloat::div_checked(Self, Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BinFloat::div_ctx(Self, Self, BinaryContext) -> (Self, BinaryFlags)
pub fn BinFloat::exponent2(Self) -> Int
pub fn BinFloat::from_coefficient(BinCoeff, precision? : Int, negative? : Bool) -> Self
pub fn BinFloat::from_double(Double, precision? : Int) -> Self
pub fn BinFloat::from_float(Float, precision? : Int) -> Self
pub fn BinFloat::from_hex(String, Int) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BinFloat::from_int(Int, precision? : Int) -> Self
pub fn BinFloat::inf(@def.Sign, precision? : Int) -> Self
pub fn BinFloat::is_negative(Self) -> Bool
pub fn BinFloat::is_negative_zero(Self) -> Bool
pub fn BinFloat::is_quiet_nan(Self) -> Bool
pub fn BinFloat::is_signaling_nan(Self) -> Bool
pub fn BinFloat::is_zero(Self) -> Bool
pub fn BinFloat::make(BinCoeff, Int, Int, negative? : Bool, mode? : @arithmetic.RoundingMode) -> Self
pub fn BinFloat::max(Self, Self) -> Self
pub fn BinFloat::min(Self, Self) -> Self
pub fn BinFloat::mul(Self, Self) -> Self
pub fn BinFloat::mul_ctx(Self, Self, BinaryContext) -> (Self, BinaryFlags)
pub fn BinFloat::nan(precision? : Int) -> Self
pub fn BinFloat::nan_payload(Self) -> BinCoeff
pub fn BinFloat::neg(Self) -> Self
pub fn BinFloat::negative_zero(precision? : Int) -> Self
pub fn BinFloat::normalized(Self) -> Self
pub fn BinFloat::one(precision? : Int) -> Self
pub fn BinFloat::pow_int(Self, Int) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BinFloat::pow_int_ctx(Self, Int, BinaryContext) -> (Self, BinaryFlags)
pub fn BinFloat::precision(Self) -> Int
pub fn BinFloat::quiet_nan(payload? : BinCoeff, negative? : Bool, precision? : Int) -> Self
pub fn BinFloat::round_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn BinFloat::sign(Self) -> @def.Sign
pub fn BinFloat::signaling_nan(payload? : BinCoeff, negative? : Bool, precision? : Int) -> Self
pub fn BinFloat::sqrt(Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BinFloat::sqrt_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn BinFloat::sub(Self, Self) -> Self
pub fn BinFloat::sub_ctx(Self, Self, BinaryContext) -> (Self, BinaryFlags)
pub fn BinFloat::to_hex(Self) -> String
pub fn BinFloat::to_interchange(Self, BinaryInterchangeFormat, rounding? : BinaryRoundingMode, tininess? : TininessDetection) -> (BinaryInterchange, BinaryFlags)
pub fn BinFloat::ulp(Self) -> Self
pub fn BinFloat::with_precision(Self, Int, @arithmetic.RoundingMode) -> Self
pub fn BinFloat::zero(precision? : Int) -> Self
pub impl @arithmetic.CompareChecked for BinFloat
pub impl @arithmetic.DivChecked for BinFloat
pub impl @arithmetic.PowIntChecked for BinFloat
pub impl @arithmetic.PowNatChecked for BinFloat
pub impl @arithmetic.SqrtChecked for BinFloat
pub impl @def.Floating for BinFloat
pub impl Add for BinFloat
pub impl Compare for BinFloat
pub impl Div for BinFloat
pub impl Mul for BinFloat
pub impl Neg for BinFloat
pub impl Show for BinFloat
pub impl Sub for BinFloat

pub struct BinaryContext {
  // private fields
} derive(Eq, @debug.Debug)
pub fn BinaryContext::binary128(rounding? : BinaryRoundingMode, tininess? : TininessDetection) -> Self
pub fn BinaryContext::binary16(rounding? : BinaryRoundingMode, tininess? : TininessDetection) -> Self
pub fn BinaryContext::binary32(rounding? : BinaryRoundingMode, tininess? : TininessDetection) -> Self
pub fn BinaryContext::binary64(rounding? : BinaryRoundingMode, tininess? : TininessDetection) -> Self
pub fn BinaryContext::e_max(Self) -> Int?
pub fn BinaryContext::e_min(Self) -> Int?
pub fn BinaryContext::from_arithmetic_context(@arithmetic.ArithmeticContext) -> Self
pub fn BinaryContext::new(Int, rounding? : BinaryRoundingMode, e_min? : Int, e_max? : Int, tininess? : TininessDetection) -> Self
pub fn BinaryContext::precision(Self) -> Int
pub fn BinaryContext::rounding(Self) -> BinaryRoundingMode
pub fn BinaryContext::tininess(Self) -> TininessDetection
pub fn BinaryContext::try_new(Int, rounding? : BinaryRoundingMode, e_min? : Int, e_max? : Int, tininess? : TininessDetection) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BinaryContext::unbounded(Int, rounding? : BinaryRoundingMode) -> Self

pub struct BinaryFlags {
  // private fields
} derive(Eq, @debug.Debug)
pub fn BinaryFlags::combine(Self, Self) -> Self
pub fn BinaryFlags::division_by_zero(Self) -> Bool
pub fn BinaryFlags::inexact(Self) -> Bool
pub fn BinaryFlags::invalid_operation(Self) -> Bool
pub fn BinaryFlags::new() -> Self
pub fn BinaryFlags::overflow(Self) -> Bool
pub fn BinaryFlags::to_testfloat_bits(Self) -> Int
pub fn BinaryFlags::underflow(Self) -> Bool

pub struct BinaryInterchange {
  // private fields
} derive(Eq)
pub fn BinaryInterchange::bits(Self) -> BinCoeff
pub fn BinaryInterchange::format(Self) -> BinaryInterchangeFormat
pub fn BinaryInterchange::from_bin_float(BinFloat, BinaryInterchangeFormat, rounding? : BinaryRoundingMode, tininess? : TininessDetection) -> (Self, BinaryFlags)
pub fn BinaryInterchange::from_bits(BinCoeff, BinaryInterchangeFormat) -> Self
pub fn BinaryInterchange::from_hex(String, BinaryInterchangeFormat) -> Self?
pub fn BinaryInterchange::to_bin_float(Self) -> BinFloat
pub fn BinaryInterchange::to_hex(Self) -> String

pub(all) enum BinaryInterchangeFormat {
  Binary16
  Binary32
  Binary64
  Binary128
} derive(Eq, @debug.Debug)
pub fn BinaryInterchangeFormat::bias(Self) -> Int
pub fn BinaryInterchangeFormat::context(Self, rounding? : BinaryRoundingMode, tininess? : TininessDetection) -> BinaryContext
pub fn BinaryInterchangeFormat::e_max(Self) -> Int
pub fn BinaryInterchangeFormat::e_min(Self) -> Int
pub fn BinaryInterchangeFormat::exponent_bits(Self) -> Int
pub fn BinaryInterchangeFormat::fraction_bits(Self) -> Int
pub fn BinaryInterchangeFormat::precision(Self) -> Int
pub fn BinaryInterchangeFormat::total_bits(Self) -> Int

pub(all) enum BinaryRoundingMode {
  RoundTiesToEven
  RoundTiesToAway
  RoundTowardZero
  RoundTowardPositive
  RoundTowardNegative
  RoundAwayFromZero
} derive(Eq, @debug.Debug)
pub fn BinaryRoundingMode::from_arithmetic(@arithmetic.RoundingMode) -> Self
pub fn BinaryRoundingMode::to_arithmetic(Self) -> @arithmetic.RoundingMode?

pub(all) enum TininessDetection {
  BeforeRounding
  AfterRounding
} derive(Eq, @debug.Debug)

// Type aliases

// Traits
```
<!-- generated-api-end -->
