# `cli/itl_expr_cli` 设计

读取 ITL，按精确 operation 名过滤，调用 `frontend/itl_expr`，输出版本化 JSON；strict 将 unsupported 变为失败。它不负责 phase 规划、语料抓取或区间算法。
