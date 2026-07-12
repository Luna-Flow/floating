# `decimal` 教程

## 从字符串构造

```moonbit
let amount = @decimal.Decimal::from_string("12.3400", precision=32).unwrap()
inspect(amount.to_string(), content="12.34")
```

输出会使用规范化后的十进制形式。

如果你需要保留输入里的量纲信息，请注意：

- `Decimal::make` / `from_int` / `from_bigint` 倾向于做数值规范化
- `from_string` 在可表达时会尽量保留原始 exponent/quantum
- `"-0"` 会保留成负零，而不是自动折叠成 `0`

## 十进制算术

```moonbit
let a = @decimal.Decimal::from_string("1.25", precision=20).unwrap()
let b = @decimal.Decimal::from_string("2.5", precision=20).unwrap()
inspect((a + b).to_string(), content="3.75")
```

## 转成二进制

```moonbit
let d = @decimal.Decimal::from_string("0.1", precision=20).unwrap()
let x = d.to_bin_float(precision=24)
let back = @decimal.Decimal::from_bin_float(x, precision=10)
inspect(back.to_string(), content="0.09999999404")
```

这说明当前实现下，`0.1` 这样的非 dyadic 十进制在二进制里只能近似表示。

## 使用 context 观察 flags

```moonbit
let ctx = @decimal.DecimalContext::decimal64()
let a = @decimal.Decimal::from_string("1", precision=16).unwrap()
let b = @decimal.Decimal::from_string("3", precision=16).unwrap()
let result, flags = a.div_ctx(b, ctx)
inspect(result.to_string())
inspect(flags)
```

当你需要和 GDA / `.decTest` 的结果逐项对齐时，优先使用 `*_ctx` 入口，而不是只看最终数值。

## 处理 special values

```moonbit
let nan = @decimal.Decimal::from_string("sNaN7", precision=16).unwrap()
let ctx = @decimal.DecimalContext::decimal64()
let result, flags = nan.plus_ctx(ctx)
inspect(result.to_string())
inspect(flags)
```

当前实现会区分 qNaN / sNaN，并尽量保留 sign 与 payload。

## 处理 interchange 编码

如果你要处理 decimal32 / decimal64 / decimal128 的 interchange bits：

- 用 `Decimal::to_interchange_hex(format)` / `Decimal::from_interchange_hex(...)` 做值与编码之间的转换
- 用 `DecimalInterchange` 保留 raw bits、做 `canonical()`、`copy_sign()` 等表示层操作

## Context 工作流

对于合法 GDA 行，使用同一个显式 context 完成解析与运算，并同时检查值和累计 flags。

## Cohort 与精确语义

解析可以保留尾零和 quantum；需要 canonical 表示时显式调用 `normalized()` 或 `reduce_ctx()`。
