# `internal/runner_cli` 设计

隔离 runner 的副作用和传输辅助：公共选项、确定性文件收集、源码读取、诊断格式化和 JSON 构造。它不含语料 parser 或数值操作，使 frontend 保持纯且易测。
