# `frontend/mpfr_expr` API

`parse_sqrt_data`/`execute_sqrt_data` handle MPFR hexadecimal sqrt rows.
`parse_pow_data`/`execute_pow_data` handle the pinned integer-power witness
format. Documents expose source and case count; summaries expose total, passed,
failed, individual results, and `success`.

Only these two repository-pinned grammars are accepted. Diagnostics preserve
source, line, and message.

## Complete Public Interface

The following snapshot is the complete generated package interface for `0.6.1`. Public declarations are authoritative; prose above groups them by behavior.

<!-- generated-api-start -->
```moonbit
// Generated using `moon info`, DON'T EDIT IT
package "Luna-Flow/floating/frontend/mpfr_expr"

import {
  "moonbitlang/core/debug",
}

// Values
pub fn execute_pow_data(MpfrPowDocument) -> RunSummary

pub fn execute_sqrt_data(MpfrDocument) -> RunSummary

pub fn parse_pow_data(String, String) -> Result[MpfrPowDocument, Array[ParseDiagnostic]]

pub fn parse_sqrt_data(String, String) -> Result[MpfrDocument, Array[ParseDiagnostic]]

// Errors

// Types and methods
pub struct CaseResult {
  // private fields
}
pub fn CaseResult::id(Self) -> String
pub fn CaseResult::message(Self) -> String
pub fn CaseResult::passed(Self) -> Bool

pub struct MpfrCase {
  // private fields
}

pub struct MpfrDocument {
  // private fields
}
pub fn MpfrDocument::case_count(Self) -> Int
pub fn MpfrDocument::source(Self) -> String

pub struct MpfrPowCase {
  // private fields
}

pub struct MpfrPowDocument {
  // private fields
}
pub fn MpfrPowDocument::case_count(Self) -> Int
pub fn MpfrPowDocument::source(Self) -> String

pub struct ParseDiagnostic {
  // private fields
} derive(Eq, @debug.Debug)
pub fn ParseDiagnostic::line(Self) -> Int
pub fn ParseDiagnostic::message(Self) -> String
pub fn ParseDiagnostic::source(Self) -> String

pub struct RunSummary {
  // private fields
}
pub fn RunSummary::failed_cases(Self) -> Int
pub fn RunSummary::passed_cases(Self) -> Int
pub fn RunSummary::results(Self) -> Array[CaseResult]
pub fn RunSummary::success(Self) -> Bool
pub fn RunSummary::total_cases(Self) -> Int

// Type aliases

// Traits
```
<!-- generated-api-end -->
