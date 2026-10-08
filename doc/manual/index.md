# floating

`Luna-Flow/floating` is arbitrary-precision floating-point arithmetic for
MoonBit: binary values with IEEE 754 semantics at any precision, IEEE 754 and
General Decimal Arithmetic decimals, and certified interval (ball) arithmetic
following IEEE 1788. Precision, rounding, exponent range, special values,
status flags, traps and enclosures are explicit values in every API rather
than hidden global state. This manual documents the current branch; the
current release is `0.8.0`.

## Install

```sh
moon add Luna-Flow/floating@0.8.0
```

Then import the packages you need in your `moon.pkg`, for example
`"Luna-Flow/floating/bin_float"`. The module needs the MoonBit toolchain 0.10
or later (`moonc` ≥ 0.10). It depends on `Luna-Flow/arithmetic` (rounding
modes, contexts, checked and contextual traits) and `Luna-Flow/luna-generic`
(algebraic traits); add `Luna-Flow/arithmetic` yourself when you name its
types. [Getting started](./getting_started.md) walks through the first
program.

## Guides

| Guide | Read it for |
| --- | --- |
| [Getting started](./getting_started.md) | choosing a package, installing, first values, contexts and failure models |
| [Numeric semantics](./numeric_semantics.md) | the shared vocabulary: exact value and rounded result, rounding functions, ulp and unit roundoff, flags, quantum, signed zero, NaN, enclosures |
| [Architecture](./architecture.md) | package layers, the numeric core pipeline, certified elementary functions, invariants |
| [Verification](./verification.md) | the gates, the published conformance claims and how to reproduce them |
| [Performance audit](./performance_audit.md) | proofs and evidence for the optimized arithmetic paths |
| [Repository conventions](./conventions.md) | documentation rules and the review checklist |

## Package map

Each package has a tutorial (how to use it), an API reference (what you can
call) and a design page (why it works this way). The four numerical cores also
have conformance and performance pages.

### Numerical cores

| Package | Purpose | Pages |
| --- | --- | --- |
| `bin_float` | arbitrary-precision binary floating point, IEEE 754 binary operations and binary16/32/64/128 interchange | [tutorial](./tutorial/bin_float.md) · [API](./api/bin_float.md) · [design](./design/bin_float.md) · [conformance](./conformance/bin_float.md) · [performance](./performance/bin_float.md) |
| `decimal` | IEEE 754 arbitrary-precision decimal with per-operation flags and DPD/BID interchange | [tutorial](./tutorial/decimal.md) · [API](./api/decimal.md) · [design](./design/decimal.md) · [conformance](./conformance/decimal.md) · [performance](./performance/decimal.md) |
| `decimal_gda` | General Decimal Arithmetic with sticky status and traps | [tutorial](./tutorial/decimal_gda.md) · [API](./api/decimal_gda.md) · [design](./design/decimal_gda.md) · [conformance](./conformance/decimal_gda.md) · [performance](./performance/decimal_gda.md) |
| `ball_float` | outward-rounded bare and decorated intervals (IEEE 1788) | [tutorial](./tutorial/ball_float.md) · [API](./api/ball_float.md) · [design](./design/ball_float.md) · [conformance](./conformance/ball_float.md) · [performance](./performance/ball_float.md) |

### Composition and shared vocabulary

| Package | Purpose | Pages |
| --- | --- | --- |
| `def` | `Sign`, `PartialOrder`, the `Floating` trait, predicates and re-exported `arithmetic` types | [tutorial](./tutorial/def.md) · [API](./api/def.md) · [design](./design/def.md) |
| `bin_float_checked` | binary pipelines that stop at the first error | [tutorial](./tutorial/bin_float_checked.md) · [API](./api/bin_float_checked.md) · [design](./design/bin_float_checked.md) |
| `decimal_checked` | IEEE decimal pipelines that accumulate flags | [tutorial](./tutorial/decimal_checked.md) · [API](./api/decimal_checked.md) · [design](./design/decimal_checked.md) |
| `decimal_gda_checked` | GDA pipelines that thread status and stop at traps | [tutorial](./tutorial/decimal_gda_checked.md) · [API](./api/decimal_gda_checked.md) · [design](./design/decimal_gda_checked.md) |
| `ball_float_checked` | interval pipelines that stop at the first error | [tutorial](./tutorial/ball_float_checked.md) · [API](./api/ball_float_checked.md) · [design](./design/ball_float_checked.md) |
| `semantic` | exact, representation-independent projection for cross-package comparison | [tutorial](./tutorial/semantic.md) · [API](./api/semantic.md) · [design](./design/semantic.md) |

### Expressions and corpus frontends

| Package | Purpose | Pages |
| --- | --- | --- |
| `numeric_expr` | host-independent numeric expression syntax and evaluation | [tutorial](./tutorial/numeric_expr.md) · [API](./api/numeric_expr.md) · [design](./design/numeric_expr.md) |
| `frontend/gda_expr` | parse and execute GDA `.decTest` files | [tutorial](./tutorial/frontend/gda_expr.md) · [API](./api/frontend/gda_expr.md) · [design](./design/frontend/gda_expr.md) |
| `frontend/itl_expr` | parse and execute ITF1788 interval test rows | [tutorial](./tutorial/frontend/itl_expr.md) · [API](./api/frontend/itl_expr.md) · [design](./design/frontend/itl_expr.md) |
| `frontend/mpfr_expr` | parse and execute pinned MPFR witnesses | [tutorial](./tutorial/frontend/mpfr_expr.md) · [API](./api/frontend/mpfr_expr.md) · [design](./design/frontend/mpfr_expr.md) |
| `frontend/testfloat_expr` | parse and execute Berkeley TestFloat vectors | [tutorial](./tutorial/frontend/testfloat_expr.md) · [API](./api/frontend/testfloat_expr.md) · [design](./design/frontend/testfloat_expr.md) |

