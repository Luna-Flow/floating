# `ball_float_checked` API

`BallFloatResult` は区間意味論を保ちながら `Result[BallFloat, ArithmeticError]` を包みます。

## 構築と観測

`ok`、`err`、`from_result`、`result` が生の結果を接続します。`exact`、`from_bounds`、`whole` と各 `from_*` が区間を構築し、不正な境界は `Err` になります。

## 合成と算術

`map`、`bind`、`flat_map` は既存エラーを短絡します。絶対値、符号反転、四則演算、整数べき、正規化、精度変更は `Self` を返し、標準演算子も実装されています。

0 を含む区間による除算は `BallFloat` と同じく whole-real enclosure を返し、`Err` にはなりません。

完全な数値面には `from_int`、`from_coefficient`、`from_float`、`from_double`、
`abs`、`neg`、`add`、`sub`、`mul`、`div`、`pow_nat`、`pow_int`、
`normalized`、`with_precision` が含まれます。

`from_coefficient` は `@bin_float.BinCoeff` と独立した `negative?` 符号を受け取り、
binary checked API は `BigInt` を受け取りません。

## 完全な公開インターフェース

次の snapshot は `0.7.1` の完全な生成 package interface です。公開宣言が名前と signature の基準で、前の説明は挙動別に整理しています。

<!-- generated-api-start -->
```moonbit
// Generated using `moon info`, DON'T EDIT IT
package "Luna-Flow/floating/ball_float_checked"

import {
  "Luna-Flow/arithmetic",
  "Luna-Flow/floating/ball_float",
  "Luna-Flow/floating/bin_float",
}

// Values

// Errors

// Types and methods
pub struct BallFloatResult {
  // private fields
}
pub fn BallFloatResult::abs(Self) -> Self
pub fn BallFloatResult::acos(Self) -> Self
pub fn BallFloatResult::acosh(Self) -> Self
pub fn BallFloatResult::add(Self, Self) -> Self
pub fn BallFloatResult::asin(Self) -> Self
pub fn BallFloatResult::asinh(Self) -> Self
pub fn BallFloatResult::atan(Self) -> Self
pub fn BallFloatResult::atan2(Self, Self) -> Self
pub fn BallFloatResult::atanh(Self) -> Self
pub fn BallFloatResult::bind(Self, (@ball_float.BallFloat) -> Self) -> Self
pub fn BallFloatResult::cos(Self) -> Self
pub fn BallFloatResult::cosh(Self) -> Self
pub fn BallFloatResult::cospi(Self) -> Self
pub fn BallFloatResult::div(Self, Self) -> Self
pub fn BallFloatResult::err(@arithmetic.ArithmeticError) -> Self
pub fn BallFloatResult::error(Self) -> @arithmetic.ArithmeticError?
pub fn BallFloatResult::exact(@bin_float.BinFloat, precision? : Int) -> Self
pub fn BallFloatResult::exp(Self) -> Self
pub fn BallFloatResult::exp10(Self) -> Self
pub fn BallFloatResult::exp2(Self) -> Self
pub fn BallFloatResult::expm1(Self) -> Self
#deprecated
pub fn BallFloatResult::flat_map(Self, (@ball_float.BallFloat) -> Self) -> Self
pub fn BallFloatResult::from_bounds(@bin_float.BinFloat, @bin_float.BinFloat, precision? : Int) -> Self
pub fn BallFloatResult::from_coefficient(@bin_float.BinCoeff, precision? : Int, negative? : Bool) -> Self
pub fn BallFloatResult::from_double(Double, precision? : Int) -> Self
pub fn BallFloatResult::from_float(Float, precision? : Int) -> Self
pub fn BallFloatResult::from_int(Int, precision? : Int) -> Self
pub fn BallFloatResult::from_result(Result[@ball_float.BallFloat, @arithmetic.ArithmeticError]) -> Self
pub fn BallFloatResult::hypot(Self, Self) -> Self
pub fn BallFloatResult::is_err(Self) -> Bool
pub fn BallFloatResult::is_ok(Self) -> Bool
pub fn BallFloatResult::ln(Self) -> Self
pub fn BallFloatResult::log10(Self) -> Self
pub fn BallFloatResult::log1p(Self) -> Self
pub fn BallFloatResult::log2(Self) -> Self
pub fn BallFloatResult::map(Self, (@ball_float.BallFloat) -> @ball_float.BallFloat) -> Self
pub fn BallFloatResult::mul(Self, Self) -> Self
pub fn BallFloatResult::neg(Self) -> Self
pub fn BallFloatResult::normalized(Self) -> Self
pub fn BallFloatResult::ok(@ball_float.BallFloat) -> Self
pub fn BallFloatResult::pow(Self, Self) -> Self
pub fn BallFloatResult::pow_int(Self, Int) -> Self
pub fn BallFloatResult::pow_nat(Self, UInt) -> Self
pub fn BallFloatResult::result(Self) -> Result[@ball_float.BallFloat, @arithmetic.ArithmeticError]
pub fn BallFloatResult::rootn(Self, Int) -> Self
pub fn BallFloatResult::sin(Self) -> Self
pub fn BallFloatResult::sinh(Self) -> Self
pub fn BallFloatResult::sinpi(Self) -> Self
pub fn BallFloatResult::sub(Self, Self) -> Self
pub fn BallFloatResult::tan(Self) -> Self
pub fn BallFloatResult::tanh(Self) -> Self
pub fn BallFloatResult::tanpi(Self) -> Self
pub fn BallFloatResult::whole(precision? : Int) -> Self
pub fn BallFloatResult::with_precision(Self, Int, @arithmetic.RoundingMode) -> Self
pub impl Add for BallFloatResult
pub impl Div for BallFloatResult
pub impl Mul for BallFloatResult
pub impl Neg for BallFloatResult
pub impl Sub for BallFloatResult

// Type aliases

// Traits
```
<!-- generated-api-end -->
