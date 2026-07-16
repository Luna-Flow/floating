# FLOATING 0.7.1 Documentation

Use this page as an index. Public names come from each package's
`pkg.generated.mbti`; package tutorials explain recommended use, and design
pages explain standards, algorithms, optimization, and switching boundaries.

## Fast Paths

- First use: [Getting Started](./getting_started.md)
- Shared numerical vocabulary: [Numeric Semantics](./numeric_semantics.md)
- Package/layer model: [Architecture](./architecture.md)
- What is actually verified: [Verification](./verification.md)
- Documentation rules: [Documentation Standard](./doc_standard.md)
- Optimization evidence: [0.7.1 Performance And Semantic Audit](./performance_audit.md)

## Application Packages

| Need | Package | Read first | Deep reference |
| --- | --- | --- | --- |
| dyadic / IEEE binary | `bin_float` | [Tutorial](./bin_float/tutorial.md) | [API](./bin_float/api.md) · [Design](./bin_float/design.md) · [Conformance](./bin_float/conformance.md) · [Performance](./bin_float/performance.md) |
| IEEE decimal / DPD / BID | `decimal` | [Tutorial](./decimal/tutorial.md) | [API](./decimal/api.md) · [Design](./decimal/design.md) · [Conformance](./decimal/conformance.md) · [Performance](./decimal/performance.md) |
| GDA sticky status and traps | `decimal_gda` | [Tutorial](./decimal_gda/tutorial.md) | [API](./decimal_gda/api.md) · [Design](./decimal_gda/design.md) · [Conformance](./decimal_gda/conformance.md) · [Performance](./decimal_gda/performance.md) |
| certified interval / IEEE 1788 | `ball_float` | [Tutorial](./ball_float/tutorial.md) | [API](./ball_float/api.md) · [Design](./ball_float/design.md) · [Conformance](./ball_float/conformance.md) · [Performance](./ball_float/performance.md) |
| first-error binary composition | `bin_float_checked` | [Tutorial](./bin_float_checked/tutorial.md) | [API](./bin_float_checked/api.md) · [Design](./bin_float_checked/design.md) |
| accumulated IEEE decimal flags | `decimal_checked` | [Tutorial](./decimal_checked/tutorial.md) | [API](./decimal_checked/api.md) · [Design](./decimal_checked/design.md) |
| sticky/trapping GDA composition | `decimal_gda_checked` | [Tutorial](./decimal_gda_checked/tutorial.md) | [API](./decimal_gda_checked/api.md) · [Design](./decimal_gda_checked/design.md) |
| first-error interval composition | `ball_float_checked` | [Tutorial](./ball_float_checked/tutorial.md) | [API](./ball_float_checked/api.md) · [Design](./ball_float_checked/design.md) |
| shared vocabulary | `def` | [Tutorial](./def/tutorial.md) | [API](./def/api.md) · [Design](./def/design.md) |
| representation-independent observation | `semantic` | [Tutorial](./semantic/tutorial.md) | [API](./semantic/api.md) · [Design](./semantic/design.md) |

## Integration And Maintainer Packages

- Expression IR: [`numeric_expr`](./numeric_expr/api.md)
- Corpora frontends: [`frontend/gda_expr`](./frontend/gda_expr/api.md),
  [`frontend/itl_expr`](./frontend/itl_expr/api.md),
  [`frontend/mpfr_expr`](./frontend/mpfr_expr/api.md), and
  [`frontend/testfloat_expr`](./frontend/testfloat_expr/api.md)
- CLI adapters: [`cli`](./cli/api.md) and its backend subpackages
- Runtime/verification: [`internal`](./internal/api.md),
  [`internal/conformance`](./internal/conformance/api.md),
  [`internal/runner_cli`](./internal/runner_cli/api.md),
  [`consistency`](./consistency/api.md), and [`bench`](./bench/api.md)

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

Use `api.md` to find a callable name, `tutorial.md` to choose a safe workflow,
and `design.md` to understand invariants and implementation choices. Generated
`pkg.generated.mbti` files win if prose and public inventory ever disagree.
