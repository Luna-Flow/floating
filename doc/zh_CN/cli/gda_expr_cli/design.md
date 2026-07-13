# `cli/gda_expr_cli` 设计

## 职责

GDA `.decTest` 执行的文件系统与输出 adapter。

## 数据流

它展开输入、每个源文件只读取一次，把解析和执行交给 `frontend/gda_expr`，最后输出文本或带 schema 版本的 JSON。

## 算法与不变量

过滤和分片必须确定；strict 模式把 unsupported 行视为失败，diagnostic 仍单独分类。

## 失败与副作用

文件读取、参数处理、JSON 渲染和退出码是被隔离的副作用。

## 实现取舍

传输层分离使 parser 测试保持确定，但会留下一个仅供主 CLI 使用的小型 adapter API。

## 稳定性

本包作为仓库基础设施维护；生成声明可能随 runner 演进，不承诺下游兼容性。
