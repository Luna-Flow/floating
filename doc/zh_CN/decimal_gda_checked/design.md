# `decimal_gda_checked` 设计

## 状态模型

`GdaDecimalChecked` 只包含一个 `GdaOutcome[Decimal]`。outcome 拥有当前定义值、
next sticky context、本步 raised flags 与可选 trapped signal。

## 状态转移

对 `Completed` 执行运算时，使用其中的值与 next context，再保存新 outcome。
对 `Trapped` 执行运算是恒等转移。这使 trap 短路显式化，避免越过配置的控制边界
继续计算。

## 恢复边界

`resume_defined` 是唯一的控制逃生口：保留定义值与 sticky context，清除当前步骤的
`raised` 观察，并恢复 completed 流水线。二元方法接收普通 GDA 值，绝不合并两个
独立 sticky context。Trap 也绝不会转换成 `ArithmeticError`。
