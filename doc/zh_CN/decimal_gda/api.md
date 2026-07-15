# `decimal_gda` API

`decimal_gda` 是 `0.7.0` 的 General Decimal Arithmetic Specification 1.70 入口。
它的 value、context、flags、traps、signals 与 outcomes 都区别于 `decimal` 中面向
IEEE 的类型。

实现同样完全独立：`Decimal` 拥有持久的 `Small(UInt64) | Limbs(base-10^9)`
coefficient，`GdaContext` 直接保存 policy 与 state，decimal32/64/128 concrete
interchange 只实现 DPD。本包及其生产 frontend 均不 import `decimal`。

## 值类型

不透明 `Decimal` 支持：

- `from_string(source, precision?) -> Decimal?`：无 context 构造；
- `zero`、`one`、`quiet_nan` 与 `signaling_nan`；
- `is_finite`、`is_infinite`、`is_nan`、`is_qnan`、`is_snan`、`is_zero`、
  `is_negative` 分类；
- `nan_payload` 观察与 `Show` 格式化。

当 conversion syntax、rounding、指数限制、sticky status 或 traps 必须可观察时，
使用包函数 `parse(source, context)`。该类型不是 `@decimal.Decimal` 的 alias；
IEEE/GDA 边界应通过文本或声明的 interchange format 穿越，不能依赖私有表示。

## Context 与舍入

`GdaContext::new` 接受正 `precision`、`GdaRoundingMode`、`e_min`、`e_max`、
`clamp`、`extended` 与 `GdaTrapSet`，非正 precision 会 abort。`try_new` 则把非正
precision 或反向指数边界返回为 `ArithmeticError`。

舍入模式包括 `HalfEven`、`HalfUp`、`HalfDown`、`Down`、`Ceiling`、`Floor`、
`Up` 与 `ZeroFiveUp`。

GDA package 的 `sqrt`、`exp`、`ln`、`log10` 按规范要求固定使用 half-even 完成数学函数
结果，不受 context 通用舍入设置影响。`power` 与普通算术仍按
`GdaContext::rounding` 舍入，这一点由官方 decTest 的多舍入向量覆盖。

Context 构造与 accessor：

| API | 含义 |
| --- | --- |
| `basic`、`default` | precision 9、half-up、non-extended；启用 Clamped、DivisionByZero、InvalidOperation、Overflow、Underflow traps |
| `decimal32`、`decimal64`、`decimal128` | 标准 precision/指数/clamp preset |
| 包函数 `context` | `GdaContext::new` 的便利入口 |
| 包函数 `decimal*_context` | 标准 preset 的便利入口 |
| `radix` | 固定为 10 |
| `precision`、`rounding`、`e_min`、`e_max`、`clamp`、`extended` | 不可变算术策略 |
| `status`、`traps` | 当前 sticky status 与启用 trap set |
| `with_traps`、`trap` | 返回修改 traps 后的新 context |
| `clear_status` | 清 sticky status，保留 traps |
| `reset` | 同时清 sticky status 与 traps |

## Signals、Flags 与 Traps

`GdaSignal` 包含 `ConversionSyntax`、`DivisionByZero`、`DivisionImpossible`、
`DivisionUndefined`、`InvalidContext`、`InvalidOperation`、`Overflow`、
`Underflow`、`Subnormal`、`Inexact`、`Rounded`、`Clamped` 与 `LostDigits`。

`GdaFlags::none`、`contains`、`combine` 用于创建、查询和并集条件集合。
`GdaTrapSet::none`、`with_signal`、`contains` 以不可变方式配置 traps。

1.70 的标准 signals 是 Clamped、DivisionByZero、InvalidOperation、Overflow、
Underflow、Subnormal、Inexact 与 Rounded。`ConversionSyntax`、
`DivisionImpossible`、`DivisionUndefined`、`InvalidContext` 作为细粒度条件诊断保留，
但都会发出 `InvalidOperation` signal；`LostDigits` 用于兼容旧式 non-extended 算术。
因此启用 `InvalidOperation` trap 会捕获上述所有 invalid conditions。

一次运算触发多个启用 signal 时，trap 优先级依次是：invalid operation、division by
zero、division undefined、division impossible、invalid context、conversion syntax、
overflow、underflow、subnormal、inexact、rounded、clamped、lost digits。

