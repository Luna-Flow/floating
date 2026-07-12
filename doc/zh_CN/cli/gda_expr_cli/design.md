# `cli/gda_expr_cli` 设计

展开 `.decTest` 文件/目录，读取并一次解析文档，构造 filter/shard，输出文本或 JSON，并把失败/strict unsupported 映射为退出码。GDA 语义由 `frontend/gda_expr` 负责，下载由 Python 工具负责。
