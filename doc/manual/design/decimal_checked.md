# decimal_checked design

## Design goal

`decimal_checked` turns a sequence of IEEE 754 decimal operations into one
value that answers two questions at the end: *what is the result* and *what
happened on the way*. IEEE decimal arithmetic reports exceptional conditions as
status flags next to a defined result; a single operation returns
`(value, flags)`, but a calculation of many steps needs the flags of every step.
`DecimalChecked` threads one context through the steps and accumulates the
flags, while keeping the IEEE rule that exceptional results are values. The
[API page](../api/decimal_checked.md) lists the operations; the
[tutorial](../tutorial/decimal_checked.md) shows audit-style pipelines.

## Mathematical background

### The flag monoid

`DecimalFlags` has thirteen Boolean fields (`inexact`, `rounded`, `overflow`,
…), so a flag set is an element of $\mathbb{F} = \{0, 1\}^{13}$, or
equivalently a subset of the set $\Sigma$ of the thirteen signals.
`DecimalFlags::combine` is the field-wise OR:

$$
(a \lor b)_i = a_i \lor b_i \qquad (i = 1, \dots, 13),
\qquad \mathbf{0} = \texttt{DecimalFlags::new()}.
$$

Because Boolean OR is associative, commutative and idempotent with identity
$0$, and the operations act field by field,

$$
\begin{aligned}
(a \lor b) \lor c &= a \lor (b \lor c), &
a \lor \mathbf{0} &= \mathbf{0} \lor a = a,\\
a \lor b &= b \lor a, &
a \lor a &= a .
\end{aligned}
$$

So $(\mathbb{F}, \lor, \mathbf{0})$ is a commutative idempotent monoid, a
*bounded join-semilattice*; under the subset reading, $\lor$ is union.
`DecimalFlags::contains(s)` reads coordinate $s$, and it is a monoid
homomorphism to $(\{0,1\}, \lor, 0)$:
$\texttt{contains}(a \lor b, s) = \texttt{contains}(a, s) \lor
\texttt{contains}(b, s)$.

### Operations as writer arrows

An IEEE operation under a fixed context $c$ is a function
$\mathrm{op}_c : D \to D \times \mathbb{F}$ on decimal values $D$, returning
the rounded result and the flags it raised (`Decimal::add_ctx`,
`div_ctx`, `sqrt_ctx`, …). Such functions are the Kleisli arrows of the
*writer monad* over $\mathbb{F}$:

$$
\begin{aligned}
\eta(v) &= (v, \mathbf{0}),\\
(v, F) \mathbin{>\!\!>\!\!=} f &= (v', F \lor r) \quad\text{where } (v', r) = f(v).
\end{aligned}
$$

The monad laws reduce to the monoid laws. Left identity:
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

`DecimalChecked` stores $\sigma = (v, c, r, F, \varepsilon)$: value, context,
flags of the latest step, accumulated flags, and an optional error. The private
`record` step is the writer bind, extended with the latest flags and guarded by
the error:

