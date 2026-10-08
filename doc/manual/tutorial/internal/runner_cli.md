# internal/runner_cli tutorial

The goal of this page is to show maintainers how to write a conformance runner
in `cli/` with the shared helpers of `internal/runner_cli`: parse the common
options, collect and read corpus files, report diagnostics, print a JSON
summary and choose the exit code. The package is internal to
`Luna-Flow/floating`; the examples are written for code inside the module and
are not compiled by the manual checker.

| I want to | Use |
| --- | --- |
| parse `--json` and the shard options | [`parse_common_options`](#quick-start) |
| expand files and directories into a sorted corpus list | [`collect_files`](#quick-start) |
| read a corpus file with a usage-style error | [`read_source`](#quick-start) |
| print a diagnostic as `file:line:column: message` | [`format_diagnostic_at`](#quick-start) |
| print a stable machine-readable summary | [`json_object`, `json_int`](#keep-output-machine-readable) |
| add my own options | [`CommonOptions::remaining`](#add-a-runner-specific-option) |
| choose the exit code | [the exit-code convention](#follow-the-exit-code-convention) |

## Quick start

There is nothing to install: the package ships inside `Luna-Flow/floating`.
Run its tests from the repository:

```bash
sh tools/run_moon_clean_exec.sh test src/internal/runner_cli --target native
```

Inside the module, import the helpers and a frontend:

```moonbit nocheck
import {
  "Luna-Flow/floating/internal/runner_cli",
  "Luna-Flow/floating/frontend/gda_expr",
}
```

A minimal runner (`run` receives the whole argument vector, program name
first):

```moonbit nocheck
///|
pub fn run(arguments : Array[String]) -> Int {
  let common = match @runner_cli.parse_common_options(arguments) {
    Ok(value) => value
    Err(message) => {
      println(message)
      return 2
    }
  }
  let files = match @runner_cli.collect_files(common.remaining(), ".decTest") {
    Ok(value) => value
    Err(message) => {
      println(message)
      return 2
    }
  }
  let documents = []
  for path in files {
    guard @runner_cli.read_source(path) is Ok(text) else {
      println("cannot read file: " + path)
      return 2
    }
    match @gda_expr.parse_dectest(path, text) {
      Ok(document) => documents.push(document)
      Err(diagnostics) => {
        let first = diagnostics[0]
        println(
          @runner_cli.format_diagnostic_at(
            first.span().source(),
            first.span().line(),
            first.message(),
          ),
        )
        return 2
      }
    }
  }
  let summary = @gda_expr.execute_documents(
    documents,
    options=@gda_expr.RunOptions::new(
      shard_count=common.shard_count(),
      shard_index=common.shard_index(),
    ),
  )
  if common.json() {
    println(
      @runner_cli.json_stringify(
        @runner_cli.json_object([
          ("totalCases", @runner_cli.json_int(summary.total_cases())),
          ("failedCases", @runner_cli.json_int(summary.failed_cases())),
        ]),
      ),
    )
  }
  if summary.success() { 0 } else { 1 }
}
```

## Everyday tasks

### Follow the exit-code convention

All runners in `cli/` use the same codes, which `tools/*.py` relies on:

| Code | Meaning |
| --- | --- |
| `0` | every executed case passed (and, in strict mode, nothing was unsupported) |
| `1` | at least one case failed, or strict mode found unsupported cases (`gda-expr` also counts legacy rows) |
| `2` | usage error, unreadable file, or parse diagnostic |

### Add a runner-specific option

`parse_common_options` leaves every argument it does not know in
`remaining()`, in order. Parse your own options from that array and treat the
rest as paths. Pass `allow_shard=false` if your runner cannot shard; the shard
options then stay in `remaining()` and your parser should reject them as
unknown.

### Keep output machine-readable

Print exactly one JSON object per invocation when `--json` is given. Build it
with `json_object` so the key order is the order you list, and use
`json_int` for counts so they print as integers.

## Going further

- The four runners in `cli/` are complete examples:
  [gda_expr_cli](../cli/gda_expr_cli.md),
  [itl_expr_cli](../cli/itl_expr_cli.md),
  [mpfr_expr_cli](../cli/mpfr_expr_cli.md) and
  [testfloat_expr_cli](../cli/testfloat_expr_cli.md).
- Build the native dispatcher with
  `sh tools/run_moon_clean_exec.sh run --release --target native src/cli -- --help`.
- Run the helper tests from a workspace that contains the module:
  `moon test -p Luna-Flow/floating/internal/runner_cli`.

## Common pitfalls

- **Program name.** `parse_common_options` skips `arguments[0]`. Pass the
  full vector, not a slice without the program name, or the first real
  argument is lost.
- **Directories are not searched recursively.** `collect_files` lists only the
  direct entries of a directory.
- **Named files must have the suffix.** A file argument without the suffix is
  an error (`not a SUFFIX file: P`), so a mistyped name cannot pass as an
  empty run.
- **Option values use MoonBit integer syntax.** `0x10` and `1_000` are
  accepted as 16 and 1000; an argument starting with `--` is never taken as a
  value, so `--shard-count --json` is a missing count.
- **Native only in practice.** File access goes through `moonbitlang/x/fs`;
  the runners are built and run on the native target.

## Next steps

- [internal/runner_cli API](../../api/internal/runner_cli.md)
- [internal/runner_cli design](../../design/internal/runner_cli.md)
- [cli tutorial](../cli.md) for the dispatcher that calls the runners.
