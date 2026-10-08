# internal/runner_cli API

`internal/runner_cli` holds the command-line plumbing shared by the
conformance runners in `cli/`: parsing of the common options, reading files,
collecting corpus files from directories, formatting diagnostics and building
JSON output. It depends on `moonbitlang/x/fs`, so file access works on the
targets that package supports (the runners are built for native). It is an
internal package; examples are not compiled. See the
[tutorial](../../tutorial/internal/runner_cli.md) and the
[design page](../../design/internal/runner_cli.md).

Import (inside the module only):

```text
import {
  "Luna-Flow/floating/internal/runner_cli",
}
```

## Command-line options

### `CommonOptions`

`CommonOptions` holds the options every runner understands and the arguments
it did not consume.

```mbti
pub struct CommonOptions {
  // private fields
}
```

### `parse_common_options`

`parse_common_options(arguments, allow_shard?)` extracts `--json` and the
shard options from a full argument vector.

```mbti
pub fn parse_common_options(Array[String], allow_shard? : Bool) -> Result[CommonOptions, String]
```

`arguments[0]` is the program name and is skipped. Recognized options:

- `--json`: sets `json()`;
- `--shard-count N`, `--shard-count=N`, `--shard-index I`,
  `--shard-index=I`: only when `allow_shard` is true (the default); otherwise
  they are left in `remaining()`.

Every other argument is kept, in order, in `remaining()`. Errors:
`"--shard-count requires a value"` (or `--shard-index`) when the value is
missing or is another option starting with `--`, `"invalid shard
count: X"` for a non-integer, and the `ShardSpec::try_new` messages when the
pair is not valid (count positive, index in `0 ..< count`). Defaults are one
shard, index 0, JSON off.

### `CommonOptions::json`, `shard_count`, `shard_index`, `remaining`

These accessors return the parsed values and a copy of the unconsumed
arguments.

```mbti
pub fn CommonOptions::json(Self) -> Bool
pub fn CommonOptions::shard_count(Self) -> Int
pub fn CommonOptions::shard_index(Self) -> Int
pub fn CommonOptions::remaining(Self) -> Array[String]
```

```moonbit nocheck
///|
test "common options" {
  let options = @runner_cli.parse_common_options([
    "runner", "--json", "--shard-count=4", "--shard-index", "2", "--cases", "a1", "dir",
  ]).unwrap()
  inspect(options.json(), content="true")
  inspect(options.shard_count(), content="4")
  inspect(options.remaining().join(" "), content="--cases a1 dir")
}
```

### `parse_int`

`parse_int(name, text)` parses a decimal integer for the option `name`.

```mbti
pub fn parse_int(String, String) -> Result[Int, String]
```

The error is `"invalid NAME: TEXT"`.

## Files

### `read_source`

`read_source(path, label?)` reads a whole UTF-8 file.

```mbti
pub fn read_source(String, label? : String) -> Result[String, String]
```

The error is `"cannot read LABEL: PATH"`; `label` defaults to `"file"`.

### `collect_files`

`collect_files(paths, suffix)` expands a list of files and directories into
the sorted list of files whose names end in `suffix`.

```mbti
pub fn collect_files(Array[String], String) -> Result[Array[String], String]
```

A directory contributes its direct entries that are files ending in `suffix`
(as `dir + "/" + entry`; subdirectories are not searched, even when their
names end in `suffix`). A file contributes itself if it ends in `suffix`. The
result is sorted in string order, so runs are reproducible across file
systems, and each path appears once. Errors: `"path does not exist: P"`,
`"not a SUFFIX file: P"` for a named file without the suffix,
`"cannot inspect path: P"`, `"cannot read directory: P"`.

## Diagnostics

### `format_diagnostic`, `format_diagnostic_at`

These functions format a message as `source:line:column: message`.

```mbti
pub fn format_diagnostic(@conformance.SourceLocation, String) -> String
pub fn format_diagnostic_at(String, Int, String, column? : Int) -> String
```

`format_diagnostic_at(source, line, message, column?)` builds the location
with `SourceLocation::new` (column defaults to 1; line and column are clamped
to at least 1).

```moonbit nocheck
///|
test "diagnostic format" {
  inspect(
    @runner_cli.format_diagnostic_at("add.decTest", 12, "malformed testcase row"),
    content="add.decTest:12:1: malformed testcase row",
  )
}
```

## JSON output

### `json_int`, `json_string`, `json_bool`, `json_strings`, `json_object`

These functions build `Json` values for runner reports.

```mbti
pub fn json_int(Int) -> Json
pub fn json_string(String) -> Json
pub fn json_bool(Bool) -> Json
pub fn json_strings(Array[String]) -> Json
pub fn json_object(Array[(String, Json)]) -> Json
```

`json_int` stores the integer with its exact decimal representation, so it
prints without a fractional part. `json_object` keeps the order of the
fields; a repeated key keeps its first position and its last value.

### `json_stringify`

`json_stringify(value)` prints a value as compact JSON with escaped strings.

```mbti
pub fn json_stringify(Json) -> String
```

```moonbit nocheck
///|
test "json report" {
  let report = @runner_cli.json_object([
    ("totalCases", @runner_cli.json_int(2)),
    ("failedIds", @runner_cli.json_strings(["a\"1"])),
  ])
  inspect(
    @runner_cli.json_stringify(report),
    content="{\"totalCases\":2,\"failedIds\":[\"a\\\"1\"]}",
  )
}
```

## Complete public interface

This snapshot is the generated `pkg.generated.mbti` of the package. It is the authority when prose and interface disagree.

<!-- generated-api-start -->
```mbti
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
