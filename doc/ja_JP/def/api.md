# @def

このページは `0.5.0` 基準の `@def` package を説明します。

## 内容

- `Sign`
- `FpClass`
- `RoundingMode`
- `Floating`
- `is_finite` / `is_nan` / `is_infinite` / `is_zero`

## `Floating` trait

```moonbit
trait Floating {
  fn classify(Self) -> FpClass
  fn sign(Self) -> Sign
  fn precision(Self) -> Int
  fn with_precision(Self, Int, RoundingMode) -> Self
  fn normalized(Self) -> Self
}
```

現在この trait は次だけを共有能力として扱います。

- 分類
- 符号
- 精度
- 精度変更
- 正規化
## `Sign`、`FpClass`、`RoundingMode`

共有 enum は観測と rounding の語彙であり、具体表現を意味しません。

## `Floating` 必須 method

trait は classification、sign、precision、retuning、normalization だけを要求し、算術は別 capability です。

## 実装と helper predicate

`BinFloat`、`Decimal`、`BallFloat` が実装し、helper は `classify` の pure projection です。
