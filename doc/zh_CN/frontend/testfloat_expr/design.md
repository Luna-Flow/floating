# `frontend/testfloat_expr` 设计

解析 TestFloat 元数据和定宽十六进制向量，通过 `BinaryInterchange` 解码、构造 `BinaryContext`，执行 add/sub/mul/div/sqrt，并比较编码结果和五个 IEEE flags；shard 按行号稳定选择。

支持格式、操作、rounding、tininess 以 `TestFloatSpec` parser 为准，不生成向量、不调用 SoftFloat、不读文件，也不扩展该矩阵。
