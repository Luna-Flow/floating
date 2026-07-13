# `frontend/itl_expr` API

`parse_itl(text)` 返回 `ItlCase` 数组或诊断；`execute_case(case, precision?)` 返回 `ItlResult`；`summarize_results` 汇总计数并保留逐行结果。通过 `ItlDisposition` 区分 executable、unsupported 与 diagnostic。

只接受当前 parser/executor 实现的 operation 和期望值形式；strict 子集见 `testdata/interval/README.md`。

## 完整公开接口

以下快照是 `0.6.0` 的完整生成包接口。公开声明是名称与签名的权威清单；前文按行为解释这些能力。

<!-- generated-api-start -->
```moonbit
// Generated using `moon info`, DON'T EDIT IT
package "Luna-Flow/floating/frontend/itl_expr"

import {
  "moonbitlang/core/debug",
}

// Values
pub fn execute_case(ItlCase, precision? : Int) -> ItlResult

pub fn parse_itl(String) -> Result[Array[ItlCase], Array[String]]

pub fn summarize_results(Array[ItlResult]) -> RunSummary

// Errors

// Types and methods
pub struct ItlCase {
  // private fields
} derive(Eq, @debug.Debug)
pub fn ItlCase::expected(Self) -> String
pub fn ItlCase::id(Self) -> String
pub fn ItlCase::operands(Self) -> Array[String]
pub fn ItlCase::operation(Self) -> String

pub(all) enum ItlDisposition {
  Executable
  Unsupported(String)
  Diagnostic(String)
}

pub struct ItlResult {
  // private fields
}
pub fn ItlResult::disposition(Self) -> ItlDisposition
pub fn ItlResult::id(Self) -> String
pub fn ItlResult::message(Self) -> String
pub fn ItlResult::passed(Self) -> Bool

pub struct RunSummary {
  // private fields
}
pub fn RunSummary::diagnostic_cases(Self) -> Int
pub fn RunSummary::executable_cases(Self) -> Int
pub fn RunSummary::failed_cases(Self) -> Int
pub fn RunSummary::passed_cases(Self) -> Int
pub fn RunSummary::results(Self) -> Array[ItlResult]
pub fn RunSummary::success(Self) -> Bool
pub fn RunSummary::total_cases(Self) -> Int
pub fn RunSummary::unsupported_cases(Self) -> Int

// Type aliases

// Traits
```
<!-- generated-api-end -->
