# @decimal.Decimal

## 稳定性

`Decimal`、`DecimalContext`、`DecimalFlags` 和 decimal interchange 是
`0.5.0` 支持的应用 API。内部 `DecCoeff` 布局不属于公开面；固定合法 GDA 语料
完全符合，唯一排除的是 `#` 占位/非标量非法输入。

本文档描述 `0.5.0` API 与 GDA 表示。

## 使用前先记住

- `Decimal` 不是“只存一个十进制字符串”的简单包装，它同时带有 sign、cohort 和 context 相关语义。
- 如果你只关心普通数值，直接使用 `add/sub/mul/div` 等入口即可。
- 如果你关心 flags、special values、preferred exponent、subnormal/overflow 等 GDA 语义，请优先使用 `*_ctx` 版本。
- 如果你关心 decimal32/64/128 的 raw interchange 表示，请使用 `DecimalInterchange`，不要只依赖标量 `Decimal`。

## 表示

有限值按下式存储：

`(-1)^negative * magnitude * 10^exponent10`

并附带工作精度 `precision`。

公开的 `coefficient()` 与 `magnitude()` observer 返回非负 coefficient 的
`BigInt` 表示；若需要单独查看符号，请使用 `is_negative()`。这一点对 `-0`
这类 GDA 风格值尤其重要，因为它的数学 coefficient 为零，但表示层仍然带有
负号。

## 构造与解析

- `Decimal::make`
- `Decimal::zero`
- `Decimal::negative_zero`
- `Decimal::one`
- `Decimal::inf`
- `Decimal::nan`
- `Decimal::quiet_nan`
- `Decimal::signaling_nan`
- `Decimal::from_int`
- `Decimal::from_bigint`
- `Decimal::from_float`
- `Decimal::from_double`
- `Decimal::from_string`
- `Decimal::from_interchange_hex`
- `Decimal::from_bin_float`
- `DecimalInterchange::from_hex`
- `DecimalInterchange::from_decimal`

说明：

- `make`、`from_int`、`from_bigint` 这类数值构造函数会通过去除可剥离的 `10`
  因子来规范化有限值。
- `from_string` 支持普通十进制、科学计数法，以及 `Infinity`、`NaN`、`sNaN`
  及其可选符号与十进制 payload；当 coefficient 能装进请求精度时，会保留解析得
  到的 exponent/quantum。
- `from_string("-0")` 会保留负零。
- 非法字符串返回 `None`。
- `from_interchange_hex` 会按指定的 decimal32/64/128 format context，把
  interchange 十六进制文本解码成标量 `Decimal`。
- `DecimalInterchange` 是公开的 raw decimal32/64/128 interchange bits 包装
  类型；当调用方需要保留、观察或 canonicalize 非 canonical 编码，而不是立刻塌
  缩成标量 decimal 值时，应使用它。

## 常见语义提醒

- `from_string` 会保留可表达范围内的 exponent/quantum，不会默认把输入先压成最短十进制。
- `from_string("-0")` 会保留负零。
- `from_float` / `from_double` 保留当前二进制浮点已经表达出来的值；因此它们是“精确保留 binary value”，不是“恢复人类原始十进制输入”。

## 访问、规范化与比较

- `classify`
- `class_name`
- `precision`
- `sign`
- `coefficient`
- `magnitude`
- `exponent10`
- `is_negative`
- `is_signed`
- `is_finite`
- `is_infinite`
- `is_nan`
- `is_canonical`
- `is_zero`
- `is_negative_zero`
- `is_normal`
- `is_subnormal`
- `is_quiet_nan`
- `is_qnan`
- `is_signaling_nan`
- `is_snan`
- `nan_payload`
- `normalized`
- `with_precision`
- `compare`
- `compare_ctx`
- `compare_signal_ctx`
- `compare_total`
- `compare_total_magnitude`
- `min`
- `max`
- `min_ctx`
- `max_ctx`
- `min_mag_ctx`
- `max_mag_ctx`
- `clamp`
- `clamp_checked`

说明：

- `compare` 遇到 `NaN` 会直接拒绝。
- `compare_ctx(lhs, rhs, ctx)` 返回十进制 `-1`、`0`、`1` 或 quiet `NaN`，并附
  带 flags。quiet NaN 不会设置 `invalid_operation`；signaling NaN 会设置它。
- `compare_signal_ctx(lhs, rhs, ctx)` 在数值结果形状上与 `compare_ctx` 相同，
  但只要任一操作数是 NaN 就会设置 `invalid_operation`。
- `clamp` 在边界无序或出现 `NaN` 时会直接拒绝；`clamp_checked` 将这些情况转换为结构化 domain error。
- 共享的 `Sign` observer 对所有有限零都会返回 `Zero`，包括负零。若零的符号
  在语义上有意义，请使用 `is_negative_zero()`。
