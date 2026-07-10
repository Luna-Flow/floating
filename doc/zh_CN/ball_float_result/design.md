# `ball_float_result` 设计

## 职责

该包装区分构造/checked 运算失败与合法但较宽的包络。whole-real fallback 是有效区间信息，不是算术错误。

## 边界

只提升返回数值的操作；自然返回 `Bool` 的关系仍留在 `BallFloat`。所有组合与数值方法都会短路已有错误。
