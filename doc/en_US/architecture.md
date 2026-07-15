# Architecture

`floating` 0.7.0 is organized as explicit numerical domains surrounded by thin
composition, parsing, and verification layers. The central architectural rule
is that numerical semantics remain pure and explicit, while filesystem,
process, corpus, and benchmark effects stay at the repository edge.

## Layer Map

| Layer | Packages | Responsibility |
| --- | --- | --- |
| Shared vocabulary | `def` | classification, sign, partial order, arithmetic type reexports, minimal `Floating` trait |
| Scalar domains | `bin_float`, `decimal`, `decimal_gda` | binary, IEEE decimal, and GDA decimal values and context semantics |
| Interval domain | `ball_float` | bare/decorated outward-rounded real enclosures |
| Checked composition | `*_checked` | preserve each domain's error, flag, or trap state in a closed pipeline |
| Semantic projection | `semantic` | exact representation-independent observations |
| Syntax | `numeric_expr` | source spans, literals, primitive calls, callback evaluation |
| Format frontends | `frontend/*` | parse one corpus grammar and execute typed cases |
| Runtime adapters | `internal/conformance`, `internal/runner_cli`, `cli/*` | summaries, sharding, files, JSON/text, exit status |
| Evidence | `consistency`, `doc_examples`, `bench/*`, `tools/`, `testdata/` | laws, docs, conformance, performance, orchestration |

Package boundaries come from `moon.pkg`. Files inside one package organize
implementation concerns but do not create namespaces.

## Standard Boundaries

The repository does not implement one universal “floating value.” Each standard
surface retains its own observable state:

| Domain | Normative model represented by 0.7.0 | Operation result |
| --- | --- | --- |
| `bin_float` | declared IEEE 754-2019 binary formats/operations | value + `BinaryFlags` |
| `decimal` | declared IEEE 754-2019 decimal/interchange boundary | value + `DecimalFlags` |
| `decimal_gda` | GDA Specification 1.70 scalar operation model | `GdaOutcome` with raised flags, sticky next context, optional trap |
| `ball_float` | declared IEEE 1788-2015 bare/decorated interval boundary | enclosure, decoration/NaI, optional `BallFlags` |

This separation prevents lossy conversions such as treating a GDA trap as an
IEEE flag, treating an IEEE defined infinity as a generic error, or treating
Entire/Empty/NaI as interchangeable interval failures.

## Numeric Core Pipeline

All scalar cores use the same architectural decomposition even though their
representations and standards differ:

```text
public immutable value(s) + explicit context
  -> special-state/domain classification
  -> exact coefficient or certified interval computation
  -> one domain-owned finalization
  -> public value + explicit effect data
```

`BinFloat` stores sign, non-negative binary coefficient, exponent, precision,
and special state. `Decimal` and GDA `Decimal` independently store sign,
package-owned base-`10^9` coefficient, exponent/quantum, precision, and special
state. `BallFloat` stores two outward-rounded binary endpoints plus Empty/Entire
state; decorated intervals add decoration and NaI without changing the bare
representation.

Finalization is the semantic firewall. Coefficient kernels may compute exact
products, quotients, roots, or guards, but they do not decide standard flags,
cohorts, traps, decorations, or endpoint direction.

## Algorithm Selection Architecture

Large integer kernels use a staged selector instead of committing to one
algorithm:

```text
size + shape + target + proof preconditions
  -> inline / schoolbook / Comba
  -> Karatsuba
  -> Toom-3
  -> NTT + exact CRT reconstruction
  -> exact fallback if an advanced precondition fails
```

Division likewise moves from word and Knuth D to Burnikel-Ziegler and reciprocal
Newton where target measurements justify it. Sparse and unbalanced shapes have
separate paths because an algorithm selected only by maximum length can waste
more work on padding than it saves asymptotically.

Switch boundaries are private, target-specific policy. They are measured with
the Maremark hierarchy across dense, sparse, square, balanced, and unbalanced
datasets; boundary tests compare exact results below, at, and above every
cutoff. Native, LLVM, Wasm, Wasm-GC, and JavaScript therefore may select
different algorithms while returning the same public result.

