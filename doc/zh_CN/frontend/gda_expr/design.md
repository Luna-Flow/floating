# `frontend/gda_expr` 设计

解析 `.decTest` 为带 context、source span 和 `numeric_expr` 的 case；执行前规范化 operation，并映射到 `Decimal` context API，同时比较结果 cohort 与 flags。case 明确分为 Executable、Diagnostic、Legacy、Unsupported；shard 按稳定位置选择。

本包不下载语料、不读文件、不起进程、不实现十进制算法；文件和退出码由 `cli/gda_expr_cli` 负责，语料编排由 Python 工具负责。官方语料中 diagnostic 只表示 `#` 占位/非标量非法输入，合法行没有 unsupported 或 legacy 且全部通过。

## 数据流与纯边界

解析、分类、执行和 summary fold 是确定性的纯转换；下载语料、文件 IO、进程退出码由外层工具负责。这样同一个 case 可以在 white-box、CLI 和分片 runner 中复用。

## 失败分类

`Executable` 的结果不匹配才是语义失败；官方 corpus 的其他诊断仅来自 `#` 非法占位输入，任何 legacy 或 unsupported 都表示实现回归。
