# `internal/runner_cli` 设计

## 职责

原生 conformance 命令 adapter 共享的副作用边界。

## 数据流

它解析公共选项、收集并读取文件、格式化诊断，并为 backend CLI 构造 JSON 值。

## 算法与不变量

文件顺序和 JSON 编码必须确定；分片参数在 frontend 执行前验证。

## 失败与副作用

文件系统读取与渲染有意集中在这里，conformance model 和数值 frontend 保持纯。

## 实现取舍

共享副作用 helper 消除了 CLI 重复，但不引入通用命令框架。

## 稳定性

本包作为仓库基础设施维护；生成声明可能随 runner 演进，不承诺下游兼容性。