### Conformance command line

| Package | Purpose | Pages |
| --- | --- | --- |
| `cli` | native dispatcher for the four conformance backends | [tutorial](./tutorial/cli.md) · [API](./api/cli.md) · [design](./design/cli.md) |
| `cli/gda_expr_cli` | file and output adapter for `.decTest` runs | [tutorial](./tutorial/cli/gda_expr_cli.md) · [API](./api/cli/gda_expr_cli.md) · [design](./design/cli/gda_expr_cli.md) |
| `cli/itl_expr_cli` | file and JSON adapter for ITF1788 runs | [tutorial](./tutorial/cli/itl_expr_cli.md) · [API](./api/cli/itl_expr_cli.md) · [design](./design/cli/itl_expr_cli.md) |
| `cli/mpfr_expr_cli` | command adapter for MPFR witness runs | [tutorial](./tutorial/cli/mpfr_expr_cli.md) · [API](./api/cli/mpfr_expr_cli.md) · [design](./design/cli/mpfr_expr_cli.md) |
| `cli/testfloat_expr_cli` | command adapter for TestFloat runs | [tutorial](./tutorial/cli/testfloat_expr_cli.md) · [API](./api/cli/testfloat_expr_cli.md) · [design](./design/cli/testfloat_expr_cli.md) |

### Infrastructure and evidence

| Package | Purpose | Pages |
| --- | --- | --- |
| `internal` | shared exact-rational, big-integer, parsing, normalization and rounding helpers | [tutorial](./tutorial/internal.md) · [API](./api/internal.md) · [design](./design/internal.md) |
| `internal/conformance` | source locations, deterministic shards, case dispositions and summaries | [tutorial](./tutorial/internal/conformance.md) · [API](./api/internal/conformance.md) · [design](./design/internal/conformance.md) |
| `internal/runner_cli` | shared CLI options, files, diagnostics and JSON | [tutorial](./tutorial/internal/runner_cli.md) · [API](./api/internal/runner_cli.md) · [design](./design/internal/runner_cli.md) |
| `consistency` | white-box cross-package laws and API audits | [tutorial](./tutorial/consistency.md) · [API](./api/consistency.md) · [design](./design/consistency.md) |
| `doc_examples` | executable documentation examples run by `just docs` | [tutorial](./tutorial/doc_examples.md) · [API](./api/doc_examples.md) · [design](./design/doc_examples.md) |
| `bench` | shared Maremark benchmark infrastructure | [tutorial](./tutorial/bench.md) · [API](./api/bench.md) · [design](./design/bench.md) |
| `bench/bin_float` | binary arithmetic and elementary-function benchmarks | [tutorial](./tutorial/bench/bin_float.md) · [API](./api/bench/bin_float.md) · [design](./design/bench/bin_float.md) |
| `bench/decimal` | IEEE decimal benchmarks | [tutorial](./tutorial/bench/decimal.md) · [API](./api/bench/decimal.md) · [design](./design/bench/decimal.md) |
| `bench/decimal_gda` | GDA decimal benchmarks | [tutorial](./tutorial/bench/decimal_gda.md) · [API](./api/bench/decimal_gda.md) · [design](./design/bench/decimal_gda.md) |
| `bench/ball_float` | interval arithmetic benchmarks | [tutorial](./tutorial/bench/ball_float.md) · [API](./api/bench/ball_float.md) · [design](./design/bench/ball_float.md) |

The application surface is the numerical cores, `def` and the checked
wrappers; `semantic` and `numeric_expr` are provisional integration surfaces.
The other packages publish interfaces because repository tools compose them,
and their design pages state narrower stability promises.

## Reading paths

- **New to the library.** Read [getting started](./getting_started.md), then
  the tutorial of the package you chose, for example the
  [`bin_float` tutorial](./tutorial/bin_float.md) or the
  [`decimal` tutorial](./tutorial/decimal.md). Keep
  [numeric semantics](./numeric_semantics.md) open for the vocabulary.
- **Using it in an application or library.** Read
  [numeric semantics](./numeric_semantics.md) once, then work from the API
  pages of your packages. Before you rely on a standard behaviour, check the
  matching conformance page; for pipelines, read the tutorial of the checked
  wrapper.
- **Contributing.** Read [architecture](./architecture.md),
  [verification](./verification.md) and the
  [repository conventions](./conventions.md), then the design page of the
  package you change. Changes to an optimized path also need the
  [performance audit](./performance_audit.md) and the package's performance
  page.

## Evidence snapshot

- The pinned GDA `official` corpus passes **64,986/64,986 legal executable
  scalar rows**, and `official0` passes 16,124/16,124. The 141 `#` placeholder
  or non-scalar rows are diagnostic exclusions.
- The binary TestFloat level-1 matrix passes 254,227,872 vectors across
  binary16/32/64/128, including fused multiply-add, remainder, round to
  integral, integer conversions and the comparison predicates, plus pinned
  MPFR square-root and elementary-function witnesses.
- The strict ITF1788 aggregate passes 4,656/4,656 selected interval cases.
- The IEEE decimal gate covers decimal32/64/128 DPD and BID encodings, flags
  and arithmetic on four targets.

These finite results do not imply support for every operation, every future
corpus revision or every real input. Read the conformance page of a package
before turning a result into a compatibility claim.

## Authority

`pkg.generated.mbti` defines what is public, and source and tests define
behaviour; if a page and the generated interface disagree, the interface wins.
