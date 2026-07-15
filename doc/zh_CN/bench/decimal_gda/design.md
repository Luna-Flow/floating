# `bench/decimal_gda` 设计

## 职责

测量 GDA 核心运算与 sticky-context checked 组合。

## 数据流

精确且不触发 trap 的输入覆盖加、乘、除、fma 与 parse。

## 不变量

核心值与 checked 值必须先相等，才能进入热点分析。

## 副作用

context 创建、输入解析、JSONL 输出与报告均位于计时 payload 外。