## Certified Elementary Architecture

Elementary functions share a proof contract across the binary, decimal, and
interval stacks:

1. produce directed lower and upper enclosures at a working precision;
2. round both endpoints to the target domain;
3. accept only if target values and observable flags agree;
4. otherwise increase precision by `max(32, work / 2)`;
5. stop after 12 refinements with structured certification detail.

`bin_float` owns the scalar dyadic certificates. `ball_float` lifts these
certificates over endpoints, critical points, poles, and domains. `decimal`
and `decimal_gda` convert exact decimal inputs to directed dyadic bounds and
convert certified endpoints back through exact integer arithmetic.

Total interval APIs may widen to a mathematically safe range such as `[-1,1]`
or Entire. `try_*` APIs expose the proof/resource failure instead. Scalar
convenience APIs use the same certified path and never substitute a host
transcendental approximation.

## Context And Effect Flow

No numerical package relies on an ambient rounding mode.

- Binary and IEEE decimal contexts are immutable inputs; flags are explicit
  outputs that callers combine.
- `decimal_gda` returns a new context whose status includes current flags, then
  chooses a trap in fixed precedence.
- `BallContext` controls outward endpoint precision/exponent bounds and returns
  interval flags.
- Binary/interval checked wrappers retain the first `ArithmeticError`.
- `DecimalChecked` preserves defined IEEE results and accumulates flags while
  retaining certification errors separately.
- `GdaDecimalChecked` threads one outcome, stops on `Trapped`, and resumes only
  through an explicit defined-result transition.

These wrappers compose existing semantics; they do not invent another arithmetic
algorithm or merge incompatible effect channels.

## Parsing And Execution

`numeric_expr` contains syntax data and post-order callback evaluation. It
performs no IO and selects no numeric backend.

Each `frontend/*` package owns one external grammar:

- `gda_expr` parses `.decTest` directives/cases and executes GDA outcomes;
- `testfloat_expr` parses TestFloat vectors and binds format, rounding, tininess;
- `mpfr_expr` parses pinned MPFR square-root, power, and elementary witnesses;
- `itl_expr` parses interval test rows and classifies the declared support set.

Frontends return typed summaries. CLI packages own files, filters, shards,
rendering, and exit codes. Python tools fetch checksum-pinned data, plan tasks,
run isolated targets/processes, and aggregate results; they do not replace the
MoonBit numerical implementation.

## Stable And Internal Boundaries

The application-facing release surfaces are `def`, the concrete numeric
packages, and checked wrappers. `semantic` and `numeric_expr` are provisional
integration surfaces. Frontends are public so repository runners can compose
them, but compatibility is limited to declared corpora and generated interfaces.

`internal/*`, CLI packages, `bench/*`, `consistency`, and `doc_examples` are
implementation/verification infrastructure. A symbol may appear in
`pkg.generated.mbti` without becoming a long-term application contract; read
the package design page before depending on it.

## Invariants

- coefficient signs are independent from non-negative magnitudes;
- finite binary normalization removes only powers of two;
- decimal parsing preserves quantum until normalization/reduction is explicit;
- context finalization is the only bounded rounding/status decision point;
- interval lower bounds round downward and upper bounds round upward;
- Empty, Entire, NaI, NaN, signed zero, and infinities remain explicit states;
- fast-path/fallback selection cannot change public values or effect data;
- conformance summary counts partition selected cases and sharding is
  deterministic;
- IO, downloads, process state, and parallel scheduling stay at tooling edges.

## Extension Rule

Add behavior to the package that owns its semantics. Reuse existing arithmetic
capability traits before creating an umbrella trait. Keep kernels private,
contexts/effects explicit, and external-format parsing outside numeric values
unless the format is a stable interchange contract.

Extending a conformance surface requires coordinated parser, executor, support
classification, CLI schema, manifest, test, generated-interface, and localized
documentation changes. Parsing a new operation is not support until strict
execution has a defined comparison and reproducible evidence.
