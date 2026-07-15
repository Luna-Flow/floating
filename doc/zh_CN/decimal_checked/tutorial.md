# `decimal_checked` 教程

`DecimalChecked` 保存当前 defined Decimal、IEEE context、最新 flags、累计 flags 与可选
certification error。

## 累积 IEEE Flags

```moonbit check
///|
test "IEEE checked decimal pipeline" {
  let context = @decimal.DecimalContext::new(precision=3)
  let checked = @decimal_checked.DecimalChecked::parse("1.2345", context)
    .add(@decimal.Decimal::one())
  inspect(checked.value().to_string(), content="2.23")
  inspect(
    checked.raised().contains(@decimal.DecimalSignal::Inexact),
    content="true",
  )
  inspect(
    checked.flags().contains(@decimal.DecimalSignal::Rounded),
    content="true",
  )
}
```

`raised()` 只描述最后一步，`flags()` 是合并历史，`outcome()` 返回 value 与累计 flags。

## 保留 Defined Exceptional Result

```moonbit check
///|
test "IEEE checked defined result" {
  let checked = @decimal_checked.DecimalChecked::from_int(
    1,
    @decimal.DecimalContext::decimal64(),
  ).div(@decimal.Decimal::zero())
  inspect(checked.value().is_infinite(), content="true")
  inspect(
    checked.raised().contains(@decimal.DecimalSignal::DivisionByZero),
    content="true",
  )
  inspect(checked.is_ok(), content="true")
}
```

`is_ok()` 表示没有 `ArithmeticError` 停止管线，不表示 flags 为空。Certification failure
进入 `error()` 并短路；IEEE rounded/inexact/overflow/division-by-zero 保留 value+flags。

## 重置 Status 窗口

`clear_flags()` 保留 value/context 并清除 latest/accumulated flags；应在应用消费上一阶段
状态后调用。`with_context` 会在新 IEEE context 下重新 apply 当前值并记录 flags，
不是纯 metadata setter。

## 不合并独立 Pipeline

Binary method 接收 plain `Decimal`，避免隐式合并两个 context 与 flags history。两个独立
checked 计算相遇时，由应用先决定 context 与 merge policy。

## 推荐做法

1. Step policy 看 `raised()`，end-to-end policy 看 `flags()`。
2. `is_ok()` 与 `flags().has_error()` 是不同问题。
3. 消费状态后再 clear。
4. 外部边界用 `result()` 返回 certification failure。
5. GDA trap 模型使用 `decimal_gda_checked`。

参见 [Design](./design.md) 与 [`decimal` 教程](../decimal/tutorial.md)。
