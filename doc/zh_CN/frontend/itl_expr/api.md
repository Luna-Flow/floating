# `frontend/itl_expr` API

`parse_itl(text)` 返回 `ItlCase` 数组或诊断；`execute_case(case, precision?)` 返回 `ItlResult`；`summarize_results` 汇总计数并保留逐行结果。通过 `ItlDisposition` 区分 executable、unsupported 与 diagnostic。

只接受当前 parser/executor 实现的 operation 和期望值形式；strict 子集见 `testdata/interval/README.md`。
