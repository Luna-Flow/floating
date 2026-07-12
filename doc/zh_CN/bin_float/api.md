# @bin_float.BinFloat

## 稳定性

`BinFloat`、`BinCoeff`、二进制 context/flags 和 binary16/32/64/128
interchange 是 `0.5.0` 支持的应用 API。limb 布局、算法阈值和完整 IEEE 754
覆盖不属于稳定承诺。

本文档描述 `0.5.0` API；数学与测试边界见[一致性说明](./conformance.md)。

## Context、flags 与 interchange

- `BinaryRoundingMode`：nearest-even、nearest-away、toward-zero、toward-positive、
  toward-negative、away-from-zero。
- `TininessDetection`：before/after rounding。
- `BinaryContext::new`、`try_new`、`unbounded`、`binary16`、`binary32`、`binary64`、`binary128`。
- `BinaryFlags`：五个 IEEE 标志、`combine`、`to_testfloat_bits`。
- `BinaryInterchangeFormat` 与 `BinaryInterchange::from_hex`、`to_hex`、
  `to_bin_float`、`from_bin_float`；`BinFloat::to_interchange`。

编码 API 返回 `(bits, flags)`。

## 构造与观察

`BinFloat::make`、`zero`、`negative_zero`、`one`、`inf`、`nan`、`quiet_nan`、
`signaling_nan`、`from_int`、`from_coefficient`、`from_float`、`from_double`。

公开系数类型是非负的 `BinCoeff`。使用 `BinCoeff::from_uint64`、`parse` 或
`from_bytes_be` 构造，再传给 `BinFloat::from_coefficient` 或 `BinFloat::make`；
符号通过独立的 `negative?` 参数表示。二进制/区间浮点不再暴露 `BigInt` 边界，
但 Decimal 与 Semantic 的既有 `BigInt` API 保持不变。

`BinCoeff` 公开 `zero`、`one`、`from_uint64`、`parse`、字节转换、比较、位查询、
加法、`sub_checked`、乘法、平方、`div_rem_checked`、`gcd`、自然数幂、移位和
按位运算。由于该类型只能表示非负值，可能产生负结果的减法与可能除零的除法使用
checked API。

### 从 0.4 二进制 API 迁移

| 旧 API | 当前 API |
| --- | --- |
| `BinFloat::from_bigint(n)` | `BinFloat::from_coefficient(c, negative=...)` |
| `BinFloat::make(n, e, p)` | `BinFloat::make(c, e, p, negative=...)` |
| `value.significand()` | `value.coefficient()` |
| `BinaryInterchange::from_bits(n, format)` / `bits() -> BigInt` | `from_bits(c, format)` / `bits() -> BinCoeff` |
| `BallFloat::from_bigint(n)` | `BallFloat::from_coefficient(c, negative=...)` |
| checked `from_bigint(n)` | checked `from_coefficient(c, negative=...)` |
| `NatHomomorphism` / `IntegralHomomorphism` | 从二进制类型移除，改用显式构造器 |

`classify`、`precision`、`sign`、`is_negative`、`is_negative_zero`、
`is_quiet_nan`、`is_signaling_nan`、`nan_payload`、`coefficient`、`exponent2`、
`is_zero`、`normalized`、`with_precision`、`ulp`、`compare`、`min`、`max`、`clamp`、`clamp_checked`
提供访问和普通操作。NaN 不可参与有序比较。

## 算术

普通 `+`、`-`、`*`、`/` 及 `add`、`sub`、`mul`、`div` 使用无界 nearest-even
context，不返回标志。需要 IEEE 语义时使用 `round_ctx`、`add_ctx`、`sub_ctx`、
`mul_ctx`、`div_ctx`、`sqrt_ctx`、`pow_int_ctx`，它们返回 `(BinFloat, BinaryFlags)`。

保留的 checked helper 是 `sqrt_bounds_for_precision`、`sqrt_for_precision`、
`compare_checked`、`div_checked`、`sqrt`、`pow_int`。
## 表示

有限值是独立符号、`BinCoeff`、`exponent2` 和 precision；零、无穷与 NaN 状态可观察。

## 访问、规范化与比较

使用 `coefficient`、`exponent2`、`normalized`、`compare` 和分类谓词观察值；NaN 不参与普通全序。

## 算术与转换

普通运算适合任意精度；context 运算返回值和 flags，interchange 负责定宽位编码。

## Checked 算术 API

底层 checked trait 将失败显式表示为 `ArithmeticError`，而 flags 仍由 `*_ctx` 返回。

## Trait 面

`Floating`、算术 checked trait 和标准运算 trait 提供最小组合能力，详见生成接口。
