# `frontend/gda_expr` API

`gda_expr` は GDA `.decTest` テキストを解析し、リポジトリの Decimal backend で case を実行します。

## 解析

`parse_dectest(source_name, text)` は `GdaDocument` または `ParseDiagnostic` 配列を返します。文書は source と cases、case は ID・操作・引数・期待値・conditions・context・式・span、context は precision・rounding・指数境界・clamp・extended・dectest mode を公開します。

## 実行

`execute_documents(documents, options?)` は `RunSummary` を返します。`RunOptions` は shard、strict-supported、case filter を設定します。summary は total、selected、executable、passed、failed、skipped、diagnostic、legacy、unsupported を別々に数え、`merge` で統合できます。`CaseDisposition` と `CaseResult` は個別 case の分類、成否、メッセージを保持します。

正確な accessor 一覧は `GdaDocument::{source,cases,case_count}`、
`GdaCase::{id,operation,normalized_operation,operands,expected,conditions,context,expression,span}`、
`GdaContext::{default,precision,rounding,min_exponent,max_exponent,clamp,extended,dectest}`、
`RunOptions::{new,shard_count,shard_index,strict_supported,case_filter}`、
`RunSummary::{total_cases,selected_cases,executable_cases,passed_cases,failed_cases,skipped_cases,diagnostic_cases,legacy_cases,unsupported_cases,results,success,merge}`、
`CaseResult::{id,passed,disposition,message}` です。

## 完全な公開インターフェース

次の snapshot は `0.6.1` の完全な生成 package interface です。公開宣言が名前と signature の基準で、前の説明は挙動別に整理しています。

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
