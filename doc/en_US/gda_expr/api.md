# `gda_expr` API

`gda_expr` parses General Decimal Arithmetic `.decTest` text and executes the
resulting cases against the repository Decimal backend.

## Parsing

`parse_dectest(source_name, text)` returns `GdaDocument` or an array of
`ParseDiagnostic`. Documents expose `source`, `cases`, and `case_count`.
`GdaCase` exposes ID, operation, normalized operation, operands, expected text,
conditions, context, expression, and source span. `GdaContext` exposes precision,
rounding, exponent bounds, clamp, extended mode, and dectest mode.

## Execution

`execute_documents(documents, options?)` returns `RunSummary`.
`RunOptions::new` configures shard count/index, strict-supported behavior, and a
case filter. Summaries expose total, selected, executable, passed, failed,
skipped, diagnostic, legacy, and unsupported counts plus individual results;
`merge` combines shard summaries and `success` reports gate status.

`CaseDisposition` distinguishes executable, diagnostic, legacy, and unsupported
cases. `CaseResult` exposes ID, pass state, disposition, and message.

Exact accessors are `GdaDocument::{source,cases,case_count}`;
`GdaCase::{id,operation,normalized_operation,operands,expected,conditions,context,expression,span}`;
`GdaContext::{default,precision,rounding,min_exponent,max_exponent,clamp,extended,dectest}`;
`RunOptions::{new,shard_count,shard_index,strict_supported,case_filter}`;
`RunSummary::{total_cases,selected_cases,executable_cases,passed_cases,failed_cases,skipped_cases,diagnostic_cases,legacy_cases,unsupported_cases,results,success,merge}`;
and `CaseResult::{id,passed,disposition,message}`.
