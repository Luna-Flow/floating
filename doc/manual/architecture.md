# Architecture

`floating` is organized as explicit numerical domains surrounded by thin
composition, parsing and verification layers. The central rule is that
numerical semantics stay pure and explicit, while files, processes, corpora and
benchmarks stay at the edge of the repository. This guide maps the packages to
those layers, follows one operation through a numeric core, and states the
invariants every layer keeps.

## Layer map

| Layer | Packages | Responsibility |
| --- | --- | --- |
| Shared vocabulary | `def` | `Sign`, `PartialOrder`, the `Floating` trait, predicates, re-exported `arithmetic` types |
| Scalar domains | `bin_float`, `decimal`, `decimal_gda` | binary, IEEE decimal and GDA decimal values with their contexts and status |
| Interval domain | `ball_float` | bare and decorated outward-rounded real enclosures |
| Checked composition | `bin_float_checked`, `decimal_checked`, `decimal_gda_checked`, `ball_float_checked` | pipelines that keep each domain's error, flag or trap state |
| Semantic projection | `semantic` | exact, representation-independent observations |
| Syntax | `numeric_expr` | source spans, literals, primitive calls, callback evaluation |
| Format frontends | `frontend/gda_expr`, `frontend/itl_expr`, `frontend/mpfr_expr`, `frontend/testfloat_expr` | parse one external corpus grammar and execute typed cases |
| Runtime adapters | `internal`, `internal/conformance`, `internal/runner_cli`, `cli` and `cli/*` | shared helpers, summaries, sharding, files, JSON and text output, exit status |
| Evidence | `consistency`, `doc_examples`, `bench` and `bench/*`, `tools/`, `testdata/` | cross-package laws, documentation examples, benchmarks, conformance orchestration |

Package boundaries come from `moon.pkg`; files inside a package organize the
implementation but do not create namespaces. Dependencies point downward: every
numeric package depends on `def` and `internal`, `ball_float` builds on
`bin_float`, `decimal` and `decimal_gda` use `bin_float` and `ball_float` for
their certified elementary functions, the checked packages wrap their domain,
and nothing numerical depends on a frontend, a CLI or a benchmark.

## Standard boundaries

There is no universal "floating value". Each standard keeps its own observable
state:

| Domain | Normative model | Operation result |
| --- | --- | --- |
| `bin_float` | IEEE 754-2019 binary arithmetic at any precision, binary16/32/64/128 interchange | value + `BinaryFlags` |
| `decimal` | IEEE 754-2019 decimal arithmetic, decimal32/64/128 DPD and BID interchange | value + `DecimalFlags` |
| `decimal_gda` | General Decimal Arithmetic Specification 1.70, scalar operations | `GdaOutcome` with raised flags, sticky next context, optional trap |
| `ball_float` | IEEE 1788-2015 bare and decorated intervals, for the declared operation set | enclosure, decoration or NaI, optional `BallFlags` |

The separation prevents lossy conversions such as treating a GDA trap as an
IEEE flag, an IEEE infinity as a generic error, or Empty, Entire and NaI as
interchangeable interval failures. [Numeric semantics](./numeric_semantics.md)
defines each of these states.

## Numeric core pipeline

All scalar cores share one decomposition, even though their representations
and standards differ:

```text
immutable operand value(s) + explicit context
  -> special-value and domain classification
  -> exact coefficient computation, or a certified enclosure
  -> one domain-owned finalization (rounding, exponent range, status)
  -> public value + explicit status
```

`BinFloat` stores a class, a sign, a non-negative binary coefficient with no
trailing zero bits, an exponent, a precision, and NaN state (signaling bit and
payload). `Decimal` and the GDA `Decimal` each store a sign, a package-owned
base-$10^9$ coefficient, an exponent that is the quantum, a precision and the
special state. `BallFloat` stores two `BinFloat` endpoints, a precision and an
Empty marker; `BallFloatDecorated` adds a decoration without changing the bare
representation.

Finalization is the semantic firewall. Kernels may compute exact sums,
products, quotients, roots or guard and sticky bits, but only the finalizer
decides the rounded value, the cohort, the flags, the traps, the decorations
and the direction of interval endpoints. It also enforces the binary
implementation exponent range $[1 - 2^{30},\ 2^{30} - 1]$ for the leading bit:
a result outside it is classified as an overflow or an underflow according to
the rounding direction instead of being stored with a saturated exponent.

