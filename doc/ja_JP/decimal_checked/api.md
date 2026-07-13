# `decimal_checked` API

`DecimalResult` は `Result[Decimal, ArithmeticError]` を包み、checked 10 進演算を閉じて合成します。

## 構築と観測

`ok`、`err`、`from_result`、`result` が生の結果境界を接続します。`from_int`、`from_bigint`、`from_float`、`from_double`、`parse` が値を作り、不正な入力は `Err` になります。

## 合成と算術

`map`、`bind`、`flat_map` は既存エラーを保持します。`abs`、`neg`、四則演算、`sqrt`、整数べき、`normalized`、`with_precision`、`min`、`max`、`clamp` は `Self` を返し、標準演算子も実装されています。

context と flags を返す Decimal 演算は `@decimal.Decimal` に残ります。この wrapper は `ArithmeticError` だけをモデル化します。

完全な数値メソッド名は `abs`、`neg`、`add`、`sub`、`mul`、`div`、`sqrt`、
`pow_nat`、`pow_int`、`normalized`、`with_precision`、`min`、`max`、`clamp` です。

## 完全な公開インターフェース

次の snapshot は `0.6.0` の完全な生成 package interface です。公開宣言が名前と signature の基準で、前の説明は挙動別に整理しています。

<!-- generated-api-start -->
```moonbit
// Generated using `moon info`, DON'T EDIT IT
package "Luna-Flow/floating/decimal_checked"

import {
  "Luna-Flow/arithmetic",
  "Luna-Flow/floating/decimal",
  "moonbitlang/core/bigint",
}

// Values

// Errors

// Types and methods
pub struct DecimalResult {
  // private fields
}
pub fn DecimalResult::abs(Self) -> Self
pub fn DecimalResult::add(Self, Self) -> Self
pub fn DecimalResult::bind(Self, (@decimal.Decimal) -> Self) -> Self
pub fn DecimalResult::clamp(Self, min~ : Self, max~ : Self) -> Self
pub fn DecimalResult::div(Self, Self) -> Self
pub fn DecimalResult::err(@arithmetic.ArithmeticError) -> Self
#deprecated
pub fn DecimalResult::flat_map(Self, (@decimal.Decimal) -> Self) -> Self
pub fn DecimalResult::from_bigint(@bigint.BigInt, precision? : Int) -> Self
pub fn DecimalResult::from_double(Double, precision? : Int) -> Self
pub fn DecimalResult::from_float(Float, precision? : Int) -> Self
pub fn DecimalResult::from_int(Int, precision? : Int) -> Self
pub fn DecimalResult::from_result(Result[@decimal.Decimal, @arithmetic.ArithmeticError]) -> Self
pub fn DecimalResult::map(Self, (@decimal.Decimal) -> @decimal.Decimal) -> Self
pub fn DecimalResult::max(Self, Self) -> Self
pub fn DecimalResult::min(Self, Self) -> Self
pub fn DecimalResult::mul(Self, Self) -> Self
pub fn DecimalResult::neg(Self) -> Self
pub fn DecimalResult::normalized(Self) -> Self
pub fn DecimalResult::ok(@decimal.Decimal) -> Self
pub fn DecimalResult::parse(String, precision? : Int) -> Self
pub fn DecimalResult::pow_int(Self, Int) -> Self
pub fn DecimalResult::pow_nat(Self, UInt) -> Self
pub fn DecimalResult::result(Self) -> Result[@decimal.Decimal, @arithmetic.ArithmeticError]
pub fn DecimalResult::sqrt(Self) -> Self
pub fn DecimalResult::sub(Self, Self) -> Self
pub fn DecimalResult::with_precision(Self, Int, @arithmetic.RoundingMode) -> Self
pub impl Add for DecimalResult
pub impl Div for DecimalResult
pub impl Mul for DecimalResult
pub impl Neg for DecimalResult
pub impl Sub for DecimalResult

// Type aliases

// Traits
```
<!-- generated-api-end -->
