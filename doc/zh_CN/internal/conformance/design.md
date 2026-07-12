# `internal/conformance` 设计

集中定义 source location、校验后的 shard、case disposition 和 summary fold。shard 按 case index 取模，merge 汇总互不重叠的计数；success 只表示没有 executable failure，不表示全部 case 都支持。

该包没有 parser、算术、文件系统或并行调度，是内部数据模型。
