# `frontend/mpfr_expr` 设计

解析三种固定 MPFR 文本：十六进制 sqrt `data_check`、仓库生成的整数幂 witness，
以及 29 运算 elementary matrix；把系数转为 `BinCoeff`，执行对应 contextual
operation，并比较值与 inexact/invalid/division-by-zero 状态。

这是 oracle 适配器而非 MPFR binding，不做运行时 C FFI/IO。仅开发期生成器依赖
MPFR 4.2.2 及其强制 nearest-away wrapper；发布包不链接 MPFR/GMP。