$$
\operatorname{record}(\sigma, (v', r')) =
\begin{cases}
\sigma & \varepsilon \ne \text{none},\\
(v', c, r', F \lor r', \text{none}) & \varepsilon = \text{none}.
\end{cases}
$$

`record_result` handles operations that may fail,
$\mathrm{op}_c : D \to (D \times \mathbb{F}) + E$: on $\mathrm{Ok}((v', r'))$
it is `record`, and on $\mathrm{Err}(e)$ it returns
$(v, c, r, F, \mathrm{Some}(e))$. So the full step is the writer monad stacked
on the exception monad, with the error absorbing.

## Design decisions

### Flags are accumulated, exceptional results stay values

**Problem.** A long decimal computation must report whether *any* step
rounded, overflowed or divided by zero, and IEEE 754 defines a result for each
such step.

**Options.** (a) Turn exceptional conditions into errors, as the
Luna-Flow/arithmetic contextual traits do for division by zero and invalid
operations. (b) Return only the last step's flags. (c) Keep the IEEE value and
accumulate the flags.

**Choice: (c).** The IEEE model is that computation continues with a defined
result and the status flags say what happened; an audit inspects the flags at
the end.[^ieee-flags] Option (a) would stop at $1/0$ although IEEE defines
$+\infty$; option (b) loses earlier conditions. Errors are reserved for the one
case where no defined IEEE result exists in this implementation: a certified
elementary function that cannot certify its rounding. Keeping both $r$
(`raised`) and $F$ (`flags`) lets a caller see the latest step and the whole
history.

[^ieee-flags]: IEEE 754-2019, clause 7 (default exception handling) and
    clause 8 (alternate exception handling): status flags are raised and remain
    raised until explicitly lowered.

### One context per pipeline, plain operands

**Problem.** A binary operation could take another pipeline as its operand.

**Choice.** Operands are plain `Decimal` values. Two pipelines carry two
contexts and two flag histories; merging them would need a rule for which
context wins, and the union of histories would hide which side raised a flag.
With plain operands the pipeline is a single linear history under one context,
and the context changes only through `with_context`, which records the flags of
rounding the current value into the new context. For the same reason the type
implements no operators.

### Mapping a Luna-Flow/arithmetic context

The pipeline takes a `DecimalContext`. A caller holding an `ArithmeticContext`
converts it with `DecimalContext::from_arithmetic_context`, which maps

| `ArithmeticContext` | `DecimalContext` |
| --- | --- |
| `precision` | `precision` |
| `rounding` | `rounding`, and `decimal_rounding = DecimalRoundingMode::from_arithmetic(rounding)` |
| `e_min`, `e_max` | the same, or $\mp 999\,999\,999$ when absent |
| `clamp` | `clamp` |

with `extended = true` and after-rounding tininess detection. So the
predefined `ArithmeticContext::decimal64()` maps exactly to
`DecimalContext::decimal64()`. The constructors pass the context through
`DecimalContext::ieee754()`, the hook that selects the IEEE profile; on the
current branch it returns the context unchanged.

The mathematical functions restrict their context as the General Decimal
Arithmetic specification does for `exp`, `ln`, `log10` and `power`: precision
and both exponent limits must lie within $999\,999$ in magnitude, otherwise the
result is NaN with `invalid_context` (private check `math_context_is_restricted`
in `src/decimal`).[^gda] The default unbounded exponent range therefore
disables them, which the API page and tutorial point out. `power` and `pown`
with an integral exponent, and `power` with the exponent $0.5$ (a square
root), are the exceptions: like the arithmetic operations they accept
contexts up to $\pm 999\,999\,999$.

[^gda]: M. Cowlishaw, *General Decimal Arithmetic Specification*, version
    1.70, "Arithmetic operations: exp, ln, log10, power" (restrictions on
    the context).

### From flags to arithmetic diagnostics

The contextual trait implementations of `Decimal` in Luna-Flow/arithmetic
report `ArithmeticDiagnostics`, six Booleans combined by
`ArithmeticDiagnostics::combine`, again field-wise OR. The private helper
`contextual_diagnostics` in `src/decimal/traits.mbt` maps flags to diagnostics
by keeping the six shared coordinates; call this projection
$\pi : \mathbb{F} \to \{0,1\}^{6}$. A coordinate projection commutes with a
field-wise OR:

$$
\pi(a \lor b)_j = (a \lor b)_{i_j} = a_{i_j} \lor b_{i_j} = \pi(a)_j \lor \pi(b)_j ,
\qquad \pi(\mathbf{0}) = \mathbf{0},
$$

so $\pi$ is a monoid homomorphism, and by induction

$$
\pi\Bigl(\bigvee_{i=0}^{n} r_i\Bigr) = \bigvee_{i=0}^{n} \pi(r_i).
$$

Converting the accumulated flags of a pipeline once at the end gives the same
diagnostics as converting each step and combining. The conditions that the
trait implementation turns into an `ArithmeticError` (division by zero and the
invalid-operation family tested by `DecimalFlags::has_error`) are not among the
coordinates kept by $\pi$; the pipeline keeps them as flags instead.

## Correctness and invariants

### Accumulated flags are the union of per-step flags

**Theorem.** Let a pipeline be constructed with flags $r_0$ (from
`from_outcome`, `from_decimal`, `parse` or a numeric constructor) and then
undergo successful steps $1, \dots, n$ with raised flags $r_1, \dots, r_n$
(including `with_context` and `apply`), with no `clear_flags` in between. Then

$$
F_n = r_0 \lor r_1 \lor \dots \lor r_n, \qquad r = r_n .
$$

*Proof.* Every constructor sets $r = F = r_0$, which is the case $n = 0$.
If $F_{k} = \bigvee_{i \le k} r_i$, a successful step $k+1$ goes through
`record` (or the identical update in `with_context`) and sets
$F_{k+1} = F_k \lor r_{k+1} = \bigvee_{i \le k+1} r_i$ by associativity, and
$r = r_{k+1}$. $\square$

By commutativity and idempotence of $\lor$, $F_n$ does not depend on the order
of the steps or on how often a signal was raised, and by the homomorphism
property of `contains`,

$$
\texttt{contains}(F_n, s) \iff \exists\, i \le n : \texttt{contains}(r_i, s).
$$

The following test checks the theorem on a three-step pipeline: the
accumulated flags equal the OR of the raised flags of the steps, in either
order of combination.

```moonbit
///|
test "accumulated flags are the union of the raised flags" {
  let ctx = @decimal.DecimalContext::decimal64()
  let s0 = @decimal_checked.DecimalChecked::from_int(1, ctx)
  let s1 = s0.div(@decimal.Decimal::from_int(3))
  let s2 = s1.add(@decimal.Decimal::from_int(10))
  let s3 = s2.div(@decimal.Decimal::zero())
  let forward = s0.raised().combine(s1.raised()).combine(s2.raised()).combine(s3.raised())
  let backward = s3.raised().combine(s2.raised()).combine(s1.raised()).combine(s0.raised())
  inspect(s3.flags() == forward, content="true")
  inspect(forward == backward, content="true")
  inspect(s3.raised().inexact, content="false")
  inspect(s3.flags().inexact && s3.flags().division_by_zero, content="true")
}
```

After `clear_flags`, the theorem holds again with $r_0 = \mathbf{0}$ from that
point. $F$ is monotone along a pipeline: $F_k \subseteq F_{k+1}$.

### Errors are absorbing

**Theorem.** If a state has $\varepsilon = \mathrm{Some}(e)$, every operation
except `clear_flags` returns it unchanged, and `clear_flags` changes only $r$
and $F$.

*Proof.* `record`, `record_result` and `with_context` start with the guard
`self.error_ is None` and return `self` otherwise; every arithmetic method goes
through `record` or `record_result`. `clear_flags` updates only the two flag
fields. $\square$

Hence the first error is the one reported, the value and flags remain those
before the failing step, and `result()` returns $\mathrm{Err}(e)$. On a
pipeline without error, `result()` is $\mathrm{Ok}((v, F))$, the writer
monad's output.

### Cost

A step costs the delegated decimal operation plus one 13-field OR and a
constant-size state copy.

## Alternatives rejected

- **Errors for IEEE exceptions.** Contradicts IEEE default exception handling
  and the purpose of the package; the contextual traits already offer that
  model for single operations.
- **Merging pipelines.** No canonical rule for two contexts; see above.
- **Mutable flags.** Luna-Flow keeps context and status as values; an
  immutable state can be forked and compared.
- **Storing the per-step history.** The union answers the audit question at
  constant size; callers who need a history keep the states they care about.

## Boundaries

- No arithmetic of its own; every result comes from `decimal`.
- No traps or alternate exception handling: IEEE flags never stop the pipeline.
  Trap-driven control flow is the [`decimal_gda_checked`](decimal_gda_checked.md)
  contract.
- No operators, no pipeline-to-pipeline operations, no implicit context
  changes.
- Only certification failures of elementary functions become errors. A
  delegated operation that aborts (on the current branch `atan2` with an
  infinite operand) aborts the pipeline too; the state model cannot turn an
  abort into an error.
- No accuracy of its own: the flags describe exactly what `decimal` reported,
  including its documented deviations (for example `inexact` on an exact
  `hypot(0.3, 0.4)`).
- The context is the IEEE decimal context of `decimal`; GDA contexts with
  sticky status belong to `decimal_gda`.
