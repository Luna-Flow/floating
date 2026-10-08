# decimal_gda_checked design

## Design goal

`decimal_gda_checked` makes the control flow of the General Decimal Arithmetic
(GDA) specification usable as a chain of method calls. In GDA every operation
receives a context, may raise *signals*, records them in the context's sticky
*status*, and stops the computation when a raised signal is enabled in the
context's *trap* set.[^gda] `decimal_gda` implements single operations as pure
functions returning a `GdaOutcome`; `GdaDecimalChecked` threads the returned
context into the next operation, short-circuits on a trap, and offers one
explicit way to continue. The [API page](../api/decimal_gda_checked.md) lists
the operations; the [tutorial](../tutorial/decimal_gda_checked.md) shows traps
and recovery.

[^gda]: M. Cowlishaw, *General Decimal Arithmetic Specification*, version
    1.70, sections "Context" (flags and trap-enablers) and "Exceptional
    conditions".

## Mathematical background

### Signals, status and traps

Let $\Sigma$ be the thirteen GDA signals (`ConversionSyntax`, `DivisionByZero`,
`DivisionImpossible`, `DivisionUndefined`, `InvalidContext`,
`InvalidOperation`, `Overflow`, `Underflow`, `Subnormal`, `Inexact`,
`Rounded`, `Clamped`, `LostDigits`). A `GdaFlags` value is a subset of
$\Sigma$, an element of $\mathbb{B}^{\Sigma}$, and `GdaFlags::combine` is
union, field-wise OR. As for the IEEE flags, $(\mathbb{B}^{\Sigma}, \cup,
\varnothing)$ is a commutative idempotent monoid (a bounded join-semilattice).
A `GdaTrapSet` is another subset $T \subseteq \Sigma$.

GDA groups four signals under *invalid operation*:
$I = \{\texttt{ConversionSyntax}, \texttt{DivisionImpossible},
\texttt{DivisionUndefined}, \texttt{InvalidContext}\}$. The implementation
expresses this in two places:

$$
\begin{aligned}
r \models s \;&\iff\; s \in r \text{, except } r \models \texttt{InvalidOperation} \iff \texttt{InvalidOperation} \in r \lor r \cap I \ne \varnothing,\\
\delta(r) \;&=\; r \cup \{\texttt{InvalidOperation} : r \cap I \ne \varnothing\}.
\end{aligned}
$$

$r \models s$ is `GdaFlags::contains`; $\delta$ is the *status delta* that
`complete_gda` (in `src/decimal_gda/gda_context.mbt`) adds to the status.

$\delta$ is a monoid homomorphism. With $\chi(r) = [\, r \cap I \ne
\varnothing \,]$ we have $\chi(a \cup b) = \chi(a) \lor \chi(b)$, hence

$$
\delta(a \cup b) = a \cup b \cup \{\texttt{InvOp} : \chi(a) \lor \chi(b)\}
= \delta(a) \cup \delta(b), \qquad \delta(\varnothing) = \varnothing .
$$

### One GDA step

A context is $c = (\pi, S, T)$: parameters $\pi$ (precision, rounding, $E_{\min}$,
$E_{\max}$, clamp, extended), status $S$ and traps $T$. An operation computes,
from operands and $\pi$, a result $v'$ and raised signals $r$. Then

