# `bin_float_bench` 设计

## 职责

用于测量代表性 `BinCoeff` 操作的专用 benchmark 包。

## 数据流

测试框架构造固定形状的操作数、运行 MoonBit bench cell 并报告测量结果，不参与生产调度。

## 算法与不变量

计时循环必须保留结果并排除初始化成本；测量是选型证据，不是正确性合同。

## 失败与副作用

被跳过的 benchmark 测试只在本地分配和计时，不执行应用 IO。

## 实现取舍

独立包避免 benchmark 依赖进入 `bin_float`，代价是阈值专用 white-box bench 仍需留在核心包内。

## 稳定性

本包作为仓库基础设施维护；生成声明可能随 runner 演进，不承诺下游兼容性。
