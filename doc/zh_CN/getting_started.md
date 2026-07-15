# 快速上手

本文面向 `Luna-Flow/floating` **`0.7.0`**，说明如何选择包、安装模块、构造
数值、选择错误模型，以及继续查阅对应参考文档。

## 选择数值域

应根据应用所需的数值语义选择表示，而不是根据输入文本看起来像什么来选择。

| 需求 | 包 | 主要值类型 | 结果模型 |
| --- | --- | --- | --- |
| 任意精度二进制有理值或 IEEE binary interchange | `bin_float` | `BinFloat` | 普通值，或 context 下的 `(value, BinaryFlags)` |
| IEEE 任意精度十进制与 decimal interchange | `decimal` | `Decimal` | 普通值，或 context 下的 `(value, DecimalFlags)` |
| General Decimal Arithmetic 状态与 traps | `decimal_gda` | `Decimal` | 带 next context 与 raised flags 的 `GdaOutcome[Decimal]` |
| 可证明的实数包络 | `ball_float` | `BallFloat` / `BallFloatDecorated` | 包络，或 context 下的 `(enclosure, BallFlags)` |
| 累计 flags 的 IEEE 十进制流水线 | `decimal_checked` | `DecimalChecked` | 定义值、本步与累计 `DecimalFlags` |
| 带 trap 控制的 GDA 流水线 | `decimal_gda_checked` | `GdaDecimalChecked` | sticky context 与 `GdaOutcome[Decimal]` |
| 短路的二进制或区间流水线 | `bin_float_checked`、`ball_float_checked` | `*Result` | 包装器内保留 `Result[..., ArithmeticError]` |
| 与具体表示无关的比较 | `semantic` | `SemanticScalar` / `SemanticInterval` | 精确投影，但有意丢弃表示元数据 |

只有在构建 parser 或 conformance 工具时才应直接使用 `numeric_expr` 与
`frontend/*`。`internal/*`、`consistency`、`doc_examples` 和 `*_bench` 是维护
基础设施，不是应用依赖入口。

## 安装与导入

安装当前版本：

```sh
moon add Luna-Flow/floating@0.7.0
moon add Luna-Flow/arithmetic
```

当前 MoonBit 包只导入实际需要的包边界：

```moonbit nocheck
import {
  "Luna-Flow/arithmetic"
  "Luna-Flow/floating/bin_float"
  "Luna-Flow/floating/decimal"
  "Luna-Flow/floating/decimal_gda"
  "Luna-Flow/floating/decimal_checked"
  "Luna-Flow/floating/decimal_gda_checked"
  "Luna-Flow/floating/ball_float"
}
```

导入路径指向 package，而不是源码文件。同一个 `moon.pkg` 内的文件属于同一
编译单元，不会各自创建子模块。

`Luna-Flow/arithmetic` 提供显式精度调整和格式转换所使用的舍入模式类型。如果
所有操作都采用默认舍入模式，可以不导入它；显式导入则能让边界策略在代码中可见。

## 构造数值

二进制系数使用 `BinCoeff`，符号独立保存。Decimal 解析保留输入 quantum，
包括有意义的尾随零。区间通常由有序的二进制端点构造。

```moonbit nocheck
let binary = @bin_float.BinFloat::make(
  @bin_float.BinCoeff::from_uint64(3UL),
  -1,
  53,
)
let decimal = @decimal.Decimal::from_string("12.3400").unwrap()
let interval = @ball_float.BallFloat::from_bounds(
  @bin_float.BinFloat::from_int(1),
  @bin_float.BinFloat::from_int(2),
)
```

`binary` 是精确二进制有理值 `3 × 2^-1`；`decimal` 保留指数 `-4`；
`interval` 表示从 1 到 2 的全部实数。只有确实需要规范 cohort 时才调用
`normalized()`。

## 选择 Context 模型

不受固定格式约束的任意精度运算可用普通方法。当 precision、指数范围、舍入、
tininess、clamp 或状态 flags 属于结果合同时，应使用 `*_ctx`。

```moonbit nocheck
let binary_context = @bin_float.BinaryContext::binary64()
let (binary_sum, binary_flags) = binary.add_ctx(binary, binary_context)

let decimal_context = @decimal.DecimalContext::decimal64()
let (decimal_value, decimal_flags) =
  @decimal.Decimal::from_string_ctx("1.234567890123456789", decimal_context)
```

IEEE context 是不可变输入，flags 是显式输出。多步计算需要累计状态时应组合
flags。GDA 则在每个 `GdaOutcome` 中返回更新后的 sticky context。

## 选择失败模型

库刻意保留了几种不等价的失败通道：

- `Option` 用于不承诺额外诊断的简单构造器；
- `Result[T, ArithmeticError]` 用于 checked 标量能力；
- `BinaryFlags`、`DecimalFlags` 与 `BallFlags` 报告产生一个已定义结果时出现的
  IEEE 或数值域条件；
- `GdaOutcome[T]` 即使触发配置的 trap，也保留 GDA 定义的结果；
- `DecimalChecked` 累计 IEEE flags，但不替换已定义的 NaN 或 infinity；
  `GdaDecimalChecked` 对 trap 短路，同时保留完整 `GdaOutcome`；
- `Entire`、`Empty` 与 `NaI` 是区间域中的值，不是通用错误。

不要把这些通道全部改写成异常或一个万能 `Result`，否则会丢失可观察数值语义。

## 正确读取结果

- 标量表示可能保留 signed zero、infinity、quiet NaN、signaling NaN 与 payload；
- 存在 NaN 时普通标量比较是偏序，total-order API 是另一组显式操作；
- `BallFloat` 使用包含与集合关系，不具有标量全序；
- 区间只要包住数学结果就是正确的，tightness 是另一项质量属性；
- `SemanticScalar` 比较数学含义，但有意丢弃 precision、quantum、signed zero、
  NaN payload、decoration 和 flags。

## 继续阅读

- [数值语义](./numeric_semantics.md)解释 precision、舍入、状态、特殊值与区间包络；
- [架构](./architecture.md)说明稳定包、解析、执行与验证基础设施之间的关系；
- [验证](./verification.md)列出快速检查、权威 gate 和每项 conformance 声明的精确范围；
- 各包的 `api.md`、`tutorial.md` 与 `design.md` 分别记录可调用名称、使用流程和实现边界。
- 数值核心证据按包归档：[`bin_float`](./bin_float/conformance.md)、[`decimal`](./decimal/conformance.md)、[`decimal_gda`](./decimal_gda/conformance.md)与 [`ball_float`](./ball_float/conformance.md)。
