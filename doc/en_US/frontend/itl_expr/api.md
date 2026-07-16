# `frontend/itl_expr` API

`parse_itl(text)` returns typed `ItlCase` values or diagnostics.
`execute_case(case, precision?)` returns an `ItlResult`; `summarize_results`
folds results into counts and retains individual rows. Callers inspect
`ItlDisposition` to distinguish executable, unsupported, and diagnostic cases.

The package accepts only the operations and expected-value forms implemented by
the current parser/executor. Consult `testdata/interval/README.md` for the strict
conformance subset.

## Complete Public Interface

The following snapshot is the complete generated package interface for `0.7.1`. Public declarations are authoritative; prose above groups them by behavior.

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
