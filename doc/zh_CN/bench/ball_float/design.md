# `bench/ball_float` 设计

## 职责

隔离二进制核、区间核心与 checked 包装的成本。

## 数据流

精确单点区间使加、乘、除能够与对应 `BinFloat` 参考值比较。

## 不变量

核心与 checked 输出必须保持以参考值为中心的单点区间。

## 副作用

Maremark 负责校准与计时，Python runner 负责进程和 artifact IO。

