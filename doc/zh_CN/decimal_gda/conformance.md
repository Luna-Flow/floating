# `decimal_gda` 一致性说明

## 发布结果

固定 official 语料的 64,986/64,986 条合法 executable 标量行全部通过，failed、unsupported 和 legacy 均为零。其余 141 行是 `#` placeholder 或 non-scalar 非法输入，作为 diagnostic 报告，不进入合法分母。

## 旧版语料

固定 `official0` 语料的 16,124/16,124 条合法 executable 行全部通过。它用于历史兼容检查，不定义当前公开面。

## 状态语义

每个操作返回 `GdaOutcome`，其中包含 GDA 定义结果、本次操作 raised flags，以及累计 sticky status 的 next context。启用 trap 会改变 outcome variant，但不会删除定义结果。

## Runner 模型

文档只解析一次，directive state 按 case 固化，确定性 shard 执行互不重叠的 case position。executable、diagnostic、unsupported、legacy、passed 与 failed 计数始终分开。

## 边界

声明只覆盖固定语料中的合法标量行。placeholder/non-scalar 非法行、未来 directive、未固定 revision 和无限十进制字符串空间不在其内。

## 复现

```sh
just conformance smoke decimal_gda
just gate decimal_gda 8
just conformance run decimal_gda --corpus official0 --strict-supported
```

manifest、过滤、phase、JSON 输出和失败排查见[十进制数据指南](../../../testdata/decimal/README.md)。
