# ball_float_checked design

## Design goal

`ball_float_checked` lets an interval computation be written as one chain of
operations in which construction mistakes and uncertifiable steps are explicit
errors, while every successful value remains a rigorous enclosure.
`BallFloatResult` closes `Result[BallFloat, ArithmeticError]` under the
operations of [`ball_float`](ball_float.md) and adds no interval algorithm.
The [API page](../api/ball_float_checked.md) lists the operations and the
[tutorial](../tutorial/ball_float_checked.md) shows pipelines in use.

## Mathematical background

### Enclosures

Write $\mathbb{IR}$ for the set of closed intervals of the real line in the
sense of IEEE 1788-2015 (set-based flavor): the empty set, bounded intervals
$[\ell, u]$, half-lines and $\mathbb{R}$ itself.[^ieee1788] A `BallFloat` $X$
denotes an element of $\mathbb{IR}$ whose finite endpoints are binary floats.
An interval operation $F$ is an *enclosure* of a real function $f$ when

$$
\{\, f(t) : t \in X \cap \operatorname{dom} f \,\} \subseteq F(X)
\qquad \text{for every } X,
$$

and likewise for binary operations. This is the fundamental theorem of interval
arithmetic in the form `ball_float` implements: evaluating a formula with
enclosures yields an enclosure of the formula's range, because enclosure is
preserved by composition. If $F$ encloses $f$ and $G$ encloses $g$, then

$$
g(f(X \cap \operatorname{dom} f) \cap \operatorname{dom} g)
\subseteq g(F(X) \cap \operatorname{dom} g)
\subseteq G(F(X)),
$$

using monotonicity of images under $\subseteq$ for the first step and the
enclosure property of $G$ for the second.[^moore]

[^ieee1788]: IEEE 1788-2015, *Standard for Interval Arithmetic*, clauses 7–10.
[^moore]: R. E. Moore, R. B. Kearfott, M. J. Cloud, *Introduction to Interval
    Analysis*, SIAM, 2009, chapter 5; van der Hoeven, "Ball arithmetic", 2009.

### The wrapper as an error monad

