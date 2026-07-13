# `internal/runner_cli` API Reference

Effect boundary shared by native conformance command adapters.

## Status

This is repository infrastructure, not a stable application API. Its generated declarations are documented for maintainers and integrations inside this module.

## Complete Public Interface

The following snapshot is the complete generated package interface for `0.6.0`. Public declarations are authoritative; prose above groups them by behavior.

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
