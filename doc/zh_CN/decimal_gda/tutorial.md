# `decimal_gda` 教程

需要 General Decimal Arithmetic rounding、sticky status、defined trap result 与
trap precedence 时使用本包；IEEE `(value, flags)` 模型使用 `decimal`。

## 唯一必须记住的规则

每次操作都返回 `GdaOutcome`。需要累积 status 时，把 `next_context()` 传给下一步。
`raised()` 只描述当前操作，`next_context().status()` 描述整条已 thread 管线。

## Parse 与计算

```moonbit nocheck
let initial = @decimal_gda.GdaContext::decimal64()
let parsed = @decimal_gda.parse("12.3400", initial)
let divisor = @decimal_gda.Decimal::from_string("2").unwrap()
let divided = @decimal_gda.divide(
  parsed.value(),
  divisor,
  parsed.next_context(),
)
inspect(divided.value().to_string(), content="6.1700")
```

Parse 保留 cohort；把 parse 后的 context 传给 divide，parse condition 才会留在 sticky status。

## 读取 Raised 与 Sticky Status

```moonbit nocheck
let context = @decimal_gda.GdaContext::new(precision=3)
let outcome = @decimal_gda.parse("1.2345", context)
inspect(
  outcome.raised().contains(@decimal_gda.GdaSignal::Rounded),
  content="true",
)
inspect(
  outcome.next_context().status().contains(@decimal_gda.GdaSignal::Rounded),
  content="true",
)
```

`clear_status()` 开始新的观察窗口并保留 traps；`reset()` 同时重置 status 与 traps。

## 配置并处理 Trap

```moonbit nocheck
let context = @decimal_gda.GdaContext::decimal64().trap(
  @decimal_gda.GdaSignal::DivisionByZero,
)
let outcome = @decimal_gda.divide(
  @decimal_gda.Decimal::one(),
  @decimal_gda.Decimal::zero(),
  context,
)
match outcome {
  @decimal_gda.Trapped(signal, value, next_context, raised) => {
    inspect(signal, content="DivisionByZero")
    inspect(value.is_infinite(), content="true")
    inspect(next_context.status().contains(signal), content="true")
    inspect(raised.contains(signal), content="true")
  }
  @decimal_gda.Completed(_, _, _) => abort("expected a trap")
}
```

Defined infinity 仍然存在；trap 改变控制流，不把结果替换成通用 error。

## 验证动态 Context

配置或用户输入应使用 `try_new`：

```moonbit nocheck
let context = @decimal_gda.GdaContext::try_new(
  precision=34,
  e_min=-6143,
  e_max=6144,
  clamp=true,
).unwrap()
```

这样非法 precision 或反向 exponent bounds 进入正常 error channel。

## Quantize 并保留 Cohort

```moonbit nocheck
let context = @decimal_gda.GdaContext::decimal64()
let value = @decimal_gda.Decimal::from_string("12.3456").unwrap()
let cents = @decimal_gda.Decimal::from_string("0.00").unwrap()
let outcome = @decimal_gda.quantize(value, cents, context)
inspect(outcome.value().quantum(), content="-2")
```

观察 Rounded/Inexact 或 invalid request 后继续 thread `next_context()`；只有需要 canonical
cohort 时才 `reduce`。

## 使用数学函数

```moonbit nocheck
let context = @decimal_gda.GdaContext::decimal64()
let nine = @decimal_gda.Decimal::from_int(9)
let root = @decimal_gda.sqrt(nine, context)
inspect(root.value().to_string(), content="3")
```

GDA 面只包含 sqrt、power、exp、ln、log10；trigonometric/hyperbolic/inverse/atan2/
hypot/pi-scaled 属于其他数值域。

## 选择正确的 Comparison

`compare` 是 quiet numeric comparison，`compare_signal` 为 signaling，`compare_total`
对 NaN/cohort 等完整表示排序，`compare_total_magnitude` 按 magnitude total order，
`same_quantum` 检查 exponent。Total comparison 用于协议排序，不替代 numerical equality。

## 长链使用 Checked Pipeline

```moonbit check
///|
test "GDA checked pipeline" {
  let checked = @decimal_gda_checked.GdaDecimalChecked::parse(
    "9",
    @decimal_gda.GdaContext::decimal64(),
  ).sqrt()
  inspect(checked.value().to_string(), content="3")
  inspect(checked.is_trapped(), content="false")
}
```

只有应用明确接受 trapped operation 的 defined result 时才调用 `resume_defined()`。

## 常见错误

- 需要 sticky 累积却重复使用原 context；
- 把 `Trapped` 当作没有 value；
- 手工 combine flags 后误以为 context status 已改变；
- 混用两个 Decimal 类型；
- 用 IEEE `decimal_checked` 处理 GDA。

## 推荐做法

1. 在计算边界验证一个 context。
2. 手工流程始终 thread `next_context()`。
3. 控制边界同时检查 raised/status。
4. 恢复前记录 trap 与 defined result。
5. 线性组合用 checked wrapper，复杂分支用原始 outcome。

## 继续阅读

[Design](./design.md)、[API](./api.md)、[Conformance](./conformance.md) 与
[`decimal_gda_checked`](../decimal_gda_checked/tutorial.md)。
