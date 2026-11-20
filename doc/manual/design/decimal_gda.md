# decimal_gda design

This page explains the mathematics that `decimal_gda` implements and why the
package is built the way it is. The [tutorial](../tutorial/decimal_gda.md)
shows how to use it and the [API page](../api/decimal_gda.md) lists every
name.

## Design goal

`decimal_gda` implements the General Decimal Arithmetic Specification
(version 1.70) by M. F. Cowlishaw[^gda] as pure MoonBit values. A GDA operation
is specified to produce more than a number: it produces a result, a set of
*conditions*, an update of the context's sticky *status*, and possibly a
*trap* that transfers control while the defined result stays available. The
goal is to model all of that exactly and observably, so that

- each operation is a total function from (operands, context) to
  (result, raised conditions, next context, trap decision), with no hidden
  state;
- results are bit-for-bit those of the specification, checked against the
  pinned official test suite (see [conformance](../conformance/decimal_gda.md));
- the package is independent of the IEEE 754 package `decimal`, so changes to
  one contract cannot leak into the other.

[^gda]: M. F. Cowlishaw, *General Decimal Arithmetic Specification*, version
    1.70 (2009), <https://speleotrove.com/decimal/decarith.html>. The test suite
    is the same author's `dectest` collection, version 2.62.

The ParseChecked adapter is a value-only adapter over the GDA to-number
conversion. It maps ArithmeticContext to the engine context, so precision,
rounding direction, exponent bounds and clamp apply. The returned Result
cannot carry GDA status or traps; callers that need those effects should use
the decimal_gda::to_number API with GdaContext.

`divide_integer` constructs its preferred zero at exponent 0 before applying
the context finalizer. This preserves the quotient sign and lets clamp fold
the exponent without treating an exact zero exponent change as rounding.

## Mathematical background

### Numbers, cohorts and the adjusted exponent

A finite GDA number is a triple $(s, c, e)$ with sign $s \in \{0, 1\}$,
coefficient $c \in \mathbb{N}$ and exponent $e \in \mathbb{Z}$, denoting

$$
v(s, c, e) = (-1)^s \cdot c \cdot 10^{e}.
$$

The map $v$ is not injective: $(0, 250, -2)$ and $(0, 25, -1)$ both denote
$2.5$. The triples with the same value form a *cohort*, and GDA keeps the
triple, not only the value, because the exponent carries meaning (the
*quantum* $10^e$: "2.50" was measured to the cent). Zero is signed, so
$(1, 0, e)$ is $-0$. For $c > 0$ write $d(c)$ for the number of decimal
digits of $c$ and

$$
\hat e = e + d(c) - 1
$$

for the *adjusted exponent*, the exponent of the leading digit: $10^{\hat e}
\le |v| < 10^{\hat e + 1}$. Besides finite numbers there are $\pm\infty$ and
quiet and signaling NaNs carrying a sign and a payload $c$.

### Contexts and the representable set

A context fixes a precision $p \ge 1$, a rounding mode, an exponent range
$e_{\min} \le e_{\max}$ and a clamp bit. A finite number is *representable*
in the context when

$$
d(c) \le p, \qquad \hat e \le e_{\max}, \qquad e \ge E_{\mathrm{tiny}}
\;\text{ where }\; E_{\mathrm{tiny}} = e_{\min} - p + 1,
$$

and, if clamping is on, also $e \le E_{\mathrm{top}} = e_{\max} - p + 1$. The
value $E_{\mathrm{tiny}}$ is the exponent of the smallest unit: a number with
$\hat e = e_{\min}$ and $p$ digits has $e = e_{\min} - p + 1$, and numbers
below $10^{e_{\min}}$ (the *subnormal* range) keep that unit while losing
leading digits. $E_{\mathrm{top}}$ is the exponent of the largest $p$-digit
number with $\hat e = e_{\max}$; clamping makes the set of exponents exactly
the one an IEEE interchange format can encode, which is why the decimal32/64/128
presets clamp.

### The arithmetic rule: exact result, then round once

Every arithmetic operation in GDA is defined by the same two-step rule:

1. compute the exact mathematical result $x$ and choose, among the triples
   that denote $x$, the one whose exponent is closest to the operation's
   *ideal exponent* $e^\ast$;
2. if that triple is not representable, round it to the context, raising
   conditions that describe what happened.

Because step 1 is exact, step 2 is a single rounding, and every bound below is
a bound on one rounding. The package follows the rule literally: each
operation builds an exact coefficient and exponent from its operands and then
calls one shared finalizer (`normalize_decimal_parts_ctx_repr` followed by
`finalize_finite_ctx`), which is the only code that rounds a finite result or
raises a precision- or range-related condition.

### Ideal exponents

The ideal exponent is the coarsest quantum that represents the exact result
using only information present in the operands. The derivations are short:

$$
\begin{aligned}
x_1 \pm x_2 &= \bigl(c_1 10^{e_1 - m} \pm c_2 10^{e_2 - m}\bigr) 10^{m},
  & m &= \min(e_1, e_2),\\
x_1 \times x_2 &= (c_1 c_2)\, 10^{e_1 + e_2}, & &\\
x_1 \div x_2 &= \frac{c_1}{c_2}\, 10^{e_1 - e_2}, & &\\
\sqrt{x} &= \sqrt{c\,10^{e - 2\lfloor e/2 \rfloor}}\;10^{\lfloor e/2 \rfloor}. & &
\end{aligned}
$$

For addition, $m$ is the largest exponent at which both operands are integers,
so it is the largest exponent at which the sum is guaranteed to be an integer
multiple of the quantum; the bracket is then an exact integer coefficient.
For multiplication the coefficient $c_1 c_2$ is an integer at exponent
$e_1 + e_2$ and in general at no larger one. For division the quotient
$c_1 / c_2$ need not be an integer, so the ideal $e_1 - e_2$ is used only when
it is reachable: the exact quotient is written with the exponent nearest to
$e_1 - e_2$ that keeps an integer coefficient of at most $p$ digits, and an
inexact quotient uses all $p$ digits. For the square root, $\lfloor e/2
\rfloor$ is the exponent whose square is the largest even exponent not above
$e$. The table summarizes the rules used by the package:

| Operation | Ideal exponent $e^\ast$ |
| --- | --- |
| `add`, `subtract`, `fma` (sum part) | $\min(e_1, e_2)$ |
| `multiply`, `fma` (product part) | $e_1 + e_2$ |
| `divide` | $e_1 - e_2$ if exact, else $p$ digits |
| `sqrt` | $\lfloor e/2 \rfloor$ if exact, else $p$ digits |
| `remainder`, `remainder_near` | $\min(e_1, e_2)$ |
| `divide_integer`, `to_integral_*` | $\max(e, 0)$ for the integral value, 0 for a quotient |
| `quantize`, `rescale` | the requested exponent |
| `scaleb` | $e + n$ |
| `power` with integer $n$, exact | $n e$ |
| `exp`, `ln`, `log10`, non-integer `power` | $p$ digits (always inexact, except `exp(0)`, `ln(1)`, `log10(10^k)`) |
| `plus`, `minus`, `abs`, `apply` | $e$ |

