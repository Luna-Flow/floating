# `frontend/testfloat_expr` API

`TestFloatSpec::parse(function, rounding, tininess?)` validates format,
operation, rounding, and tininess. `parse_testfloat(source, text, spec)` returns
a typed document; `execute_document(document, options?)` executes stable shards
and returns result/count accessors.

Supported operations are `Add`, `Subtract`, `Multiply`, `Divide`, and
`SquareRoot` over binary16/32/64/128. A successful summary means selected rows
matched values and flags; it does not expand the supported matrix.

## Complete Public Interface

The following snapshot is the complete generated package interface for `0.6.0`. Public declarations are authoritative; prose above groups them by behavior.

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
