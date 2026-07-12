# `cli/testfloat_expr_cli` 设计

校验一个向量文件及 function/rounding/tininess/shard 选项，委托 `frontend/testfloat_expr`，序列化摘要和退出码。不从文件名推断语义，也不生成 TestFloat case。
