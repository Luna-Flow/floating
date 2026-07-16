# @internal

このページは `0.7.1` 基準の `@internal` package を説明します。実装補助層であり、安定公開 API の約束ではありません。

## `BigInt` 補助

- `bigint_zero`
- `bigint_one`
- `abs_bigint`
- `sign_of_bigint`

## べき乗・桁数補助

- `pow2`
- `pow5`
- `pow10`
- `digits10`

## 正規化補助

- `remove_factor2`
- `remove_factor10`
- `exact_divide_by_power_of_ten`: 指定した `10` のべきで割り切れる場合だけ厳密商を返します。
- `trim_trailing_decimal_zeros`: 任意の上限内で末尾 10 進ゼロを除き、新しい係数・指数・除去数を返します。

## 丸め補助

- `round_positive_div`
- `round_shift`
- `compare_abs`

## 10 進解析補助

- `split_decimal_string`

## 完全な公開インターフェース

次の snapshot は `0.7.1` の完全な生成 package interface です。公開宣言が名前と signature の基準で、前の説明は挙動別に整理しています。

<!-- generated-api-start -->
```moonbit
// Generated using `moon info`, DON'T EDIT IT
package "Luna-Flow/floating/internal"

import {
  "Luna-Flow/arithmetic",
  "Luna-Flow/floating/def",
  "moonbitlang/core/bigint",
}

// Values
pub fn abs_bigint(@bigint.BigInt) -> @bigint.BigInt

pub fn bigint_one() -> @bigint.BigInt

pub fn bigint_zero() -> @bigint.BigInt

pub fn certified_dyadic_div(CertifiedDyadic, CertifiedDyadic, Int) -> Result[CertifiedInterval[CertifiedDyadic], @arithmetic.ArithmeticError]

pub fn certified_dyadic_fraction(@bigint.BigInt, @bigint.BigInt, Int) -> Result[CertifiedInterval[CertifiedDyadic], @arithmetic.ArithmeticError]

pub fn certified_failure(String, @arithmetic.CertificationStage, @arithmetic.CertificationFailureReason, Int, CertifiedRefinementBudget) -> @arithmetic.ArithmeticError

pub fn compare_abs(@bigint.BigInt, @bigint.BigInt) -> Int

pub fn digits10(@bigint.BigInt) -> Int

pub fn exact_divide_by_power_of_ten(@bigint.BigInt, Int) -> @bigint.BigInt?

pub fn pow10(Int) -> @bigint.BigInt

pub fn pow2(Int) -> @bigint.BigInt

pub fn pow5(Int) -> @bigint.BigInt

pub fn remove_factor10(@bigint.BigInt, Int) -> (@bigint.BigInt, Int)

pub fn remove_factor2(@bigint.BigInt, Int) -> (@bigint.BigInt, Int)

pub fn[A, B, E, C] result_lift2(Result[A, E], Result[B, E], (A, B) -> C) -> Result[C, E]

pub fn[A, B, E, C] result_lift2_checked(Result[A, E], Result[B, E], (A, B) -> Result[C, E]) -> Result[C, E]

pub fn round_positive_div(@bigint.BigInt, @bigint.BigInt, Bool, @arithmetic.RoundingMode) -> @bigint.BigInt

pub fn round_shift(@bigint.BigInt, Int, Bool, @arithmetic.RoundingMode) -> @bigint.BigInt

pub fn sign_of_bigint(@bigint.BigInt) -> @def.Sign

pub fn split_decimal_string(String) -> (Bool, String, Int)?

pub fn trim_trailing_decimal_zeros(@bigint.BigInt, Int, max_drop? : Int) -> (@bigint.BigInt, Int, Int)

// Errors

// Types and methods
pub struct CertifiedDyadic {
  numerator_ : @bigint.BigInt
  scale_ : Int
}
pub fn CertifiedDyadic::add(Self, Self) -> Self
pub fn CertifiedDyadic::compare(Self, Self) -> Int
pub fn CertifiedDyadic::from_int(Int) -> Self
pub fn CertifiedDyadic::mul(Self, Self) -> Self
pub fn CertifiedDyadic::neg(Self) -> Self
pub fn CertifiedDyadic::new(@bigint.BigInt, Int) -> Self
pub fn CertifiedDyadic::numerator(Self) -> @bigint.BigInt
pub fn CertifiedDyadic::round_down(Self, Int) -> Self
pub fn CertifiedDyadic::round_up(Self, Int) -> Self
pub fn CertifiedDyadic::scale(Self) -> Int
pub fn CertifiedDyadic::sub(Self, Self) -> Self

pub struct CertifiedInterval[T] {
  lower_ : T
  upper_ : T
}
pub fn[T] CertifiedInterval::lower(Self[T]) -> T
pub fn[T] CertifiedInterval::new(T, T, (T, T) -> Int) -> Result[Self[T], @arithmetic.ArithmeticError]
pub fn[T] CertifiedInterval::upper(Self[T]) -> T

pub struct CertifiedRefinementBudget {
  work_precision : Int
  refinements_ : Int
  limit_ : Int
}
pub fn CertifiedRefinementBudget::available(Self) -> Bool
pub fn CertifiedRefinementBudget::new(Int, limit? : Int) -> Self
pub fn CertifiedRefinementBudget::next(Self) -> Self
pub fn CertifiedRefinementBudget::precision(Self) -> Int
pub fn CertifiedRefinementBudget::refinements(Self) -> Int

pub struct ExactRat {
  // private fields
} derive(Eq)
pub fn ExactRat::denominator(Self) -> @bigint.BigInt
pub fn ExactRat::new(@bigint.BigInt, @bigint.BigInt) -> Self
pub fn ExactRat::numerator(Self) -> @bigint.BigInt

// Type aliases

// Traits
```
<!-- generated-api-end -->
