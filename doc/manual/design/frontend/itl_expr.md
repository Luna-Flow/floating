# frontend/itl_expr design

## Design goal

The ITF1788 project publishes interval test cases for IEEE 1788-2015[^ieee1788]
in a small language, ITL. This package executes those cases against
`ball_float`, so that the interval claims in the
[ball_float conformance page](../../conformance/ball_float.md) rest on an
external, pinned corpus. Like the other frontends it is pure: text in,
results out, no IO.

[^ieee1788]: IEEE Std 1788-2015, *IEEE Standard for Interval Arithmetic*. The
    set-based flavor, decorations (clause 8) and the overlap relation (clause
    10.6.4) are the parts exercised here.

## Mathematical background

### Intervals and tightest results

In the set-based model an interval is a closed connected subset of
$\mathbb{R}$: the empty set, the whole line, or $[a, b]$ with
$-\infty \le a \le b \le +\infty$ (infinite ends are open). For an operation
$f$ and intervals $X_1, \dots, X_n$, the *range* is
$f(X_1, \dots, X_n) = \{ f(x_1, \dots, x_n) : x_i \in X_i \}$ over the points
where $f$ is defined. In a number format $\mathbb{F}$ (here binary64) the
*tightest* result is the smallest $\mathbb{F}$-interval containing the hull of
the range:

$$
\operatorname{tight}_{\mathbb{F}}(f, X) =
\Bigl[\, \max\{ a \in \mathbb{F} : a \le \inf f(X) \},\;
         \min\{ b \in \mathbb{F} : b \ge \sup f(X) \} \,\Bigr].
$$

ITF1788 cases list this tightest interval as the expected value for the
operations IEEE 1788 requires to be tightest. A test that compares bounds for
equality therefore checks two things at once: *containment* (the result
encloses the range) and *tightness* (no bound is one or more ulps too wide).

### Decorations

A decorated interval is a pair $(X, d)$ with $d$ in the chain
$\mathsf{com} > \mathsf{dac} > \mathsf{def} > \mathsf{trv} > \mathsf{ill}$,
recording what is known about the evaluation that produced $X$ (for example,
$\mathsf{com}$: defined and continuous on a bounded box with a bounded
result). NaI ("not an interval") is the decorated empty set with
$\mathsf{ill}$. Operations propagate decorations by taking the minimum of the
inputs' decorations and the decoration of the operation on that box.

### Overlap states

The overlap relation of two intervals has sixteen values: the thirteen
relations of Allen's interval algebra for two nonempty intervals (`before`,
`meets`, `overlaps`, `starts`, `containedBy`, `finishes`, `equals` and their
converses) and three values for empty arguments. The package also maps a
NaI argument to `undefined`.

### The pass rule

For an interval-valued case with actual result $(A, d_A)$ and expected
$(E, d_E)$, the case passes when

$$
\bigl(A = \text{NaI} \wedge E = \text{NaI}\bigr) \;\vee\;
\Bigl( \operatorname{sets}(A, E) \wedge
\bigl(\text{no `\_` in the expected text} \vee d_A = d_E\bigr) \Bigr),
$$

where $\operatorname{sets}(A, E)$ holds when both are empty or both are
nonempty with $\inf A = \inf E$ and $\sup A = \sup E$, comparing bounds
numerically (`BinFloat::compare == 0`, so $-0 = +0$, as in IEEE 1788 where
intervals are sets of reals). A number-valued case passes when the actual
number compares equal to the expected bound; a boolean case when the booleans
are equal; an overlap case when the state names are equal.

## Design decisions

### Execute against the public `ball_float` API

Each ITL operation maps to one public method of
`@ball_float.BallFloatDecorated` (for example `add` to `+`, `sqrt` to
`sqrt_interval`, `pown` to `pown`, `overlap` to `overlap_state`), and
results are rounded with `BallContext::binary64()`. Testing through the
public API means the corpus checks exactly what users call, including the
decoration logic.

### Reading bounds

