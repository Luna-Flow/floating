# `frontend/testfloat_expr` 设计

解析 TestFloat 元数据和定宽十六进制向量，通过 `BinaryInterchange` 解码、构造 `BinaryContext`，执行算术、mulAdd、rem、roundToInt、整数转换或比较函数，并比较编码结果、整数或 0/1 结果以及五个 IEEE flags；非法整数转换只比较 flags，因为 SoftFloat 的哨兵值与平台相关；shard 按行号稳定选择。

支持格式、操作、rounding、tininess 以 `TestFloatSpec` parser 为准，不生成向量、不调用 SoftFloat、不读文件，也不扩展该矩阵。
