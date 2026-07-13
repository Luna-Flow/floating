# `internal/conformance` 设计

## 职责

conformance 位置、disposition、分片与汇总的纯共享模型。

## 数据流

frontend 构造不可变 case result；summary fold 统计分类，merge 合并互不重叠的 shard，success 只取决于 executable failure。

## 算法与不变量

分片按 case index 确定选择，unsupported 或 diagnostic 行不会伪装成通过的 executable 行。

## 失败与副作用

本包不执行解析、算术、IO 或调度副作用。

## 实现取舍

共享模型避免 runner 计数漂移，同时 frontend wrapper 保留领域专用公开名称。

## 稳定性

本包作为仓库基础设施维护；生成声明可能随 runner 演进，不承诺下游兼容性。
