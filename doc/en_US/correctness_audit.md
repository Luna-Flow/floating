# Correctness Audit

This audit maps the **`0.4.0`** public surface to current implementation and
verification boundaries. Generated interfaces inventory the API; source and
tests define behavior.

## Core Numeric Packages

| Area | Contract | Evidence | Status |
| --- | --- | --- | --- |
| `def` | `Floating` contains classification, sign, precision, retuning, and normalization; arithmetic capabilities stay separate. | `src/def/pkg.generated.mbti`, consistency tests | Verified |
| `bin_float` | Finite values use normalized dyadic representation; precision changes round explicitly; checked operations return `ArithmeticError`. | `src/bin_float`, `src/consistency` | Verified with rounding boundary |
| `decimal` representation | Values retain sign, magnitude, exponent/quantum, and precision; signed zero and qNaN/sNaN payloads remain observable. | `src/decimal`, Decimal white-box tests | Verified |
| `decimal` context | `*_ctx` applies precision, rounding, exponent, clamp, and extended settings and returns accumulated `DecimalFlags`. | `src/decimal/*_ctx.mbt`, conformance cases | Verified with operation-specific corpus coverage |
| `decimal` interchange | decimal32/64/128 encode and decode are exposed through `DecimalInterchange`; canonicalization and status are explicit. | `src/decimal/interchange.mbt`, interchange phase | Verified with conformance boundary |
| `ball_float` | Bounds round outward; arithmetic encloses real results; relations are interval-based; zero-containing division returns a whole-real enclosure. | `src/ball_float`, consistency tests | Verified with enclosure boundary |

## Composition And Semantic Packages

| Area | Contract | Evidence | Status |
| --- | --- | --- | --- |
| `*_result` | Existing errors short-circuit; value-producing checked operations stay closed over `Self`; `result()` restores the raw boundary. | Generated interfaces and implementation packages | Verified |
| `semantic` | Concrete values and arithmetic failures project to representation-independent semantic variants. | `src/semantic`, consistency tests | Verified |
| `numeric_expr` | Expression storage is private; callbacks own literal and operation semantics; evaluation reports node-specific failures. | `src/numeric_expr`, package tests | Verified |
| `gda_expr` | Diagnostics, legacy rows, unsupported rows, and executable mismatches remain distinct; deterministic options and summaries are public. | parser/execution tests, smoke fixture | Verified |

## Validation Gates

- `just smoke`: checked-in end-to-end parser/backend fixture.
- `just ci`: focused Decimal coefficient-kernel white-box gate.
- `just pr`: all-target check, generated-interface refresh, native interpreter
  build, and staged official-corpus execution.

Official corpora are external pinned inputs. Unsupported and diagnostic rows
remain visible in summaries; strict mode can make them fail the gate. See the
[conformance guide](../../testdata/decimal/README.md).
