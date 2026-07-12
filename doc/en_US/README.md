# FLOATING Documentation

These pages describe the `0.5.0` release. Public names come from each package's
`pkg.generated.mbti`.

## Packages

- Core: [`def`](./def), [`bin_float`](./bin_float), [`decimal`](./decimal), [`ball_float`](./ball_float)
- Checked: [`bin_float_checked`](./bin_float_checked), [`decimal_checked`](./decimal_checked), [`ball_float_checked`](./ball_float_checked)
- Semantic/IR: [`semantic`](./semantic), [`numeric_expr`](./numeric_expr)
- Frontends: [`frontend/gda_expr`](./frontend/gda_expr), [`frontend/itl_expr`](./frontend/itl_expr), [`frontend/mpfr_expr`](./frontend/mpfr_expr), [`frontend/testfloat_expr`](./frontend/testfloat_expr)
- Runtime/verification: [`internal`](./internal), [`internal/conformance`](./internal/conformance), [`internal/runner_cli`](./internal/runner_cli), [`consistency`](./consistency), [`bin_float_bench`](./bin_float_bench)
- CLI: [`cli`](./cli), [`cli/gda_expr_cli`](./cli/gda_expr_cli), [`cli/itl_expr_cli`](./cli/itl_expr_cli), [`cli/mpfr_expr_cli`](./cli/mpfr_expr_cli), [`cli/testfloat_expr_cli`](./cli/testfloat_expr_cli)

Each package has a `design.md`; library packages also expose API and tutorial
pages. Implementation, CLI, and test packages document their boundaries even
when they are not application APIs.

## Public Surface And Stability

`0.5.0` is a pre-1.0 release. “Stable” below means an intentional application
surface for this release, not an ABI promise across all future versions.

| Package | Public surface | Stability | Not included |
| --- | --- | --- | --- |
| `bin_float` | `BinFloat`, `BinCoeff`, contexts, flags, interchange | Stable release surface | Complete IEEE 754 operation set |
| `decimal` | `Decimal`, contexts/flags, GDA operations, interchange | Stable release surface | Only `#` placeholder/non-scalar invalid rows are excluded |
| `ball_float` | bare/decorated intervals, relations, directed arithmetic | Stable release surface | Reverse interval operations; guaranteed tightness |
| `*_checked` | short-circuit `Result[..., ArithmeticError]` pipelines | Stable composition surface | Context flags, decorations, recovery policy |
| `semantic` | exact rational/infinity/NaN/interval projection | Provisional integration surface | Representation metadata and arithmetic |
| `numeric_expr` | syntax nodes and callback evaluation | Provisional integration surface | Text parsing and concrete numeric semantics |
| `frontend/*`, `cli/*` | conformance parsers, runners, and commands | Verification infrastructure | General-purpose file/format compatibility |
| `internal/*`, `consistency`, `*_bench` | implementation and verification helpers | Not application API | Compatibility guarantees |

Read `api.md` for callable names, `design.md` for invariants and algorithm
choices, and `tutorial.md` for the shortest supported workflow. Generated
`pkg.generated.mbti` files are the authority when prose and inventory differ.

## GDA Result

The official 144-file corpus passes **64,986/64,986 legal executable scalar
rows**, with zero unsupported and zero legacy classifications. The remaining
141 rows are all `#` placeholder/non-scalar invalid inputs and are excluded from
the legal semantic denominator. The official0 corpus likewise passes all
16,124 legal rows.

## Verification

Use `just smoke` and `just conformance smoke <backend>` for committed fixtures.
Full corpus commands and exact supported-operation boundaries live in
`testdata/*/README.md`. Passing a pinned corpus never implies complete IEEE
754, GDA, or ITF1788 coverage.
