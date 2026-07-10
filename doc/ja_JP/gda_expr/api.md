# `gda_expr` API

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
