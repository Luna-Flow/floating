# `decimal` 一致性说明

## 合同分离

`decimal` 是 IEEE 754 算术与 interchange 表面。General Decimal Arithmetic 的 sticky status 和 trap 属于 `decimal_gda`；通过 GDA 语料本身不能建立 IEEE 声明。

## 独立 IEEE 语料

提交到仓库的 IEEE 语料覆盖 decimal32/64/128 DPD/BID interchange、canonical 与 non-canonical 编码、特殊值、flags、total order 和核心算术。DPD fixture 穷举全部 1,024 个 declet。

## Oracle 分层

mandatory operation vector 使用精确整数/有理数构造和已记录的 DPD/BID bridge。初等函数在可用时使用独立高精度或区间 oracle。结果值或编码 bits 与 IEEE flags 分开记录，避免“数值看似正确”掩盖 flag 错误。

提交的 elementary 层包含 2,784 个证明行。MPFR 4.2.2 生成 768-bit 向下/向上
dyadic 端点；精确整数转换把两端在全部 `DecimalRoundingMode` 下舍入到
decimal32/64/128，只有结果与 flags 唯一时才保留该行。加入这些行后，native、
Wasm、Wasm-GC、JavaScript 各为 2,949/2,949，完整 gate 为 15,735/15,735。
RDFP 与 Arb 仍是可选 secondary route；不可用时不计入已执行证据。

## Targets

`just gate decimal` 运行 native、Wasm、Wasm-GC 与 JavaScript。LLVM 因仓库不包含所需本地产物而排除。target-specific 系数调度不得改变值、编码或 flags。

## 边界

固定矩阵是有限的，不声明覆盖 IEEE 754 全部操作、所有 payload 传播策略或所有可能十进制输入。补充的 `dd*`/`dq*` decTest 行只作诊断，不是 IEEE oracle。

## 复现

```sh
just conformance smoke decimal
just gate decimal
just decimal-kernel-ci
```

语料来源、vector family 和失败记录见[十进制数据指南](../../../testdata/decimal/README.md)。