## Outcomes 与状态传递

每个 context operation 都返回 `GdaOutcome[T]`：

```moonbit nocheck
enum GdaOutcome[T] {
  Completed(T, GdaContext, GdaFlags)
  Trapped(GdaSignal, T, GdaContext, GdaFlags)
}
```

两种 variant 都包含 defined result、带 sticky status 的 next context 与本次 raised
flags。`value`、`next_context` 与 `raised` 无需 match 即可读取公共字段。

若要累计 status，把 `outcome.next_context()` 传入下一步。再次使用旧输入 context
意味着下一步从旧 status 开始。Trap 不会丢弃结果。

## 算术操作

所有函数都把 operands 放在前、`GdaContext` 放在最后，并返回 `GdaOutcome[...]`。

| 族 | 函数 |
| --- | --- |
| Context application/unary | `apply`、`plus`、`minus`、`abs` |
| 基础算术 | `add`、`subtract`、`multiply`、`divide`、`fma` |
| 商与余数 | `divide_integer`、`remainder`、`remainder_near` |
| 指数/quantum | `quantize`、`rescale`、`scaleb`、`reduce` |
| 整数转换 | `to_integral_exact`、`to_integral_value` |
| 初等函数 | `sqrt`、`exp`、`ln`、`log10`、`power` |
| 相邻值 | `next_plus`、`next_minus`、`next_toward` |
| 逻辑数字 | `logical_and`、`logical_or`、`logical_xor`、`logical_invert` |
| 数字移动 | `shift`、`rotate` |
| 比较 | `compare`、`compare_signal`、`compare_total`、`compare_total_magnitude` |

`compare` 与 `compare_signal` 返回 GDA decimal comparison value；`compare_total` 与
`compare_total_magnitude` 在 outcome 内返回 `Int`。Total comparison 感知表示，
不同于普通数值比较。

## 边界与保证

该包服务于 GDA 集成与 `.decTest` 行为。新的 IEEE 754 代码通常应使用 `decimal`，
其中运算返回 `(Decimal, DecimalFlags)`，context 不携带 sticky status 或 traps。
三角、反三角、`atan2`、双曲、`hypot` 与 pi-scaled 函数不属于 GDA 运算，
因此本包有意不提供这些 API。

固定 `official` corpus 的 64,986 条合法 executable scalar row 全部通过，
`official0` 的 16,124 条合法行全部通过。这不把 diagnostic `#` placeholder/
non-scalar 行变成数值，也不承诺无限资源或未来 directive 的兼容性。

## 完整公开接口

以下快照是 `0.7.0` 的完整生成包接口。公开声明是名称与签名的权威清单；前文按行为解释这些能力。

