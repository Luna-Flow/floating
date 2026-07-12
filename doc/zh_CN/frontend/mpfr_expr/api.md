# `frontend/mpfr_expr` API

`parse_sqrt_data`/`execute_sqrt_data` 处理 MPFR 十六进制 sqrt 行；`parse_pow_data`/`execute_pow_data` 处理固定整数幂 witness。document 暴露 source/case count，summary 暴露 total/passed/failed/results/success。

只支持仓库固定的两种语法；诊断保留 source、line 和 message。
