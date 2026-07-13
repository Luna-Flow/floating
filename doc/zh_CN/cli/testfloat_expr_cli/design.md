# `cli/testfloat_expr_cli` 设计

## 职责

Berkeley TestFloat vector 文件的命令 adapter。

## 数据流

它验证 function、rounding、tininess 和 shard 选项，再把解析与执行交给 `frontend/testfloat_expr`。

## 算法与不变量

元数据始终显式，不从文件名猜测；JSON 字段和退出码保持稳定以供工具消费。

## 失败与副作用

文件访问、选项解析、渲染和退出码都隔离在该边界。

## 实现取舍

显式元数据稍显冗长，但能防止错误格式或舍入策略静默选择另一套 oracle 合同。

## 稳定性

本包作为仓库基础设施维护；生成声明可能随 runner 演进，不承诺下游兼容性。
