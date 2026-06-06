# @def

本文档描述当前 `0.1.0` 基线中的 `@def` 包。

## 组成

- `Sign`：统一的符号分类，包含 `Negative`、`Zero`、`Positive`
- `FpClass`：统一的浮点分类，包含 `Finite`、`Infinity`、`NaN`
- `RoundingMode`：统一的舍入模式枚举
- `Floating`：仓库级共享 trait
- `is_finite` / `is_nan` / `is_infinite` / `is_zero`：基于 trait 的辅助谓词

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

它当前只约束：

- 分类
- 符号
- 精度
- 精度重整
- 规范化

当前实现者：

- `@bin_float.BinFloat`
- `@decimal.Decimal`
- `@ball_float.BallFloat`