- `class_name(ctx)` 返回该值在给定 exponent context 下的 GDA 风格分类字符串，
  包括 normal/subnormal 区分。
- `is_canonical()` 目前恒为 `true`，因为这个包还没有引入替代性的十进制交换编
  码。
- `is_qnan()` 和 `is_snan()` 是现有 quiet/signaling NaN 谓词的 GDA 命名别名。
- `Eq` 代表泛型 Luna-Flow 所使用的数值相等：`+0 == -0`，而且 NaN 与 NaN 在
  `Eq` 层也视为相等。若需要区分表示层细节，请使用显式 NaN observer。

## 何时用 context 版本

- 需要 flags：用 `*_ctx`
- 需要保留/观察 NaN payload、quieting、`invalid_operation`：用 `*_ctx`
- 需要和官方 `.decTest` / GDA 规则逐项对齐：用 `*_ctx`
- 只想做日常数值运算且不关心状态位：可先用非 `ctx` facade

## 算术与转换

- `neg`
- `abs`
- `copy`
- `copy_abs`
- `copy_negate`
- `copy_sign`
- `add`
- `add_ctx`
- `plus_ctx`
- `minus_ctx`
- `abs_ctx`
- `sub`
- `sub_ctx`
- `mul`
- `mul_ctx`
- `div`
- `div_ctx`
- `sqrt`
- `sqrt_ctx`
- `fma_ctx`
- `divide_integer`
- `remainder`
- `remainder_near`
- `next_plus`
- `next_minus`
- `next_toward`
- `exp_ctx`
- `ln_ctx`
- `logb_ctx`
- `scaleb_ctx`
- `to_sci_string`
- `to_eng_string`
- `shift_ctx`
- `rotate_ctx`
- `quantize`
- `rescale`
- `reduce_ctx`
- `normalize_ctx`
- `same_quantum`
- `to_integral_exact`
- `to_integral_value`
- `logical_and`
- `logical_or`
- `logical_xor`
- `logical_invert`
- `to_interchange_hex`
- `to_bin_float`

## Interchange 编码

- `DecimalInterchangeFormat::context`
- `Decimal::to_interchange_hex`
- `DecimalInterchange::format`
- `DecimalInterchange::to_hex`
- `DecimalInterchange::to_decimal`
- `DecimalInterchange::canonical`
- `DecimalInterchange::is_canonical`
- `DecimalInterchange::copy`
- `DecimalInterchange::copy_abs`
- `DecimalInterchange::copy_negate`
- `DecimalInterchange::copy_sign`

支持的运算符：

- `+`
- `-`
- `*`
- `/`
- 一元 `-`

转换语义：

- 十进制转二进制时，非 dyadic 值可能只能近似表示。
- 二进制转十进制时，会精确保留当前 `BinFloat` 内部已经存储的有限值。
- `to_sci_string(src, ctx)` 与 `to_eng_string(src, ctx)` 实现 `toSci`、`toEng`
  decTest 所使用的 GDA 字符串转换操作。它们会在当前 decimal context 下解析有
  限数、无穷、qNaN、sNaN 文本，再返回 canonical GDA scientific 或
  engineering 文本以及转换状态 flags。该路径覆盖语法诊断、payload 边界、丢
  弃零 digit 时的 `rounded`、按舍入方向溢出到无穷或最大有限值、Etiny 下溢、
  clamped zero exponent，以及 `Infinity`、`NaN7`、`sNaN` 这类 canonical
  special spelling。
- `logb_ctx` 在当前 context 下把 adjusted exponent 作为 Decimal 整数返回。有限
  零返回带 `division_by_zero` 的 `-Infinity`；无穷返回 `+Infinity`；NaN 按
  context 的 quiet/payload 规则传播。adjusted exponent 需要做 context 舍入时，
  如果丢弃的 digit 全为零，只设置 `rounded` 而不设置 `inexact`，与 GDA 整数
  结果语义保持一致。
- `scaleb_ctx` 在当前 context 下返回 `self * 10^other`。scale operand 必须是
  exponent 为零的有限整数，且落在 GDA context 允许范围内；非法 scale operand
  返回 quiet `NaN` 并设置 `invalid_operation`。有限结果会在可能时保留
  coefficient cohort，然后再做 exponent bound finalization，包括 Etiny
  subnormal 舍入、clamped zero 与按舍入方向产生的 overflow flags。
- `shift_ctx` 与 `rotate_ctx` 按当前 context precision 作为 digit 宽度实现 GDA
  coefficient digit 移动。count operand 必须是范围内的有限整数；非法 count 返
  回 quiet `NaN` 并设置 `invalid_operation`。quiet NaN 保留其符号和 payload，
  signaling NaN 会被 quiet 化，payload 截断遵循当前 context precision。
