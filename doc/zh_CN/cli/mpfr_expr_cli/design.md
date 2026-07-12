# `cli/mpfr_expr_cli` 设计

根据固定语法识别 sqrt 或整数幂语料，委托 `frontend/mpfr_expr` 并输出文本/JSON。一次只接收一个文件且不 shard；识别属于传输层，不是数值猜测。
