# Decimal Architecture Research

This note records the implemented boundary and remaining research questions for
the **`0.4.0`** Decimal architecture. It is not a promise of future APIs. The
generated interface and [API reference](./api.md) define the public surface.

## Implemented Baseline

- `Decimal` separates sign, magnitude coefficient, exponent/quantum, precision,
  and special-value payload.
- `DecimalContext` and `DecimalFlags` carry GDA rounding, exponent bounds,
  clamp, extended mode, and condition state.
- Context operations cover arithmetic, quantization, comparison, logical digits,
  adjacent values, elementary functions, formatting, and integral conversion.
- `DecimalInterchange` supports decimal32/64/128 encoding, decoding, and canonicalization.
- `numeric_expr`, `gda_expr`, and the native CLI form the runtime `.decTest` path.

## Architectural Principles

- Separate exact representation, context finalization, flags, and checked
  `ArithmeticError` projection.
- Preserve stored quantum versus normalized cohort form.
- Separate expression syntax, GDA frontend policy, Decimal backend semantics,
  and corpus/process scheduling.
- Constrain public behavior with generated interfaces, white-box tests, and
  official conformance inputs together.

## Research Boundary

Performance kernels, additional semantic projections, interchange diagnostics,
and wider ecosystem integration remain implementation work. They are not
released APIs until they exist in source, generated interfaces, and tests.
