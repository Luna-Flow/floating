# `bin_float_checked` design

## Design goal

`bin_float_checked` lets a binary floating-point computation be written as a
chain of operations in which every failure is explicit and none is lost,
without an unwrapping step after each operation. `BinFloatResult` closes
`Result[BinFloat, ArithmeticError]` under the operations of
[`bin_float`](bin_float.md): it adds no arithmetic, only composition. The
[API page](../api/bin_float_checked.md) lists the operations and the
[tutorial](../tutorial/bin_float_checked.md) shows pipelines in use.

## Mathematical background

### The error monad

Let $V$ be the set of `BinFloat` values and $E$ the set of `ArithmeticError`
values. A `BinFloatResult` is an element of the disjoint union

$$
M V = V + E = \{\, \mathrm{Ok}(x) : x \in V \,\} \cup \{\, \mathrm{Err}(e) : e \in E \,\}.
$$

$M$ is the *exception* (or *Either*) monad with the error type fixed.[^moggi]
Its unit and bind are `ok` and `bind`:

$$
\begin{aligned}
\eta(x) &= \mathrm{Ok}(x), \\
\mathrm{Ok}(x) \mathbin{>\!\!>\!\!=} f &= f(x), \\
\mathrm{Err}(e) \mathbin{>\!\!>\!\!=} f &= \mathrm{Err}(e),
\end{aligned}
$$

for $f : V \to M V$. A function $f : V \to M V$ is a *Kleisli arrow*: an
operation that may fail. Every checked operation of `bin_float`
(`BinFloat::sqrt`, `div_checked`, `try_ln_ctx`, …) and every checked trait
method of Luna-Flow/arithmetic (`SqrtChecked::sqrt_checked`,
`DivChecked::div_checked`, `PowIntChecked::pow_int_checked`, …) is such an
arrow once its non-value arguments are fixed. The wrapper turns them into
methods that take *and* return $M V$, so arrows can be chained.

`map` is the functor action, and it is bind followed by the unit:

$$
\texttt{map}(m, g) = m \mathbin{>\!\!>\!\!=} (\eta \circ g),
$$

which is exactly how the code computes it (`Result::map`). Since
$\eta \circ g$ never returns $\mathrm{Err}$, `map` cannot introduce an error.

[^moggi]: E. Moggi, "Notions of computation and monads", *Information and
    Computation* 93(1), 1991; P. Wadler, "Monads for functional programming",
    1995.

### Lifting binary operations

A binary operation $\oplus : V \times V \to M V$ (for infallible operators,
$\eta(x \oplus y)$) is lifted to $M V \times M V \to M V$ by

$$
\operatorname{lift}_{\oplus}(a, b) = a \mathbin{>\!\!>\!\!=} \bigl(x \mapsto b \mathbin{>\!\!>\!\!=} (y \mapsto x \oplus y)\bigr),
$$

which is the private helper `bin_result_lift2_checked` (and
`bin_result_lift2` for infallible $\oplus$, using `map` for the inner step).
Unfolding the definition gives the three cases the API describes:

$$
\operatorname{lift}_{\oplus}(a, b) =
\begin{cases}
\mathrm{Err}(e) & a = \mathrm{Err}(e),\\
\mathrm{Err}(e') & a = \mathrm{Ok}(x),\ b = \mathrm{Err}(e'),\\
x \oplus y & a = \mathrm{Ok}(x),\ b = \mathrm{Ok}(y).
\end{cases}
$$

`clamp` nests three binds in the order value, `min`, `max`, so it selects among
three operand errors the same way.

## Design decisions

### A closed wrapper instead of `Result` everywhere

**Problem.** `bin_float` returns `Result` from its checked operations and plain
values from its infallible ones. A computation that mixes them needs an unwrap
or a `match` after every checked step, and it is easy to drop an error by
unwrapping too early.

**Options.** (a) Ask users to write `match` chains. (b) Use MoonBit's `raise`
errors. (c) Provide a closed type whose every operation accepts the possibly
failed operands.

**Choice: (c).** Luna-Flow libraries report failures as structured `Result`
values rather than raised errors, so (b) would break the convention of the
checked traits. With (c) every operation takes `BinFloatResult` operands, so a
formula `two / (one / a + one / b)` is written with ordinary operators, and the
error of the first failing step is carried to the end. The wrapper stays a
separate type so that plain `BinFloat` keeps its IEEE meaning (`1 / 0` is
$+\infty$) in algebraic code.

### First error, not all errors

**Problem.** When both operands of an operation have failed, one error must be
returned.

**Options.** (a) Return the left error. (b) Collect both, as an applicative
validation would. (c) Return an arbitrary one.