Operations whose exact value is enormous never materialize it. A far addend
collapses to a sticky bit, the IEEE remainder reduces a huge dividend modulo
$2y$ by square-and-multiply on $2^k$, rounding to an integer splits the
coefficient by shifting, and interval endpoint sums drop an addend that lies
more than $\max(65536, p)$ bits below the other to a directed sticky term. Each
shortcut feeds the finalizer exactly the round and sticky information the full
computation would.

## Algorithm selection

Large-integer kernels use a staged selector rather than one algorithm:

```text
size + shape + target + proof preconditions
  -> inline / schoolbook / Comba
  -> Karatsuba
  -> Toom-3
  -> NTT + exact CRT reconstruction
  -> exact fallback if an advanced precondition fails
```

Division likewise moves from word division and Knuth's algorithm D to
Burnikel–Ziegler and reciprocal Newton iteration where target measurements
justify it. Sparse and unbalanced operands have their own paths, because an
algorithm chosen only by the larger length can waste more on padding than it
saves asymptotically.

Crossover points are private, target-specific policy. They are measured with
the Maremark benchmark hierarchy (`bench/*`) on dense, sparse, square, balanced
and unbalanced data, and boundary tests compare exact results below, at and
above every cutoff. Native, LLVM, Wasm, Wasm-GC and JavaScript may therefore
pick different algorithms but must return the same public result.

## Certified elementary functions

Elementary functions (exponentials, logarithms, powers, roots, trigonometric,
hyperbolic and inverse functions) follow one proof contract across the binary,
decimal and interval stacks, in the style of Ziv's strategy:[^ziv]

1. Decide results that are certainly outside the context range (overflow,
   underflow) from certified bounds on $\log_2$ of the result, before any
   refinement.
2. Compute directed lower and upper enclosures $[\ell, h]$ of the exact value
   at a working precision $w = p + 64$.
3. Round both endpoints to the target. Because rounding is monotone, if
   $\operatorname{rnd}(\ell) = \operatorname{rnd}(h)$ with the same flags, every
   value in $[\ell, h]$, including the exact one, rounds to that result.
4. Otherwise increase $w$ by $\max(32, \lfloor w/2 \rfloor)$ and repeat, at
   most 12 times.
5. If no attempt agrees, `try_*` functions return a `CertificationFailure`
   with the stage, reason, precision, working precision and attempt count; the
   non-`try` functions return a defined invalid result (a quiet NaN with
   *invalid operation* in binary) and never abort.

`bin_float` owns the scalar dyadic certificates. `ball_float` lifts them over
endpoints, critical points, poles and domain boundaries. `decimal` and
`decimal_gda` convert exact decimal inputs to directed dyadic bounds, run the
binary certificate, and convert the certified endpoints back through exact
integer arithmetic; endpoints far outside the decimal range are replaced by
representatives that round identically, so no huge decimal is expanded. Total
interval functions may widen to a safe set such as $[-1, 1]$ or Entire, while
their checked forms expose the failure. No path substitutes a host `Double`
approximation.

[^ziv]: A. Ziv, "Fast evaluation of elementary mathematical functions with
    correctly rounded last bit", *ACM TOMS* 17(3), 1991. Muller et al.,
    *Handbook of Floating-Point Arithmetic*, 2nd ed., 2018, ch. 10, discusses
    the table-maker's dilemma this loop resolves.

## Decimal text conversion

`BinFloat::from_string_ctx` and `to_decimal_string_ctx` are correctly rounded
for every precision and exponent without expanding $10^{k}$ when $k$ is huge.
Parsing first decides certain overflow or underflow from a logarithmic
estimate; for small exponents it rounds the exact rational $D \cdot 10^{k}$;
for large ones it encloses $D \cdot 10^{k}$ with directed powers of ten and
widens the working precision until both ends round alike, which terminates
because no tie is possible there. Formatting finds the leading decimal exponent
from a binary estimate corrected by directed powers of ten, and
`to_shortest_string_ctx` bisects on the digit count, which is valid because
reading back is monotone in the number of digits.

## Context and status flow

No numerical package relies on an ambient rounding mode.

- Binary and IEEE decimal contexts are immutable inputs; flags are explicit
  outputs that callers `combine`.
- `decimal_gda` returns a new context whose status includes the raised flags,
  then selects at most one trap by fixed precedence.