- `to_interchange_hex(format)` 会先把有限值应用到目标 decimal32/64/128
  format context，再编码成 interchange 十六进制文本；`from_interchange_hex`
  则执行反向解码，并接受 canonical 与 non-canonical interchange payload、
  可选前导 `#`、大小写十六进制字符以及首尾 ASCII 空白。
- `DecimalInterchange::to_hex()` 会输出 canonical wrapper 文本：hex body 统一为
  大写，并补足当前 decimal32/64/128 format 所要求的固定 digit 宽度。
- `DecimalInterchangeFormat::context()` 会返回与当前 decimal32、decimal64 或
  decimal128 interchange format 对应的 preset context，供 encode/decode helper
  复用。
- `DecimalInterchange::from_decimal(value, format)` 是 wrapper 形式的 encode
  入口：它会返回与 `value.to_interchange_hex(format)` 相同的表示结果与 flags，
  但把输出 bits 封装成 `DecimalInterchange`，便于继续做表示层操作。
- `DecimalInterchange` 让调用方能在不先塌缩到标量 Decimal cohort 的前提下，
  进行 canonicalization、sign-copy 等表示层操作。

## 文档边界

- 本页的目标是说明公开 API 和关键语义入口。
- `DecimalInterchange::canonical()` 会保留当前 interchange format，对 raw bits
  做一次 canonicalization，而且重复调用仍保持同一 canonical 结果。
- `DecimalInterchange::is_canonical()` 是与 `canonical()` 配套的表示层谓词：它会
  判断当前 raw bits 是否已经处于 canonical interchange form，包括 special
  value 编码。
- `DecimalInterchange::to_decimal()` 会按 wrapper 内保存的 interchange format
  解码，并保留 raw bits 所表达的 special-value 符号、qNaN/sNaN 形态与 payload
  语义。
- `DecimalInterchange::copy()` 是保留表示层的 wrapper copy：它会原样保留 raw
  bits 和 format，包括 non-canonical 编码。
- `DecimalInterchange::copy_sign` 要求两个操作数使用同一种 interchange
  format；跨 decimal32/64/128 的 mixed-format sign-copy 会被直接拒绝，而不会
  静默重解释 bit layout。
- `DecimalInterchange::copy_abs`、`copy_negate`、`copy_sign` 只会改动 raw sign
  bit；对 NaN、Infinity 和有限编码的 payload/coefficient continuation bits 都应
  保持不变。

## Context 与 Flags

- `DecimalContext::new`
- `DecimalContext::try_new`
- `DecimalContext::exact`
- `DecimalContext::decimal32`
- `DecimalContext::decimal64`
- `DecimalContext::decimal128`
- `DecimalContext::from_arithmetic_context`
- `DecimalRoundingMode::from_arithmetic`
- `DecimalRoundingMode::to_arithmetic`
- `DecimalFlags::new`
- `DecimalFlags::combine`
- `DecimalFlags::has_error`

`*_ctx` 方法返回 `(Decimal, DecimalFlags)`。当前 context 层会跟踪有限结果的
`lost_digits`；当非 extended 的 GDA 运算在执行前对超精度 operand 做非精确缩减时，
该标志会与 `rounded`、`inexact` 一起设置。
`rounded` 与 `inexact`、signaling-NaN 的 `invalid_operation`、除零、未定义
除法、有限结果的 exponent 边界、clamp 补零、overflow、subnormal 与 underflow
状态。`decimal32` / `decimal64` / `decimal128` 构造器会保存预期精度与 exponent
边界，而 context-aware 的有限结果会按这些边界完成 finalization。

`DecimalContext` 同时保存共享的 Luna-Flow `rounding` 与十进制原生的
`decimal_rounding`。前者是 `ArithmeticContext` 和通用 checked traits 的桥接层；
后者覆盖 context-aware Decimal 运算所需的完整 GDA 舍入基线：`HalfEven`、
`HalfUp`、`HalfDown`、`Down`、`Ceiling`、`Floor`、`Up`、`ZeroFiveUp`。像
`HalfUp`、`HalfDown`、`ZeroFiveUp` 这样的 GDA-only 模式，在
`DecimalRoundingMode::to_arithmetic()` 中会返回 `None`，因为共享的 Luna-Flow
rounding enum 并不声称自己支持这些模式。

`DecimalContext::new` 的 `extended` 命名参数控制 GDA arithmetic mode，默认值为
`true`。普通用户无需配置即可使用 extended arithmetic；需要复现经典 decNumber
subset 语义时，可显式使用
`DecimalContext::new(precision=17, extended=false)`。关闭后，operand reduction、
`lost_digits`、零与 cohort 处理以及 transcendental 的经典舍入行为都会遵循 GDA
subset 路径。

