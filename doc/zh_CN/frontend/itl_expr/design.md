# `frontend/itl_expr` 设计

解析 ITF1788 行格式，按操作把 case 分派到 `BallFloat`/`BallFloatDecorated`，对区间、布尔、overlap、数值和 decoration 使用专门比较器，并通过共享 conformance model 汇总。

不支持的操作、arity 或期望值保持显式 disposition。本包不宣称完整 IEEE 1788，不读文件，也不选择 strict phase。
