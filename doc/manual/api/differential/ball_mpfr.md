# differential/ball_mpfr API

## Purpose

`differential/ball_mpfr` is the test side of the untimed differential stage of `BallFloat` against MPFR (`tools/ball_diff.py`). It is a test-only package and exports no MoonBit items. Its one test reads a file of operand rows and the oracle file written by `tools/ball_mpfr_oracle.c`, runs every row on `BallFloat` (`add`, `sub`, `mul`, `div`, `sqr`, `sqrt`, `fma`, `exp`, `ln`) and compares both bounds of the result, and the operands as the library read them, with the oracle's, as canonical text; for `exp` and `ln` the result must enclose the oracle's and not be wider than 1,024 units of the last place. The [tutorial](../../tutorial/differential/ball_mpfr.md) shows how to run it and the [design page](../../design/differential/ball_mpfr.md) explains the comparison.

## Importing

The package is test-only and exports no items, so there is nothing to import from it. Its tests import the packages under test and the file and environment access of the runner:

```moonbit nocheck
import {
  "Luna-Flow/floating/ball_float" @ball,
  "Luna-Flow/floating/bin_float" @binary,
  "moonbitlang/async",
  "moonbitlang/core/env",
  "moonbitlang/core/string",
  "moonbitlang/x/fs",
} for "test"
```

## Environment and output

| Name | Meaning |
| --- | --- |
| `BALLDIFF_INPUTS` | the row file (`id op size class operand...`, an operand is `lo:hi`) |
| `BALLDIFF_ORACLE` | the oracle file (`id lo hi flags echo lohex hihex`), same ids in the same order |

Without the two variables the test does nothing. It prints `BALLDIFF_FAIL id op size class expected lo hi got lo hi` for a differing row, `BALLDIFF_UNDECIDED id` for a row the oracle marked undecided, and `BALLDIFF_SUMMARY rows=N failed=K undecided=U`; it fails when any row differs. `tools/ball_diff.py run` reads these lines.

## Complete public interface

The package exports no MoonBit items.

<!-- generated-api-start -->
```mbti
// Generated using `moon info`, DON'T EDIT IT
package "Luna-Flow/floating-tools/differential/ball_mpfr"

// Values

// Errors

// Types and methods

// Type aliases

// Traits
```
<!-- generated-api-end -->
