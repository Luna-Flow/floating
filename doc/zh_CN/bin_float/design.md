# `bin_float` 设计说明

`BinFloat` 是当前仓库里的二进制优先表示。

## 核心不变式

- 有限非零值保存为 `significand * 2^exponent2`
- `significand` 会被剥离所有可移除的 2 因子
- 零值使用唯一规范表示

## 精度控制

当 significand 的有效二进制位数超过目标精度时，实现会：

1. 计算多出来的位数
2. 通过右移舍入
3. 再次规范化

## 比较

有限值比较先对齐指数，再比较展开后的 significand。`NaN` 不参与有序比较。
