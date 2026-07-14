# `decimal_checked` 设计

## 状态模型

`DecimalChecked` 是值、IEEE context、本步 flags 与累计 flags 的不可变乘积。
构造时强制调用 `DecimalContext::ieee754()`，避免 GDA profile 泄漏进本包。

## 状态转移

每个方法执行一次 contextual 运算：返回值成为下一个值，返回 flags 成为
`raised`，并通过 `combine` 累计到 `flags`。IEEE 异常结果仍是定义值。
`with_context` 显式在新 IEEE context 下重新应用当前值，并记录本次 flags。

## 组合边界

二元方法接收普通 `Decimal`。若接收另一个 `DecimalChecked`，就必须任意决定如何
合并 context 与 flag 历史；因此本类型也不实现运算符。wrapper 只在底层数值运算
之外增加常量级状态复制与 flag 组合。