当前 exponent-bound 实现遵循 GDA baseline 规则，并已由合法行 conformance 覆盖。高于 `e_max`
的结果目前会产生无穷，并设置 `overflow`、`rounded`、`inexact`。精确但低于
`e_min` 的结果会设置 `subnormal`；不精确的 subnormal 结果还会额外设置
`underflow`。clamp 模式可以在保持数值不变的前提下给 coefficient 补尾零并降低
exponent，同时设置 `clamped`。

context-aware 的有限加、减、乘以及 quantize 风格操作，在结果能装进 context
时会保留该操作偏好的 exponent。例如，精确的十进制刻度结果 `1.20 + 3.40` 可以
保留在 `4.60` cohort，而不是被 canonicalize 成 `4.6`。

`fma_ctx` 先精确完成乘法，再在加上第三个操作数后统一应用 context 舍入。
`divide_integer` 返回 exponent 为 `0` 的整数部分，并在整数商无法装进 context
precision 时报告 `division_impossible`。`remainder` 使用该整数商，因此当前已实
现的有限情形遵循 `x - divide_integer(x, y) * y`。`remainder_near` 使用最近整
数商，平局时朝偶数商方向打破。

`power_ctx` 是当前可执行标量 `power.decTest` 覆盖面的 context-aware GDA 幂运
算入口。它覆盖精确有限整数指数、包括 million-scale case 在内的舍入大整数指数、
通过当前 context honest finalization 处理的终止与非终止倒数结果、精确 `+1`
与 `-1` 恒等式、NaN priority 传播、无穷底数的非整数符号/domain 情形、无穷指
数极限情形、有限正底数的非整数幂、有限非整数 power 的 operand-range invalid
行，以及有限 10 的幂底数在大整数指数下必然 overflow 或 half-even underflow
to zero 的情形。它也会上报官方 math-function `Invalid_context` restriction
行。唯一排除的是 diagnostic `#` interchange/非标量占位输入；不存在非诊断标量
`power` 子集缺口。

`log10_ctx` 是 context-aware 的 GDA 十进制对数入口。它使用 fixed-point
logarithm baseline，保留 NaN 的符号/payload quiet 传播，把 signed zero 映射为
`-Infinity`，把正无穷映射为 `Infinity`，并对负有限值与负无穷返回带
`invalid_operation` 的 quiet `NaN`。正的有限对数结果会通过当前 context 舍入，
同时也覆盖官方 math-function `Invalid_context` restriction 行。

`exp_ctx` 与 `ln_ctx` 是 context-aware 的 GDA 数学函数入口。`exp_ctx` 使用带
十进制 range reduction 的 fixed-point exponential evaluation，处理 NaN、无穷、
有限 signed zero（`exp(0) = 1`）、一般有限值、overflow/underflow 边界，以及
官方 math-function `Invalid_context` restriction 行。`ln_ctx` 使用
fixed-point logarithm baseline，处理 NaN、无穷、signed zero、负有限
invalid-operation 情形、精确等于 1 的有限值（`ln(1) = 0`），以及一般正有限值。

## Trait 面

`Decimal` 当前实现了：

- `@arithmetic.CompareChecked`
- `@arithmetic.DivChecked`
- `@arithmetic.ParseChecked`
- `@arithmetic.PowIntChecked`
- `@arithmetic.PowNatChecked`
- `@arithmetic.SqrtChecked`
- `@def.Floating`
- `@luna-generic.Zero`
- `@luna-generic.One`
- `@luna-generic.AddMonoid`
- `@luna-generic.MulMonoid`
- `@luna-generic.AddGroup`
- `@luna-generic.Semiring`
- `@luna-generic.Ring`
- `Eq`、`Add`、`Sub`、`Mul`、`Div`、`Neg`、`Show`

行为补充：

- `Decimal` 不实现独立的超越函数 trait 或常量 trait；初等函数通过显式 context 方法提供。
- 与 `Luna-Flow/arithmetic` 的主要集成面仍然是 checked arithmetic traits。
- 这个包已经开始向 GDA 兼容表示迁移，并且已经暴露十进制 interchange
  encode/decode API；一致性状态以当前 `gda_expr` 执行汇总为准，不笼统承诺
  每个 diagnostic 行都可执行。

## 公开接口补充清单

`DecCoeff` 已收回为包内实现，公开表示边界统一使用 `BigInt`。
生成接口还包含 `Decimal::{from_string_ctx,parse,apply_ctx,trim,div_checked,compare_checked,compare_total_ctx,compare_total_magnitude_ctx}`
和 `DecimalInterchange::to_decimal_ctx`。
