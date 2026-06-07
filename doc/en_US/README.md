# FLOATING Documentation

This directory contains the English documentation baseline for `floating` `0.2.0`.

## Core Documents

- [Documentation Standard](./doc_standard.md)
- [Correctness Audit Ledger](./correctness_audit.md)
- [@def API](./def/api.md)
- [@def Design](./def/design.md)
- [@internal API](./internal/api.md)
- [@internal Design](./internal/design.md)

## Numeric Packages

- `bin_float` and `decimal` implement checked scalar capability traits from `Luna-Flow/arithmetic`.
- `ball_float` implements enclosure relations plus checked division and checked integer power, without a fake total ordering.
- This repository does not reintroduce transcendental layers, calculus, matrices, complex numbers, or special functions in this integration pass.

- [@bin_float API](./bin_float/api.md)
- [@bin_float Tutorial](./bin_float/tutorial.md)
- [@bin_float Design](./bin_float/design.md)
- [@decimal API](./decimal/api.md)
- [@decimal Tutorial](./decimal/tutorial.md)
- [@decimal Design](./decimal/design.md)
- [@ball_float API](./ball_float/api.md)
- [@ball_float Tutorial](./ball_float/tutorial.md)
- [@ball_float Design](./ball_float/design.md)
