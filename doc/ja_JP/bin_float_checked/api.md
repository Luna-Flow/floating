# `bin_float_checked` API

`BinFloatResult` は `Result[BinFloat, ArithmeticError]` を包み、checked 2 進演算を同じ型の中で合成します。

## 構築と観測

- `ok`、`err`、`from_result` は既存結果を包み、`result` は生の `Result` を取り出します。
- `from_int`、`from_coefficient`、`from_float`、`from_double` は成功値を作ります。
  `from_coefficient` は `@bin_float.BinCoeff` と `negative?` を受け取ります。

## 合成

`map` は失敗しない値変換、`bind` と `flat_map` は `BinFloatResult` を返す変換を適用します。既存エラーはコールバックを実行せず短絡します。

## 数値演算

`abs`、`neg`、四則演算、`sqrt`、整数べき、`normalized`、`with_precision`、`ulp`、`min`、`max`、`clamp` はすべて `Self` を返し、標準演算子も実装されています。

四則演算と整数べきの正確なメソッド名は `add`、`sub`、`mul`、`div`、
`pow_nat`、`pow_int` です。

## 完全な公開インターフェース

次の snapshot は `0.6.1` の完全な生成 package interface です。公開宣言が名前と signature の基準で、前の説明は挙動別に整理しています。

<!-- generated-api-start -->
```moonbit
// Generated using `moon info`, DON'T EDIT IT
package "Luna-Flow/floating/bin_float_checked"

import {
  "Luna-Flow/arithmetic",
  "Luna-Flow/floating/bin_float",
}

// Values

// Errors

// Types and methods
pub struct BinFloatResult {
  // private fields
}
pub fn BinFloatResult::abs(Self) -> Self
pub fn BinFloatResult::add(Self, Self) -> Self
pub fn BinFloatResult::bind(Self, (@bin_float.BinFloat) -> Self) -> Self
pub fn BinFloatResult::clamp(Self, min~ : Self, max~ : Self) -> Self
pub fn BinFloatResult::div(Self, Self) -> Self
pub fn BinFloatResult::err(@arithmetic.ArithmeticError) -> Self
#deprecated
pub fn BinFloatResult::flat_map(Self, (@bin_float.BinFloat) -> Self) -> Self
pub fn BinFloatResult::from_coefficient(@bin_float.BinCoeff, precision? : Int, negative? : Bool) -> Self
pub fn BinFloatResult::from_double(Double, precision? : Int) -> Self
pub fn BinFloatResult::from_float(Float, precision? : Int) -> Self
pub fn BinFloatResult::from_int(Int, precision? : Int) -> Self
pub fn BinFloatResult::from_result(Result[@bin_float.BinFloat, @arithmetic.ArithmeticError]) -> Self
pub fn BinFloatResult::map(Self, (@bin_float.BinFloat) -> @bin_float.BinFloat) -> Self
pub fn BinFloatResult::max(Self, Self) -> Self
pub fn BinFloatResult::min(Self, Self) -> Self
pub fn BinFloatResult::mul(Self, Self) -> Self
pub fn BinFloatResult::neg(Self) -> Self
pub fn BinFloatResult::normalized(Self) -> Self
pub fn BinFloatResult::ok(@bin_float.BinFloat) -> Self
pub fn BinFloatResult::pow_int(Self, Int) -> Self
pub fn BinFloatResult::pow_nat(Self, UInt) -> Self
pub fn BinFloatResult::result(Self) -> Result[@bin_float.BinFloat, @arithmetic.ArithmeticError]
pub fn BinFloatResult::sqrt(Self) -> Self
pub fn BinFloatResult::sub(Self, Self) -> Self
pub fn BinFloatResult::ulp(Self) -> Self
pub fn BinFloatResult::with_precision(Self, Int, @arithmetic.RoundingMode) -> Self
pub impl Add for BinFloatResult
pub impl Div for BinFloatResult
pub impl Mul for BinFloatResult
pub impl Neg for BinFloatResult
pub impl Sub for BinFloatResult

// Type aliases

// Traits
```
<!-- generated-api-end -->
