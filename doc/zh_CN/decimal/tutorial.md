# `decimal` 教程

适用于 decimal quantum、IEEE context/flags 或 decimal32/64/128 DPD/BID interchange
属于契约的场景。需要 sticky GDA status/trap 时使用
[`decimal_gda`](../decimal_gda/tutorial.md)。

## 选择入口

| 需求 | 推荐 API |
| --- | --- |
| 保留 quantum 的 parse | `parse/from_string` |
| bounded context 与 flags | `from_string_ctx`、`*_ctx` |
| canonical cohort | `normalized/reduce_ctx` |
| 固定格式 bits | `DecimalInterchange` |
| 可观察 elementary proof failure | `try_*_ctx` |
| 累积 IEEE 状态 | `decimal_checked` |

## Parse 时不丢 Quantum

```moonbit check
///|
test "decimal parsing preserves quantum" {
  let amount = @decimal.Decimal::from_string("12.3400", precision=10).unwrap()
  inspect(amount.to_string(), content="12.3400")
  inspect(amount.quantum(), content="-4")
  let reduced = amount.normalized()
  inspect(reduced.to_string(), content="12.34")
  inspect(reduced.quantum(), content="-2")
}
```

`normalized()` 改变 cohort 但不改数学值。Scale 对金额、测量或协议有意义时不要自动调用。
需要错误详情用 `parse`，`None` 足够时用 `from_string`。

## 计算精确 Decimal 值

```moonbit check
///|
test "exact decimal arithmetic" {
  let a = @decimal.Decimal::from_string("1.25", precision=20).unwrap()
  let b = @decimal.Decimal::from_string("2.5", precision=20).unwrap()
  inspect((a + b).to_string(), content="3.75")
  inspect((a * b).to_string(), content="3.125")
}
```

外部规定 precision/rounding/exponent 时不要只依赖 operand precision，应使用 context。

## 使用 Context 并保留 Flags

```moonbit check
///|
test "decimal64 parse and divide" {
  let context = @decimal.DecimalContext::decimal64()
  let (value, parse_flags) = @decimal.Decimal::from_string_ctx(
    "1.234567890123456789",
    context,
  )
  let three = @decimal.Decimal::from_int(3, precision=context.precision())
  let (quotient, divide_flags) = value.div_ctx(three, context)
  let flags = parse_flags.combine(divide_flags)
  inspect(quotient.is_finite(), content="true")
  inspect(flags.contains(@decimal.DecimalSignal::Rounded), content="true")
}
```

`has_error()` 是便捷策略，但 inexact、rounded、subnormal、overflow、clamped 影响业务时
应检查具体 signal。

## 有意 Quantize

目标 exponent 属于契约时使用 `quantize`：

```moonbit nocheck
let context = @decimal.DecimalContext::decimal64()
let value = @decimal.Decimal::from_string("12.3456").unwrap()
let cents = @decimal.Decimal::from_string("0.00").unwrap()
let (rounded, flags) = value.quantize(cents, context)
// rounded has quantum -2; inspect Rounded/Inexact before accepting it.
```

装不下 context 时返回 invalid-operation，不会偷偷选另一个 scale。

## 编码 Decimal Interchange

```moonbit check
///|
test "decimal64 DPD round trip" {
  let value = @decimal.Decimal::from_string("1.25").unwrap()
  let (encoded, encode_flags) =
    @decimal.DecimalInterchange::from_decimal_with_encoding(
      value,
      @decimal.DecimalInterchangeFormat::Decimal64,
      @decimal.DecimalInterchangeEncoding::DPD,
    )
  let (decoded, decode_flags) = encoded.to_decimal_ctx()
  inspect(decoded.to_string(), content="1.25")
  inspect(encode_flags.combine(decode_flags).has_error(), content="false")
}
```

外部协议要求时才选 BID。GDA concrete interchange 为独立 DPD surface。

## 调用认证初等函数

```moonbit check
///|
test "certified decimal logarithm" {
  let context = @decimal.DecimalContext::decimal64()
  let ten = @decimal.Decimal::from_int(10, precision=context.precision())
  match ten.try_log10_ctx(context) {
    Ok((value, flags)) => {
      inspect(value.to_string(), content="1")
      inspect(flags.has_error(), content="false")
    }
    Err(_) => abort("decimal log10 could not be certified"),
  }
}
```

两端 directed dyadic bound 必须舍入成相同 Decimal 与 flags 才会被接受。

## 谨慎转换 Decimal 与 Binary

```moonbit check
///|
test "binary decimal boundary" {
  let exact_binary = @bin_float.BinFloat::make(
    @bin_float.BinCoeff::from_uint64(3UL),
    -2,
    32,
  )
  let exact_decimal = @decimal.Decimal::from_bin_float(exact_binary, precision=20)
  inspect(exact_decimal.to_string(), content="0.75")

  let tenth = @decimal.Decimal::from_string("0.1", precision=20).unwrap()
  let approximate_binary = tenth.to_bin_float(precision=24)
  let back = @decimal.Decimal::from_bin_float(approximate_binary, precision=10)
  inspect(back.to_string(), content="0.09999999404")
}
```

构造原 decimal 实数的 interval 时必须 TowardNegative/TowardPositive 转两次；
nearest point + `BallFloat::exact` 只包住该 binary point。

## 特殊值与排序

Signed zero、infinity、qNaN/sNaN、payload 均显式；`compare_total` 用于表示级确定排序，
不能代替数值相等；`same_quantum` 检查 cohort exponent 而非 equality。

## 推荐做法

1. 保留 parse quantum，直到显式 normalize/quantize。
2. 使用一个 context 并组合所有 flags。
3. Interchange 只作为 IO boundary。
4. 不可信 elementary input 使用 `try_*_ctx`。
5. IEEE pipeline 用 `decimal_checked`，GDA 用对应 GDA 包。

## 继续阅读

[Design](./design.md)、[Conformance](./conformance.md)、[Performance](./performance.md)
分别解释实现、证据与阈值；[`decimal_checked`](../decimal_checked/tutorial.md) 展示 flag 累积。