A zero result has no leading digit, so its exponent is simply the ideal one,
clamped into $[E_{\mathrm{tiny}}, e_{\max}]$ (or $E_{\mathrm{top}}$). `quantize`
and `rescale` of a zero follow the rule too: the requested exponent must be at
most $e_{\max}$, and under `clamp` one above $E_{\mathrm{top}}$ is folded down to
it with `clamped`, as decNumber's `decQuantizeOp` does by calling `decFinalize`
for a zero. The sign of
an exact zero sum is $+$ unless both operands are negative, or the mode is
`Floor` and either is; this is the decimal form of the IEEE rule that
$x - x = +0$ except when rounding towards $-\infty$.

```moonbit
///|
test "ideal exponents" {
  let ctx = @decimal_gda.GdaContext::decimal64()
  let d = (s : String) => @decimal_gda.Decimal::from_string(s).unwrap()
  inspect(@decimal_gda.add(d("1.30"), d("1.2"), ctx).value(), content="2.50")
  inspect(@decimal_gda.multiply(d("1.30"), d("1.2"), ctx).value(), content="1.560")
  inspect(@decimal_gda.divide(d("2.40"), d("2"), ctx).value(), content="1.20")
  inspect(@decimal_gda.divide(d("1"), d("4"), ctx).value(), content="0.25")
  inspect(@decimal_gda.sqrt(d("1.00"), ctx).value(), content="1.0")
  inspect(@decimal_gda.subtract(d("1.0"), d("1.00"), ctx).value(), content="0.00")
}
```

### Rounding to precision

Let the exact result be $(-1)^s c\,10^{e}$ with $d(c) = p + k$, $k \ge 1$.
Divide off the $k$ low digits, $c = q\,10^{k} + r$ with $0 \le r < 10^k$. Every
rounding mode returns $(-1)^s (q + \delta)\,10^{e+k}$ with an increment
$\delta \in \{0, 1\}$, and the eight modes differ only in $\delta$
(`should_increment_decimal_repr`):

$$
\begin{aligned}
\delta_{\mathrm{Down}} &= 0, &
\delta_{\mathrm{Up}} &= [r > 0],\\
\delta_{\mathrm{Ceiling}} &= [r > 0 \wedge s = 0], &
\delta_{\mathrm{Floor}} &= [r > 0 \wedge s = 1],\\
\delta_{\mathrm{HalfUp}} &= [2r \ge 10^k], &
\delta_{\mathrm{HalfDown}} &= [2r > 10^k],\\
\delta_{\mathrm{HalfEven}} &= [2r > 10^k \vee (2r = 10^k \wedge q \text{ odd})], &
\delta_{\mathrm{ZeroFiveUp}} &= [r > 0 \wedge q \equiv 0 \pmod 5].
\end{aligned}
$$

`ZeroFiveUp` reads "round towards zero, unless the retained last digit is 0 or
5". After it, a last digit of 0 or 5 means the rounding was exact, and any
other last digit after an inexact rounding is never 0 or 5. Rounding the
result again to at least one digit fewer, in any mode, therefore gives the
same value as rounding the exact result once in that mode: the retained digit
acts as a sticky digit, as round-to-odd does in binary. The comparison $2r$ versus $10^k$ is done exactly on
the decimal limbs (`dec_coeff_div_pow10_round_info_repr` returns the quotient,
whether $r > 0$, and the sign of $2r - 10^k$). If $q + \delta = 10^p$ the result
is renormalized to $10^{p-1} \cdot 10^{e+k+1}$. Before rounding, the finalizer
first tries to drop trailing zeros of $c$; when the exact coefficient is too
long only because of zeros, the result is exact and only `Rounded` is raised.

Let $u = 10^{e+k}$ be the unit in the last place of the result $\hat x$. Since
$|\delta\,10^k - r| \le 10^k/2$ in the half modes and $< 10^k$ otherwise,

$$
|\hat x - x| \le \tfrac12 u \;\;(\text{half modes}), \qquad
|\hat x - x| < u \;\;(\text{others}),
$$

and since $c \ge 10^{p+k-1}$ gives $|x| \ge 10^{p-1} u$,

$$
\frac{|\hat x - x|}{|x|} \le \tfrac12\,10^{1-p} \;\;(\text{half modes}),
\qquad
\frac{|\hat x - x|}{|x|} < 10^{1-p} \;\;(\text{others}).
$$

This is the decimal unit roundoff $\mathbf u = \frac12 10^{1-p}$ of the
standard model $\mathrm{fl}(x \circ y) = (x \circ y)(1 + \varepsilon)$,
$|\varepsilon| \le \mathbf u$.[^higham] Rounding raises `Rounded` whenever
$k \ge 1$ digits are removed and `Inexact` whenever a removed digit was
nonzero ($r > 0$).

[^higham]: N. J. Higham, *Accuracy and Stability of Numerical Algorithms*,
    2nd ed., SIAM 2002, §2.2. Decimal wobble is larger than binary: the
    relative spacing varies by a factor of 10 across a decade, against 2 in
    binary (Goldberg 1991, §1.2).

The full proofs of this bound and of the other rounding facts on this page are
in the attachment:

[Rounding proofs for decimal_gda](../../attachments/design_decimal_gda_rounding.typ)

### Subnormal results and $E_{\mathrm{tiny}}$

If the exact result has $\hat e < e_{\min}$ it is *tiny*. A tiny result may
still need the unit $10^{E_{\mathrm{tiny}}}$ at most, so the rounding position
is not "keep $p$ digits" but "keep the digits at or above
$10^{E_{\mathrm{tiny}}}$". With an exact coefficient of $D$ digits and
exponent $e$, rounding to $p$ digits would give the exponent
$e + \max(0, D - p)$; when that is below $E_{\mathrm{tiny}}$ the finalizer
instead removes $k = E_{\mathrm{tiny}} - e$ digits, possibly all of them, in
one rounding. A longer coefficient whose exponent is below
$E_{\mathrm{tiny}}$ but whose magnitude is normal is rounded once to $p$
digits; rounding it to the subnormal grid first would round twice (in
decimal32, $3.000001\cdot 10^{-45} \times 1.500001\cdot 10^{-45}$ is
`4.500005E-90`). The
absolute error is then bounded by the subnormal unit,

$$
|\hat x - x| \le \tfrac12\,10^{E_{\mathrm{tiny}}} \;\;(\text{half modes}),
$$

