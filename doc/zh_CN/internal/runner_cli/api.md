# `internal/runner_cli` API 参考

原生 conformance 命令 adapter 共享的副作用边界。

## 状态

这是仓库基础设施，不是稳定应用 API。生成声明供本模块维护者和内部集成查阅。

## 完整公开接口

以下快照是 `0.7.0` 的完整生成包接口。公开声明是名称与签名的权威清单；前文按行为解释这些能力。

<!-- generated-api-start -->
```moonbit
// Generated using `moon info`, DON'T EDIT IT
package "Luna-Flow/floating/internal/runner_cli"

import {
  "Luna-Flow/floating/internal/conformance",
}

// Values
pub fn collect_files(Array[String], String) -> Result[Array[String], String]

pub fn format_diagnostic(@conformance.SourceLocation, String) -> String

pub fn format_diagnostic_at(String, Int, String, column? : Int) -> String

pub fn json_bool(Bool) -> Json

pub fn json_int(Int) -> Json

pub fn json_object(Array[(String, Json)]) -> Json

pub fn json_string(String) -> Json

pub fn json_stringify(Json) -> String

pub fn json_strings(Array[String]) -> Json

pub fn parse_common_options(Array[String], allow_shard? : Bool) -> Result[CommonOptions, String]

pub fn parse_int(String, String) -> Result[Int, String]

pub fn read_source(String, label? : String) -> Result[String, String]

// Errors

// Types and methods
pub struct CommonOptions {
  // private fields
}
pub fn CommonOptions::json(Self) -> Bool
pub fn CommonOptions::remaining(Self) -> Array[String]
pub fn CommonOptions::shard_count(Self) -> Int
pub fn CommonOptions::shard_index(Self) -> Int

// Type aliases

// Traits
```
<!-- generated-api-end -->
