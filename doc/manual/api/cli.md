# cli API

`cli` is the native executable `floating-conformance`. It dispatches its
arguments to one of the four conformance runners (`gda`, `testfloat`, `mpfr`,
`itl`) and exits with the runner's code. The package has no public MoonBit
items; this page documents its command-line interface. The
[tutorial](../tutorial/cli.md) shows typical invocations and the
[design page](../design/cli.md) explains the layering.

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

The runner receives the program name followed by the forwarded arguments and
interprets them as documented in
[gda_expr_cli](cli/gda_expr_cli.md), [testfloat_expr_cli](cli/testfloat_expr_cli.md),
[mpfr_expr_cli](cli/mpfr_expr_cli.md) and [itl_expr_cli](cli/itl_expr_cli.md).

## Exit status

| Code | Meaning |
| --- | --- |
| `0` | `--help`, or the runner reported success |
| `1` | the runner found failing cases (or unsupported cases in strict mode) |
| `2` | a missing, repeated or unknown `--backend`, or a runner usage, file or parse error |

Messages go to standard output.

## Build

The executable is built by the conformance tooling:

```sh
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
