# decimal_checked design

## Design goal

`decimal_checked` represents a sequence of IEEE 754 decimal operations as one
value. At the end, that value reports the result and what happened during the
calculation. Each IEEE decimal operation returns `(value, flags)`.
Exceptional conditions set status flags, and a multi-step calculation needs
the flags raised by each step. `DecimalChecked` carries one context through
the steps and accumulates their flags; exceptional IEEE results remain values. The
[API page](../api/decimal_checked.md) lists the operations, and the
[tutorial](../tutorial/decimal_checked.md) shows audit-style pipelines.

## Mathematical background

### The flag monoid

`DecimalFlags` has six Boolean fields (`inexact`, `underflow`, `overflow`,
…), so a flag set is an element of $\mathbb{F} = \{0, 1\}^{6}$ or, equivalently,
a subset of $\Sigma$, the set of six flags. `DecimalFlags::combine` applies
field-wise OR:

$$
(a \lor b)_i = a_i \lor b_i \qquad (i = 1, \dots, 6),
\qquad \mathbf{0} = \texttt{DecimalFlags::new()}.
$$

Boolean OR is associative, commutative and idempotent, with identity $0$.
Since the operation applies OR independently to each field, it satisfies

$$
\begin{aligned}
(a \lor b) \lor c &= a \lor (b \lor c), &
a \lor \mathbf{0} &= \mathbf{0} \lor a = a,\\
a \lor b &= b \lor a, &
a \lor a &= a .
\end{aligned}
$$

Thus $(\mathbb{F}, \lor, \mathbf{0})$ is a commutative idempotent monoid and
a *bounded join-semilattice*. Under the subset view, $\lor$ is set union. The
accessor for flag $s$ (`inexact`, `underflow`, …)
reads coordinate $s$ and is a monoid homomorphism to $(\{0,1\}, \lor, 0)$:
$\texttt{contains}(a \lor b, s) = \texttt{contains}(a, s) \lor
\texttt{contains}(b, s)$.

### Operations as writer arrows

Fix a context $c$ and let $D$ be the set of decimal values. An IEEE operation
is a function $\mathrm{op}_c : D \to D \times \mathbb{F}$ that returns a
rounded result and its raised flags. Examples include `Decimal::add_ctx`,
`div_ctx` and `sqrt_ctx`. Such functions are the Kleisli arrows of the
*writer monad* over $\mathbb{F}$:

$$
\begin{aligned}
\eta(v) &= (v, \mathbf{0}),\\
(v, F) \mathbin{>\!\!>\!\!=} f &= (v', F \lor r) \quad\text{where } (v', r) = f(v).
\end{aligned}
$$

