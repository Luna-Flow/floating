# `consistency` 设计

## 职责

用于跨包定律与公开面审计的 white-box 包。

## 数据流

测试比较数值包之间的 alias、capability trait、checked wrapper、semantic projection 和迁移不变量。

## 算法与不变量

每个 witness 都小而确定；外部语料完整性属于 conformance runner。

## 失败与副作用

本包没有运行时 API 或 IO；失败通过测试断言指出合同不一致。

## 实现取舍

集中跨包定律便于发现漂移，而包内算法细节仍留在所属包的 white-box 测试。

## 稳定性

本包作为仓库基础设施维护；生成声明可能随 runner 演进，不承诺下游兼容性。