but the relative error is not bounded by $\mathbf u$ any more: the precision
falls gradually from $p$ digits to 1 as $|x|$ drops from $10^{e_{\min}}$ to
$10^{E_{\mathrm{tiny}}}$. The conditions record this: `Subnormal` is raised for
every tiny result (GDA, and this package's GDA functions, detect tininess
*before* rounding, from the exact $\hat e$), `Underflow` when a tiny result is
also inexact, and `Clamped` when it rounds to zero (the zero then takes the
exponent $E_{\mathrm{tiny}}$). Because tininess is decided before rounding,
a result such as $0.9951$ at $p = 3$, $e_{\min} = 0$ raises `Subnormal` and
`Underflow` even though it rounds to the normal number `1.00`. GDA 1.70 has no
other rule (the after-rounding rule is an IEEE 754 choice for binary formats
only), so the package has no tininess parameter.

### Clamping

With `clamp`, a result with $e > E_{\mathrm{top}}$ but $\hat e \le e_{\max}$
is representable as a value but not as a triple. Since $\hat e \le e_{\max}$
means $d(c) + e - 1 \le e_{\max}$, padding the coefficient with
$e - E_{\mathrm{top}}$ zeros gives

$$
d\bigl(c\,10^{e - E_{\mathrm{top}}}\bigr) = d(c) + e - E_{\mathrm{top}}
\le e_{\max} + 1 - E_{\mathrm{top}} = p,
$$

so the padded triple has at most $p$ digits and the same value. The package
does exactly this and raises `Clamped`; the value is unchanged, only the
cohort member differs. Zeros are clamped the same way, by moving their
exponent into $[E_{\mathrm{tiny}}, E_{\mathrm{top}}]$.

### Overflow

If the rounded result has $\hat e > e_{\max}$ the operation overflows:
`Overflow`, `Inexact` and `Rounded` are raised and the result is either
$\pm\infty$ or the largest finite number of the same sign,
$N_{\max} = (10^p - 1) \cdot 10^{E_{\mathrm{top}}}$. Which one follows from
treating $\infty$ as the representable number beyond $N_{\max}$ and applying
the mode's own direction: the half modes and `Up` move away from zero, so they
reach $\infty$; `Down` and `ZeroFiveUp` move towards zero (`ZeroFiveUp` would
only round away from zero from a last digit 0 or 5, and the last digit of
$N_{\max}$ is 9), so they stop at $N_{\max}$; `Ceiling` gives $+\infty$ for a
positive and $-N_{\max}$ for a negative result, and `Floor` the mirror image
(`overflow_to_infinity`):

| Mode | positive overflow | negative overflow |
| --- | --- | --- |
| `HalfEven`, `HalfUp`, `HalfDown`, `Up` | $+\infty$ | $-\infty$ |
| `Down`, `ZeroFiveUp` | $+N_{\max}$ | $-N_{\max}$ |
| `Ceiling` | $+\infty$ | $-N_{\max}$ |
| `Floor` | $+N_{\max}$ | $-\infty$ |

### Conditions, signals and traps

GDA distinguishes *conditions* (what happened: division by zero, a result was
rounded, a conversion was malformed, …), *signals* (the named events a
condition triggers) and *traps* (signals the user has asked to interrupt the
computation). The package keeps one flag per condition (thirteen) and one
trap-enabler per signal (nine), and maps conditions to the GDA signals by one
rule: the four detailed invalid conditions conversion syntax, division
impossible, division undefined and invalid context all signal
`InvalidOperation` (GDA 1.70, pages 51 and 52). Formally, let $\mathcal S$ be
the thirteen flags and let $\iota \subset \mathcal S$ be the five
invalid-family flags. For a flag set $R$ and a signal $\sigma$,

$$
\sigma \in^\ast R \iff
\begin{cases}
R \cap \iota \neq \emptyset & \sigma = \mathrm{InvalidOperation},\\
\sigma \in R & \text{otherwise,}
\end{cases}
$$

which is `GdaFlags::contains`. An operation is then the state machine