`BallFloatResult` is the exception monad $M V = V + E$ with $V$ the set of
`BallFloat` values and $E$ the set of `ArithmeticError` values, with
$\eta = $ `ok` and $\mathbin{>\!\!>\!\!=} = $ `bind`. The laws (left and right
identity, associativity) and the functor laws of `map` are proved in the
[`bin_float_checked` design](bin_float_checked.md#the-monad-laws); the proof is
a case analysis on $\mathrm{Ok}/\mathrm{Err}$ that does not use any property of
$V$. The operators are lifted by the same left-biased scheme
(`ball_result_lift2`), so the
[first-error theorem](bin_float_checked.md#the-first-error-theorem) applies
unchanged: an expression reports the error of the first originating node in
post-order.

## Design decisions

### What is an error and what is a value

**Problem.** An interval computation can end in four kinds of situation: the
input does not describe an interval; the operation has no meaning for an
argument (degree-zero root); the library cannot certify a tight enough
enclosure; or the true range is empty or unbounded.

**Choice.** The first three are errors; the fourth is a value.

| Situation | Outcome | Source |
| --- | --- | --- |
| NaN bound, $\ell = +\infty$, $u = -\infty$, $\ell > u$ | `DomainError` | `try_from_bounds` |
| non-finite `exact`, `from_double`, `from_float` source | `DomainError` | `try_exact`, `try_from_double`, `try_from_float` |
| `rootn` of degree $0$ | `DomainError` | `try_rootn` |
| enclosure not certifiable within budget | `CertificationFailure` | `try_*_interval`, `try_hypot` |
| range empty ($\ln$ of negatives, $1/\{0\}$) | success: empty interval | interval operation |
| range unbounded ($1/[-1,1]$) | success: entire or half-line | interval operation |

**Why.** An empty or unbounded result is the *correct* enclosure of the true
range, so turning it into an error would make the wrapper disagree with the
set-based semantics: $\ln([-1, 1]) = [-\infty, 0]$ is a sound answer, and
$\ln(\{-2\}) = \varnothing$ is the exact answer. By contrast, $[+\infty,
+\infty]$ is not a set of reals at all, and a degree-zero root is undefined for
every argument; these are mistakes of the caller. A certification failure means
that the library refuses to return a result it cannot prove, which is also not
an enclosure. Callers who consider an empty or unbounded result a failure in
their application add that rule with `bind` (see the tutorial).

### Arithmetic operators cannot fail

`add`, `sub`, `mul` and `div` lift the `BallFloat` operators with `map`, so
they never introduce an error: the four set operations always have an
enclosure in $\mathbb{IR}$ (for division, $X / Y$ is defined as the hull of
$\{ s/t : s \in X, t \in Y \setminus \{0\} \}$, empty when $Y = \{0\}$). The
only errors in an arithmetic expression are those of its leaves.

### Powers go through the arithmetic traits

`pow_nat` and `pow_int` call `PowNatChecked::pow_nat_checked` and
`PowIntChecked::pow_int_checked` of Luna-Flow/arithmetic with
`ArithmeticContext::new(x.precision())`. `BallFloat` reads only the precision
from the context (rounding direction and exponent bounds have no meaning for an
outward-rounded enclosure) and re-rounds the base and the result with
`with_precision`, which is sound but can add one ulp per side. The two traits
are implemented differently, and only one of them avoids the *dependency
problem*. $X \cdot X$ treats the two factors as independent, so for
$X = [-1, 1]$ it gives $[-1, 1]$, whereas $\{t^2 : t \in X\} = [0, 1]$.
`pow_int` uses `BallFloat::pown`, which evaluates $t \mapsto t^n$ on the
monotone pieces of one variable $t$ and returns $[0, 1]$. `pow_nat` uses binary
powering, $X^{n} = X^{\lfloor n/2 \rfloor} \cdot X^{\lfloor n/2 \rfloor}
\cdot X^{n \bmod 2}$ evaluated with interval products, so it encloses the
larger set $\{t_1 t_2 \cdots t_n : t_i \in X\}$ and returns $[-1, 1]$; both
are enclosures of $\{t^n\}$, but only `pow_int` is tight. `pow_nat(0)` starts
from $\{1\}$ without inspecting the base, so it maps an empty interval to
$\{1\}$.

### No decorations and no flags

IEEE 1788 decorations (`com`, `dac`, `def`, `trv`, `ill`) record whether a
function was defined and continuous on the input; `ball_float` provides them in
its decorated type `BallFloatDecorated`. The wrapper does not carry them, because a decoration is
information about a successful evaluation, not a failure, and combining it with
the error channel would make every `map` responsible for decoration
propagation. The same holds for `BallFlags`. Applications that need either use
`ball_float` directly.

### Construction precision

The constructors use the defaults of `ball_float` (16 bits for integers, 53 for
`Double`, 24 for `Float`, the source precision for `exact`, the larger bound
precision for `from_bounds`). All constructors round outward, so the source value is always enclosed:
`from_int` and `from_coefficient` convert the integer exactly and then round
the singleton outward, which gives a two-point interval when the integer
needs more bits than the precision.

## Correctness and invariants

- **Soundness.** If every leaf of an expression is a success enclosing the
  intended real input, and the expression evaluates to $\mathrm{Ok}(Y)$, then
  $Y$ encloses the range of the real formula over the inputs. This is the
  composition argument above together with the fact that the wrapper applies
  exactly the `ball_float` operations on successes; it inherits the few
  exceptions listed under
  [Known limitations](ball_float.md#known-limitations) (the elementary methods
  use the `try_` forms, which those exceptions mostly do not affect).
- **Error determinism.** If the expression evaluates to $\mathrm{Err}(e)$,
  then $e$ is the error of the first originating node in post-order.
- **No hidden recovery.** No method turns an error into a value, and `map`
  never turns a value into an error ($\texttt{map} = \mathbin{>\!\!>\!\!=}
  \circ\, (\eta \circ -)$).
- **Cost.** Each wrapper step adds $O(1)$ work to the interval operation it
  delegates to.

## Alternatives rejected

- **Empty results as errors.** Breaks set-based semantics and would report an
  error for $\ln([-1, 1])$ where a sound enclosure exists.
- **Carrying decorations in the wrapper.** Would duplicate the decorated API
  of `ball_float` with a second propagation rule.
- **Context variants (`exp_ctx`, …).** Enclosures are outward-rounded at the
  interval's precision; changing precision is done explicitly with
  `with_precision`, which encloses for every rounding mode (but may widen by
  one ulp per side).
- **Accumulating errors.** As for the binary wrapper, there is no combining
  operation on `ArithmeticError`.

## Boundaries

- No interval algorithm of its own; every enclosure comes from `ball_float`.
- No decorations, `BallFlags`, interval contexts or interchange formats.
- No error recovery or accumulation; only the first error is kept.
- No `Eq`, `Show`, or enclosure relations on the wrapper itself; extract the
  `BallFloat` with `result()` to test containment or ordering.
- Out-of-domain parts of an argument are ignored, not reported.
