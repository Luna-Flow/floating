# differential/harness API

## Purpose

`differential/harness` holds the behaviour of the seeded random differential
executable: it parses the command line, splits a corpus into batches, runs
each batch through the matching frontend under the mare_mark runner and writes
the JSONL record. The package `differential` is only the entry point that
calls `run` with `@env.args()`. The command line and the workflow are
documented on the [`differential` page](../differential.md); the
[tutorial](../../tutorial/differential/harness.md) shows what the package is
for and the [design page](../../design/differential/harness.md) explains the
split.

## Importing

```moonbit nocheck
import {
  "Luna-Flow/floating-tools/differential/harness",
}
```

The package needs `moonbitlang/async` and is built for native, JavaScript,
Wasm and LLVM, not for wasm-gc.

## Function specification

### `run`

```mbti
pub async fn run(Array[String]) -> Unit
```

`run(args)` takes the program arguments (the program name, and under Node.js
the script path too, come first). It exits the process with `2` for a bad
command line or corpus and with `1` when a batch disagrees with its oracle;
otherwise it returns after the record is written.

## Complete public interface

<!-- generated-api-start -->
```mbti
// Generated using `moon info`, DON'T EDIT IT
package "Luna-Flow/floating-tools/differential/harness"

// Values
pub async fn run(Array[String]) -> Unit

// Errors

// Types and methods

// Type aliases

// Traits
```
<!-- generated-api-end -->
