# `decimal` 设计

## 职责与表示

有限值保存独立符号、非负 `BigInt` 系数、十进制指数和工作精度；负零、无穷、qNaN/sNaN 与 payload 可观察。解析和量子敏感操作可以保留尾零/指数 cohort，`normalized()`/`reduce_ctx()` 只做数学值不变的 cohort 规范化。

## 系数与舍入算法

包内 `DecCoeff` 是小端 base-1000 数组，提供位移、加减、schoolbook 乘法、长除、精确幂和舍入辅助，但不暴露该存储类型。公开系数仍是 `BigInt`，与二进制栈的 `BinCoeff` 迁移有意不同；当前没有 Karatsuba/Toom/FFT 分派。

## Context 与效果边界

`*_ctx` 先处理特殊值和精确系数/指数，再按八种十进制 rounding 舍入，最后应用指数界限、subnormal、clamp 和 `DecimalFlags`。FMA 在最终加法后才舍入；quantize 固定目标指数，结果系数超 precision 时报告 `invalid_operation`。

## 能力边界

公共能力包含算术、FMA、整除/余数、quantize/rescale、total compare、逻辑数字、邻接值、分类、格式化、decimal32/64/128 互换和初等函数。固定 official/official0 语料中的所有合法 executable 标量行均已通过，unsupported 和 legacy 为零；唯一排除的是 `#` 占位/非标量非法输入。

## 数学模型与 cohort

有限值表示为 `(-1)^negative × coefficient × 10^exponent10`。`1.20` 与 `1.2`
数学值相同但 quantum 不同；`normalized()`/`reduce_ctx()` 只改变 cohort，不改变
数学值。因此普通 equality、`same_quantum` 和 total order 是不同的观察。

## Context 与 flags

`*_ctx` 依次处理特殊值、精确系数/指数、precision 与八种 rounding、指数界限、
clamp 和 `DecimalFlags`。`rounded` 不必然意味着 `inexact`，`subnormal` 不必然
意味着 `underflow`；组合多个运算时必须显式 `DecimalFlags::combine`。

## 复杂度与取舍

对 `n` 个 base-1000 limb，加减、比较、移位和规范化是 `O(n)`，schoolbook
乘法与长除法是 `O(n²)`。base-1000 让解析、进位和 GDA 舍入容易审计；当前精度
通常受 context 限制，因此暂不承担 Karatsuba/Toom/FFT 的实现与调参成本。未来
可以替换内核而不改变 `Decimal`/`DecimalContext` 契约。
