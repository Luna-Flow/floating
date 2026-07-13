# `frontend/itl_expr` API

`parse_itl(text)` は `ItlCase` または diagnostic、`execute_case(case, precision?)` は `ItlResult`、`summarize_results` は件数と各行を返します。`ItlDisposition` で executable/unsupported/diagnostic を区別します。

現在の parser/executor が実装する operation と期待値形式だけを受け入れ、strict subset は `testdata/interval/README.md` に定義します。

## 完全な公開インターフェース

次の snapshot は `0.6.0` の完全な生成 package interface です。公開宣言が名前と signature の基準で、前の説明は挙動別に整理しています。

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
