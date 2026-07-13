# `internal/conformance` API リファレンス

conformance location、disposition、shard、summary の pure shared model です。

## 状態

repository infrastructure であり、stable application API ではありません。生成宣言は module 内の保守と統合向けです。

## 完全な公開インターフェース

次の snapshot は `0.6.0` の完全な生成 package interface です。公開宣言が名前と signature の基準で、前の説明は挙動別に整理しています。

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
