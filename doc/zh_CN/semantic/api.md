# `semantic` API

该包把具体数值表示投影到与表示无关的语义模型。

## 精确值与标量

- `ExactRational::new` 构造规范化有理数；`from_scaled_integer` 构造精确的带基数缩放整数。
- `SemanticScalar` 包含 `Rational`、`Infinity(Sign)` 和 `NaN`。
- `from_bin_float` 与 `from_decimal` 投影具体标量。

## 区间与错误

- `SemanticInterval` 保存公开的 `lower`、`upper`，`from_ball_float` 投影区间。
- `SemanticError` 区分除零、解析、定义域、格式、未支持操作和无序比较。
- `SemanticError::from_arithmetic` 把 `ArithmeticError` 映射到该语义错误词汇。
- `SemanticResult[T]` 为 `Value(T)` 或 `Error(SemanticError)`。
- `semantic_scalar_result`、`semantic_interval_result` 用调用方提供的投影函数转换 checked 结果。
