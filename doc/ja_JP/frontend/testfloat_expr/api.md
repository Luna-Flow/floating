# `frontend/testfloat_expr` API

`TestFloatSpec::parse(function, rounding, tininess?)` が format/operation/rounding/tininess を検証し、`parse_testfloat` が typed document、`execute_document` が stable shard の結果と件数を返します。

対象は binary16/32/64/128 の Add/Subtract/Multiply/Divide/SquareRoot だけです。summary success は選択行の値と flags が一致したことだけを意味します。

## 完全な公開インターフェース

次の snapshot は `0.7.1` の完全な生成 package interface です。公開宣言が名前と signature の基準で、前の説明は挙動別に整理しています。

<!-- generated-api-start -->
```moonbit
// Generated using `moon info`, DON'T EDIT IT
package "Luna-Flow/floating/frontend/testfloat_expr"

import {
  "Luna-Flow/floating/bin_float",
  "moonbitlang/core/debug",
}

// Values
pub fn execute_document(TestFloatDocument, options? : RunOptions) -> RunSummary

pub fn parse_testfloat(String, String, TestFloatSpec) -> Result[TestFloatDocument, Array[ParseDiagnostic]]

// Errors

// Types and methods
pub struct CaseResult {
  // private fields
}
pub fn CaseResult::id(Self) -> String
pub fn CaseResult::message(Self) -> String
pub fn CaseResult::passed(Self) -> Bool

pub struct ParseDiagnostic {
  // private fields
} derive(Eq, @debug.Debug)
pub fn ParseDiagnostic::line(Self) -> Int
pub fn ParseDiagnostic::message(Self) -> String
pub fn ParseDiagnostic::source(Self) -> String

pub struct RunOptions {
  // private fields
}
pub fn RunOptions::new(shard_count? : Int, shard_index? : Int) -> Self
pub fn RunOptions::shard_count(Self) -> Int
pub fn RunOptions::shard_index(Self) -> Int

pub struct RunSummary {
  // private fields
}
pub fn RunSummary::failed_cases(Self) -> Int
pub fn RunSummary::passed_cases(Self) -> Int
pub fn RunSummary::results(Self) -> Array[CaseResult]
pub fn RunSummary::selected_cases(Self) -> Int
pub fn RunSummary::success(Self) -> Bool
pub fn RunSummary::total_cases(Self) -> Int

pub struct TestFloatCase {
  // private fields
}
pub fn TestFloatCase::id(Self) -> String
pub fn TestFloatCase::line(Self) -> Int

pub struct TestFloatDocument {
  // private fields
}
pub fn TestFloatDocument::case_count(Self) -> Int
pub fn TestFloatDocument::cases(Self) -> Array[TestFloatCase]
pub fn TestFloatDocument::source(Self) -> String
pub fn TestFloatDocument::spec(Self) -> TestFloatSpec

pub(all) enum TestFloatOperation {
  Add
  Subtract
  Multiply
  Divide
  SquareRoot
} derive(Eq, @debug.Debug)

pub struct TestFloatSpec {
  // private fields
} derive(Eq, @debug.Debug)
pub fn TestFloatSpec::format(Self) -> @bin_float.BinaryInterchangeFormat
pub fn TestFloatSpec::function_name(Self) -> String
pub fn TestFloatSpec::operation(Self) -> TestFloatOperation
pub fn TestFloatSpec::parse(String, String, tininess? : String) -> Result[Self, String]
pub fn TestFloatSpec::rounding(Self) -> @bin_float.BinaryRoundingMode
pub fn TestFloatSpec::tininess(Self) -> @bin_float.TininessDetection

// Type aliases

// Traits
```
<!-- generated-api-end -->
