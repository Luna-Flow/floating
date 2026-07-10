# `gda_expr` API

`gda_expr` 解析 GDA `.decTest` 文本，并用仓库 Decimal 后端执行 case。

## 解析

`parse_dectest(source_name, text)` 返回 `GdaDocument` 或 `ParseDiagnostic` 数组。`GdaDocument` 暴露来源与 case；`GdaCase` 暴露 ID、操作、参数、期望值、conditions、context、表达式和 span；`GdaContext` 暴露 precision、rounding、指数边界、clamp、extended 与 dectest 模式。

## 执行

`execute_documents(documents, options?)` 返回 `RunSummary`。`RunOptions` 配置 shard、strict-supported 与 case filter。汇总分别统计 total、selected、executable、passed、failed、skipped、diagnostic、legacy 和 unsupported，并可用 `merge` 合并。`CaseDisposition` 与 `CaseResult` 保留每个 case 的分类、通过状态和消息。

精确 accessor 清单为 `GdaDocument::{source,cases,case_count}`；
`GdaCase::{id,operation,normalized_operation,operands,expected,conditions,context,expression,span}`；
`GdaContext::{default,precision,rounding,min_exponent,max_exponent,clamp,extended,dectest}`；
`RunOptions::{new,shard_count,shard_index,strict_supported,case_filter}`；
`RunSummary::{total_cases,selected_cases,executable_cases,passed_cases,failed_cases,skipped_cases,diagnostic_cases,legacy_cases,unsupported_cases,results,success,merge}`；
以及 `CaseResult::{id,passed,disposition,message}`。
