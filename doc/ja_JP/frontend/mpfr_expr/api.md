# `frontend/mpfr_expr` API

`parse_sqrt_data`/`execute_sqrt_data` は MPFR hex sqrt、
`parse_pow_data`/`execute_pow_data` は固定 integer-power witness、
`parse_elementary_data`/`execute_elementary_data` は固定 29-operation matrix を
扱います。document は source/case count、summary は
total/passed/failed/results/success を公開します。

repository 固定の三つの文法だけを受け入れ、diagnostic は source、line、message を保持します。

## 完全な公開インターフェース

次の snapshot は `0.7.0` の完全な生成 package interface です。公開宣言が名前と signature の基準で、前の説明は挙動別に整理しています。

<!-- generated-api-start -->
```moonbit
// Generated using `moon info`, DON'T EDIT IT
package "Luna-Flow/floating/frontend/mpfr_expr"

import {
  "moonbitlang/core/debug",
}

// Values
pub fn execute_elementary_data(MpfrElementaryDocument) -> RunSummary

pub fn execute_pow_data(MpfrPowDocument) -> RunSummary

pub fn execute_sqrt_data(MpfrDocument) -> RunSummary

pub fn parse_elementary_data(String, String) -> Result[MpfrElementaryDocument, Array[ParseDiagnostic]]

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

pub struct MpfrElementaryDocument {
  // private fields
}
pub fn MpfrElementaryDocument::case_count(Self) -> Int
pub fn MpfrElementaryDocument::source(Self) -> String

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
