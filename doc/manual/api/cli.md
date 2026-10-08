# cli API

## Purpose

`cli` is the native executable `floating-conformance`. It dispatches its
arguments to one of the four conformance runners (`gda`, `testfloat`, `mpfr`,
`itl`) and exits with the runner's code. The package has no public MoonBit
items; this page documents its command-line interface. The
[tutorial](../tutorial/cli.md) shows typical invocations and the
[design page](../design/cli.md) explains the layering.

## Importing

`cli` is an executable package (`pkgtype(kind: "executable")`) and cannot be
imported. Its `moon.pkg` imports the four runners and the process helpers:

```moonbit nocheck
import {
  "moonbitlang/core/env",
  "moonbitlang/x/sys",
  "Luna-Flow/floating/cli/gda_expr_cli",
  "Luna-Flow/floating/cli/itl_expr_cli",
  "Luna-Flow/floating/cli/mpfr_expr_cli",
  "Luna-Flow/floating/cli/testfloat_expr_cli",
}
```

To run a corpus from your own MoonBit code, import a runner such as
[`cli/gda_expr_cli`](cli/gda_expr_cli.md) and call its `run`, or call a
frontend directly.

## Command line

```text
floating-conformance --backend <gda|testfloat|mpfr|itl> [backend options]
floating-conformance --help
```

| Argument | Meaning |
| --- | --- |
| `--backend NAME`, `--backend=NAME` | selects the runner; required, non-empty, at most once (an empty `--backend=` is an error) |
| `--help`, `-h` | prints the usage line and exits with 0 when reached, even after `--backend` (the runners' own `--help` is therefore not reachable through the dispatcher) |
| anything else | forwarded, in order, to the runner |

Arguments are scanned from left to right and the first error ends the scan:
`--backend` without a value, or a second `--backend`, exits with 2 before a
later `--help` is seen. The value after `--backend` is taken as is, so
`--backend --help` asks for a backend named `--help` (exit 2). An empty
`--backend=` counts as not given: `--backend= --backend gda` is accepted and
runs `gda` (tracked in [#78](https://github.com/Luna-Flow/floating/issues/78); a fix is proposed in [#83](https://github.com/Luna-Flow/floating/pull/83)).

The runner receives the program name followed by the forwarded arguments and
interprets them as documented in
[gda_expr_cli](cli/gda_expr_cli.md), [testfloat_expr_cli](cli/testfloat_expr_cli.md),
[mpfr_expr_cli](cli/mpfr_expr_cli.md) and [itl_expr_cli](cli/itl_expr_cli.md).

## Exit status

| Code | Meaning |
| --- | --- |
| `0` | `--help`, or the runner reported success |
| `1` | the runner found failing cases; for `itl` also diagnostic cases; with `--strict-supported` (`gda`, `itl`) also unsupported cases, and for `gda` legacy ones |
| `2` | a missing, repeated or unknown `--backend`, or a runner usage, file or parse error |

Messages go to standard output.

## Build

The executable is built by the conformance tooling:

```bash
just conformance build decimal_gda    # or binary, interval
sh tools/run_moon_clean_exec.sh run --release --target native src/cli -- --help
```

`tools/conformance_cli.py` builds `src/cli` once per backend into
`_build/conformance/<backend>/` and copies it to
`<backend>-conformance.exe`, so parallel builds for different backends do not
share a target directory.

## Complete public interface

The package exports no MoonBit items.

<!-- generated-api-start -->
```mbti
// Generated using `moon info`, DON'T EDIT IT
package "Luna-Flow/floating/cli"

// Values

// Errors

// Types and methods

// Type aliases

// Traits
```
<!-- generated-api-end -->
