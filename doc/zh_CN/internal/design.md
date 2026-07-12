# `internal` 设计

该包提供共享的纯辅助：2/5/10 次幂、十进制切分、因子移除、位数、正商/位移舍入、`ExactRat` 和 Result 提升。它不拥有上下文、flags、解析策略之外的语义、IO 或公开数值表示。

这是模块内部实现边界，不是稳定应用 API；应用应使用 `bin_float`、`decimal`、`ball_float` 或 `semantic`。

## 纯函数与复杂度

辅助函数不读写外部状态；幂缓存和舍入只在局部分配。位数、因子移除和字符串切分按输入长度线性工作，算术复杂度由调用方的 `BigInt` 运算主导。

## 兼容边界

这些名字服务当前实现与 white-box 测试，不参与稳定性承诺；公开调用应通过 concrete numeric packages。
