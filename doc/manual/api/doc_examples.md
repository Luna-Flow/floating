# doc_examples API

## Purpose

`doc_examples` is a test-only package. Its only source is
`tooling/src/doc_examples/README.mbt.md`, whose `moonbit check` blocks are compiled
and run as tests; it exports no MoonBit items. The blocks are short,
executable versions of the main workflows of the public packages (binary
contexts and interchange, GDA sticky status, IEEE decimal flags, intervals and
decorations, checked pipelines, semantic comparison, `numeric_expr`, and the
four conformance frontends). See the [tutorial](../tutorial/doc_examples.md)
and the [design page](../design/doc_examples.md).

## Importing

Nothing can be imported from `doc_examples`. Its `moon.pkg` imports the
packages its examples use, for tests only:

```moonbit nocheck
import {
  "Luna-Flow/floating/ball_float",
  "Luna-Flow/floating/ball_float_checked",
  "Luna-Flow/floating/bin_float",
  "Luna-Flow/floating/bin_float_checked",
  "Luna-Flow/floating/decimal",
  "Luna-Flow/floating/decimal_gda",
  "Luna-Flow/floating/decimal_gda_checked",
  "Luna-Flow/floating/decimal_checked",
  "Luna-Flow/floating-tools/semantic",
  "Luna-Flow/floating-tools/numeric_expr",
  "Luna-Flow/floating-tools/frontend/gda_expr",
  "Luna-Flow/floating-tools/frontend/itl_expr",
  "Luna-Flow/floating-tools/frontend/mpfr_expr",
  "Luna-Flow/floating-tools/frontend/testfloat_expr",
} for "test"
```

## Examples

The README holds eleven `moonbit check` tests, one per workflow: binary
context and interchange, GDA sticky status, IEEE decimal status, interval and
decorated semantics, checked pipelines, the semantic projection,
`numeric_expr` callbacks, and one inline document for each of the GDA, ITL,
MPFR and TestFloat frontends.

## Complete public interface

The package exports no MoonBit items.

<!-- generated-api-start -->
```mbti
// Generated using `moon info`, DON'T EDIT IT
package "Luna-Flow/floating-tools/doc_examples"

// Values

// Errors

// Types and methods

// Type aliases

// Traits
```
<!-- generated-api-end -->