The monad laws follow from the monoid laws. For left identity:
$\eta(v) \mathbin{>\!\!>\!\!=} f = (v', \mathbf{0} \lor r) = f(v)$. Right
identity: $(v, F) \mathbin{>\!\!>\!\!=} \eta = (v, F \lor \mathbf{0}) =
(v, F)$. Associativity: with $f(v) = (v', r)$ and $g(v') = (v'', s)$, both
$((v, F) \mathbin{>\!\!>\!\!=} f) \mathbin{>\!\!>\!\!=} g$ and
$(v, F) \mathbin{>\!\!>\!\!=} (x \mapsto f(x) \mathbin{>\!\!>\!\!=} g)$
equal $(v'', (F \lor r) \lor s) = (v'', F \lor (r \lor s))$.[^writer]

[^writer]: P. Wadler, "Monads for functional programming", 1995 (the output
    monad); any monoid gives a writer monad, and the laws are exactly the
    monoid laws.

### The pipeline state

`DecimalChecked` stores the state
$\sigma = (v, c, r, F, \varepsilon)$: value, context, latest-step flags,
accumulated flags, and an optional error. Its private `record` step implements
writer bind, records the latest flags and does nothing after an error:

$$
\operatorname{record}(\sigma, (v', r')) =
\begin{cases}
\sigma & \varepsilon \ne \text{none},\\
(v', c, r', F \lor r', \text{none}) & \varepsilon = \text{none}.
\end{cases}
$$

`record_result` handles an operation that may fail,
$\mathrm{op}_c : D \to (D \times \mathbb{F}) + E$. For
$\mathrm{Ok}((v', r'))$, it calls `record`; for $\mathrm{Err}(e)$, it returns
$(v, c, r, F, \mathrm{Some}(e))$. The full step therefore combines the
writer monad with the exception monad, where an error absorbs later steps.

## Design decisions

### Flags are accumulated, exceptional results stay values

**Problem.** A long decimal computation must report whether *any* step
rounded, overflowed or divided by zero, and IEEE 754 defines a result for each
such step.

**Options.** (a) Turn exceptional conditions into errors, as the
Luna-Flow/arithmetic contextual traits do for division by zero and invalid
operations. (b) Return only the last step's flags. (c) Keep the IEEE value and
accumulate the flags.

**Choice: (c).** Under the IEEE model, a defined result is returned and status
flags report exceptional conditions; an audit can inspect those flags at
the end.[^ieee-flags] Option (a) would stop at $1/0$ although IEEE defines
$+\infty$. Option (b) would lose conditions raised by earlier steps. Errors
arise only in the one case where this implementation has no defined IEEE
result: a certified elementary function cannot certify its rounding. Both $r$
(`raised`) and $F$ (`flags`) are kept, so callers can inspect
the latest step and the accumulated conditions.

[^ieee-flags]: IEEE 754-2019 7 (default exception handling) and 8 (alternate
    exception handling): status flags are raised and remain raised until
    explicitly lowered.

### One context per pipeline, pipeline operands

**Problem.** A binary operation took a plain `Decimal` as its right operand.
The result could not include flags or an error from the computation that
produced that operand.

**Choice.** The right operand of a binary operation is a `DecimalChecked`, as
for `GdaDecimalChecked`. Each pipeline carries a context and a flag history.
The left pipeline's context wins. Conditions from the right pipeline join
`raised` and `flags` in the result. An error in the left pipeline stays; an
error in the right one is taken before the operation runs, and the left value
is kept.

The context changes only through `with_context`, which records the flags from
rounding the current value into the new context. Call
`DecimalChecked::from_decimal(x, ctx)` to lift a plain value; the method applies
the context. A signaling NaN lifted this way is quieted with
`invalid_operation`. A value wider than the context is rounded by the lift, so
an operand intended to enter the operation exactly is lifted in a wide
context; the operation itself uses the right value as it is.
The constructor that took a value, context and flags is private, so a caller
cannot state flags that no operation raised. For the same reason the type
implements no operators.

### Mapping a Luna-Flow/arithmetic context

The pipeline takes a `DecimalContext`. A caller holding an `ArithmeticContext`
converts it with `DecimalContext::from_arithmetic_context`, which maps

| `ArithmeticContext` | `DecimalContext` |
| --- | --- |
| `precision` | `precision` |
| `rounding` | `rounding` (`DecimalRoundingMode::from_arithmetic`; `AwayFromZero` is an `Err`) |
| `e_min`, `e_max` | `e_max` as given, `e_min` must be `1 - e_max` (alone: `e_max = 1 - e_min`), the default range of `DecimalContext::new` when absent |
| `clamp` | ignored (every IEEE format clamps) |

Before-rounding tininess detection (IEEE 754-2019 7.5) is the only rule. So the
predefined `ArithmeticContext::decimal64()` maps exactly to
`DecimalContext::decimal64()`.

The mathematical functions `exp`, `ln`, `log10` and `pow` restrict their
context to decNumber's range: precision (by default, see
`DecimalContext::elementary_precision_limit`) and both exponent limits must lie
within $999\,999$ in magnitude, otherwise the result is NaN with
`not_computed`, and the `try_` forms, which the pipeline calls, return `Err`
(private check `math_context_is_restricted` in `library/src/decimal`).
This implementation limit is `DEC_MAX_MATH`, not a rule of the GDA operation
text. decTest requires it (`power.decTest` powx4001 to powx4005 and the
matching rows of `exp`, `ln` and `log10`), and GDA's Invalid context condition
permits it.[^gda] A precision of 1,000 digits or more without an explicit
`e_max` (the default range is then beyond 999,999) therefore disables them,
which the API page and tutorial point out. `pow` and `pown` with an integral
exponent, and `pow` with exponent $0.5$ (a square root), are the exceptions in
the exponent limits: like arithmetic operations, they accept contexts up to
$\pm 999\,999\,999$; the precision limit applies to them as to the others.

[^gda]: M. Cowlishaw, *General Decimal Arithmetic Specification*, version
    1.70, "Context" (the Invalid context condition under "Exceptional
    conditions") and the decTest rows named above.

### From flags to arithmetic diagnostics

The contextual trait implementations of `Decimal` in Luna-Flow/arithmetic
report `ArithmeticDiagnostics`, six Booleans combined by
`ArithmeticDiagnostics::combine` with field-wise OR. The private helper
`contextual_diagnostics` in `library/src/decimal/traits.mbt` maps flags to
diagnostics by keeping the three shared coordinates (`inexact`, `overflow`,
`underflow`) and leaving the other three false. Let this projection be
$\pi : \mathbb{F} \to \{0,1\}^{6}$. A coordinate projection commutes with
field-wise OR:

$$
\pi(a \lor b)_j = (a \lor b)_{i_j} = a_{i_j} \lor b_{i_j} = \pi(a)_j \lor \pi(b)_j ,
\qquad \pi(\mathbf{0}) = \mathbf{0},
$$

so $\pi$ is a monoid homomorphism, and by induction

$$
\pi\Bigl(\bigvee_{i=0}^{n} r_i\Bigr) = \bigvee_{i=0}^{n} \pi(r_i).
$$

Converting the accumulated flags once at the end therefore gives the same
diagnostics as converting each step and combining them. The conditions that
the trait implementation turns into an `ArithmeticError` (division by zero
and the invalid-operation family tested by `DecimalFlags::has_error`) are not
coordinates of $\pi$. The pipeline retains them as flags.

## Correctness and invariants

### Accumulated flags are the union of per-step flags

**Theorem.** Let a pipeline be constructed with flags $r_0$ (from
`from_decimal`, `parse` or a numeric constructor) and then
undergo successful steps $1, \dots, n$ with raised flags $r_1, \dots, r_n$
(including `with_context` and `apply`), with no `clear_flags` in between and
with plain steps only (a step with a pipeline as its right operand also joins
the flags of that pipeline, `raised` with its `raised` and `flags` with its
`flags`; the `flags` of an operand can exceed its `raised`, so the equation
below then holds only with the `flags` of those operands also joined on the
right side). Then

$$
F_n = r_0 \lor r_1 \lor \dots \lor r_n, \qquad r = r_n .
$$

*Proof.* Every constructor sets $r = F = r_0$, which is the case $n = 0$.
If $F_{k} = \bigvee_{i \le k} r_i$, a successful step $k+1$ goes through
`record` (or the identical update in `with_context`) and sets
$F_{k+1} = F_k \lor r_{k+1} = \bigvee_{i \le k+1} r_i$ by associativity, and
$r = r_{k+1}$. $\square$

Commutativity and idempotence of $\lor$ mean that $F_n$ does not depend on the
order of the steps or on the number of times a signal was raised. Since `contains` is a
homomorphism,

$$
\texttt{contains}(F_n, s) \iff \exists\, i \le n : \texttt{contains}(r_i, s).
$$

This test checks the theorem on a three-step pipeline. The accumulated flags
equal the OR of each step's raised flags, regardless of the order used to
combine them.

```moonbit
///|
test "accumulated flags are the union of the raised flags" {
  let ctx = @decimal.DecimalContext::decimal64()
  let s0 = @decimal_checked.DecimalChecked::from_int(1, ctx)
  let s1 = s0.div(@decimal_checked.DecimalChecked::from_decimal(@decimal.Decimal::from_int(3), ctx))
  let s2 = s1.add(@decimal_checked.DecimalChecked::from_decimal(@decimal.Decimal::from_int(10), ctx))
  let s3 = s2.div(@decimal_checked.DecimalChecked::from_decimal(@decimal.Decimal::zero(), ctx))
  let forward = s0.raised().combine(s1.raised()).combine(s2.raised()).combine(s3.raised())
  let backward = s3.raised().combine(s2.raised()).combine(s1.raised()).combine(s0.raised())
  inspect(s3.flags() == forward, content="true")
  inspect(forward == backward, content="true")
  inspect(s3.raised().inexact(), content="false")
  inspect(s3.flags().inexact() && s3.flags().division_by_zero(), content="true")
}
```

After `clear_flags`, the theorem holds again with $r_0 = \mathbf{0}$ from that
point. $F$ is monotone along a pipeline: $F_k \subseteq F_{k+1}$.

### Errors are absorbing

**Theorem.** If a state has $\varepsilon = \mathrm{Some}(e)$, every operation
except `clear_flags` returns it unchanged. `clear_flags` changes only $r$ and
$F$.

*Proof.* `record`, `record_result` and `with_context` first check the guard
`self.error_ is None`; when it fails, they return `self`. Every arithmetic
method uses `record` or `record_result`. `clear_flags` updates only the two
flag fields. $\square$

Therefore, the first error is the one reported, the value remains that before
the failing step (and the flags too, except that a step with a pipeline operand
joins the flags of the operand), and `result()` returns $\mathrm{Err}(e)$.
Without an error, `result()` returns $\mathrm{Ok}((v, F))$, the writer monad's
output.

### Cost

A step adds one 6-field OR and a constant-size state copy to the delegated
decimal operation.

## Alternatives rejected

- **Errors for IEEE exceptions.** This conflicts with IEEE default exception
  handling and the package's purpose; contextual traits already provide that
  model for single operations.
- **Merging pipelines.** No canonical rule exists for two contexts; see the
  preceding decision.
- **Mutable flags.** Luna-Flow represents context and status as values, so an
  immutable state can be forked and compared.
- **Storing the per-step history.** The union answers the audit question at
  constant size. Callers that need a history can keep the states they need.

## Boundaries

- This package has no arithmetic of its own; every result comes from `decimal`.
- It exposes no alternate exception handling. IEEE flags never stop the
  pipeline. Stop-or-divert handling for an operation on a signal is the
  [`decimal_gda_checked`](decimal_gda_checked.md) contract.
- It has no operators, no operation that combines two contexts (the context of
  the left pipeline wins), and no implicit context changes.
- Only certification failures of elementary functions become errors. If a
  delegated operation aborts, the pipeline aborts; the state model cannot turn
  an abort into an error.
- It defines no accuracy of its own. Flags report exactly what `decimal`
  returned.
- Its context is the IEEE decimal context of `decimal`. GDA contexts that
  retain status flags belong to `decimal_gda`.
