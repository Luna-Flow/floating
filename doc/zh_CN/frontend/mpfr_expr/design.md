# `frontend/mpfr_expr` 设计

解析两种固定 MPFR 文本：十六进制 sqrt `data_check` 和仓库生成的整数幂 witness；把系数转为 `BinCoeff`，执行 `sqrt_ctx`/`pow_int_ctx`，比较值和 inexact。

这是 oracle 适配器而非 MPFR binding，只支持这两种语法和操作，不做 FFI/IO，不覆盖其他 MPFR 函数或语料未包含的 rounding。