$$
(\vec x, C) \;\longmapsto\;
\begin{cases}
\mathrm{Completed}(v, C, \emptyset) & R = \emptyset,\\
\mathrm{Completed}(v, C', R) & R \neq \emptyset,\ \tau = \bot,\\
\mathrm{Trapped}(\tau, v, C', R) & \tau \neq \bot,
\end{cases}
$$

where $(v, R) = F(\vec x, \pi(C))$ is the result and raised flags computed from
the operands and the *policy* $\pi(C)$ (precision, rounding, exponent range,
clamp, extended) alone,

$$
C'.\mathrm{status} = C.\mathrm{status} \cup R \cup
\bigl\{\mathrm{InvalidOperation} \mid R \cap \iota \neq \emptyset\bigr\},
\qquad C'.\pi = C.\pi,\quad C'.\mathrm{traps} = C.\mathrm{traps},
$$

and $\tau$ is the first signal in the precedence list
InvalidOperation, DivisionByZero, Overflow, Underflow, Subnormal, Inexact,
Rounded, Clamped, LostDigits with $\tau \in^\ast R$ and
$\tau \in C.\mathrm{traps}$, or $\bot$ if there is none (`complete_gda` and
`trapped_signal`).

Three properties follow directly from the definition and are what users rely
on:

1. **The value does not depend on status or traps.** $v$ and $R$ are
   functions of $(\vec x, \pi(C))$; status and traps only enter $C'$ and
   $\tau$. Enabling a trap therefore never changes a result, and
   `Trapped` can carry the defined result.
2. **Status is monotone and idempotent.** $C.\mathrm{status} \subseteq
   C'.\mathrm{status}$, and since $\cup$ is associative, commutative and
   idempotent, the status after a threaded sequence is the union of all raised
   sets, independent of how the sequence is grouped.
3. **The trap choice is deterministic.** The precedence list is a total order
   on signals, so one operation selects at most one trap, whatever the order
   in which its conditions were detected.

```moonbit
///|
test "status is the union of the raised sets" {
  let ctx = @decimal_gda.GdaContext::new(precision=3)
  let d = (s : String) => @decimal_gda.Decimal::from_string(s).unwrap()
  let a = @decimal_gda.divide(d("1"), d("3"), ctx) // Inexact, Rounded
  let b = @decimal_gda.divide(d("1"), d("0"), a.next_context()) // DivisionByZero
  let expected = a.raised().combine(b.raised())
  inspect(b.next_context().status() == expected, content="true")
  // Trapping changes the variant, never the value.
  let trapping = ctx.trap(Inexact)
  let t = @decimal_gda.divide(d("1"), d("3"), trapping)
  inspect(t.value() == a.value(), content="true")
  inspect(t is @decimal_gda.GdaOutcome::Trapped(Inexact, _, _, _), content="true")
}
```

## Design decisions

### Thread status through `GdaOutcome`, not global state

**Problem.** The GDA specification describes the context as a mutable object
whose status flags operations set. Most implementations (decNumber, Python's
`decimal`) keep a current context per thread.

**Options.** (a) A mutable context passed by reference; (b) a thread-local or
global current context; (c) an immutable context returned with every result.

**Choice: (c).** Every GDA function returns `GdaOutcome`, and the caller passes
`next_context()` to the next operation. The reasons are the properties above.
Because $F$ reads only the policy, the state machine factors into a pure
numerical part and a pure bookkeeping part, and both are referentially
transparent: an expression can be re-evaluated, memoized or run on another
thread without changing its result or its flags. A test runner can snapshot a
context and run the same operation under it many times; the `.decTest` runner
in [`frontend/gda_expr`](../api/frontend/gda_expr.md) does exactly that. MoonBit
also has no thread-local storage, so (b) would mean process-global state,
which Luna-Flow excludes. The cost is explicit threading; the
[`decimal_gda_checked`](decimal_gda_checked.md) package removes it for linear
pipelines. When nothing is raised, the input context is returned unchanged,
so exact operations do not allocate a new context.

### Keep a trap's defined result

In GDA a trap transfers control, but the specification still defines the
result the operation would have delivered. Representing a trap as an error
(`Result::Err`, `raise`) would discard that value. `Trapped` keeps the value,
the next context and the raised set, so the caller can inspect, log or resume
from it; property 1 guarantees it is the same value as without the trap.

### Keep the detailed invalid conditions

The specification reports conversion syntax, division impossible, division
undefined and invalid context through the signal `InvalidOperation`. The
package keeps them as separate *flags* and makes `contains(InvalidOperation)`
true for each, and sets `invalid_operation` in the status whenever one is
raised. They are not signals: the trap set has nine trap-enablers, the signals
of the specification, so a trap cannot be set on a condition alone, which GDA
has no trap-enabler for. The decTest files name conditions (`Conversion_syntax`,
`Division_undefined`, ...), which is why the flags stay at thirteen. A program that only knows the GDA signals sees exactly the GDA
behaviour, while a test harness or a diagnostic can still tell a malformed
literal from $0/0$. Placing `InvalidOperation` first in the precedence list
makes an `InvalidOperation` trap catch all four, as the specification
requires.

### One finalizer, special values first

Each operation first decides the special cases (NaN propagation, invalid
operations, infinities, exact zeros), then builds an exact finite coefficient
and exponent, and only then calls the finalizer. No coefficient algorithm sets
a flag. This keeps the conditions a function of the exact result and the
policy, independent of which multiplication or division kernel was chosen, and
lets kernels be tuned without touching the standard-facing behaviour.

### A GDA package independent of `decimal`

IEEE 754-2008 decimal arithmetic grew out of GDA, so the two agree on most
finite results, but their contracts differ:

| Aspect | `decimal_gda` (GDA 1.70) | `decimal` (IEEE 754-2019) |
| --- | --- | --- |
| Precision | any $p \ge 1$ per context | the format's $p$ (or a chosen one) |
| Rounding modes | eight, including `HalfUp`, `HalfDown`, `ZeroFiveUp` | the IEEE attributes |
| Conditions | sticky status in the context, traps with defined results | per-operation flags returned with the value |
| Detailed invalid conditions, `LostDigits`, subset arithmetic | yes | no |
| Tininess | before rounding | selectable |
| Elementary functions | `sqrt`, `exp`, `ln`, `log10`, `power` | the IEEE recommended set |
| Interchange | DPD | DPD and BID |

A shared core would have to carry the union of both state models, and a change
made for one standard could silently change the other's results. The package
therefore owns its value type, contexts, finalizer and DPD codec, and
`tools/check_imports.py` (part of `just pr`) fails if it imports `decimal`, or
the reverse.

What the two packages do share is the part that has no standard in it: the
integer arithmetic on coefficients, in the internal package
`internal/decimal_kernel`. It contains the limb representation, addition,
subtraction, comparison, shifts by powers of ten, digit counts, and the
multiplication and division algorithms with their per-target thresholds. Its
functions are exact integer functions: they take coefficients and return
coefficients, they raise no condition, and they know neither a rounding mode,
a context nor a flag. A change there cannot change which condition an
operation raises, only how fast the exact integer is found, and the kernel
imports neither decimal package (`tools/check_imports.py` checks that too).
Two copies of this code had already diverged: a fix in one did not reach the
other, and `decimal` lacked the small-value fast paths of `decimal_gda`. The
thresholds are therefore one set, measured on the shared kernel.

The rounding-direction decisions are shared too, because they are pure functions
of a coefficient and the digits that were discarded: whether the kept magnitude
grows by one unit in the last place, for the eight directions. Each package
converts its own rounding-mode type into the kernel's direction enum with one
total match, so the kernel knows neither type. What the decision is applied to,
and every flag, clamp, subnormal and overflow rule around it, stays in the
finalizer of each package. The same holds for the exact integer helpers that
roots, logarithm series and the logical digit operations are built on.

The status-free engine (a private `DecimalContext`, `DecimalFlags` and the
`*_ctx` methods) is private to the package: the functions named after the GDA
operations are the only public spelling of every operation, so each operation
exists once. The engine returns flags per operation, which is what the
`Luna-Flow/arithmetic` trait implementations use. The IEEE 754 contract lives
in `decimal`.

### Fast paths that are proven equivalent

Two kinds of shortcut avoid the general machinery without changing any
observable result.

*Small exact integers.* `parse`, `add`, `subtract`, `multiply` and `fma` first
check whether all operands are integers with exponent 0 and coefficients below
$10^{18}$, the exact result is a nonzero integer below $10^{18}$ with at most
$p$ digits, its adjusted exponent lies in $[e_{\min}, e_{\max}]$, exponent 0
is allowed by clamping, and the context is extended. Under these predicates
the general path performs no rounding, raises no condition and returns
exponent 0 (the ideal exponent of every one of these operations), so the
shortcut returns `Completed(v, C, none)` with the same $v$. A zero result is
excluded because its sign depends on the rounding mode.

*Absorbed addends.* When adding $x_1$ and a much smaller $x_2$ with
$\hat e_2 < \hat e_1 - p + 1$, the exact sum need not be formed. Every digit of
$x_2$ lies below the last retained digit of $x_1$, so $x_2$ influences the
rounding only through its sign and its comparison with half a unit:

$$
\hat x = \mathrm{round}\bigl(x_1 + x_2\bigr)
= \bigl(q + \delta(\operatorname{sign} x_2,\; |x_2| \lessgtr \tfrac12 u)\bigr) u,
$$

which is the rounding table above with $r$ replaced by a sticky
representative of the same comparison class. `exact_base_small_addend_result`
evaluates exactly that, with `compare_magnitude_to_half_ulp` comparing $x_2$
with $u/2$ exactly. The special case where $x_1$ is a power of ten and $x_2$
has the opposite sign (the unit below $x_1$ is ten times smaller) is excluded
and takes the general path.

*Overflow of the larger addend.* The shortcut returns the overflow of $x_1$
rounded alone only when the sum overflows as well, because overflow is judged
on the rounded sum (see Overflow above). That holds when $x_2$ has the sign of
$x_1$ (the sum is larger in magnitude), or when $p \ge 2$ and
$\hat e_1 \ge e_{\max} + 2$ (the sum is more than $0.9 \cdot 10^{\hat e_1}$).
Otherwise an opposite sign can pull the sum back into range, so the case takes
the general path: `add(9.5, -0.5)` at precision 1 and $e_{\max} = 0$ is `9`,
not an overflow. A non-extended context rounds the operands first, so the
shortcut is unchanged there.

The argument needs $x_1$ itself to end at or above the last retained
position, so this shortcut is taken only when $x_1$ fits the context exactly
(and not under `ZeroFiveUp`, whose rounding depends on the last kept digit).
When $x_1$ has digits below that position, or is exactly a midpoint, $x_2$ can
still move the sum across a boundary that the comparison with $u/2$ does not
see. An extended context then replaces $x_2$ by a *sticky unit*, as the
`decimal` package does. Let $t$ be the target exponent of $x_1$ alone and
$g = \min(e_1, t - 2)$. Every digit of $x_1$ and every rounding boundary of
the sum (the grid $10^{t}$, its midpoints, and the grid $10^{t-1}$ with its
midpoints, which a cancellation can reach) lies on the grid $10^{g}$. If
$0 < |x_2| < 10^{g}$, the sum lies strictly between the same two neighbours on
that grid as $x_1 \pm 10^{g-1}$, with the sign of $x_2$, so rounding that short
value once gives the result and the flags of the exact sum in every mode:
at precision 7, `add(1598618.5, 1E-20)` under `HalfEven` is `1598619`, and
`subtract(1598618, 9.9E-11)` under `ZeroFiveUp` is `1598617`.

*Plain sums.* The general route of `add` and `subtract` passes through the
context-taking engine (operand preparation, the sum, the normalizer, the
finalizer, the outcome), whose temporaries are records and tuples: a 34-digit
`add` made 28.9 allocations and a native library such as libmpdec makes none.
When the context is extended and does not clamp, both operands are finite and
nonzero, the smaller adjusted exponent is not below $\hat e_1 - p + 1$ (no
operand is absorbed) and the nonzero exact sum has adjusted exponent in
$[e_{\min}, e_{\max} - 1]$ (so after a possible carry into a digit beyond
$p$ it can neither overflow nor be subnormal, and its exponent is not
clamped), the result is the exact aligned sum rounded once to $p$ digits at the
exponent $\min(e_1, e_2)$ plus the digits discarded, with `rounded` raised
when digits were discarded and `inexact` when a nonzero one was. Dropping a
run of zero digits first and then rounding the rest gives the same value,
exponent and flags as rounding once. `gda_add_plain` computes exactly that: the
sum is formed in one limb array and rounded in place by the kernel (see the
design of `internal/decimal_kernel`), the flags are shared constants (`GdaFlags`
and `DecimalFlags` are immutable records compared by value, so sharing is not
observable) and the outcome is built once; when the status of the context
already contains the raised conditions the outcome carries the input context
itself. Every other case returns `None` and takes the general
route, which remains the definition; the white-box test compares both routes
for `add` and `subtract` on random operands of 1 to 120 digits with mixed signs,
cancellations and exponent gaps, at nine precisions and all eight rounding
modes, with tight and wide exponent ranges, clamping and trapped signals.

*Plain products and quotients.* `multiply` and `divide` take the same kind of
shortcut as the plain sums, under the same predicates (an extended context
without clamping, finite nonzero operands, a result whose adjusted exponent
lies in $[e_{\min}, e_{\max} - 1]$, so that it can neither overflow, nor be
subnormal, nor change exponent for the exponent range). A product is the exact
product rounded once to $p$ digits at the exponent $e_1 + e_2$ plus the digits
discarded. A quotient is formed by one division of $a \cdot 10^{k}$ with
$k = \max(0, p + 2 + n_b - n_a)$ ($n_a$, $n_b$ the digit counts of the
coefficients), which gives at least $p + 2$ digits, rounded with `ZeroFiveUp` so
that a nonzero remainder leaves the last digit off 0 and 5, and then rounded
once to $p$ digits; `rounded` and `inexact` are raised. A quotient with a
finite decimal expansion (the remainder test of the same division) is left to
the general route, because its exponent follows the ideal-exponent rules. The
general route scales the dividend by $10^{p + n_b + 2}$ whatever $n_a$ is, which
makes the quotient about twice as long as it must be; the value, the exponent
and the flags of an inexact quotient do not depend on the number of guard
digits beyond $p + 2$ (rounding sees the discarded part only through its
position relative to the midpoints, and `ZeroFiveUp` preserves that), so the
plain path uses the shorter scale. The white-box test compares both routes for
`multiply` and `divide` on random operands of 1 to 120 digits, with exact
quotients (a product divided by one of its factors, divisors $2^a 5^b$), short
divisors with repeating expansions, carries into $10^p$, chained contexts and
all rounding modes.

### Division

`divide` handles $0$, $\infty$ and exact divisions by powers of ten and by
small exact divisors separately. Otherwise it scales the dividend by
$10^{t}$ with $t = p + d(c_2) + 2$, so that $Q = c_1 10^{t} / c_2 \ge
10^{p+2}$ has at least $p + 3$ integer digits, rounds $Q$ to an integer $q$
with `ZeroFiveUp` (explained below), and then rounds $q$ to $p$ digits in the
context mode. Whether the quotient
terminates is decided exactly (`has_finite_decimal_expansion_repr`: $c_1/c_2$
terminates iff $c_2 / \gcd(c_1, c_2)$ has no prime factors other than 2 and 5),
which selects the ideal-exponent cohort for exact quotients and forces
`Inexact` with a $p$-digit coefficient for the others. An exact quotient that
needs rounding, from any of these paths, goes to the subnormal grid only when
its value is below $10^{e_{\min}}$ and is otherwise rounded once to $p$
digits, as in the finalizer: at precision 5, `divide(77223, 16E+21)` is
`4.8264E-18`.

The two successive roundings are equivalent to one for the directed modes,
because truncations compose:
$\lfloor \lfloor y/10^j \rfloor / 10^m \rfloor = \lfloor y/10^{j+m} \rfloor$.
For the half modes a first rounding in the context mode could *manufacture a
tie*: the discarded digits of $q$ are exactly $50\cdots0$ while $Q \ne q$. At
precision 1, $1/2222 = 0.00045004\ldots$ would give $q = 4500$ (unit
$10^{-7}$), and the second rounding would see a tie and return `0.0004`. The
first rounding therefore uses `ZeroFiveUp`: when $Q \ne q$ it leaves a last
digit other than 0 and 5, so $q$ is neither a $p$-digit number nor a $p$-digit
midpoint and lies strictly on the same side of every such point as $Q$. The
second rounding then returns $\circ_p(Q)$ for every mode $\circ$, and
`divide(1, 2222)` at precision 1 is `0.0005`.[^gda-div-05up]

[^gda-div-05up]: This is decNumber's `DEC_ROUND_05UP` device. With the
    context mode in the first rounding, a sweep of $c_1 < 20$, $c_2 < 3000$,
    $p \le 3$ finds 12 misrounded quotients.

### Square root

`sqrt` first tries an exact root: it removes trailing zeros, makes the
exponent even, takes the integer square root $(s, \rho)$ with $s^2 + \rho = c$
by Newton's iteration $a \leftarrow \lfloor (a + \lfloor c/a \rfloor)/2
\rfloor$, and accepts $\rho = 0$, then pads towards the ideal exponent
$\lfloor e/2 \rfloor$ within $p$ digits. An exact root longer than $p$
digits is an exact value like any other, so the finalizer rounds it once,
ties included: at $p = 1$, $\sqrt{2.25} = 1.5$ is a tie and gives `2` in
half-even and `1` in half-down. Otherwise the root is irrational and the
package rounds it directly at the final position. With root exponent $f = \max(E_{\mathrm{tiny}}, \lfloor \hat
e/2 \rfloor - p + 1)$ it computes $s = \lfloor \sqrt{c\,10^{e - 2f}} \rfloor$
and decides the increment by comparing the radicand with the square of the
midpoint, which is exact in integers:

$$
\sqrt{N} \gtrless s + \tfrac12
\iff 4N \gtrless (2s + 1)^2 .
$$

Rounding once at $f$ (not first at $p$ digits and then again at
$E_{\mathrm{tiny}}$) avoids double rounding of tiny roots. Because exact
roots were handled first, the comparison only ever decides an irrational
root, which cannot equal a midpoint, so the strict comparison decides every
mode. When $e - 2f < 0$ the radicand $N$ is not an integer; the comparison is
then made as $4c \gtrless (2s+1)^2\,10^{2f - e}$, still in integers, so no
digit of $c$ is truncated. The GDA function always rounds half to even.

### Integer powers

For an integer exponent $n$ the result is computed as the GDA specification
prescribes: if the exact power fits in $p$ digits it is returned exactly with
exponent $n e$; otherwise binary powering runs at working precision
$w = p + d(|n|) + 2$ (one digit fewer in subset contexts) with half-even
rounding after every product, and the final product is rounded to the
context. A negative $n$ starts from a rounded $1/x$ in extended contexts and
takes the reciprocal at the end in subset contexts. If that reciprocal already
overflows the working context, the power overflows, and the sign of the result
is the sign of $x^n$ (negative only for a negative $x$ and an odd $n$), not the
sign of $x$: $(-0.07)^{-8}$ overflows to $+\infty$ and $(-0.07)^{-7}$ to
$-\infty$.
The reciprocal keeps the cohort of the division ($1 / 5 \times 10^{-2}$ is
$2 \times 10^{1}$, not $20$), because the exponent of an exact power is the one
repeated multiplication gives: $0.05^{-8}$ is $2.56 \times 10^{10}$ with three
digits and no `Rounded`.

A zero exponent is decided before all of this: for a finite nonzero $x$ (and
for $\pm\infty$) $x^0$ is the integer $1$ with exponent $0$ and no conditions
in every context, a clamped one included ("the result will be 1 and exact"). It
is not folded down, as decNumber does not (`decNumberPower` leaves by an early
exit before its final rounding and clamping, `decCopyFit` and `decFinish`) and as
libmpdec does not. The IEEE interchange encoders fold a result down
themselves, at an exponent above $E_{\max} - P_{\max} + 1$, that is 90, 369 and
6111 for decimal32, decimal64 and decimal128, which the exponent $0$ of $1$ never
reaches; only a clamped context with $e_{\max} < p - 1$, which no IEEE format
has, could tell the two results apart.

The working context never clamps. `Clamped` and `Rounded` therefore come from two
places only: an intermediate rounding that discards non-zero digits makes the
result inexact, and the final rounding to the context folds down an exponent
above $E_{\mathrm{top}}$ and raises `Clamped` when it does. An exact result such
as $(-0.5)^{-2} = 4$ at precision 1 and $e_{\max} = 0$ raises neither.

Write $\mathbf u_w = \frac12 10^{1-w}$ and let the accumulator hold
$x^k(1 + \theta_k)$. A squaring gives
$x^{2k}(1+\theta_k)^2(1+\delta)$ and a multiplication by $x$ gives
$x^{k+1}(1+\theta_k)(1+\delta)$ with $|\delta| \le \mathbf u_w$, so
$1 + |\theta_{2k}| \le (1+|\theta_k|)^2(1+\mathbf u_w)$ and
$1 + |\theta_{k+1}| \le (1+|\theta_k|)(1+\mathbf u_w)$. By induction on
the binary expansion, $1 + |\theta_m| \le (1+\mathbf u_w)^{m-1}$ for every
$m \ge 1$: the error of binary powering is that of $m - 1$ successive
roundings, although only about $2\log_2 m$ products are formed.[^higham]
Starting from a rounded reciprocal adds the factor
$(1+\mathbf u_w)^{|n|}$, because its error is raised to the power $|n|$.
With $m$ the total exponent count ($|n| - 1$ for $n > 0$, $2|n| - 1$ for
$n < 0$) and $m \mathbf u_w \le 10^{-p}$,

$$
|\theta| \le (1 + \mathbf u_w)^{m} - 1 \le m\,\mathbf u_w\,(1 + m\,\mathbf u_w),
\qquad
|n|\,\mathbf u_w < 10^{d(|n|)} \cdot \tfrac12\,10^{1 - p - d(|n|) - 2}
= \tfrac12\,10^{-1-p}.
$$

Since the exact result $y$ satisfies $|y| < 10^{p}\,u$ for the unit $u$ in
the last place of the rounded result, a relative error $\theta$ is at most
$|\theta|\,10^p$ units. This gives at most $0.05$ units in the last place
for $n > 0$ and $0.1$ units for $n < 0$; adding the final rounding, an inexact
integer power is within $0.55$ or $0.6$ units in the last place in the half
modes and within $1.05$ or $1.1$ units in the directed modes. In subset
contexts $w$ is one digit smaller, so the working error grows tenfold and the
half-mode bound becomes about $1$ unit. None of this is correct rounding: a
result whose exact value lies within $0.1$ units of a rounding boundary can
round the wrong way. The specification does not require more for integer
powers. Exponents so large
that the result must overflow or underflow are detected beforehand from the
bounds $n(\hat e + 1) - 1$ and $n \hat e$ on the result's adjusted exponent.
The underflow shortcut is taken only when the upper bound is at most
$E_{\text{tiny}} - 2$, so the exact power is below $\tfrac12 10^{E_{\text{tiny}}}$,
and the result is that value rounded in the context's rounding mode: zero in
the half modes and `Down`, and $\pm 10^{E_{\text{tiny}}}$ when the mode rounds
away from zero for the result's sign.

An inexact result is delivered with the coefficient of $p$ digits: the working
arithmetic drops the trailing zeros of the rounded value, so they are restored
after the final rounding (GDA 1.70: a result with more digits than the precision
is "rounded (shortened) to exactly precision digits"; IEEE 754-2019 §5.2: the
cohort member of least possible exponent for an inexact result), the same as for
a non-integer exponent. `power(99999E-1, -1)` at precision 2 is `0.00010`. Only a
subset context strips the zeros, as Appendix A prescribes, and a subnormal
result has fewer digits because its exponent is $E_{\mathrm{tiny}}$.

Tininess is judged on the exact power, before rounding (GDA 1.70: Subnormal when
the adjusted exponent is below $e_{\min}$ "before any rounding", Underflow when the
result is also inexact). The working arithmetic only sees the power rounded to $w$
digits, so when the delivered result is exactly $10^{e_{\min}}$ the side of the
exact power is decided separately: the power is recomputed at precision
$w' = p + d(|n|) + 6$, then doubled (five attempts in all), with relative error below
$10^{d(|n|) + 2 - w'}$ (at most $2|n|$ roundings of $\mathbf u_{w'}$), and compared
with $10^{e_{\min}}(1 \pm 10^{d(|n|) + 2 - w'})$. A power outside that band is
subnormal exactly when it is below $10^{e_{\min}}$; for
$1/1.00000000000000000001$ at $p = 1$ and $e_{\min} = 0$ the exact value
$0.99999999999999999999$ is separated at $w' = 32$, so the result `1` carries
`Subnormal` and `Underflow`. The test is made only when tininess is detected
before rounding, as GDA does.

### Correctly rounded `exp`, `ln`, `log10` and non-integer `power`

These functions are evaluated by certified interval arithmetic and a Ziv-style
refinement loop.[^ziv] For $f(x)$:

1. **Exact cases first.** $\exp 0 = 1$, $\ln 1 = 0$, $\log_{10} 10^k = k$,
   special operands, domain errors, and the cases `power` can decide exactly
   ($x^{1/2}$ via `sqrt`, powers of ten, $1^y$, guaranteed overflow or
   underflow, and exact rational powers: $y = a/q$ in lowest terms with $x$
   a perfect $q$-th power, such as $4^{1.5} = 8$, the root taken before the
   power so no intermediate is longer than the result; and $10^k$ to a
   non-integral $y$ with $ky$ an integer, which is the exact $10^{ky}$ in every
   rounding mode, `decimal_power_ten_noninteger_result`) never
   reach the loop. An exact result is a boundary of its rounding cell in the
   directed modes (and an exact midpoint is one in the half modes), which the
   loop could never certify.
2. **Enclose the input.** $x$ is converted to a binary ball $[x^-, x^+]$ at
   $w$ bits with directed rounding (`to_bin_float` towards $-\infty$ and
   $+\infty$), so $x \in [x^-, x^+]$ exactly.
3. **Enclose the output.** `ball_float` evaluates $f$ on the ball and returns
   $[L, U] \ni f(x)$ (for `log10`, $\ln$ divided by a cached enclosure of
   $\ln 10$; for `power`, $\exp(y \ln x)$ through enclosures of $\ln x$).
4. **Certify a candidate.** A decimal approximation $\tilde y$ (the ball
   midpoint; `power` may use a decimal series evaluation) is rounded to $r$.
   The candidate is only a guess that the test below certifies: the result
   is $r$ when the whole enclosure lies strictly inside the rounding cell of
   $r$, and then the midpoint of the enclosure, which belongs to it, rounds to
   the same cell. `exp` therefore takes the midpoint (the series with the same number of
   digits when $|x| \ge 10^3$, where the midpoint is a binary float of enormous
   exponent), converted to
   $\max(p + 8, \lfloor 0.31\,w \rfloor + 4)$ digits so that the conversion
   error is below the radius of the enclosure and cannot carry the candidate
   onto a cell boundary that the enclosure itself avoids. Let $(a, b)$
   be the open interval of reals around $r$ that round to $r$: the two
   midpoints with the neighbours for the half modes, $(r, r^+)$ or $(r^-, r)$
   for the directed ones (the real rounding cell of a directed mode is
   half-open, $[r, r^+)$ or $(r^-, r]$; the test uses the open interior, which
   is sufficient). Its endpoints are exact decimals; each is enclosed in
   binary, and the result is accepted when
   $$
   a \le a^+ < L \le f(x) \le U < b^- \le b ,
   $$
   which proves $\mathrm{round}(f(x)) = r$. A second test rounds both exact
   dyadic endpoints $L$ and $U$ to the context; since every rounding mode is
   monotone, $\mathrm{round}(L) = \mathrm{round}(U) = r$ also proves
   $\mathrm{round}(f(x)) = r$.
5. **Refine.** Otherwise the working precision grows,
   $w \leftarrow w + \max(32, \lfloor w/2 \rfloor)$; at most $L$
   evaluations are made, where $L$ is the refinement limit of the
   `GdaContext` (`GdaContext::refinement_limit`, default twelve, so the
   last evaluation runs at roughly $1.5^{11} \approx 86$ times the starting
   precision).

The starting precision is $w_0 = \max(128, 4D + 64)$ bits with
$D = \max(d(c), p)$: four bits per decimal digit exceed
$\log_2 10 \approx 3.32$, so the input is carried without loss of decimal
information and 64 guard bits remain. For arguments with $\hat e = 0$ in a
wide, unclamped context with $p \le 64$, a cheaper first attempt uses about
$\frac{10}{3} D + 12$ bits and falls back to $w_0$ if it cannot certify.

The loop always stops, after at most $L$ evaluations (twelve by default). With
`with_refinement_limit(None)` the count is unbounded, but the loop still stops
when the working precision passes $\max(8\,000\,000,\ 256\,w_0)$ bits (at most
$10^9$), with the same certification failure, so the work and the memory stay
bounded. It certifies a
result whenever $f(x)$ is neither a representable number nor a midpoint (for
the half modes) and the budget is large enough, because the enclosure shrinks
to a point while $f(x)$ stays at a positive distance from every rounding
boundary. For `exp`, `ln` and
`log10` this always holds after step 1: by the Lindemann–Weierstrass theorem
$e^x$ is transcendental for rational $x \ne 0$, hence $\ln x$ is irrational
for rational $x \ne 1$, and $\log_{10} x$ is rational only for integral
powers of ten; representable numbers and midpoints are rational. If the
budget is still exhausted (for example a `power` whose exact value is a
midpoint and is not caught in step 1), the `try_*` methods return a
certification failure and the GDA functions return NaN with
`InvalidOperation`, never an unproven result.

The GDA functions `exp`, `ln`, `log10` and `sqrt` pass a copy of the context
with `HalfEven` rounding, because the specification defines these functions as
correctly rounded with round-half-even regardless of the context mode; `power`
uses the context's mode, as the specification and its test vectors require,
and reports non-integer powers as `Inexact` with $p$ digits even when the
power happens to be exact (`decimal_power_noninteger_gda_result`), and never as `Clamped` unless the result rounds to zero: the padded form of a nonzero result has an exponent of at most $e_{\max} - p + 1$, so no fold-down is left to report, whatever route computed it (a square root for the exponent $0.5$, an exact rational power, a power of ten, the certified loop). The exact
value is the correctly rounded one in every direction, so a directed mode never
adds a unit in the last place: `power(1E-5, 1.2)` is `1E-6` padded to $p$ digits
with `Inexact` and `Rounded` in every mode, as `power.decTest` rows powx2039
and powx2040 show for `1^y` in `ceiling`. Two more
rules are implemented. First, these functions accept only contexts with $p$,
$e_{\max}$ and $-e_{\min}$ at most 999,999 (`math_context_is_restricted`,
raising `InvalidContext` otherwise). That is a deliberate implementation limit,
decNumber's `DEC_MAX_MATH`, not a rule of the GDA operation text: the official
decTest suite requires it (`power.decTest` powx4001 to powx4005 and the
matching rows of `exp.decTest`, `ln.decTest` and `log10.decTest`), and GDA 1.70
permits it through the Invalid context condition, which covers a precision that
exceeds the capability of the implementation. Second, in subset arithmetic `ln` reproduces the result of the classic reference
algorithm, which can be one unit in the last place above the correctly rounded
one (`decimal_ln_subset_result`), because the legacy subset test vectors
encode that result.

[^ziv]: A. Ziv, "Fast evaluation of elementary mathematical functions with
    correctly rounded last bit", *ACM TOMS* 17(3), 1991. On ball arithmetic see
    J. van der Hoeven, "Ball arithmetic", 2009, and F. Johansson, "Arb: efficient
    arbitrary-precision midpoint-radius interval arithmetic", *IEEE Trans.
    Computers* 66(8), 2017.

### Coefficient representation and kernels

The kernel lives in `internal/decimal_kernel` and is shared with `decimal`
(see the previous section). A coefficient is either `Small(UInt64)` for values below $10^{18}$ or an array
of base-$10^9$ limbs with a cached digit count, both persistent: operations
never mutate operand limbs. Decimal limbs make digit counts, trailing-zero
removal, the half-unit comparison and the `ZeroFiveUp` last-digit test
constant-time or linear without binary-to-decimal conversion. Multiplication
and division choose among schoolbook, Karatsuba, Toom-3, a dual-modulus NTT,
Knuth's algorithm D, Burnikel–Ziegler and Newton reciprocal division by limb
count, with thresholds per target:

| Target | Karatsuba mul / square | Toom-3 | first NTT mul / square | Burnikel–Ziegler | Newton division |
| --- | ---: | ---: | ---: | ---: | ---: |
| native | 96 / 48 | 1,152 | 1,728 / 640 | from 2,816 | off |
| LLVM | 96 / 96 | 2,048 | 4,096 / 2,048 | 2,048 | 4,096 |
| Wasm, Wasm-GC, JS | 96 / 96 | 4,096 | 8,192 / 4,096 | 2,048 | 4,096 |

The thresholds are measured performance policy, not semantics: every kernel
returns the exact product or quotient, so the choice cannot change a result or
a flag. See [performance](../performance/decimal_gda.md) for the measurements.

## Correctness and invariants

- **Single rounding.** Every finite result other than integer `power`, the
  division case above and the to-integral operations on integers longer than
  $p$ digits is the exact result rounded once, so
  $|\hat x - x| \le \frac12 u$ in the half modes and $< u$ otherwise, and
  $|\hat x - x|/|x| \le \frac12 10^{1-p}$ outside the subnormal range.
- **Ideal cohort.** An exact result is returned at the representable exponent
  nearest to its ideal exponent, so operations on exact data keep their
  quantum (`2.50 × 3 = 7.50`).
- **Independence of status.** $F(\vec x, C)$ depends on $C$ only through its
  policy: results never depend on the sticky status or the traps.
- **Status algebra.** Status only grows, and the status after a threaded
  sequence is the union of the raised sets.
- **Trap determinism.** At most one trap fires per operation, selected by a
  fixed total order; `Trapped` carries the same value as `Completed` would.
- **Certified elementary functions.** A finite inexact result of `exp`, `ln`,
  `log10` or non-integer `power` is returned only together with a proof
  (Lemma 3 or 4 of the attachment) that it is the correctly rounded value; a
  failure to prove it yields NaN and `InvalidOperation`.
- **Total order.** `compare_total` is a total order on triples (sign, then
  class, then value, then exponent, then payload), and `Decimal::compare` is
  a total preorder in which NaNs form one class above all numbers.
- **Evidence.** The pinned `official` test suite passes 64,986/64,986 legal
  executable scalar rows and the legacy `official0` suite 16,124/16,124
  ([conformance](../conformance/decimal_gda.md)). These are finite claims: the
  half-mode division tie above and to-integral operands longer than the
  precision are not covered by any pinned row.

## Alternatives rejected

- **A mutable or global current context.** Rejected because it makes results
  and flags depend on evaluation order and hidden state (see the first design
  decision).
- **Traps as errors.** Rejected because the GDA-defined result would be lost.
- **Sharing the engine with `decimal`.** Rejected because one standard's
  change could alter the other's results; a measured duplication is cheaper
  than an accidental semantic coupling.
- **Binary floating point for elementary functions with a fixed number of
  guard digits.** Rejected because no fixed number of guard digits guarantees
  correct rounding (the table-maker's dilemma); certification with refinement
  does, and fails visibly when it cannot.
- **Normalizing every result.** Rejected because the quantum is part of a
  GDA number; normalization is available explicitly as `reduce`.

## Boundaries

- The package implements the GDA operations and nothing else: no
  trigonometric, hyperbolic or other functions outside the specification, and
  no IEEE 754 operations.
- It does not parse `.decTest` files, run test suites or read files; that is
  [`frontend/gda_expr`](../api/frontend/gda_expr.md) and the repository tools.
- It does not provide BID interchange; only DPD.
- It does not give correct rounding for integer powers beyond the GDA
  requirement.
- It does not provide a mutable or global context, and contexts carry no
  identity: two contexts with the same fields are interchangeable.
- It does not store exponents beyond the stored range: a finite value needs
  an exponent of at least $-2^{31}+3$ and an adjusted exponent of at most
  $2^{31}-2$, the range of the working context of the plain operators. The
  constructors reject a value outside it (they never replace it silently),
  context operations overflow or underflow against the context range, decided
  from the exact exponent, and the operations without a context overflow or
  underflow at the limits of the stored range.
