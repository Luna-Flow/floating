# FLOATING Documentation

These pages describe the `0.6.1` release. Public names come from each package's
`pkg.generated.mbti`.

Start with [Getting Started](./getting_started.md), then read
[Numeric Semantics](./numeric_semantics.md), [Architecture](./architecture.md),
and [Verification](./verification.md) before opening a package reference.

## Packages

- Core: [`def`](./def/api.md), [`bin_float`](./bin_float/api.md), [`decimal`](./decimal/api.md), [`decimal_gda`](./decimal_gda/api.md), [`ball_float`](./ball_float/api.md)
- Checked: [`bin_float_checked`](./bin_float_checked/api.md), [`decimal_checked`](./decimal_checked/api.md), [`decimal_gda_checked`](./decimal_gda_checked/api.md), [`ball_float_checked`](./ball_float_checked/api.md)
- Semantic/IR: [`semantic`](./semantic/api.md), [`numeric_expr`](./numeric_expr/api.md)
- Frontends: [`frontend/gda_expr`](./frontend/gda_expr/api.md), [`frontend/itl_expr`](./frontend/itl_expr/api.md), [`frontend/mpfr_expr`](./frontend/mpfr_expr/api.md), [`frontend/testfloat_expr`](./frontend/testfloat_expr/api.md)
- Runtime/verification: [`internal`](./internal/api.md), [`internal/conformance`](./internal/conformance/api.md), [`internal/runner_cli`](./internal/runner_cli/api.md), [`consistency`](./consistency/api.md), [`bin_float_bench`](./bin_float_bench/api.md)
- CLI: [`cli`](./cli/api.md), [`cli/gda_expr_cli`](./cli/gda_expr_cli/api.md), [`cli/itl_expr_cli`](./cli/itl_expr_cli/api.md), [`cli/mpfr_expr_cli`](./cli/mpfr_expr_cli/api.md), [`cli/testfloat_expr_cli`](./cli/testfloat_expr_cli/api.md)

Every package has `api.md`, `tutorial.md`, and `design.md`. Infrastructure,
CLI, benchmark, and test packages use those pages to document maintainer entry
points and explicitly state that they are not stable application APIs.

## Public Surface And Stability

`0.6.1` is a pre-1.0 release. “Stable” below means an intentional application
surface for this release, not an ABI promise across all future versions.

| Package | Public surface | Stability | Not included |
| --- | --- | --- | --- |
| `bin_float` | `BinFloat`, `BinCoeff`, contexts, flags, interchange | Stable release surface | Complete IEEE 754 operation set |
| `decimal` | `Decimal`, IEEE contexts/flags, interchange | Stable release surface | Complete IEEE 754 operation set |
| `decimal_gda` | GDA `Decimal`, contexts, sticky flags, traps, outcomes | Stable GDA surface | Unbounded future directives and non-scalar placeholders |
| `ball_float` | bare/decorated intervals, relations, directed arithmetic | Stable release surface | Reverse interval operations; guaranteed tightness |
| `bin_float_checked`, `ball_float_checked` | short-circuit `Result[..., ArithmeticError]` pipelines | Stable composition surface | Context flags and decorations |
| `decimal_checked` | IEEE context, defined result, latest and accumulated flags | Stable IEEE composition surface | GDA sticky status and traps |
| `decimal_gda_checked` | sticky context, trap short-circuit, explicit defined-result recovery | Stable GDA composition surface | IEEE per-operation context model |
| `semantic` | exact rational/infinity/NaN/interval projection | Provisional integration surface | Representation metadata and arithmetic |
| `numeric_expr` | syntax nodes and callback evaluation | Provisional integration surface | Text parsing and concrete numeric semantics |
| `frontend/*`, `cli/*` | conformance parsers, runners, and commands | Verification infrastructure | General-purpose file/format compatibility |
| `internal/*`, `consistency`, `*_bench` | implementation and verification helpers | Not application API | Compatibility guarantees |

Read `api.md` for callable names, `design.md` for invariants and algorithm
choices, and `tutorial.md` for the shortest supported workflow. Generated
`pkg.generated.mbti` files are the authority when prose and inventory differ.

## Numerical Evidence

- [`bin_float` conformance](./bin_float/conformance.md) and [performance](./bin_float/performance.md)
- [`decimal` IEEE conformance](./decimal/conformance.md) and [performance](./decimal/performance.md)
- [`decimal_gda` conformance](./decimal_gda/conformance.md)
- [`ball_float` conformance](./ball_float/conformance.md)

Performance thresholds are implementation evidence, not public guarantees.
Conformance pages state the exact finite claim and its exclusions.

## GDA Result

The official 144-file corpus passes **64,986/64,986 legal executable scalar
rows**, with zero unsupported and zero legacy classifications. The remaining
141 rows are all `#` placeholder/non-scalar invalid inputs and are excluded from
the legal semantic denominator. The official0 corpus likewise passes all
16,124 legal rows.

## Verification

Use `just conformance smoke <backend>` for committed fixtures.
Full corpus commands and exact supported-operation boundaries live in
`testdata/*/README.md`. Passing a pinned corpus never implies complete IEEE
754, GDA, or ITF1788 coverage.
