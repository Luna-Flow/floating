# cli/dispatch API

## Purpose

`cli/dispatch` holds the behaviour of the `floating-conformance` executable:
it scans the program arguments for `--backend`, forwards the rest to one of
the four conformance runners and returns the process exit code. The package
`cli` is only the entry point that passes `@env.args()` to it and exits with
the result, so that the dispatcher is a library with its own tests. The
command line is documented on the [`cli` page](../cli.md); the
[tutorial](../../tutorial/cli/dispatch.md) calls it from a test and the
[design page](../../design/cli/dispatch.md) explains the split.

## Importing

```moonbit nocheck
import {
  "Luna-Flow/floating-tools/cli/dispatch",
}
```

The examples use the alias `@dispatch`.

## Function specification

### `dispatch`

```mbti
pub fn dispatch(Array[String]) -> Int32
```

`dispatch(arguments)` expects the program name at index 0, followed by the
command line. It returns `0` after `--help`, `2` for a missing, repeated,
empty or unknown `--backend`, and otherwise the return value of the runner
(`0`, `1` or `2`). Messages go to standard output. It never exits the
process; the caller does.

## Complete public interface

<!-- generated-api-start -->
```mbti
// Generated using `moon info`, DON'T EDIT IT
package "Luna-Flow/floating-tools/cli/dispatch"

// Values
pub fn dispatch(Array[String]) -> Int32

// Errors

// Types and methods

// Type aliases

// Traits
```
<!-- generated-api-end -->
