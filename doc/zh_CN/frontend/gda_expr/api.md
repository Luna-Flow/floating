# `frontend/gda_expr` API

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

## 完整公开接口

以下快照是 `0.6.1` 的完整生成包接口。公开声明是名称与签名的权威清单；前文按行为解释这些能力。

<!-- generated-api-start -->
```moonbit
// Generated using `moon info`, DON'T EDIT IT
package "Luna-Flow/floating/frontend/gda_expr"

import {
  "Luna-Flow/floating/numeric_expr",
  "moonbitlang/core/debug",
}

// Values
pub fn execute_documents(Array[GdaDocument], options? : RunOptions) -> RunSummary

pub fn parse_dectest(String, String) -> Result[GdaDocument, Array[ParseDiagnostic]]

// Errors

// Types and methods
pub(all) enum CaseDisposition {
  Executable
  Diagnostic(String)
  Legacy(String)
  Unsupported(String)
}

pub struct CaseResult {
  // private fields
}
pub fn CaseResult::disposition(Self) -> CaseDisposition
pub fn CaseResult::id(Self) -> String
pub fn CaseResult::message(Self) -> String
pub fn CaseResult::passed(Self) -> Bool

pub struct GdaCase {
  // private fields
}
pub fn GdaCase::conditions(Self) -> Array[String]
pub fn GdaCase::context(Self) -> GdaContext
pub fn GdaCase::expected(Self) -> String
pub fn GdaCase::expression(Self) -> @numeric_expr.Expr
pub fn GdaCase::id(Self) -> String
pub fn GdaCase::normalized_operation(Self) -> String
pub fn GdaCase::operands(Self) -> Array[String]
pub fn GdaCase::operation(Self) -> String
pub fn GdaCase::span(Self) -> @numeric_expr.SourceSpan

pub struct GdaContext {
  // private fields
} derive(Eq, @debug.Debug)
pub fn GdaContext::clamp(Self) -> Bool
pub fn GdaContext::dectest(Self) -> String
pub fn GdaContext::default() -> Self
pub fn GdaContext::extended(Self) -> Bool
pub fn GdaContext::max_exponent(Self) -> Int
pub fn GdaContext::min_exponent(Self) -> Int
pub fn GdaContext::precision(Self) -> Int
pub fn GdaContext::rounding(Self) -> String

pub struct GdaDocument {
  // private fields
}
pub fn GdaDocument::case_count(Self) -> Int
pub fn GdaDocument::cases(Self) -> Array[GdaCase]
pub fn GdaDocument::source(Self) -> String

pub struct ParseDiagnostic {
  // private fields
} derive(Eq, @debug.Debug)
pub fn ParseDiagnostic::message(Self) -> String
pub fn ParseDiagnostic::span(Self) -> @numeric_expr.SourceSpan

pub struct RunOptions {
  // private fields
} derive(Eq, @debug.Debug)
pub fn RunOptions::case_filter(Self) -> String
pub fn RunOptions::new(shard_count? : Int, shard_index? : Int, strict_supported? : Bool, case_filter? : String) -> Self
pub fn RunOptions::shard_count(Self) -> Int
pub fn RunOptions::shard_index(Self) -> Int
pub fn RunOptions::strict_supported(Self) -> Bool

pub struct RunSummary {
  // private fields
}
pub fn RunSummary::diagnostic_cases(Self) -> Int
pub fn RunSummary::executable_cases(Self) -> Int
pub fn RunSummary::failed_cases(Self) -> Int
pub fn RunSummary::legacy_cases(Self) -> Int
pub fn RunSummary::merge(Array[Self]) -> Self
pub fn RunSummary::passed_cases(Self) -> Int
pub fn RunSummary::results(Self) -> Array[CaseResult]
pub fn RunSummary::selected_cases(Self) -> Int
pub fn RunSummary::skipped_cases(Self) -> Int
pub fn RunSummary::success(Self) -> Bool
pub fn RunSummary::total_cases(Self) -> Int
pub fn RunSummary::unsupported_cases(Self) -> Int

// Type aliases

// Traits
```
<!-- generated-api-end -->
