# `bench/bin_float` 设计

## 职责

测量系数核、`BinFloat`、checked 包装、完整初等函数矩阵与平方 crossover 候选。

## 数据流

确定性精确系数在同一 Maremark case 中进入系数、核心与 checked 实现。

## 不变量

算术分层必须得到同一精确值；初等函数核心与 checked 路径必须先通过一致性校验；调优只比较 `mul(x, x)` 与 `square(x)`。

## 副作用

只有统一 runner 显式包含 skipped test 时才会流式输出 `mmka_1` JSONL 与热点/调优结果。

