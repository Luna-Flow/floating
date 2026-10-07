# FLOATING 0.8.0 Documentation

<!-- historical-performance-baseline: 0.7.1 -->

Use this page as an index. Public names come from each package's
`pkg.generated.mbti`; package tutorials explain recommended use, and design
pages explain standards, algorithms, optimization, and switching boundaries.

## Fast Paths

- First use: [Getting Started](./getting_started.md)
- Shared numerical vocabulary: [Numeric Semantics](./numeric_semantics.md)
- Package/layer model: [Architecture](./architecture.md)
- What is actually verified: [Verification](./verification.md)
- Documentation rules: [Repository conventions](./conventions.md)
- Optimization evidence: [0.7.1 Performance And Semantic Audit](./performance_audit.md)

## Application Packages

| Need | Package | Read first | Deep reference |
| --- | --- | --- | --- |
| dyadic / IEEE binary | `bin_float` | [Tutorial](./tutorial/bin_float.md) | [API](./api/bin_float.md) · [Design](./design/bin_float.md) · [Conformance](./conformance/bin_float.md) · [Performance](./performance/bin_float.md) |
| IEEE decimal / DPD / BID | `decimal` | [Tutorial](./tutorial/decimal.md) | [API](./api/decimal.md) · [Design](./design/decimal.md) · [Conformance](./conformance/decimal.md) · [Performance](./performance/decimal.md) |
| GDA sticky status and traps | `decimal_gda` | [Tutorial](./tutorial/decimal_gda.md) | [API](./api/decimal_gda.md) · [Design](./design/decimal_gda.md) · [Conformance](./conformance/decimal_gda.md) · [Performance](./performance/decimal_gda.md) |
| certified interval / IEEE 1788 | `ball_float` | [Tutorial](./tutorial/ball_float.md) | [API](./api/ball_float.md) · [Design](./design/ball_float.md) · [Conformance](./conformance/ball_float.md) · [Performance](./performance/ball_float.md) |
| first-error binary composition | `bin_float_checked` | [Tutorial](./tutorial/bin_float_checked.md) | [API](./api/bin_float_checked.md) · [Design](./design/bin_float_checked.md) |
| accumulated IEEE decimal flags | `decimal_checked` | [Tutorial](./tutorial/decimal_checked.md) | [API](./api/decimal_checked.md) · [Design](./design/decimal_checked.md) |
| sticky/trapping GDA composition | `decimal_gda_checked` | [Tutorial](./tutorial/decimal_gda_checked.md) | [API](./api/decimal_gda_checked.md) · [Design](./design/decimal_gda_checked.md) |
| first-error interval composition | `ball_float_checked` | [Tutorial](./tutorial/ball_float_checked.md) | [API](./api/ball_float_checked.md) · [Design](./design/ball_float_checked.md) |
| shared vocabulary | `def` | [Tutorial](./tutorial/def.md) | [API](./api/def.md) · [Design](./design/def.md) |
| representation-independent observation | `semantic` | [Tutorial](./tutorial/semantic.md) | [API](./api/semantic.md) · [Design](./design/semantic.md) |

## Integration And Maintainer Packages

- Expression IR: [`numeric_expr`](./api/numeric_expr.md)
- Corpora frontends: [`frontend/gda_expr`](./api/frontend/gda_expr.md),
  [`frontend/itl_expr`](./api/frontend/itl_expr.md),
  [`frontend/mpfr_expr`](./api/frontend/mpfr_expr.md), and
  [`frontend/testfloat_expr`](./api/frontend/testfloat_expr.md)
- CLI adapters: [`cli`](./api/cli.md) and its backend subpackages
- Runtime/verification: [`internal`](./api/internal.md),
  [`internal/conformance`](./api/internal/conformance.md),
  [`internal/runner_cli`](./api/internal/runner_cli.md),
  [`consistency`](./api/consistency.md), and [`bench`](./api/bench.md)

These packages publish generated interfaces because repository tools compose
them, but their design pages define narrower stability promises than the
application packages.

## Evidence Snapshot

- The pinned GDA `official` corpus passes **64,986/64,986 legal executable
  scalar rows**; `official0` passes 16,124/16,124. The remaining 141 `#`
  placeholder/non-scalar rows are diagnostic exclusions.
- The pinned strict ITF1788 aggregate passes 4,656/4,656 selected interval rows.
- Binary and IEEE decimal claims are operation/format matrices documented on
  their conformance pages, including pinned MPFR elementary-function evidence.

These finite results do not imply complete support for every future directive,
standard operation, or real input. Read the corresponding conformance page
before turning a result into a compatibility claim.

## Reading Rule

Use the API chapter to find a callable name, the tutorial chapter to choose a
safe workflow, and the design chapter to understand invariants and
implementation choices. The conformance and performance chapters hold the
evidence for the four numerical cores. Generated `pkg.generated.mbti` files win
if prose and public inventory ever disagree.
