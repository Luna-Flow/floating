# consistency API

## Purpose

`consistency` is a white-box test package. It exports no MoonBit items; its
content is a suite of about 250 deterministic tests (28 in
`api_audit_wbtest.mbt` and 228 in `core_wbtest.mbt` on the current branch) that check laws *across*
the packages of `floating`: that the binary, decimal, GDA and interval cores,
their checked wrappers, `semantic`, and the shared `internal` helpers agree
with each other and with exact `BigInt` and rational oracles. This page
records the package's role and its (empty) interface; the
[tutorial](../tutorial/consistency.md) shows how to run and extend it and the
[design page](../design/consistency.md) explains what is checked.

## Importing

Nothing can be imported from `consistency`. Its `moon.pkg` imports the cores
for white-box tests only:

```moonbit nocheck
import {
  "Luna-Flow/arithmetic" @lf_arith,
  "Luna-Flow/luna-generic" @lf_alg,
  "Luna-Flow/floating/bin_float",
  "Luna-Flow/floating/bin_float_checked",
  "Luna-Flow/floating/decimal",
  "Luna-Flow/floating/decimal_checked",
  "Luna-Flow/floating/decimal_gda",
  "Luna-Flow/floating/decimal_gda_checked",
  "Luna-Flow/floating/ball_float",
  "Luna-Flow/floating/ball_float_checked",
  "Luna-Flow/floating/def",
  "Luna-Flow/floating/internal",
  "Luna-Flow/floating/semantic",
} for "wbtest"
```

## Test files

| File | Content |
| --- | --- |
| `api_audit_wbtest.mbt` | audits of public behaviour that spans packages: `def` predicates, `internal` rounding and parsing helpers, error and context types, the decimal interchange facade (bit-exact encodings, canonical predicates, sign operations), checked compare of `bin_float`, generic checked traits through `Luna-Flow/arithmetic`, and the `semantic` interpretation of binary, decimal and interval values |
| `core_wbtest.mbt` | cross-package arithmetic laws: `internal` digit and trimming helpers against `BigInt`, `bin_float` exactness on dyadics and generic trait use, `decimal` and `decimal_gda` cohort, signed-zero and NaN-payload rules (many rows taken from the official decTest suite), `ball_float` enclosure properties, checked-pipeline closure, and total constructors |
| `bin_coeff_migration_wbtest.mbt` | helpers that build `BinFloat` values from `BigInt` for the tests above |

All tests are white-box (`*_wbtest.mbt`) and import every core package for
`wbtest` only, so the package adds nothing to any build of the library.

## Complete public interface

The package exports no MoonBit items.

<!-- generated-api-start -->
```mbti
// Generated using `moon info`, DON'T EDIT IT
package "Luna-Flow/floating/consistency"

// Values

// Errors

// Types and methods

// Type aliases

// Traits
```
<!-- generated-api-end -->
