# Architecture

`floating` is organized as explicit numerical domains surrounded by thin
composition, parsing, and verification layers. The architecture keeps pure
numeric transformations separate from filesystem, process, and corpus effects.

## Layer Map

| Layer | Packages | Responsibility |
| --- | --- | --- |
| Shared vocabulary | `def` | Classification, sign, partial order, reexported arithmetic types, minimal `Floating` trait |
| Scalar domains | `bin_float`, `decimal`, `decimal_gda` | Binary, IEEE decimal, and GDA decimal semantics |
| Interval domain | `ball_float` | Bare and decorated outward-rounded enclosures |
| Checked composition | `bin_float_checked`, `decimal_checked`, `ball_float_checked` | Closed short-circuit pipelines over `ArithmeticError` |
| Semantic projection | `semantic` | Exact representation-independent observations |
| Syntax | `numeric_expr` | Source spans, literals, primitive calls, callback evaluation |
| Format frontends | `frontend/*` | Parse a corpus format and execute typed cases |
| Runtime adapters | `internal/conformance`, `internal/runner_cli`, `cli/*` | Shared summaries, sharding, files, JSON, exit codes |
| Verification | `consistency`, `doc_examples`, `*_bench`, `tools/`, `testdata/` | Laws, executable docs, performance, corpus orchestration |

Package boundaries come from `moon.pkg`. File names inside a package organize
implementation concerns but do not create namespaces.

## Numeric Cores

`BinFloat` stores an independent sign, a non-negative `BinCoeff`, a binary
exponent, precision, and special-value state. Non-JS targets use a private
inline/limb coefficient kernel; JS uses a hidden host-`bigint` adapter with the
same public contract.

`Decimal` stores sign, a private decimal coefficient, base-10 exponent,
precision, cohort information, and special-value state. The coefficient kernel
uses target-calibrated multiplication and division dispatch, while public
behavior is defined by decimal value, quantum, context, and flags rather than
by limb layout.

`BallFloat` stores lower and upper binary endpoints plus Empty/Entire state.
Directed rounding produces an enclosure. `BallFloatDecorated` adds IEEE 1788
decorations and NaI without changing the bare interval representation.

## Context And Effect Flow

Ordinary arithmetic is a pure value transformation. Contextual arithmetic is
also pure: a context is explicit input, and the result plus flags are explicit
output. No package relies on ambient rounding state.

```text
value(s) + immutable context
          -> classify special states
          -> exact or guarded finite computation
          -> one bounded-format finalization
          -> rounded value + operation flags
```

`decimal_gda` adds immutable state threading. Each operation combines newly
raised flags into the context's sticky status and selects the highest-priority
enabled trap. The returned context must be passed to the next operation if the
caller wants status accumulation.

Checked wrappers form a different effect channel: they retain the first
`ArithmeticError` and skip later operations. They do not accumulate IEEE flags,
GDA status, decorations, or a recovery policy.

## Parsing And Execution

`numeric_expr` contains only syntax data and post-order callback evaluation.
It performs no IO and chooses no numeric backend.

Each `frontend/*` package owns one external grammar:

- `gda_expr` parses `.decTest` directives and cases, then executes GDA rows;
- `testfloat_expr` parses TestFloat vectors and binds function/rounding/tininess;
- `mpfr_expr` parses pinned MPFR square-root and integer-power data;
- `itl_expr` parses interval test language rows and classifies support.

Frontends return typed summaries. CLI packages read files, select shards or
filters, serialize JSON/text, and map summary state to process status. Python
tools fetch pinned data, plan tasks, run multiple processes/targets, and
aggregate results; they do not replace the MoonBit numerical implementation.

## Stable And Internal Boundaries

The application-facing release surfaces are `def`, the concrete numeric
packages, and the checked wrappers. `semantic` and `numeric_expr` are
provisional integration surfaces. Frontends are public so repository runners
can compose them, but their compatibility promise is limited to the declared
corpora and generated interfaces.

`internal/*`, CLI packages, benchmark packages, `consistency`, and
`doc_examples` are implementation or verification infrastructure. A symbol can
appear in `pkg.generated.mbti` and still be outside the stable application
contract; consult the package design page before depending on it.

## Invariants

- Coefficient signs are independent from non-negative magnitudes.
- Finite normalized forms remove only representation redundancy and preserve
  mathematical value.
- Decimal parsing may preserve cohort/quantum until normalization is explicit.
- Context finalization is the only point that applies bounded precision,
  exponent, clamp, and status policy.
- Interval lower bounds round downward and upper bounds round upward.
- Empty, Entire, NaI, NaN, and infinities remain explicit states.
- Summary counts partition selected corpus cases; sharding is deterministic.
- IO, process state, downloads, and parallel scheduling stay at tooling edges.

## Extension Rules

Add behavior to the package that owns its semantics. Reuse existing arithmetic
capability traits before creating a new umbrella trait. Keep numeric kernels
private, context and flags explicit, and format parsing outside concrete value
types unless the format is part of that type's stable interchange contract.

When extending a conformance surface, update the parser model, executor,
support classification, CLI schema, corpus manifest, tests, and localized docs
together. A newly parsed operation is not “supported” until strict execution
has a defined result comparison and reproducible evidence.

