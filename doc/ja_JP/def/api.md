# @def

このページは現在の `0.1.0` 基準における `@def` パッケージを説明します。

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