<!-- generated-api-start -->
```moonbit
// Generated using `moon info`, DON'T EDIT IT
package "Luna-Flow/floating/decimal_gda"

import {
  "Luna-Flow/arithmetic",
  "Luna-Flow/floating/bin_float",
  "Luna-Flow/floating/def",
  "Luna-Flow/luna-generic",
  "moonbitlang/core/bigint",
  "moonbitlang/core/debug",
}

// Values
pub fn abs(Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn add(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn apply(Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn class_name(Decimal, GdaContext) -> GdaOutcome[String]

pub fn compare(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn compare_signal(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn compare_total(Decimal, Decimal, GdaContext) -> GdaOutcome[Int]

pub fn compare_total_magnitude(Decimal, Decimal, GdaContext) -> GdaOutcome[Int]

pub fn context(precision? : Int, rounding? : GdaRoundingMode, e_min? : Int, e_max? : Int, clamp? : Bool, extended? : Bool) -> GdaContext

pub fn decimal128_context() -> GdaContext

pub fn decimal32_context() -> GdaContext

pub fn decimal64_context() -> GdaContext

pub fn divide(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn divide_integer(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn exp(Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn fma(Decimal, Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn is_normal(Decimal, GdaContext) -> GdaOutcome[Bool]

pub fn is_subnormal(Decimal, GdaContext) -> GdaOutcome[Bool]

pub fn ln(Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn log10(Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn logb(Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn logical_and(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn logical_invert(Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn logical_or(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn logical_xor(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn max(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn max_mag(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn min(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn min_mag(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn minus(Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn multiply(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn next_minus(Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn next_plus(Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn next_toward(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn parse(String, GdaContext) -> GdaOutcome[Decimal]

pub fn plus(Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn power(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn quantize(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn reduce(Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn remainder(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn remainder_near(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn rescale(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn rotate(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn same_quantum(Decimal, Decimal, GdaContext) -> GdaOutcome[Bool]

pub fn scaleb(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn shift(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn sqrt(Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn subtract(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn to_integral_exact(Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn to_integral_value(Decimal, GdaContext) -> GdaOutcome[Decimal]

// Errors

// Types and methods
pub struct Decimal {
  // private fields
} derive(@debug.Debug)
pub fn Decimal::abs(Self) -> Self
pub fn Decimal::abs_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::add(Self, Self) -> Self
pub fn Decimal::add_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::apply_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::clamp(Self, min~ : Self, max~ : Self) -> Self
pub fn Decimal::clamp_checked(Self, min~ : Self, max~ : Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn Decimal::class_name(Self, DecimalContext) -> String
pub fn Decimal::classify(Self) -> @arithmetic.FpClass
pub fn Decimal::coefficient(Self) -> @bigint.BigInt
pub fn Decimal::compare(Self, Self) -> Int
pub fn Decimal::compare_checked(Self, Self) -> Result[Int, @arithmetic.ArithmeticError]
pub fn Decimal::compare_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::compare_signal_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::compare_total(Self, Self) -> Int
pub fn Decimal::compare_total_ctx(Self, Self, DecimalContext) -> (Int, DecimalFlags)
pub fn Decimal::compare_total_magnitude(Self, Self) -> Int
pub fn Decimal::compare_total_magnitude_ctx(Self, Self, DecimalContext) -> (Int, DecimalFlags)
pub fn Decimal::copy(Self) -> Self
pub fn Decimal::copy_abs(Self) -> Self
pub fn Decimal::copy_negate(Self) -> Self
pub fn Decimal::copy_sign(Self, Self) -> Self
pub fn Decimal::div(Self, Self) -> Self
pub fn Decimal::div_checked(Self, Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn Decimal::div_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::divide_integer(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::exp_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::exponent10(Self) -> Int
pub fn Decimal::fma_ctx(Self, Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::from_bigint(@bigint.BigInt, precision? : Int) -> Self
pub fn Decimal::from_bin_float(@bin_float.BinFloat, precision? : Int) -> Self
pub fn Decimal::from_double(Double, precision? : Int) -> Self
pub fn Decimal::from_float(Float, precision? : Int) -> Self
pub fn Decimal::from_int(Int, precision? : Int) -> Self
pub fn Decimal::from_interchange_hex(String, GdaInterchangeFormat) -> Self?
pub fn Decimal::from_string(String, precision? : Int) -> Self?
pub fn Decimal::from_string_ctx(String, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::get_payload(Self) -> @bigint.BigInt
pub fn Decimal::inf(@def.Sign, precision? : Int) -> Self
pub fn Decimal::is_canonical(Self) -> Bool
pub fn Decimal::is_finite(Self) -> Bool
pub fn Decimal::is_infinite(Self) -> Bool
pub fn Decimal::is_nan(Self) -> Bool
pub fn Decimal::is_negative(Self) -> Bool
pub fn Decimal::is_negative_zero(Self) -> Bool
pub fn Decimal::is_normal(Self, DecimalContext) -> Bool
pub fn Decimal::is_qnan(Self) -> Bool
pub fn Decimal::is_quiet_nan(Self) -> Bool
pub fn Decimal::is_signaling_nan(Self) -> Bool
pub fn Decimal::is_signed(Self) -> Bool
pub fn Decimal::is_snan(Self) -> Bool
pub fn Decimal::is_subnormal(Self, DecimalContext) -> Bool
pub fn Decimal::is_zero(Self) -> Bool
pub fn Decimal::ln_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::log10_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::logb_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::logical_and(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::logical_invert(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::logical_or(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::logical_xor(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::magnitude(Self) -> @bigint.BigInt
pub fn Decimal::make(@bigint.BigInt, Int, Int, mode? : @arithmetic.RoundingMode) -> Self
pub fn Decimal::max(Self, Self) -> Self
pub fn Decimal::max_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::max_mag_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::maximum_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::maximum_mag_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::maximum_magnitude_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::maximum_number_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::maximum_number_mag_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::maximum_number_magnitude_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::min(Self, Self) -> Self
pub fn Decimal::min_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::min_mag_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::minimum_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::minimum_mag_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::minimum_magnitude_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::minimum_number_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::minimum_number_mag_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::minimum_number_magnitude_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::minus_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::mul(Self, Self) -> Self
pub fn Decimal::mul_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::nan(precision? : Int) -> Self
pub fn Decimal::nan_payload(Self) -> @bigint.BigInt
pub fn Decimal::neg(Self) -> Self
pub fn Decimal::negative_zero(precision? : Int) -> Self
pub fn Decimal::next_minus(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::next_plus(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::next_toward(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::normalize_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::normalized(Self) -> Self
pub fn Decimal::one(precision? : Int) -> Self
pub fn Decimal::parse(String, precision? : Int) -> Result[Self, @arithmetic.ArithmeticError]
pub fn Decimal::plus_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::power_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::precision(Self) -> Int
pub fn Decimal::quantize(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::quantum(Self) -> Int
pub fn Decimal::quiet_nan(payload? : @bigint.BigInt, negative? : Bool, precision? : Int) -> Self
pub fn Decimal::reduce_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::remainder(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::remainder_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::remainder_near(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::rescale(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::rotate_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::same_quantum(Self, Self) -> Bool
pub fn Decimal::scaleb_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::set_payload(Self, @bigint.BigInt) -> Self
pub fn Decimal::set_payload_signaling(Self, @bigint.BigInt) -> Self
pub fn Decimal::shift_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::sign(Self) -> @def.Sign
pub fn Decimal::signaling_nan(payload? : @bigint.BigInt, negative? : Bool, precision? : Int) -> Self
pub fn Decimal::sqrt(Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn Decimal::sqrt_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::sub(Self, Self) -> Self
pub fn Decimal::sub_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::to_bin_float(Self, precision? : Int, mode? : @arithmetic.RoundingMode) -> @bin_float.BinFloat
pub fn Decimal::to_eng_string(String, DecimalContext) -> (String, DecimalFlags)
pub fn Decimal::to_integral_exact(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::to_integral_value(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::to_interchange_hex(Self, GdaInterchangeFormat) -> (String, DecimalFlags)
pub fn Decimal::to_sci_string(String, DecimalContext) -> (String, DecimalFlags)
pub fn Decimal::trim(Self) -> Self
pub fn Decimal::try_exp_ctx(Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::try_ln_ctx(Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::try_log10_ctx(Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::try_power_ctx(Self, Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::with_precision(Self, Int, @arithmetic.RoundingMode) -> Self
pub fn Decimal::zero(precision? : Int) -> Self
pub impl @arithmetic.AbsContextual for Decimal
pub impl @arithmetic.AddContextual for Decimal
pub impl @arithmetic.CompareChecked for Decimal
pub impl @arithmetic.DivChecked for Decimal
pub impl @arithmetic.DivContextual for Decimal
pub impl @arithmetic.ExpContextual for Decimal
pub impl @arithmetic.MulContextual for Decimal
pub impl @arithmetic.NumericFormatContextual for Decimal
pub impl @arithmetic.ParseChecked for Decimal
pub impl @arithmetic.PowIntChecked for Decimal
pub impl @arithmetic.PowNatChecked for Decimal
pub impl @arithmetic.SqrtChecked for Decimal
pub impl @arithmetic.SqrtContextual for Decimal
pub impl @arithmetic.SubContextual for Decimal
pub impl @def.Floating for Decimal
pub impl @luna-generic.AddGroup for Decimal
pub impl @luna-generic.AddMonoid for Decimal
pub impl @luna-generic.IntegralHomomorphism for Decimal
pub impl @luna-generic.MulMonoid for Decimal
pub impl @luna-generic.NatHomomorphism for Decimal
pub impl @luna-generic.One for Decimal
pub impl @luna-generic.Ring for Decimal
pub impl @luna-generic.Semiring for Decimal
pub impl @luna-generic.Zero for Decimal
pub impl Add for Decimal
pub impl Compare for Decimal
pub impl Div for Decimal
pub impl Eq for Decimal
pub impl Mul for Decimal
pub impl Neg for Decimal
pub impl Show for Decimal
pub impl Sub for Decimal

pub struct DecimalContext {
  // private fields
} derive(Eq)
pub fn DecimalContext::clamp(Self) -> Bool
pub fn DecimalContext::decimal128() -> Self
pub fn DecimalContext::decimal32() -> Self
pub fn DecimalContext::decimal64() -> Self
pub fn DecimalContext::decimal_rounding(Self) -> DecimalRoundingMode
pub fn DecimalContext::e_max(Self) -> Int
pub fn DecimalContext::e_min(Self) -> Int
pub fn DecimalContext::exact() -> Self
pub fn DecimalContext::extended(Self) -> Bool
pub fn DecimalContext::from_arithmetic_context(@arithmetic.ArithmeticContext) -> Self
pub fn DecimalContext::new(precision? : Int, rounding? : @arithmetic.RoundingMode, decimal_rounding? : DecimalRoundingMode, e_min? : Int, e_max? : Int, clamp? : Bool, extended? : Bool, tininess? : DecimalTininessDetection) -> Self
pub fn DecimalContext::precision(Self) -> Int
pub fn DecimalContext::rounding(Self) -> @arithmetic.RoundingMode
pub fn DecimalContext::tininess(Self) -> DecimalTininessDetection
pub fn DecimalContext::try_new(precision? : Int, rounding? : @arithmetic.RoundingMode, decimal_rounding? : DecimalRoundingMode, e_min? : Int, e_max? : Int, clamp? : Bool, extended? : Bool, tininess? : DecimalTininessDetection) -> Result[Self, @arithmetic.ArithmeticError]
pub fn DecimalContext::with_rounding(Self, @arithmetic.RoundingMode) -> Self
pub fn DecimalContext::with_tininess(Self, DecimalTininessDetection) -> Self

pub struct DecimalFlags {
  inexact : Bool
  rounded : Bool
  lost_digits : Bool
  invalid_operation : Bool
  division_by_zero : Bool
  overflow : Bool
  underflow : Bool
  subnormal : Bool
  clamped : Bool
  conversion_syntax : Bool
  division_impossible : Bool
  division_undefined : Bool
  invalid_context : Bool
} derive(Eq)
pub fn DecimalFlags::combine(Self, Self) -> Self
pub fn DecimalFlags::contains(Self, DecimalSignal) -> Bool
pub fn DecimalFlags::has_error(Self) -> Bool
pub fn DecimalFlags::new() -> Self

pub(all) enum DecimalRoundingMode {
  HalfEven
  HalfUp
  HalfDown
  Down
  Ceiling
  Floor
  Up
  ZeroFiveUp
} derive(Eq)
pub fn DecimalRoundingMode::from_arithmetic(@arithmetic.RoundingMode) -> Self
pub fn DecimalRoundingMode::to_arithmetic(Self) -> @arithmetic.RoundingMode?

pub(all) enum DecimalSignal {
  ConversionSyntax
  DivisionByZero
  DivisionImpossible
  DivisionUndefined
  InvalidContext
  InvalidOperation
  Overflow
  Underflow
  Subnormal
  Inexact
  Rounded
  Clamped
  LostDigits
} derive(Eq)

pub(all) enum DecimalTininessDetection {
  BeforeRounding
  AfterRounding
} derive(Eq)

pub struct GdaContext {
  // private fields
}
pub fn GdaContext::basic() -> Self
pub fn GdaContext::clamp(Self) -> Bool
pub fn GdaContext::clear_status(Self) -> Self
pub fn GdaContext::decimal128() -> Self
pub fn GdaContext::decimal32() -> Self
pub fn GdaContext::decimal64() -> Self
pub fn GdaContext::default() -> Self
pub fn GdaContext::e_max(Self) -> Int
pub fn GdaContext::e_min(Self) -> Int
pub fn GdaContext::extended(Self) -> Bool
pub fn GdaContext::new(precision? : Int, rounding? : GdaRoundingMode, e_min? : Int, e_max? : Int, clamp? : Bool, extended? : Bool, traps? : GdaTrapSet) -> Self
pub fn GdaContext::precision(Self) -> Int
pub fn GdaContext::radix(Self) -> Int
pub fn GdaContext::reset(Self) -> Self
pub fn GdaContext::rounding(Self) -> GdaRoundingMode
pub fn GdaContext::status(Self) -> GdaFlags
pub fn GdaContext::trap(Self, GdaSignal, enabled? : Bool) -> Self
pub fn GdaContext::traps(Self) -> GdaTrapSet
pub fn GdaContext::try_new(precision? : Int, rounding? : GdaRoundingMode, e_min? : Int, e_max? : Int, clamp? : Bool, extended? : Bool, traps? : GdaTrapSet) -> Result[Self, @arithmetic.ArithmeticError]
pub fn GdaContext::with_traps(Self, GdaTrapSet) -> Self

pub struct GdaFlags {
  conversion_syntax : Bool
  division_by_zero : Bool
  division_impossible : Bool
  division_undefined : Bool
  invalid_context : Bool
  invalid_operation : Bool
  overflow : Bool
  underflow : Bool
  subnormal : Bool
  inexact : Bool
  rounded : Bool
  clamped : Bool
  lost_digits : Bool
} derive(Eq)
pub fn GdaFlags::combine(Self, Self) -> Self
pub fn GdaFlags::contains(Self, GdaSignal) -> Bool
pub fn GdaFlags::none() -> Self

pub struct GdaInterchange {
  // private fields
}
pub fn GdaInterchange::canonical(Self) -> Self
pub fn GdaInterchange::copy(Self) -> Self
pub fn GdaInterchange::copy_abs(Self) -> Self
pub fn GdaInterchange::copy_negate(Self) -> Self
pub fn GdaInterchange::copy_sign(Self, Self) -> Self
pub fn GdaInterchange::format(Self) -> GdaInterchangeFormat
pub fn GdaInterchange::from_decimal(Decimal, GdaInterchangeFormat) -> (Self, DecimalFlags)
pub fn GdaInterchange::from_hex(String, GdaInterchangeFormat) -> Self?
pub fn GdaInterchange::is_canonical(Self) -> Bool
pub fn GdaInterchange::to_decimal(Self) -> Decimal
pub fn GdaInterchange::to_decimal_ctx(Self) -> (Decimal, DecimalFlags)
pub fn GdaInterchange::to_hex(Self) -> String

pub(all) enum GdaInterchangeFormat {
  Decimal32
  Decimal64
  Decimal128
} derive(Eq)
pub fn GdaInterchangeFormat::context(Self) -> DecimalContext

pub(all) enum GdaOutcome[T] {
  Completed(T, GdaContext, GdaFlags)
  Trapped(GdaSignal, T, GdaContext, GdaFlags)
}
pub fn[T] GdaOutcome::next_context(Self[T]) -> GdaContext
pub fn[T] GdaOutcome::raised(Self[T]) -> GdaFlags
pub fn[T] GdaOutcome::value(Self[T]) -> T

pub(all) enum GdaRoundingMode {
  HalfEven
  HalfUp
  HalfDown
  Down
  Ceiling
  Floor
  Up
  ZeroFiveUp
} derive(Eq)

pub(all) enum GdaSignal {
  ConversionSyntax
  DivisionByZero
  DivisionImpossible
  DivisionUndefined
  InvalidContext
  InvalidOperation
  Overflow
  Underflow
  Subnormal
  Inexact
  Rounded
  Clamped
  LostDigits
} derive(Eq)

pub struct GdaTrapSet {
  conversion_syntax : Bool
  division_by_zero : Bool
  division_impossible : Bool
  division_undefined : Bool
  invalid_context : Bool
  invalid_operation : Bool
  overflow : Bool
  underflow : Bool
  subnormal : Bool
  inexact : Bool
  rounded : Bool
  clamped : Bool
  lost_digits : Bool
} derive(Eq)
pub fn GdaTrapSet::contains(Self, GdaSignal) -> Bool
pub fn GdaTrapSet::none() -> Self
pub fn GdaTrapSet::with_signal(Self, GdaSignal, enabled? : Bool) -> Self

// Type aliases

// Traits
```
<!-- generated-api-end -->
