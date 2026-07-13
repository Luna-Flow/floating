# `bin_float` 一致性说明

本文记录 `0.6.0` 二进制浮点语义与验证边界。有限测试全部通过是
声明范围内的证据，不是对所有实数输入的形式化证明。

## 标准、论文与参考实现

- IEEE 754-2019：interchange format、舍入方向、带符号零、NaN、异常标志与
  before/after rounding 的 tininess 语义。
- Fousse、Hanrot、Lefèvre、Pélissier、Zimmermann，
  [MPFR: A Multiple-Precision Binary Floating-Point Library with Correct Rounding](https://doi.org/10.1145/1236463.1236468)，
  ACM TOMS 33(2), 2007：任意精度的“精确结果、仅一次舍入”模型。
- Berkeley SoftFloat/TestFloat 3e：独立产生 IEEE 结果位与异常标志的参考
  实现和测试向量。

## 数学语义与算法

有限非零值表示 dyadic 实数

`(-1)^negative * coefficient * 2^exponent2`，其中 `coefficient` 是非负的 `BinCoeff`。

非零 coefficient 会移除 2 因子以规范化；`+0` 与 `-0` 不会合并。无穷、qNaN、
sNaN、NaN 符号及 payload 都是显式状态。

`add_ctx`、`sub_ctx`、`mul_ctx`、`div_ctx`、`sqrt_ctx` 与 `pow_int_ctx` 的
顺序固定为：先处理 IEEE 特殊值；在 dyadic/有理数或平方根界上计算精确数学
结果；按目标精度和方向仅舍入一次；最后做指数范围/subnormal 量化，并从该过程
导出五个 IEEE 标志。实现不会根据测试 ID、测试数值或向量格式选择分支。

例如 binary16 `0x0400 * 0x3BFF` 的结果位为 `0x0400`，标志仍为
`inexact | underflow`。after-rounding tininess 依据目标精度、无界指数的舍入
结果，而不能由最终 normal 编码倒推。

## 固定语料与结果

完整门禁定义见
[`testdata/bin_float/README.md`](../../../testdata/bin_float/README.md)。

| 来源 | 范围 | 结果 |
| --- | --- | --- |
| TestFloat 3e level 1、seed 1 | 4 格式 × 5 运算 × 5 舍入 × 2 tininess | 7,461,360 / 7,461,360 |
| MPFR 4.2.2 `tests/data/sqrt` | 全部可执行十六进制 sqrt 行 | 1,055 / 1,055 |
| MPFR 4.2.2 `pow_si` 固定语料 | 4 种精度 × 5 种受支持舍入 × 6 组输入 | 120 / 120 |
| 提交的 smoke | TestFloat、sqrt 与 `pow_si` 见证 | 183 / 183 |
| TestFloat 3e level 2 | binary16 的全部已声明运算/方向/tininess | 50,205,600 / 50,205,600 |

binary16 level-2 结果是额外的流式压力证据，不将更大的 binary32/64/128 level-2
语料误写为已完成声明。对非 NaN，解释器严格比较编码位和异常位。期望结果为 NaN 时，只比较 quiet-NaN
类别和异常位：IEEE 754 允许新生成 NaN 的 payload 选择；实现本身仍保留选中的
输入 NaN 的符号/payload，并 quiet sNaN。`--level 2` 使用有界分块而不丢行，
但属于巨大的可选压力语料，未计入上述已通过的有限门禁声明。

## 声明边界

## 证据稳定性

固定矩阵是本版本的证据边界；新增操作必须单独定义语料合同和 oracle，不能从现有通过结果外推。

## 证据记录

每次门禁同时记录格式、舍入、tininess、编码结果和异常位；summary 文件是可复核的机器证据。

上述结果只覆盖四个 interchange format 上的 contextual 加、减、乘、除和平方根。
不宣称 FMA、remainder、转换、比较、min/max、total order、十进制格式或全部
IEEE 754 操作的一致性。`pow_int_ctx` 的 MPFR 固定语料独立覆盖数值和 inexact；
nearest-away、before/after tininess 与完整 flags 由精确 dyadic/rational oracle
差分覆盖，因为 MPFR 明确禁止把 `MPFR_RNDNA` 当作通用 `pow_si` 舍入参数。

日常运行 `just conformance smoke binary`；完整固定门禁运行 `just bin-ci`。
