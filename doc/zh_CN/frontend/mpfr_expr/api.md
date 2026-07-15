# `frontend/mpfr_expr` API

`parse_sqrt_data`/`execute_sqrt_data` 处理 MPFR 十六进制 sqrt 行；
`parse_pow_data`/`execute_pow_data` 处理固定整数幂 witness；
`parse_elementary_data`/`execute_elementary_data` 处理固定 29 运算 matrix。
document 暴露 source/case count，summary 暴露 total/passed/failed/results/success。

只支持仓库固定的三种语法；诊断保留 source、line 和 message。

## 完整公开接口

以下快照是 `0.7.0` 的完整生成包接口。公开声明是名称与签名的权威清单；前文按行为解释这些能力。

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
