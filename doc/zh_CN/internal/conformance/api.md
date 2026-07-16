# `internal/conformance` API 参考

conformance 位置、disposition、分片与汇总的纯共享模型。

## 状态

这是仓库基础设施，不是稳定应用 API。生成声明供本模块维护者和内部集成查阅。

## 完整公开接口

以下快照是 `0.7.1` 的完整生成包接口。公开声明是名称与签名的权威清单；前文按行为解释这些能力。

<!-- generated-api-start -->
```moonbit
// Generated using `moon info`, DON'T EDIT IT
package "Luna-Flow/floating/internal/conformance"

import {
  "moonbitlang/core/debug",
}

// Values

// Errors

// Types and methods
pub(all) enum CaseDisposition {
  Executable
  Diagnostic(String)
  Legacy(String)
  Unsupported(String)
} derive(Eq, @debug.Debug)

pub struct CaseResult {
  // private fields
} derive(Eq, @debug.Debug)
pub fn CaseResult::disposition(Self) -> CaseDisposition
pub fn CaseResult::executable(String, Bool, message? : String) -> Self
pub fn CaseResult::id(Self) -> String
pub fn CaseResult::message(Self) -> String
pub fn CaseResult::new(String, CaseDisposition, Bool, message? : String) -> Self
pub fn CaseResult::passed(Self) -> Bool

pub struct RunSummary {
  // private fields
} derive(Eq, @debug.Debug)
pub fn RunSummary::diagnostic_cases(Self) -> Int
pub fn RunSummary::executable_cases(Self) -> Int
pub fn RunSummary::failed_cases(Self) -> Int
pub fn RunSummary::from_results(Int, Array[CaseResult]) -> Self
pub fn RunSummary::legacy_cases(Self) -> Int
pub fn RunSummary::merge(Array[Self]) -> Self
pub fn RunSummary::passed_cases(Self) -> Int
pub fn RunSummary::results(Self) -> Array[CaseResult]
pub fn RunSummary::selected_cases(Self) -> Int
pub fn RunSummary::skipped_cases(Self) -> Int
pub fn RunSummary::success(Self) -> Bool
pub fn RunSummary::total_cases(Self) -> Int
pub fn RunSummary::unsupported_cases(Self) -> Int

pub struct ShardSpec {
  // private fields
} derive(Eq, @debug.Debug)
pub fn ShardSpec::count(Self) -> Int
pub fn ShardSpec::index(Self) -> Int
pub fn ShardSpec::new(Int, Int) -> Self
pub fn ShardSpec::selects(Self, Int) -> Bool
pub fn ShardSpec::try_new(Int, Int) -> Result[Self, String]

pub struct SourceLocation {
  // private fields
} derive(Eq, @debug.Debug)
pub fn SourceLocation::column(Self) -> Int
pub fn SourceLocation::line(Self) -> Int
pub fn SourceLocation::new(String, Int, column? : Int) -> Self
pub fn SourceLocation::source(Self) -> String

// Type aliases

// Traits
```
<!-- generated-api-end -->
