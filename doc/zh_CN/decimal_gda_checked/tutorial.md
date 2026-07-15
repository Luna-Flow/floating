# `decimal_gda_checked` 教程

`GdaDecimalChecked` 保存一个 GDA outcome，并在线性计算中 thread sticky context。
Trap 后后续操作停止，直到显式恢复。

## Thread Sticky Status

```moonbit check
///|
test "GDA checked sticky pipeline" {
  let checked = @decimal_gda_checked.GdaDecimalChecked::parse(
    "1.2345",
    @decimal_gda.GdaContext::new(precision=3),
  ).add(@decimal_gda.Decimal::one())
  inspect(
    checked.status().contains(@decimal_gda.GdaSignal::Rounded),
    content="true",
  )
}
```

`raised()` 是最新操作，`status()` 是 next context 中的累计 conditions，`outcome()`
暴露完整 `Completed/Trapped`。

## 在 Trap 处停止

```moonbit check
///|
test "GDA checked trap short-circuit" {
  let context = @decimal_gda.GdaContext::decimal64().trap(
    @decimal_gda.GdaSignal::DivisionByZero,
  )
  let trapped = @decimal_gda_checked.GdaDecimalChecked::from_decimal(
    @decimal_gda.Decimal::one(),
    context,
  ).divide(@decimal_gda.Decimal::zero())
  inspect(trapped.is_trapped(), content="true")
  inspect(trapped.value().is_infinite(), content="true")
  inspect(trapped.trapped_signal() is Some(_), content="true")
  inspect(trapped.add(@decimal_gda.Decimal::one()).is_trapped(), content="true")
}
```

Defined infinity 保留；trapped 状态上的后续操作是 identity transition。

## 只按策略恢复

```moonbit check
///|
test "GDA checked explicit recovery" {
  let context = @decimal_gda.GdaContext::decimal64().trap(
    @decimal_gda.GdaSignal::DivisionByZero,
  )
  let trapped = @decimal_gda_checked.GdaDecimalChecked::from_decimal(
    @decimal_gda.Decimal::one(),
    context,
  ).divide(@decimal_gda.Decimal::zero())
  let resumed = trapped.resume_defined()
  inspect(resumed.is_trapped(), content="false")
  inspect(resumed.value().is_infinite(), content="true")
}
```

`resume_defined()` 保留 value/sticky context 并清除当前 raised observation；只有应用记录并
处理 trap、明确允许继续时才能调用。

## 保持 Binary Operand 为 Plain Value

`add/multiply/quantize` 接收 plain GDA Decimal，避免合并独立 sticky context。两条管线
相遇时由外部选择 controlling context/status policy。

## 推荐做法

1. 业务边界检查 `is_trapped/trapped_signal`。
2. 恢复前记录 raised、status 与 defined value。
3. 不要只为继续运行而 resume。
4. 多分支 trap handling 用 raw outcome，线性组合用 wrapper。

参见 [Design](./design.md) 与 [`decimal_gda` 教程](../decimal_gda/tutorial.md)。
