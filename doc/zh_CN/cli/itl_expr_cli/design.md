# `cli/itl_expr_cli` 设计

## 职责

ITL 区间 case 的文件系统与 JSON adapter。

## 数据流

它读取 ITL 文件、应用可选操作过滤，把 case 交给 `frontend/itl_expr`，并输出稳定汇总。

## 算法与不变量

unsupported case 始终显式；strict 模式只改变门禁成功条件，不改写 case disposition。

## 失败与副作用

文件访问和输出是副作用；区间解析与算术仍是纯包调用。

## 实现取舍

该 adapter 避免复制区间语义，同时有意把 phase 规划留给 Python 工具。

## 稳定性

本包作为仓库基础设施维护；生成声明可能随 runner 演进，不承诺下游兼容性。