- `BallContext` fixes the endpoint precision and exponent bounds and returns
  `BallFlags`.
- `BinFloat`, `Decimal` and GDA `Decimal` implement the contextual traits of
  `Luna-Flow/arithmetic` (`AddContextual`, …, `ExpContextual`), so generic code
  can run all three under one `ArithmeticContext`;
  `BinaryContext::from_arithmetic_context` and the decimal equivalents carry
  its precision, rounding, exponent bounds and clamp.
- `BinFloatResult` and `BallFloatResult` keep the first `ArithmeticError`.
- `DecimalChecked` keeps defined IEEE results, accumulates flags, and keeps
  certification errors separately.
- `GdaDecimalChecked` threads one outcome, stops on `Trapped`, and resumes only
  through the explicit `resume_defined` transition.

These wrappers compose existing semantics; they add no arithmetic of their own
and never merge incompatible status channels.

## Public surface and trait methods

The generated `pkg.generated.mbti` of each package is the authority for what
is public. With MoonBit 0.10, methods of a trait implementation are no longer
promoted to the type automatically: a method such as `BinFloat::to_string`,
`Decimal::add_contextual` or `BinFloat::sqrt_checked` is callable with dot
syntax only because the package declares it with `pub extend`, and the
`.mbti` then lists it as `pub fn Type::name`. A trait method that is not listed
that way is still reachable through the trait (for example
`@def.is_finite(x)` over `Floating`), but not as `x.method()`.

## Parsing and execution

`numeric_expr` holds syntax data and post-order callback evaluation. It
performs no IO and selects no numeric backend.

Each `frontend/*` package owns one external grammar:

- `gda_expr` parses `.decTest` directives and cases and executes GDA outcomes;
- `testfloat_expr` parses Berkeley TestFloat vectors and binds format,
  operation, rounding, tininess and exactness;
- `mpfr_expr` parses the pinned MPFR square-root, integer-power and
  elementary witnesses;
- `itl_expr` parses ITF1788 interval rows and classifies the declared support
  set.

Frontends return typed summaries. The `cli` packages own files, filters,
shards, rendering and exit codes, on top of `internal/conformance` (shards,
case dispositions, summaries) and `internal/runner_cli` (options, files, JSON).
Python tools under `tools/` fetch checksum-pinned data, plan tasks, run
isolated targets and processes, and aggregate results; they never replace the
MoonBit implementation.

## Stability boundaries

The application surface is `def`, the four numeric packages and the four
checked wrappers. `semantic` and `numeric_expr` are provisional integration
surfaces. Frontends are public so that repository runners can compose them,
but their compatibility promise is limited to the declared corpora.

`internal` and `internal/*`, `cli` and `cli/*`, `bench` and `bench/*`,
`consistency` and `doc_examples` are implementation and verification
infrastructure. A symbol may appear in `pkg.generated.mbti` without becoming a
long-term application contract; read the package's design page before
depending on it.

## Invariants

- The sign of a value is independent of its non-negative coefficient.
- Finite binary normalization removes only factors of two.
- Decimal parsing preserves the quantum until a normalizing or reducing
  operation is called explicitly.
- Context finalization is the only place where a bounded result is rounded and
  status is decided.
- Interval lower endpoints round toward $-\infty$ and upper endpoints toward
  $+\infty$.
- Empty, Entire, NaI, NaN, signed zero and the infinities stay explicit
  states.
- A finite result never carries an exponent outside the implementation range.
- Fast paths and fallbacks cannot change public values or status.
- Conformance summaries partition the selected cases, and sharding is
  deterministic.
- IO, downloads, process state and parallel scheduling stay in the tooling.

## Extension rule

Add behaviour to the package that owns its semantics. Reuse the capability
traits of `Luna-Flow/arithmetic` and `Luna-Flow/luna-generic` before creating
an umbrella trait. Keep kernels private, contexts and status explicit, and
external-format parsing outside the numeric types unless the format is a
stable interchange contract. Promote a new trait method to dot syntax with
`pub extend` when it belongs to the type's public surface.

Extending a conformance surface needs coordinated changes to the parser,
executor, support classification, CLI schema, corpus manifest, tests,
generated interfaces and documentation. Parsing a new operation is not support
until strict execution has a defined comparison and reproducible evidence; see
[verification](./verification.md).
