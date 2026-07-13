# `decimal_gda` 教程

当计算必须遵循 General Decimal Arithmetic rounding、sticky status 与 trap 行为时，
使用本包；如果需要 IEEE `(value, flags)` 模型，应使用 `decimal`。

## 解析并计算

创建 context，通过它解析，并传递返回的 context：

```moonbit nocheck
let initial = @decimal_gda.GdaContext::decimal64()
let parsed = @decimal_gda.parse("12.3400", initial)
let divisor = @decimal_gda.Decimal::from_string("2").unwrap()
let result = @decimal_gda.divide(
  parsed.value(),
  divisor,
  parsed.next_context(),
)
inspect(result.value().to_string(), content="6.1700")
```

`result.raised()` 只含除法产生的条件；`result.next_context().status()` 同时包含
解析与除法的条件。

## 观察 Raised 与 Sticky Status

显式查询一个 condition：

```moonbit nocheck
let context = @decimal_gda.GdaContext::new(precision=3)
let outcome = @decimal_gda.parse("1.2345", context)
let rounded = outcome.raised().contains(@decimal_gda.GdaSignal::Rounded)
let sticky = outcome.next_context().status().contains(
  @decimal_gda.GdaSignal::Rounded,
)
inspect((rounded, sticky), content="(true, true)")
```

`clear_status()` 在保留 traps 的同时开始新的状态窗口；只有 status 与 traps 都需要
回到默认时才调用 `reset()`。

## 配置 Trap

Trap set 不可变。在 context 上启用一个 signal：

```moonbit nocheck
let trapped_context = @decimal_gda.GdaContext::decimal64().trap(
  @decimal_gda.GdaSignal::DivisionByZero,
)
let one = @decimal_gda.Decimal::one()
let zero = @decimal_gda.Decimal::zero()
let outcome = @decimal_gda.divide(one, zero, trapped_context)
match outcome {
  @decimal_gda.Trapped(signal, value, next_context, raised) => {
    inspect(signal, content="DivisionByZero")
    inspect(value.is_infinite(), content="true")
    inspect(next_context.status().contains(signal), content="true")
    inspect(raised.contains(signal), content="true")
  }
  @decimal_gda.Completed(_, _, _) => abort("expected trap")
}
```

定义结果 infinity 仍然可用。Trap 改变控制信息，不抹去数值结果。

## 使用 Checked Context 构造

Context 参数来自配置或用户输入时使用 `try_new`：

```moonbit nocheck
let context = @decimal_gda.GdaContext::try_new(
  precision=34,
  e_min=-6143,
  e_max=6144,
  clamp=true,
).unwrap()
```

这样可以避免非正 precision 或反向指数边界触发 abort。

## 选择正确比较

- `compare` 执行 quiet numeric comparison，返回 decimal comparison value；
- `compare_signal` 使用 signaling comparison；
- `compare_total` 排列完整表示，包括 NaN 与 cohort；
- `compare_total_magnitude` 对 magnitude 应用 total order。

确定性排序或 protocol canonicalization 使用 total comparison；不要用它替代普通
数值相等。

## 避免常见错误

- 需要累计 sticky status 时不要重复使用原 context；
- 不要把 `Trapped` 理解成“没有值”，应检查 defined result；
- 不要手工组合 `GdaFlags` 后假设 context status 已改变，应传递 `next_context()`；
- 不要把 `decimal` 与 `decimal_gda` 的值混用；
- 合同要求 GDA signals/traps 时不要使用 checked wrapper；后者保留的是
  `ArithmeticError`，不是 GDA 状态。

