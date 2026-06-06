# `def` 设计说明

`@def` 是当前仓库的协议层。

## 为什么 trait 很小

当前 `Floating` 没有把四则运算、总序比较、解析和格式化塞进去，原因是：

- 四则运算已经由 MoonBit 的运算符 trait 表达
- `ball_float` 不适合总序比较
- 静态构造函数不适合直接放进这个 trait

因此它只保留三个实现包真正共享且稳定的能力边界。

## 作用

`@def` 统一了：

- `Sign`
- `FpClass`
- `RoundingMode`
- `precision`
- `normalized`

这样 `bin_float`、`decimal`、`ball_float` 即使内部表示不同，也能共享同一套语义命名。