Hexadecimal bounds `0x…p…` are parsed exactly as an integer significand and a
binary exponent, then rounded to the working precision. Decimal bounds are
parsed as a decimal with $2p + 16$ digits and converted to binary with one
rounding to nearest-even at $p$ bits. For a literal with at most $2p + 16$
significant digits the decimal parse is exact, so the bound is rounded once.
A longer literal is rounded twice, and the second rounding can then land on
the wrong side of a binary midpoint; the decimal expansion of a binary64
midpoint can have hundreds of digits, so this needs a literal with more than
$2p + 16 = 122$ significant digits, which ITF1788 data does not use.
Rounding to nearest rather than outward is a simplification: it is exact for
bounds that are binary64 numbers, but a decimal bound such as `0.1` is read as
the nearest binary64 number, which may lie inside or outside the interval the
literal denotes.

### Decorations only when the case states one

ITL writes undecorated expectations (`[4.0,6.0]`) for the set-based tests and
decorated ones (`[4.0,6.0]_com`) for the decoration tests. The executor parses
an undecorated literal as $\mathsf{com}$ but compares decorations only when the
expected text contains `_`, so set-based cases are not failed by the decoration
the implementation attaches.

### Three dispositions and a strict summary

`Unsupported` marks cases the library does not implement (unknown operations
such as the reverse operations `mulRevToPair`, or, in the binary dispatch, an
expectation with a `signal` annotation). `Diagnostic` marks cases whose data
cannot be read. The classification is made by the dispatch path, not by the
operation alone: the generic binary path reads the operands before it looks
the operation up, so an unknown operation with a non-interval operand
(`nums2interval 1.0 2.0`, `rootn [1.0,8.0] 3`) becomes a `Diagnostic`, and a
`signal` annotation on a unary, ternary, numeric or integer-power case makes
its expected value unreadable and therefore a `Diagnostic` as well.
`RunSummary::success` fails on any failed case *and* on any diagnostic,
because unreadable data in a pinned corpus is a defect of the parser or the
corpus, not an excluded feature. Unsupported cases do not fail `success`; the
CLI's `--strict-supported` turns them into a failing exit code for the phases
that claim full support.

## Correctness and invariants

**Counter identities.** Every result has exactly one disposition, so
$\text{total} = \text{executable} + \text{unsupported} + \text{diagnostic}$
and $\text{executable} = \text{passed} + \text{failed}$.

**Soundness of a pass.** If an interval-valued case passes, the actual bounds
equal the expected bounds. When the expected value is the tightest
binary64 enclosure, the actual result is then both an enclosure of the range
and tightest; when the corpus only promises an enclosure (accurate rather
than tightest operations), a pass shows that the implementation reached the
same bounds.

**Determinism.** Parsing and execution depend only on the text and
`precision`; results do not depend on the order in which cases are executed,
so a caller may filter or reorder cases freely.

**Totality.** Every completed statement becomes a case or a parse diagnostic,
and `execute_case` never aborts on case content: every unreadable input is
reported through a disposition. Statement boundaries come only from a line
ending in `;`, so a line with a trailing `//` comment is not a boundary and
merges with the next statement into one case with an unreadable expected
value; the number of cases is then lower than the number of statements.

## Alternatives rejected

- **Containment-only checking** ($E \subseteq A$). It would accept results that
  are many ulps too wide and hide accuracy regressions.
- **Always comparing decorations.** It would fail set-based cases on the
  default decoration, although those cases make no decoration claim.
- **Treating signals as passes.** IEEE 1788 signals (for example
  `UndefinedOperation`) are not observable through the current API, so such
  cases are reported as not executed rather than silently passed.

## Boundaries

- Reverse operations, `mulRevToPair`, string conversions and exception
  signals are not executed.
- Decimal bounds are rounded to nearest, not outward.
- Interval results are always rounded to binary64; `precision` only affects
  how bounds are read.
- Comments are recognized only at the start of a line: `/*` opens a block
  comment only there, and a trailing `// …` after `;` merges the statement
  with the next one.
- Unknown operations with non-interval operands are diagnostics, not
  unsupported cases, and therefore fail `RunSummary::success`.
- No file IO and no operation filtering; both are in
  [`cli/itl_expr_cli`](../cli/itl_expr_cli.md).