$$
\operatorname{step}(v', r, c) =
\begin{cases}
\texttt{Completed}(v', c, \varnothing) & r = \varnothing,\\
\texttt{Trapped}(\tau(r, T), v', c[S \cup \delta(r)], r) & \tau(r, T) \text{ defined},\\
\texttt{Completed}(v', c[S \cup \delta(r)], r) & \text{otherwise},
\end{cases}
$$

where the trap selector $\tau(r, T)$ is the first $s$ in the fixed priority
list `InvalidOperation`, `DivisionByZero`, `DivisionUndefined`,
`DivisionImpossible`, `InvalidContext`, `ConversionSyntax`, `Overflow`,
`Underflow`, `Subnormal`, `Inexact`, `Rounded`, `Clamped`, `LostDigits` with
$r \models s$ and $s \in T$. Note that the status is updated *before* the trap
decision, so the trapped signal is in the next status, and that $v'$ is the
defined result GDA prescribes for the condition (for example $\pm\infty$ for
division by zero), not a placeholder.

### The pipeline as a monad with an absorbing trap

Write $O = \texttt{Completed}(V \times C \times \mathbb{B}^{\Sigma}) +
\texttt{Trapped}(\Sigma \times V \times C \times \mathbb{B}^{\Sigma})$ for
`GdaOutcome[Decimal]`. Every pipeline method is the bind of

$$
\begin{aligned}
\texttt{Completed}(v, c, \_) \mathbin{>\!\!>\!\!=} f &= f(v, c),\\
\texttt{Trapped}(s, v, c, r) \mathbin{>\!\!>\!\!=} f &= \texttt{Trapped}(s, v, c, r),
\end{aligned}
$$

with $f(v, c) = \mathrm{op}(v, \dots, c)$ the `decimal_gda` function, and the
unit is $\eta(v, c) = \texttt{Completed}(v, c, \varnothing)$. This is the state
monad over contexts combined with an exception whose payload is the whole
trapped outcome.[^monads] Left identity,
$\eta(v, c) \mathbin{>\!\!>\!\!=} f = f(v, c)$, holds by the first
equation. Associativity,
$(x \mathbin{>\!\!>\!\!=} f) \mathbin{>\!\!>\!\!=} g =
x \mathbin{>\!\!>\!\!=} (\lambda (v, c).\, f(v, c) \mathbin{>\!\!>\!\!=} g)$,
holds by case analysis on $x$: a `Trapped` input is returned unchanged by both
sides, and a `Completed` input reduces both sides to
$f(v, c) \mathbin{>\!\!>\!\!=} g$. Right identity holds only up to the
latest-step flags: $x \mathbin{>\!\!>\!\!=} \eta$ maps
$\texttt{Completed}(v, c, r)$ to $\texttt{Completed}(v, c, \varnothing)$,
which agrees with $x$ in value and context but not in $r$. So the structure is
a monad on outcomes taken modulo the `raised` field, which is a per-step
observation that every step overwrites; nothing in the pipeline reads it.

[^monads]: E. Moggi, "Notions of computation and monads", 1991 (state and
    exception monads); P. Wadler, "Monads for functional programming", 1995.

## Design decisions

### The state is exactly one `GdaOutcome`

**Problem.** A pipeline must remember the value, the context to use next, the
latest signals and whether a trap fired.

**Choice.** `GdaDecimalChecked` stores one `GdaOutcome` and nothing else, so
it is the outcome type of `decimal_gda` closed under its operations. Every
observation (`value`, `context`, `raised`, `status`, `is_trapped`,
`trapped_signal`) is a projection of the outcome, and `from_outcome` /
`outcome` convert in both directions without loss.

### A trap is a stop, not an error

**Problem.** A trapped GDA condition must stop the computation, but it is not
a failure of the library: the specification defines both the result and the
status for it, and an application may decide to continue.

**Options.** (a) Convert a trap to `ArithmeticError`. (b) Keep the trapped
outcome as the state and require explicit recovery.

**Choice: (b).** Converting would lose the defined result and the next
context, which is what a GDA handler needs to continue. A trapped state is a
fixed point of every operation (see below), and `resume_defined()` is the only
exit. Making recovery explicit keeps "we accepted the defined result after a
trap" visible in the code.

### What resuming keeps

$\rho = $ `resume_defined` maps
$\texttt{Trapped}(s, v, c, r) \mapsto \texttt{Completed}(v, c, \varnothing)$
and leaves a completed outcome unchanged. It keeps the context, so

$$
\operatorname{status}(\rho(x)) = \operatorname{status}(x), \qquad
\operatorname{traps}(\rho(x)) = \operatorname{traps}(x), \qquad
\rho \circ \rho = \rho .
$$

The status keeps recording the trapped signal, as the specification requires
of a flag that was raised; the trap set is unchanged, so a recurrence traps
again. Only the per-step `raised` and the trap marker are dropped.

```moonbit
///|
test "resume keeps status and traps and is idempotent" {
  let ctx = @decimal_gda.GdaContext::default()
  let zero = @decimal_gda.Decimal::zero()
  let trapped = @decimal_gda_checked.GdaDecimalChecked::parse("1", ctx).divide(zero)
  let once = trapped.resume_defined()
  let twice = once.resume_defined()
  inspect(once.status() == trapped.status(), content="true")
  inspect(twice.status() == once.status(), content="true")
  inspect(twice.value().to_string() == once.value().to_string(), content="true")
  // the context after resuming still traps division by zero
  let again = @decimal_gda_checked.GdaDecimalChecked::parse("2", once.context()).divide(zero)
  inspect(again.is_trapped(), content="true")
}
```

### Plain operands and no context merging

The second operand of every binary method is a plain `Decimal`. Two pipelines
would carry two sticky statuses and two trap sets; merging them has no
specified meaning in GDA, where a computation has one current context.

### Relation to Luna-Flow/arithmetic

The pipeline takes a `GdaContext`, which carries status and traps that
`ArithmeticContext` does not have. The contextual trait implementations of
`@decimal_gda.Decimal` (for generic code over Luna-Flow/arithmetic) use the
package's IEEE-style `DecimalContext::from_arithmetic_context` and report
`ArithmeticDiagnostics` per operation, without traps. The two models are kept
apart: a generic algorithm cannot observe a trap, and a GDA pipeline does not
lose its status to a diagnostics record.

## Correctness / invariants

### The status is sticky

**Theorem.** Let a pipeline start from a context with status $S_0$ and pass
through completed steps with raised signals $r_1, \dots, r_n$. Then the status
of the final context is

$$
S_n = S_0 \cup \delta(r_1) \cup \dots \cup \delta(r_n) = S_0 \cup \delta(r_1 \cup \dots \cup r_n).
$$

*Proof.* By induction: a step with $r = \varnothing$ leaves the context
unchanged, and $S \cup \delta(\varnothing) = S$; otherwise the step sets
$S_{k+1} = S_k \cup \delta(r_{k+1})$. The second equality is the homomorphism
property of $\delta$. $\square$

Consequences: the status only grows ($S_k \subseteq S_{k+1}$), it does not
depend on the order of the steps' signals, and
$\texttt{InvalidOperation} \in S_n$ whenever any invalid-operation condition was
raised. The step that traps is included, because the status is updated before
the trap decision, and $\rho$ preserves the status, so the theorem extends
across `resume_defined`.

### The first trap ends the pipeline

**Theorem.** In a pipeline $x_k = \mathrm{op}_k(x_{k-1})$, if step $j$ is the
first whose outcome is `Trapped`, then $x_n = x_j$ for every $n \ge j$ unless
`resume_defined` is applied.

*Proof.* Every operation method matches on the outcome and returns `self` for
`Trapped`, so $x_{k} = x_{k-1}$ for $k > j$; induction on $k$. $\square$

Together with the selector $\tau$, the reported signal is determined: it is the
highest-priority trapped signal raised by the first trapping step.

### Trapping depends on the step, not on the history

The trap test uses the signals $r$ raised by the current step, not the status
$S$. A signal raised earlier under a context without that trap does not trap
later steps, and clearing the status does not affect trapping. This matches
GDA, where a trap is an event of the operation that raised the condition.

### Cost

A step costs the GDA operation plus constant work on two 13-field records.
When the operation raises nothing, the context is passed on unchanged.

## Alternatives rejected

- **Traps as `ArithmeticError`.** Loses the defined result and next context.
- **Automatic resumption.** Would hide the decision to accept a trapped
  result; GDA leaves that decision to the handler.
- **Operators on the pipeline.** Same objection as merging contexts.
- **Clearing the status on resume.** Would erase evidence that a trapped
  condition occurred.

## Boundaries

- No arithmetic of its own; every operation comes from `decimal_gda`.
- Only the operation set in the generated interface has pipeline methods;
  other `decimal_gda` operations are run on `value()` / `context()` and
  re-wrapped with `from_outcome`.
- No `ArithmeticError`, no IEEE `DecimalFlags`; IEEE-style flag accumulation is
  the [`decimal_checked`](decimal_checked.md) contract.
- No merging of pipelines, no implicit recovery, no changes to the trap set
  during a pipeline.