**Choice: (a).** Collecting errors would need a monoid on `ArithmeticError`,
which the type does not have, and a list of errors would be a different type.
The left-biased choice is deterministic and agrees with how the expression is
read; the [first-error theorem](#the-first-error-theorem) below states exactly
which error a whole expression reports.

### Which context an operation uses

Operations without a context argument must pick a precision and an exponent
range. The wrapper uses the operand's own format so that a pipeline started at
some precision stays at that precision:

| Operation | Context used |
| --- | --- |
| `+`, `-`, `*`, `/`, `min`, `max` | as the `BinFloat` operator: the larger operand precision, nearest-even |
| unary elementary functions, `rootn` | `BinaryContext::unbounded(x.precision())` |
| `pow`, `hypot`, `atan2` | `BinaryContext::unbounded(max(p_x, p_y))` |
| `sqrt`, `pow_int`, `pown` | the `BinFloat` method at the operand's precision |
| `pow_nat` | `ArithmeticContext::new(x.precision())`, passed to `PowNatChecked` |
| every `*_ctx` method | the given `BinaryContext` |

`unbounded(p)` means precision $p$, round to nearest-even, and no exponent
limits, so these operations never overflow or underflow. For `pow_nat` the
wrapper goes through the Luna-Flow/arithmetic trait, and `bin_float` maps the
`ArithmeticContext` to a `BinaryContext` with
`BinaryContext::from_arithmetic_context`: the precision is copied, the
`RoundingMode` is mapped to the binary rounding attribute, and `e_min` /
`e_max` become exponent bounds when present (both absent gives
`unbounded`). The `clamp` field of `ArithmeticContext` has no binary meaning
and is not used.

### Contextual operations keep the value and drop the flags

`BinFloat::*_ctx` operations return $(v, \phi) \in V \times F$ where $F$ is the
set of `BinaryFlags`. The `_ctx` methods of the wrapper compose them with the
projection $\pi_1(v, \phi) = v$:

$$
\texttt{add\_ctx}(a, b, c) = \operatorname{lift}_{\eta \circ \pi_1 \circ \oplus_c}(a, b).
$$

This is a deliberate loss. Keeping the flags would make the wrapper a
combination of the exception monad with the writer monad on $F$, and the
binary flags would then have to be combined with operations that report none
(`map`, the plain operators). The decimal pipeline makes the opposite choice
because IEEE decimal arithmetic is usually audited by its flags; see the
[`decimal_checked` design](decimal_checked.md). As a consequence, IEEE
exceptional cases of the `_ctx` methods are successes: `div_ctx` by zero
yields $\pm\infty$, while `div` (which calls `div_checked`) fails. The two
names make the two contracts visible at the call site.

## Correctness / invariants

### The monad laws

For all $x \in V$, $m \in M V$ and Kleisli arrows $f, g$:

$$
\begin{aligned}
&\text{(left identity)} && \eta(x) \mathbin{>\!\!>\!\!=} f = f(x),\\
&\text{(right identity)} && m \mathbin{>\!\!>\!\!=} \eta = m,\\
&\text{(associativity)} && (m \mathbin{>\!\!>\!\!=} f) \mathbin{>\!\!>\!\!=} g = m \mathbin{>\!\!>\!\!=} \bigl(x \mapsto f(x) \mathbin{>\!\!>\!\!=} g\bigr).
\end{aligned}
$$

*Proof.* Left identity is the first defining equation of bind. For right
identity, case $m = \mathrm{Ok}(x)$: $\mathrm{Ok}(x) \mathbin{>\!\!>\!\!=}
\eta = \eta(x) = \mathrm{Ok}(x)$; case $m = \mathrm{Err}(e)$: both sides are
$\mathrm{Err}(e)$. For associativity, case $m = \mathrm{Err}(e)$: the left side
is $\mathrm{Err}(e) \mathbin{>\!\!>\!\!=} g = \mathrm{Err}(e)$ and the right
side is $\mathrm{Err}(e)$. Case $m = \mathrm{Ok}(x)$: both sides reduce to
$f(x) \mathbin{>\!\!>\!\!=} g$. $\square$

In code these read `BinFloatResult::ok(x).bind(f) ≡ f(x)`,
`m.bind(BinFloatResult::ok) ≡ m` and
`m.bind(f).bind(g) ≡ m.bind(x => f(x).bind(g))`, where $\equiv$ compares
`result()`. Associativity is what makes a pipeline independent of how it is
split into helper functions: a helper that chains two checked steps can be
inlined or extracted without changing the result.

The functor laws follow from $\texttt{map}(m, g) = m \mathbin{>\!\!>\!\!=}
(\eta \circ g)$:

$$
\begin{aligned}
\texttt{map}(m, \mathrm{id}) &= m \mathbin{>\!\!>\!\!=} \eta = m,\\
\texttt{map}(\texttt{map}(m, g), h) &= (m \mathbin{>\!\!>\!\!=} \eta g) \mathbin{>\!\!>\!\!=} \eta h
  = m \mathbin{>\!\!>\!\!=} (x \mapsto \eta(g x) \mathbin{>\!\!>\!\!=} \eta h)
  = m \mathbin{>\!\!>\!\!=} \eta (h \circ g) = \texttt{map}(m, h \circ g).
\end{aligned}
$$

So `normalized`, `neg`, `abs`, `ulp` and `with_precision`, which are all
`map`s, can be fused or reordered exactly as the underlying `BinFloat`
functions can.

The laws can be checked on concrete arrows; here $f$ is the checked square
root and $g$ the checked logarithm:

```moonbit
///|
test "monad laws on checked arrows" {
  let f = fn(x : @bin_float.BinFloat) { @bin_float_checked.BinFloatResult::from_result(x.sqrt()) }
  let g = fn(x : @bin_float.BinFloat) {
    @bin_float_checked.BinFloatResult::ok(x).ln()
  }
  let same = fn(a : @bin_float_checked.BinFloatResult, b : @bin_float_checked.BinFloatResult) {
    match (a.result(), b.result()) {
      (Ok(x), Ok(y)) => x == y
      (Err(e), Err(d)) => e == d
      _ => false
    }
  }
  for n in [-4, 0, 2, 9] {
    let x = @bin_float.BinFloat::from_int(n)
    let m = @bin_float_checked.BinFloatResult::ok(x)
    assert_true(same(m.bind(f), f(x)))
    assert_true(same(m.bind(@bin_float_checked.BinFloatResult::ok), m))
    assert_true(same(m.bind(f).bind(g), m.bind(y => f(y).bind(g))))
  }
}
```

### The first-error theorem

Consider an expression tree whose leaves are `BinFloatResult` values and whose
inner nodes are wrapper operations. MoonBit evaluates arguments eagerly, so
every node is evaluated. Say that a node *originates* an error when all its
children are successes and the operation itself fails (a leaf originates its
error if it is an `Err`).

**Theorem.** If any node originates an error, the expression evaluates to the
error originated by the first originating node in post-order (children left to
right, then the node). Otherwise it evaluates to the success obtained by
applying the `bin_float` operations to the leaf values.

*Proof* by induction on the tree. A leaf is immediate. For a node
$n = \operatorname{lift}_{\oplus}(t_1, t_2)$, post-order lists the nodes of
$t_1$, then those of $t_2$, then $n$. If $t_1$ contains an originating node,
by induction $t_1$ evaluates to the error $e$ of the first one, which also
comes first in the post-order of $n$, and $\operatorname{lift}_{\oplus}$
returns the left error $e$. Otherwise $t_1$ evaluates to $\mathrm{Ok}(x)$; if
$t_2$ contains an originating node, $t_2$ evaluates to the error of the first
one, and by the second case of $\operatorname{lift}_{\oplus}$ it is returned,
again matching post-order. Otherwise both are successes, $n$ originates an
error exactly when $x \oplus y$ fails, and that is the result. Unary nodes are
binds and follow from the same case analysis; `clamp` is the three-child
version. $\square$

For example, in `left + one / zero` the leaf `left` comes first in post-order,
so its error is reported, and in `one / zero + left` the division is first.
The lifted operation is therefore *not* commutative on errors even when
$\oplus$ is commutative on values: on successes
$\operatorname{lift}_{+}(\mathrm{Ok}\,x, \mathrm{Ok}\,y) = \mathrm{Ok}(x+y) =
\mathrm{Ok}(y+x)$ because rounded binary addition is commutative, but with two
errors the reported one depends on the order.

### No other invariant

The wrapper holds one `Result` and adds no state, so every invariant of
`BinFloat` (normalized coefficient, precision at least one, correctly rounded
operations) carries over unchanged to the success branch. Each wrapper step
costs $O(1)$ on top of the delegated operation.

## Alternatives rejected

- **Storing `BinaryFlags` in the wrapper.** See the decision above; flags
  belong to the `(value, flags)` APIs of `bin_float`.
- **Turning NaN results into errors.** IEEE defines NaN as a value, and
  `bin_float` already decides which cases are errors in its checked APIs; a
  second policy here would make the wrapper disagree with the checked trait
  implementations of the same type.
- **Error accumulation.** Needs a combining operation on `ArithmeticError`,
  which Luna-Flow/arithmetic does not define.
- **Implicit recovery.** There is no method that turns an error back into a
  value; recovery is the caller's decision after `result()`.

## Boundaries

- No arithmetic of its own: every numeric result comes from `bin_float`.
- No IEEE flags, no context state, no interchange encoding and no decimal
  conversion.
- No error recovery or error accumulation; only the first error is kept.
- No `Eq`, `Show` or `Compare` on the wrapper; compare through `result()`.
- The operation set is the one in the generated interface; operations of
  `bin_float` without a wrapper method are reached through `map` or `bind`.
