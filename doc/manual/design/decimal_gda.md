# decimal_gda design

This page explains the mathematics that `decimal_gda` implements and why the
package is built the way it is. The [tutorial](../tutorial/decimal_gda.md)
shows how to use it and the [API page](../api/decimal_gda.md) lists every
name.

## Design goal

`decimal_gda` implements the General Decimal Arithmetic Specification
(version 1.70) by M. F. Cowlishaw[^gda] as pure MoonBit values. A GDA operation
is specified to produce more than a number: it produces a result, a set of
*conditions*, an update of the flags of the context, and possibly a
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

## Mathematical background

### Numbers, cohorts and the adjusted exponent

A finite number of GDA is a triple $(s, c, q)$ with sign $s \in \{0, 1\}$,
coefficient $c \in \mathbb{N}$ and exponent $q \in \mathbb{Z}$, denoting

$$
v(s, c, q) = (-1)^s \cdot c \cdot 10^{q}.
$$

The map $v$ is not injective: $(0, 250, -2)$ and $(0, 25, -1)$ both denote
$2.5$. The triples with the same value form a *cohort*. GDA keeps the triple,
not only the value, because the exponent carries meaning: it gives the
*quantum* $10^q$, and "2.50" was measured to the cent. Zero is signed, so
$(1, 0, q)$ is $-0$. For $c > 0$ write $d(c)$ for the number of decimal
digits of $c$ and

$$
\hat q = q + d(c) - 1
$$

for the *adjusted exponent*, the exponent of the leading digit:
$10^{\hat q} \le |v| < 10^{\hat q + 1}$. Besides finite numbers there are the
special values $\pm\infty$ and the quiet and signaling NaNs, which carry a sign
and a payload $c$.

### Contexts and the representable set

A context fixes a precision $p \ge 1$, a rounding, an exponent range
$E_{\min} \le E_{\max}$ and a clamp bit. A finite number is *representable*
in the context when

$$
d(c) \le p, \qquad \hat q \le E_{\max}, \qquad q \ge E_{\mathrm{tiny}}
\;\text{ where }\; E_{\mathrm{tiny}} = E_{\min} - p + 1,
$$

and, if clamping is on, also $q \le E_{\mathrm{top}} = E_{\max} - p + 1$.

The value $E_{\mathrm{tiny}}$ is the exponent of the smallest unit. A number
with $\hat q = E_{\min}$ and $p$ digits has $q = E_{\min} - p + 1$, and numbers
below $10^{E_{\min}}$ (the *subnormal* range) keep that unit while losing
leading digits. The value $E_{\mathrm{top}}$ is the exponent of the largest
$p$-digit number with $\hat q = E_{\max}$. Clamping makes the set of exponents
exactly the one an IEEE interchange format can encode, which is why the
`decimal32`, `decimal64` and `decimal128` presets clamp.

### The arithmetic rule: exact result, then round once

Every arithmetic operation in GDA is defined by the same two-step rule:

1. compute the exact mathematical result $x$ and choose, among the triples
   that denote $x$, the one whose exponent is closest to the operation's
   *ideal exponent* $q^\ast$;
2. if that triple is not representable, round it to the context, raising
   conditions that describe what happened.

Step 1 is exact, so step 2 is a single rounding, and every bound below is a
bound on one rounding.

The package follows the rule literally. Each operation builds an exact
coefficient and exponent from its operands and then calls one shared
finalizer (in the source: `normalize_decimal_parts_ctx_repr` followed by
`finalize_finite_ctx`). The finalizer is the only code that rounds a finite
result or raises a condition related to precision or range.

### Ideal exponents

The ideal exponent is the coarsest quantum that represents the exact result
using only information present in the operands. Write the operands as
$x_1 = c_1 10^{q_1}$ and $x_2 = c_2 10^{q_2}$, and the operand of the square
root as $x = c\,10^{q}$, leaving signs aside. Let $q_{\min}$ be the smaller of
the two exponents, $\min(q_1, q_2)$. The derivations are short:

$$
\begin{aligned}
x_1 \pm x_2 &= \bigl(c_1 10^{q_1 - q_{\min}} \pm c_2 10^{q_2 - q_{\min}}\bigr) 10^{q_{\min}},
  & q_{\min} &= \min(q_1, q_2),\\
x_1 \times x_2 &= (c_1 c_2)\, 10^{q_1 + q_2}, & &\\
x_1 \div x_2 &= \frac{c_1}{c_2}\, 10^{q_1 - q_2}, & &\\
\sqrt{x} &= \sqrt{c\,10^{q - 2\lfloor q/2 \rfloor}}\;10^{\lfloor q/2 \rfloor}. & &
\end{aligned}
$$

For addition, $q_{\min}$ is the largest exponent at which both operands have an
integer coefficient. It is therefore the largest exponent at which the sum is
guaranteed to be an integer multiple of the quantum, and the bracket is then an
exact integer coefficient. For multiplication the coefficient $c_1 c_2$ is an
integer at exponent $q_1 + q_2$ and in general at no larger one. For division
the quotient $c_1 / c_2$ need not be an integer, so the ideal $q_1 - q_2$ is
used only when it is reachable. The exact quotient is written with the exponent
nearest to $q_1 - q_2$ that keeps an integer coefficient of at most $p$ digits,
and an inexact quotient uses all $p$ digits. For the square root,
$\lfloor q/2 \rfloor$ is the exponent of the root whose square has the largest
even exponent not above $q$, namely $2\lfloor q/2 \rfloor$.

The table lists the ideal exponent $q^\ast$ of each operation. In it, $n$ is
the integer operand of `scaleb` and of an integer `power`, and $k$ is an integer.

| Operation | Ideal exponent $q^\ast$ |
| --- | --- |
| `add`, `subtract`, `fma` (sum part) | $q_{\min}$ |
| `multiply`, `fma` (product part) | $q_1 + q_2$ |
| `divide` | $q_1 - q_2$ if exact, else $p$ digits |
| `sqrt` | $\lfloor q/2 \rfloor$ if exact, else $p$ digits |
| `remainder`, `remainder_near` | $q_{\min}$ |
| `divide_integer`, `to_integral_*` | $\max(q, 0)$ for the integral value, 0 for a quotient |
| `quantize`, `rescale` | the requested exponent |
| `scaleb` | $q + n$ |
| `power` with integer $n$, exact | $n q$ |
| `exp`, `ln`, `log10`, non-integer `power` | $p$ digits (always inexact, except `exp(0)`, `ln(1)`, `log10(10^k)`) |
| `plus`, `minus`, `abs`, `apply` | $q$ |

A zero result has no leading digit, so its exponent is simply the ideal one,
clamped into $[E_{\mathrm{tiny}}, E_{\max}]$, or into
$[E_{\mathrm{tiny}}, E_{\mathrm{top}}]$ under clamping. For a zero, `quantize` and `rescale`
follow the rule too: the requested exponent must be at most
$E_{\max}$, and under `clamp` one above $E_{\mathrm{top}}$ is folded down to it
with `clamped`, as decNumber's `decQuantizeOp` does by calling `decFinalize`
for a zero.

For a zero quotient, `divide_integer` builds the zero at the ideal exponent 0
and then passes it to the shared finalizer. The zero keeps the sign of the quotient,
and clamping can fold the exponent down without the change of an exact zero's
exponent counting as rounding.

The sign of an exact zero sum is $+$ unless both operands are negative, or the
rounding is `Floor` and either operand is negative (GDA 1.70, page 24
(Arithmetic operations)). This is the decimal form of the rule of IEEE 754-2019
6.3 that $x - x = +0$ except when rounding towards $-\infty$.

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

Rounding shortens the coefficient of an exact result to the $p$ digits of the
context's precision. Let the exact result be $x = (-1)^s c\,10^{q}$, with sign
$s$, coefficient $c$ and exponent $q$, and let $d(c) = p + k$ with $k \ge 1$,
where $d(c)$ is the number of decimal digits of $c$. Divide off the $k$ low
digits, $c = h\,10^{k} + r$ with $0 \le r < 10^k$, so that $h$ is the retained
head and $r$ the discarded tail. Each of the eight rounding algorithms (GDA
1.70, pages 13 and 14 (Abstract representation of context)) returns
$\hat x = (-1)^s (h + \delta)\,10^{q+k}$ with an increment $\delta \in \{0, 1\}$,
and the eight differ only in $\delta$ (in the source:
`should_increment_decimal_repr`). Below, $[P]$ is 1 when the condition $P$
holds and 0 otherwise:

$$
\begin{aligned}
\delta_{\mathrm{Down}} &= 0, &
\delta_{\mathrm{Up}} &= [r > 0],\\
\delta_{\mathrm{Ceiling}} &= [r > 0 \wedge s = 0], &
\delta_{\mathrm{Floor}} &= [r > 0 \wedge s = 1],\\
\delta_{\mathrm{HalfUp}} &= [2r \ge 10^k], &
\delta_{\mathrm{HalfDown}} &= [2r > 10^k],\\
\delta_{\mathrm{HalfEven}} &= [2r > 10^k \vee (2r = 10^k \wedge h \text{ odd})], &
\delta_{\mathrm{ZeroFiveUp}} &= [r > 0 \wedge h \equiv 0 \pmod 5].
\end{aligned}
$$

The algorithm `ZeroFiveUp` reads "round towards zero, unless the retained last digit is 0 or
5". After it, a last digit of 0 or 5 means the rounding was exact, and any
other last digit after an inexact rounding is never 0 or 5. Rounding the
result again to at least one digit fewer, in any rounding algorithm,
therefore gives the same value as rounding the exact result once in that
algorithm (GDA 1.70, page 14 (Abstract representation of context), note 17, states this use). The retained last
digit acts as a *sticky digit*: when something nonzero was discarded, it is
moved off 0 and 5, the values at which a later rounding tests the discarded
part against zero or half. Round-to-odd does the same in binary.

The comparison $2r$ versus $10^k$ is done exactly on the [decimal
limbs](#coefficient-representation-and-kernels) of the coefficient (in the
source: `dec_coeff_div_pow10_round_info_repr` returns the quotient, whether
$r > 0$, and the sign of $2r - 10^k$). If $h + \delta = 10^p$, the rounded
coefficient has $p + 1$ digits; its last digit, a zero, is dropped and the
result is $10^{p-1} \cdot 10^{q+k+1}$ (GDA 1.70, page 14 (Abstract representation of context)). Before rounding,
the [finalizer](#the-arithmetic-rule-exact-result-then-round-once) first
reduces $c$ by dropping its trailing zeros; when the exact coefficient is too
long only because of zeros, the result is exact and only `Rounded` is raised.

Let $u = 10^{q+k}$ be the unit in the last place of the result $\hat x$. Since
$\hat x - x = (-1)^s(\delta\,10^k - r)\,10^{q}$, and since
$|\delta\,10^k - r| \le 10^k/2$ for the half-way algorithms (`HalfUp`,
`HalfDown`, `HalfEven`) and $< 10^k$ for the directed algorithms (`Down`, `Up`,
`Ceiling`, `Floor`) and for `ZeroFiveUp`,

$$
|\hat x - x| \le \tfrac12 u \;\;(\text{half-way algorithms}), \qquad
|\hat x - x| < u \;\;(\text{directed algorithms and } \mathtt{ZeroFiveUp}),
$$

and since $c \ge 10^{p+k-1}$ gives $|x| \ge 10^{p-1} u$,

$$
\frac{|\hat x - x|}{|x|} \le \tfrac12\,10^{1-p} \;\;(\text{half-way algorithms}),
\qquad
\frac{|\hat x - x|}{|x|} < 10^{1-p} \;\;(\text{directed algorithms and } \mathtt{ZeroFiveUp}).
$$

The bound $\frac12 10^{1-p}$ is the decimal unit roundoff $\mathbf u$ of the
standard model $\mathrm{fl}(x \circ y) = (x \circ y)(1 + \varepsilon)$,
$|\varepsilon| \le \mathbf u$, in which $\circ$ is an arithmetic operation,
$\mathrm{fl}$ its rounded result and $\varepsilon$ the relative error.[^higham]
Rounding raises `Rounded` whenever $k \ge 1$ digits are removed and `Inexact`
whenever a removed digit was nonzero ($r > 0$).

[^higham]: N. J. Higham, *Accuracy and Stability of Numerical Algorithms*,
    2nd ed., SIAM 2002, section 2.2. Decimal wobble is larger than binary: the
    relative spacing varies by a factor of 10 across a decade, against 2 in
    binary (Goldberg 1991, section 1.2).

The full proofs of this bound and of the other rounding facts on this page are
in the attachment:

[Rounding proofs for decimal_gda](../../attachments/design_decimal_gda_rounding.typ)

### Subnormal results and $E_{\mathrm{tiny}}$

Let $E_{\min}$ be the least adjusted exponent of a normal number in the
context, and $E_{\mathrm{tiny}} = E_{\min} - p + 1$ the least exponent a
result may have (GDA 1.70, page 11 (Normal numbers, subnormal numbers and
Underflow)). If the exact result has $\hat q < E_{\min}$, where
$\hat q = q + d(c) - 1$ is its adjusted exponent, it is *tiny*. A tiny result
may still need the unit $10^{E_{\mathrm{tiny}}}$ at most, so the rounding
position is not "keep $p$ digits" but "keep the digits at or above
$10^{E_{\mathrm{tiny}}}$". With an exact coefficient of $D$ digits and
exponent $q$, rounding to $p$ digits would give the exponent
$q + \max(0, D - p)$; when that is below $E_{\mathrm{tiny}}$ the finalizer
instead removes $k = E_{\mathrm{tiny}} - q$ digits, possibly all of them, in
one rounding.

A longer coefficient whose exponent is below $E_{\mathrm{tiny}}$ but whose
magnitude is normal is rounded once to $p$ digits; rounding it to the
subnormal grid first would round twice. In decimal32 ($p = 7$,
$E_{\min} = -95$), $3.000001\cdot 10^{-45} \times 1.500001\cdot 10^{-45}$ is
`4.500005E-90`.

The absolute error is then bounded by the subnormal unit,

$$
|\hat x - x| \le \tfrac12\,10^{E_{\mathrm{tiny}}} \;\;(\text{half-way algorithms}),
$$

but the relative error is not bounded by $\mathbf u$ any more: the precision
of the value falls gradually from $p$ digits to 1 as $|x|$ drops from
$10^{E_{\min}}$ to $10^{E_{\mathrm{tiny}}}$.

The conditions record this. `Subnormal` is raised for every tiny result; GDA
1.70 and the functions of this package detect tininess *before* rounding, from
the exact $\hat q$ (GDA 1.70, page 11 (Normal numbers, subnormal numbers and Underflow)). `Underflow` is raised when a tiny
result is also inexact (GDA 1.70, pages 11 and 12 (Normal numbers, subnormal numbers and Underflow)), and `Clamped` when it
rounds to zero; the zero then takes the exponent $E_{\mathrm{tiny}}$ (GDA 1.70, page 12 (Normal numbers, subnormal numbers and Underflow), gives the
exponent). Because tininess is decided before rounding, a result such as
$0.9951$ at $p = 3$, $E_{\min} = 0$ raises `Subnormal` and `Underflow` even
though it rounds to the normal number `1.00` (GDA 1.70, page 12 (Normal numbers, subnormal numbers and Underflow), says a
subnormal result is indicated even when it rounds to $10^{E_{\min}}$).

GDA 1.70 has no other rule: the after-rounding rule is an IEEE 754 choice for
binary formats only (IEEE 754-2019 7.5), so the package has no tininess
parameter.

### Clamping

With `clamp`, a result with $q > E_{\mathrm{top}}$ but $\hat q \le E_{\max}$
is representable as a value but not as a triple. Here $\hat q = q + d(c) - 1$
is the adjusted exponent of the result, $d(c)$ is the number of digits of its
coefficient $c$, and $E_{\mathrm{top}} = E_{\max} - p + 1$ is the largest
exponent a triple of at most $p$ digits can have. Since $\hat q \le E_{\max}$
means $d(c) + q - 1 \le E_{\max}$, padding the coefficient with
$q - E_{\mathrm{top}}$ zeros gives

$$
d\bigl(c\,10^{q - E_{\mathrm{top}}}\bigr) = d(c) + q - E_{\mathrm{top}}
\le E_{\max} + 1 - E_{\mathrm{top}} = p,
$$

so the padded triple has at most $p$ digits and the same value. The package
does exactly this and raises `Clamped`; the value is unchanged, only the
cohort member differs. Zeros are clamped the same way, by moving their
exponent into $[E_{\mathrm{tiny}}, E_{\mathrm{top}}]$.

### Overflow

If the rounded result has $\hat q > E_{\max}$ the operation overflows:
`Overflow`, `Inexact` and `Rounded` are raised and the result is either
$\pm\infty$ or the largest finite number of the same sign,
$N_{\max} = (10^p - 1) \cdot 10^{E_{\mathrm{top}}}$. Which one follows from
treating $\infty$ as the representable number beyond $N_{\max}$ and applying
the rounding algorithm to it as to any other result. The half-way algorithms
and `Up` move away from zero, so they reach $\infty$. The algorithms `Down` and `ZeroFiveUp`
move towards zero, so they stop at $N_{\max}$: `ZeroFiveUp` would round away
from zero only from a last digit 0 or 5, and the last digit of $N_{\max}$ is 9.
With `Ceiling` the result is $+\infty$ for a positive and $-N_{\max}$ for a
negative overflow, and with `Floor` it is the mirror image (in the source: `overflow_to_infinity`):

| Rounding | positive overflow | negative overflow |
| --- | --- | --- |
| `HalfEven`, `HalfUp`, `HalfDown`, `Up` | $+\infty$ | $-\infty$ |
| `Down`, `ZeroFiveUp` | $+N_{\max}$ | $-N_{\max}$ |
| `Ceiling` | $+\infty$ | $-N_{\max}$ |
| `Floor` | $+N_{\max}$ | $-\infty$ |

### Conditions, signals and traps

GDA distinguishes *conditions* (what happened: division by zero, a result was
rounded, a conversion was malformed, and so on), *signals* (the named events a
condition triggers) and *traps* (signals the user has asked to interrupt the
computation). The package keeps one flag per condition (thirteen) and one
trap-enabler per signal (nine), and maps conditions to the GDA signals by one
rule: the four detailed invalid conditions conversion syntax, division
impossible, division undefined and invalid context all signal
`InvalidOperation` (GDA 1.70, pages 51 and 52 (Exceptional conditions)).
Formally, let $\mathcal S$ be the thirteen flags and let
$\iota \subset \mathcal S$ be the five invalid-family flags. For a set $R$ of
raised flags and a signal $\sigma$,

$$
\sigma \in^\ast R \iff
\begin{cases}
R \cap \iota \neq \emptyset & \sigma = \mathrm{InvalidOperation},\\
\sigma \in R & \text{otherwise,}
\end{cases}
$$

which is `GdaFlags::contains`. An operation takes operands $\vec x$ and a
context $C$ and is then the state machine

$$
(\vec x, C) \;\longmapsto\;
\begin{cases}
\mathrm{Completed}(v, C, \emptyset) & R = \emptyset,\\
\mathrm{Completed}(v, C', R) & R \neq \emptyset,\ \tau = \bot,\\
\mathrm{Trapped}(\tau, v, C', R) & \tau \neq \bot,
\end{cases}
$$

where $(v, R) = F(\vec x, \pi(C))$ is the result and the raised flags computed
from the operands and the *policy* $\pi(C)$ (precision, rounding, exponent
range, clamp, extended) alone,

$$
C'.\mathrm{flags} = C.\mathrm{flags} \cup R \cup
\bigl\{\mathrm{InvalidOperation} \mid R \cap \iota \neq \emptyset\bigr\},
\qquad C'.\pi = C.\pi,\quad C'.\mathrm{traps} = C.\mathrm{traps},
$$

and $\tau$ is the first signal in the precedence list InvalidOperation,
DivisionByZero, Overflow, Underflow, Subnormal, Inexact, Rounded, Clamped,
LostDigits with $\tau \in^\ast R$ and $\tau \in C.\mathrm{traps}$, or $\bot$ if
there is none (in the source: `complete_gda` and `trapped_signal`).

Three properties follow directly from the definition and are what users rely
on:

1. **The value does not depend on the flags or the traps.** $v$ and $R$ are
   functions of $(\vec x, \pi(C))$; the flags and the traps only enter $C'$ and
   $\tau$. Enabling a trap therefore never changes a result, and `Trapped` can
   carry the defined result.
2. **The flags of the context are monotone and idempotent.** $C.\mathrm{flags} \subseteq C'.\mathrm{flags}$, and since $\cup$
   is associative, commutative and idempotent, the flags after a threaded
   sequence are the union of all raised sets, independent of how the sequence
   is grouped.
3. **The trap choice is deterministic.** The precedence list is a total order
   on signals, so one operation selects at most one trap, whatever the order in
   which its conditions were detected.

```moonbit
///|
test "status is the union of the raised sets" {
  let ctx = @decimal_gda.GdaContext::new(precision=3)
  let d = (s : String) => @decimal_gda.Decimal::from_string(s).unwrap()
  let a = @decimal_gda.divide(d("1"), d("3"), ctx) // Inexact, Rounded
  let b = @decimal_gda.divide(d("1"), d("0"), a.next_context()) // DivisionByZero
  let expected = a.raised().combine(b.raised())
  inspect(b.next_context().flags() == expected, content="true")
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
whose flags operations set. GDA 1.70 says that the flags are reset only by
explicit user action (page 15 (flags and trap-enablers)). Most
implementations (decNumber, Python's `decimal`) keep a current context per thread.

**Options.** (a) A mutable context passed by reference; (b) a thread-local or
global current context; (c) an immutable context returned with every result.

**Choice: (c).** Every GDA function returns `GdaOutcome`, and the caller passes
`next_context()` to the next operation. The reasons are the three properties of
[Conditions, signals and traps](#conditions-signals-and-traps), and three
further facts:

- $F$ reads only the policy. The state machine therefore factors into a pure
  numerical part and a pure bookkeeping part, and both are referentially
  transparent: an expression can be re-evaluated, memoized or run on another
  thread without changing its result or its flags.
- A test runner can snapshot a context and run the same operation under it many
  times. The `.decTest` runner in
  [`frontend/gda_expr`](../api/frontend/gda_expr.md) does exactly that.
- MoonBit has no thread-local storage, so (b) would mean process-global state,
  which Luna-Flow excludes.

The cost is explicit threading; the
[`decimal_gda_checked`](decimal_gda_checked.md) package removes it for linear
pipelines. When nothing is raised, the input context is returned unchanged, so
exact operations do not allocate a new context.

### Keep a trap's defined result

In GDA a trap transfers control, but the specification still defines the result
the operation would have delivered, and the trap handler has access to it (GDA
1.70, page 15 (flags and trap-enablers)). Representing a trap as an error
(`Result::Err`, `raise`) would discard that value. `Trapped` keeps the value,
the next context and the raised set, so the caller can inspect, log or resume
from it. Property 1 of
[Conditions, signals and traps](#conditions-signals-and-traps) guarantees that
it is the same value as without the trap.

### Keep the detailed invalid conditions

The specification reports conversion syntax, division impossible, division
undefined and invalid context through the signal `InvalidOperation` (GDA 1.70,
pages 51 and 52 (Exceptional conditions)). The package keeps them as separate
*flags* and makes `contains(InvalidOperation)` true for each. Whenever one of
them is raised, `invalid_operation` is raised in the flags as well.

They are not signals. The trap set has nine trap-enablers, one for each of the
signals of the specification, and GDA has no trap-enabler for a condition
alone, so a trap cannot be set on one. The decTest files name conditions
(`Conversion_syntax`, `Division_undefined`, ...), which is why the flags stay at
thirteen. A program that only knows the GDA signals sees exactly the GDA
behaviour, while a test harness or a diagnostic can still tell a malformed
literal from $0/0$. `InvalidOperation` comes first in the precedence list of
[Conditions, signals and traps](#conditions-signals-and-traps), which makes an
`InvalidOperation` trap catch all four, as the specification requires.

### One finalizer, special values first

Each operation first decides the special cases (NaN propagation, invalid
operations, infinities, exact zeros), then builds an exact finite coefficient
and exponent, and only then calls the shared finalizer of
[the arithmetic rule](#the-arithmetic-rule-exact-result-then-round-once). No
coefficient algorithm raises a condition. This keeps the conditions a function
of the exact result and of the policy of the context (precision, rounding,
exponent range, clamp, extended), independent of which multiplication or
division kernel was chosen, and lets kernels be tuned without touching the
standard-facing behaviour.

### A GDA package independent of `decimal`

IEEE 754-2008 decimal arithmetic grew out of GDA, so the two agree on most
finite results, but their contracts differ:

| Aspect | `decimal_gda` (GDA 1.70) | `decimal` (IEEE 754-2019) |
| --- | --- | --- |
| Precision | any $p \ge 1$ per context | the format's $p$ (or a chosen one) |
| Rounding | eight rounding algorithms (GDA 1.70, pages 13 and 14 (Abstract representation of context)), including `HalfUp`, `HalfDown`, `ZeroFiveUp` | the rounding-direction attributes (IEEE 754-2019 4.3) |
| Conditions | flags in the context that stay raised until cleared, traps with defined results | per-operation flags returned with the value |
| Detailed invalid conditions, `LostDigits`, subset arithmetic | yes | no |
| Tininess | before rounding | before rounding |
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
coefficients, they raise no condition, and they know neither a rounding
algorithm, a context nor a flag. A change there cannot change which condition
an operation raises, only how fast the exact integer is found, and the kernel
imports neither decimal package (`tools/check_imports.py` checks that too).

A copy of this code in each package is rejected, because the two copies had
diverged: a fix in one did not reach the other, and `decimal` lacked the
small-value fast paths of `decimal_gda`. The thresholds are therefore one set, measured on the
shared kernel.

The increment decision of each rounding algorithm is shared too, because it is
a pure function of a coefficient and the digits that were discarded: whether the
kept magnitude grows by one unit in the last place, for each of the eight
rounding algorithms ([Rounding to precision](#rounding-to-precision) gives
each). Each package converts its own rounding type (`GdaRoundingMode` here)
into the kernel's own enumeration of rounding algorithms with one total match,
so the kernel knows neither type. What the decision is applied to, and every
flag, clamp, subnormal and overflow rule around it, stays in the finalizer of
each package. The exact integer helpers on which roots, logarithm series and
the logical digit operations are built are shared in the same way.

The engine that accumulates no flags in its context is private to the package
(in the source: `DecimalContext`, `DecimalFlags` and the `*_ctx` methods). The
functions named after the GDA operations are the only public spelling of every
operation, so each operation exists once. The engine returns flags per
operation, which is what the `Luna-Flow/arithmetic` trait implementations use.
The IEEE 754 contract lives in `decimal`.

### Fast paths that are proven equivalent

Two kinds of shortcut avoid the general machinery without changing any
observable result.

`parse`, `add`, `subtract`, `multiply` and `fma` take the small-integer
shortcut when all of these hold:

- all operands are integers with exponent 0 and coefficients below $10^{18}$;
- the exact result is a nonzero integer below $10^{18}$ with at most $p$
  digits;
- its adjusted exponent lies in $[E_{\min}, E_{\max}]$;
- exponent 0 is allowed by clamping;
- the context is extended.

Under these predicates the general path performs no rounding, raises no
condition and returns exponent 0 (the ideal exponent of every one of these
operations). The shortcut therefore returns `Completed(v, C, none)`, where $v$
is the value of the general path and $C$ the context passed in. A zero result
is excluded because its sign depends on the rounding.

An addend that lies below the last retained digit of the other is absorbed.
Let $x_1$ and $x_2$ be the operands of an addition, and write $q_i$ and
$\hat q_i$ for the exponent and the adjusted exponent of $x_i$. When $x_2$ is
much smaller, $\hat q_2 < \hat q_1 - p + 1$, the exact sum need not be formed.
Every digit of $x_2$ lies below the last retained digit of $x_1$, so $x_2$
influences the rounding only through its sign and its comparison with half a
unit:

$$
\hat x = \mathrm{round}\bigl(x_1 + x_2\bigr)
= \bigl(h + \delta(\operatorname{sign} x_2,\; |x_2| \lessgtr \tfrac12 u)\bigr) u,
$$

where $h$ and $u$ are the retained head and the unit in the last place of the
rounded result, as in [Rounding to precision](#rounding-to-precision). This is
the rounding table of that section with $r$ replaced by a sticky
representative of the same comparison class. The implementation evaluates
exactly that (in the source: `exact_base_small_addend_result`), comparing $x_2$
with $u/2$ exactly. The case where $x_1$ is a power of ten and $x_2$ has the
opposite sign (the unit below $x_1$ is ten times smaller) is excluded and
takes the general path.

The shortcut returns the overflow of $x_1$ rounded alone only when the sum
overflows as well, because overflow is judged on the rounded sum (see
[Overflow](#overflow)). That holds in two cases:

- $x_2$ has the sign of $x_1$, so the sum is larger in magnitude;
- $p \ge 2$ and $\hat q_1 \ge E_{\max} + 2$, so the sum is more than
  $0.9 \cdot 10^{\hat q_1}$.

Otherwise an opposite sign can pull the sum back into range, so the case
takes the general path: `add(9.5, -0.5)` at precision 1 and $E_{\max} = 0$ is
`9`, not an overflow. A non-extended context rounds the operands first, so the
shortcut is unchanged there.

The argument needs $x_1$ itself to end at or above the last retained
position, so this shortcut is taken only when $x_1$ fits the context exactly
(and not under `ZeroFiveUp`, whose rounding depends on the last kept digit).
When $x_1$ has digits below that position, or is exactly a midpoint, $x_2$ can
still move the sum across a boundary that the comparison with $u/2$ does not
see. An extended context then replaces $x_2$ by a *sticky unit*, as the
`decimal` package does. Let $t$ be the target exponent of $x_1$ alone and
$g = \min(q_1, t - 2)$. Every digit of $x_1$ and every rounding boundary of
the sum lies on the grid $10^{g}$. The boundaries are the grid $10^{t}$, its
midpoints, and the grid $10^{t-1}$ with its midpoints, which a cancellation
can reach. If $0 < |x_2| < 10^{g}$, the sum lies strictly between the same two
neighbours on that grid as $x_1 \pm 10^{g-1}$, with the sign of $x_2$. Rounding
that short value once therefore gives the result and the flags of the exact
sum under every rounding algorithm. At precision 7, `add(1598618.5, 1E-20)`
under `HalfEven` is `1598619`, and `subtract(1598618, 9.9E-11)` under
`ZeroFiveUp` is `1598617`.

The general route of `add` and `subtract` passes through the context-taking
engine (operand preparation, the sum, the normalizer, the finalizer, the
outcome), whose temporaries are records and tuples that allocate. The plain-sum
shortcut avoids them. Let $x_1$ be the operand of larger adjusted exponent. It
is taken when:

- the context is extended and does not clamp;
- both operands are finite and nonzero;
- the smaller adjusted exponent is not below $\hat q_1 - p + 1$, so no operand
  is absorbed;
- the nonzero exact sum has adjusted exponent in $[E_{\min}, E_{\max} - 1]$, so
  that after a possible carry into a digit beyond $p$ it can neither overflow
  nor be subnormal, and its exponent is not clamped.

The result is then the exact aligned sum rounded once to $p$ digits at the
exponent $\min(q_1, q_2)$ plus the digits discarded, with `rounded` raised when
digits were discarded and `inexact` when a nonzero one was. Dropping a run of
zero digits first and then rounding the rest gives the same value, exponent
and flags as rounding once. The shortcut computes that result directly (in the
source: `gda_add_plain`):

- The sum is formed in one limb array and rounded in place by the kernel (see
  the design of `internal/decimal_kernel`).
- The flags are shared constants. Sharing is not observable, because `GdaFlags`
  and `DecimalFlags` are immutable records compared by value.
- The outcome is built once. When the flags of the context already contain the
  raised conditions, the outcome carries the input context itself.

Every other case returns `None` and takes the general route, which remains the
definition. A test compares both routes for `add` and `subtract`
([conformance](../conformance/decimal_gda.md)).

`multiply` and `divide` take the same kind of shortcut as the plain sums, under
the same predicates: an extended context without clamping, finite nonzero
operands, and a result whose adjusted exponent lies in
$[E_{\min}, E_{\max} - 1]$, so that it can neither overflow, nor be subnormal,
nor change exponent for the exponent range. A product is the exact product
rounded once to $p$ digits at the exponent $q_1 + q_2$ plus the digits
discarded.

A quotient is formed in four steps. Let $a$ and $b$ be the coefficients of
dividend and divisor, with $n_a$ and $n_b$ digits, and
$k = \max(0, p + 2 + n_b - n_a)$ (a meaning of $k$ local to this section).

1. Divide $a \cdot 10^{k}$ by $b$ once. The quotient has at least $p + 2$
   digits.
2. Round it with `ZeroFiveUp`, so that a nonzero remainder leaves the last
   digit off 0 and 5 (see [Rounding to precision](#rounding-to-precision)).
3. Round the result once to $p$ digits.
4. Raise `rounded` and `inexact`.

A quotient with a finite decimal expansion (the remainder test of the same
division) is left to the general route, because its exponent follows the
[ideal exponent](#ideal-exponents) rules. The general route scales the
dividend by $10^{p + n_b + 2}$ whatever $n_a$ is, which makes the quotient
about twice as long as it must be. The value, the exponent and the flags of an
inexact quotient do not depend on the number of guard digits beyond $p + 2$,
because rounding sees the discarded part only through its position relative to
the midpoints, and `ZeroFiveUp` preserves that. The plain path therefore uses
the shorter scale. A test compares both routes for `multiply` and `divide`
([conformance](../conformance/decimal_gda.md)).

### Division

`divide` handles $0$, $\infty$ and exact divisions by powers of ten and by
small exact divisors separately. Every other quotient takes three steps. Let
$c_1$ and $c_2$ be the coefficients of the dividend and the divisor, and $p$ the
precision of the context.

1. Scale the dividend by $10^{T}$ with $T = p + d(c_2) + 2$. The scaled quotient
   is $Q = c_1 10^{T} / c_2$. Since $c_1 \ge 1$ and $c_2 < 10^{d(c_2)}$, the
   quotient satisfies $Q \ge 10^{p+2}$, so $Q$ has at least $p + 3$ integer digits.
2. Round $Q$ to an integer $Q_0$ with `ZeroFiveUp`, the rounding algorithm of
   [Rounding to precision](#rounding-to-precision); the tie it prevents is shown
   in the example of the half-way algorithms.
3. Round $Q_0$ to $p$ digits with the rounding of the context.

Whether the quotient terminates is decided exactly: $c_1/c_2$ terminates iff
$c_2 / \gcd(c_1, c_2)$ has no prime factors other than 2 and 5 (in the source:
`has_finite_decimal_expansion_repr`). The decision selects the ideal-exponent
cohort for exact quotients and forces `Inexact` with a $p$-digit coefficient
for the others. An exact quotient that needs rounding, from any of these
paths, goes to the subnormal grid only when its value is below
$10^{E_{\min}}$. Otherwise it is rounded once to $p$ digits, as in the
[finalizer](#the-arithmetic-rule-exact-result-then-round-once). At precision 5,
`divide(77223, 16E+21)` is `4.8264E-18`.

For the directed algorithms the two successive roundings are equivalent to
one, because truncations compose: for a real $y$ and integers $j, m \ge 0$,
$\lfloor \lfloor y/10^j \rfloor / 10^m \rfloor = \lfloor y/10^{j+m} \rfloor$.
That is, truncating twice is truncating once at the coarser position.

For the half-way algorithms a first rounding by the rounding of the context
could *manufacture a tie*: the discarded digits of $Q_0$ are exactly
$50\cdots0$ while $Q \ne Q_0$. At precision 1, $1/2222 = 0.00045004\ldots$
would give $Q_0 = 4500$ (unit $10^{-7}$), and the second rounding would see a
tie and return `0.0004`. The first rounding therefore uses `ZeroFiveUp`. When
$Q \ne Q_0$ it leaves a last digit other than 0 and 5. A $p$-digit number and
a $p$-digit midpoint both end in 0 or 5 in the unit of $Q_0$, so $Q_0$ is
neither of them and lies strictly on the same side of every such point as $Q$.
The second rounding then returns $\circ_p(Q)$ for every rounding algorithm
$\circ$, where $\circ_p(x)$ is $x$ rounded to $p$ digits by $\circ$. So
`divide(1, 2222)` at precision 1 is `0.0005`.[^gda-div-05up]

[^gda-div-05up]: This is decNumber's `DEC_ROUND_05UP` device; GDA 1.70, page 14
    (Abstract representation of context) gives `round-05up` for the same purpose, arithmetic at shorter
    lengths without double rounding. With the rounding of the context in the
    first rounding, a sweep of $c_1 < 20$, $c_2 < 3000$, $p \le 3$ finds 12
    misrounded quotients.

### Square root

The function `sqrt` first tries an exact root. Let $c$ be the coefficient and
$q$ the exponent of the operand. The function removes trailing zeros, makes
the exponent even and takes the integer square root $(z, \rho)$ of $c$, with
$z^2 + \rho = c$, by Newton's iteration, which updates the iterate $a$ by
$a \leftarrow \lfloor (a + \lfloor c/a \rfloor)/2 \rfloor$. It accepts
$\rho = 0$ and then pads towards the ideal exponent $\lfloor q/2 \rfloor$
within $p$ digits (GDA 1.70, page 39 (square-root)). An exact root longer than
$p$ digits is an exact result like any other, so the finalizer rounds it once,
ties included: at $p = 1$, $\sqrt{2.25} = 1.5$ is a tie, which gives `2` under
`HalfEven` and `1` under `HalfDown`.

Otherwise the root is irrational and the package rounds it directly at the
final position. The root exponent is
$f = \max(E_{\mathrm{tiny}}, \lfloor \hat q/2 \rfloor - p + 1)$, the scaled
radicand is $M = c\,10^{q - 2f}$, and the integer root is
$z = \lfloor \sqrt{M} \rfloor$. The increment is decided by comparing the
radicand with the square of the midpoint, which is exact in integers:

$$
\sqrt{M} \gtrless z + \tfrac12
\iff 4M \gtrless (2z + 1)^2 .
$$

Rounding once at $f$ (not first at $p$ digits and then again at
$E_{\mathrm{tiny}}$) avoids double rounding of tiny roots. Because exact roots
were handled first, the comparison only ever decides an irrational root, which
cannot equal a midpoint, so the strict comparison decides every rounding
algorithm. When $q - 2f < 0$ the radicand $M$ is not an integer; the comparison
is then made as $4c \gtrless (2z+1)^2\,10^{2f - q}$, still in integers, so no
digit of $c$ is truncated. The GDA function `sqrt` always rounds half to even
(GDA 1.70, page 39 (square-root)).

The route above can be shortened for an operand that is certainly not a
square. It takes one root to find out whether the operand is a square and, for
a non-square, a second root at the final position, with a midpoint comparison
that forms three products as long as the radicand. A random operand is never a
square, and the second root already decides the rounding. What remains is to
recognise a non-square without taking a root of it. The plain path (in the
source: `decimal_sqrt_plain`) rests on two steps.

1. One root decides the rounding. With $M$ and $z$ of the irrational root and
   $\rho = M - z^2$, the root is exact iff $\rho = 0$. Otherwise
   $M > (z + \tfrac12)^2$ iff $\rho > z$, because
   $(z + \tfrac12)^2 = z^2 + z + \tfrac14$ and $\rho$ is an integer. The
   comparison with the midpoint is therefore one comparison of $\rho$ with $z$.
2. A non-square is recognised without taking a root of it. Write the operand
   as $c_0 10^{k}$ with $c_0$ not divisible by 10, so that $c_0$ is the
   coefficient without its trailing zeros and $k$ is $q$ plus their number.
   The root is a decimal iff $k$ is even and $c_0$ is a square. If $k$ were
   odd, $10 c_0$ would have to be a square, so the root would be divisible by
   10, and $10$ would divide $c_0$. If $k$ is even, the root is
   $\sqrt{c_0}\,10^{k/2}$, a decimal only when $\sqrt{c_0}$ is one, that is,
   when $c_0$ is a square, since the square root of an integer is an integer
   or irrational. A square is a square modulo every integer, so the plain
   path takes an operand whose $k$ is odd, or whose $c_0$ is not a square
   modulo 64, 63, 65 or 11 (a remainder by a word each, from the lowest
   limbs). The operands that pass all four tests, every square and about one
   non-square in 120, are left to the route above. A square therefore pays
   the five remainders and does not pay a root twice as long as it needs.

The path also requires:

- the root is neither subnormal nor possibly beyond the range,
  $E_{\min} \le \lfloor \hat q/2 \rfloor < E_{\max}$, so the exponent of the
  result, after a carry too, is at most $E_{\max} - p + 1$ and no clamp folds
  it;
- the radicand is an integer, $q - 2f \ge 0$, that is, a coefficient of at
  most $2p$ digits.

The result has exactly $p$ digits at the exponent $f$; `Inexact` and `Rounded`
are raised. A white-box test compares it with the route above at the public
level (value, every condition, the flags of the context), on random operands,
squares and near squares ([conformance](../conformance/decimal_gda.md)).

### Integer powers

For a base $x$ and an integer exponent $n$, the result follows GDA 1.70, page 35
(power). If the exact power fits in $p$ digits, it is returned exactly with
exponent $n q$, where $q$ is the exponent of $x$. Otherwise binary powering runs
at working precision $w = p + d(|n|) + 2$ digits, one digit fewer in subset
contexts, where $d(|n|)$ is the number of digits of $|n|$. Every product is
rounded with `HalfEven`, and the final product is rounded to the context.

A negative $n$ starts from a rounded $1/x$ in extended contexts; in subset
contexts the reciprocal is taken at the end. If that reciprocal already
overflows the working context, the power overflows. The sign of the overflowed
result is the sign of $x^n$ (negative only for a negative $x$ and an odd $n$),
not the sign of $x$: $(-0.07)^{-8}$ overflows to $+\infty$ and $(-0.07)^{-7}$ to
$-\infty$.

The reciprocal keeps the cohort of the division ($1 / 5 \times 10^{-2}$ is
$2 \times 10^{1}$, not $20$). The reason is that the exponent of an exact power
is the one repeated multiplication gives: $0.05^{-8}$ is $2.56 \times 10^{10}$
with three digits and no `Rounded`.

A zero exponent is decided before all of this. For a finite nonzero $x$ (and
for $\pm\infty$), $x^0$ is the integer $1$ with exponent $0$ and raises no
condition in every context, a clamped one included (GDA 1.70, page 35 (power):
"the result will be 1 and exact"). The result is not folded down, as decNumber
does not fold it (`decNumberPower` leaves by an early exit before its final
rounding and clamping, `decCopyFit` and `decFinish`) and as libmpdec does not.

The IEEE interchange encoders fold a result down themselves, at an exponent
above $E_{\max} - P_{\max} + 1$, where $E_{\max}$ and $P_{\max}$ are the maximum
exponent and the precision of the format. That is 90, 369 and 6111 for
decimal32, decimal64 and decimal128, which the exponent $0$ of $1$ never
reaches. Only a clamped context with $E_{\max} < p - 1$, which no IEEE format
has, could tell the two results apart.

The working context never clamps, so `Clamped` and `Rounded` come from two
places only. An intermediate rounding that discards non-zero digits makes the
result inexact. The final rounding to the context folds down an exponent above
$E_{\mathrm{top}}$ and raises `Clamped` when it does. An exact result such as
$(-0.5)^{-2} = 4$ at precision 1 and $E_{\max} = 0$ raises neither.

*Error of binary powering.* Write $\mathbf u_w = \frac12 10^{1-w}$, the unit
roundoff of precision $w$ for the half-way algorithms
([Rounding to precision](#rounding-to-precision)), and let $\delta$, with
$|\delta| \le \mathbf u_w$, be the relative error of one rounding. Let the
accumulator hold $x^\ell(1 + \theta_\ell)$, where $\ell$ is the power of $x$ it has
reached and $\theta_\ell$ its relative error. A squaring gives
$x^{2\ell}(1+\theta_\ell)^2(1+\delta)$ and a multiplication by $x$ gives
$x^{\ell+1}(1+\theta_\ell)(1+\delta)$, so
$1 + |\theta_{2\ell}| \le (1+|\theta_\ell|)^2(1+\mathbf u_w)$ and
$1 + |\theta_{\ell+1}| \le (1+|\theta_\ell|)(1+\mathbf u_w)$. By induction on
the binary expansion, $1 + |\theta_\ell| \le (1+\mathbf u_w)^{\ell-1}$ for every
$\ell \ge 1$: the error of binary powering is that of $\ell - 1$ successive
roundings, although only about $2\log_2 \ell$ products are formed.[^higham]
Starting from a rounded reciprocal adds the factor
$(1+\mathbf u_w)^{|n|}$, because its error is raised to the power $|n|$.
Let $m$ be the exponent of the factor $1 + \mathbf u_w$ in the whole bound:
$m = |n| - 1$ for $n > 0$ and $m = 2|n| - 1$ for $n < 0$. With
$m \mathbf u_w \le 10^{-p}$,

$$
|\theta| \le (1 + \mathbf u_w)^{m} - 1 \le m\,\mathbf u_w\,(1 + m\,\mathbf u_w),
\qquad
|n|\,\mathbf u_w < 10^{d(|n|)} \cdot \tfrac12\,10^{1 - p - d(|n|) - 2}
= \tfrac12\,10^{-1-p}.
$$

*Error in units in the last place.* The exact result $y$ satisfies
$|y| < 10^{p}\,u$ for the unit $u$ in the last place of the rounded result, so a
relative error $\theta$ is at most $|\theta|\,10^p$ units. This gives the working
error of the second column of the table below, in units in the last place.
Adding the final rounding gives the bound for an inexact integer power in the
other two columns.

| Exponent | Working error, at most (units) | Final result, half-way algorithms, within (units) | Final result, directed algorithms, within (units) |
| --- | --- | --- | --- |
| $n > 0$ | $0.05$ | $0.55$ | $1.05$ |
| $n < 0$ | $0.1$ | $0.6$ | $1.1$ |

In subset contexts $w$ is one digit smaller, so the working error grows tenfold
and the bound for the half-way algorithms becomes about $1$ unit. None of this
is correct rounding: a power whose exact result lies within $0.1$ units of a
rounding boundary can round the wrong way. The specification does not require more
for integer powers (GDA 1.70, page 35 (power)).

*Exponents that overflow or underflow.* Exponents so large that the result must
overflow or underflow are detected beforehand from the bounds
$n(\hat q + 1) - 1$ and $n \hat q$ on the adjusted exponent of the result,
where $\hat q$ is the adjusted exponent of $x$. The underflow shortcut is taken
only when the upper bound is at most $E_{\mathrm{tiny}} - 2$, so the exact power
is below $\tfrac12 10^{E_{\mathrm{tiny}}}$. The result is then that value rounded
by the rounding algorithm of the context: zero for the half-way algorithms and
`Down`, and $\pm 10^{E_{\mathrm{tiny}}}$ when the rounding algorithm rounds away
from zero for the result's sign.

*Digits of an inexact result.* An inexact result is delivered with a
coefficient of $p$ digits. The working arithmetic drops the trailing zeros of
the rounded value, so they are restored after the final rounding. GDA 1.70,
page 23 (Arithmetic operations), says a result with more digits than the
precision is "rounded (shortened) to exactly precision digits", and
IEEE 754-2019 5.2 selects the cohort member of least possible exponent for an inexact
result. A non-integer exponent gives the same
([non-integer power](#correctly-rounded-exp-ln-log10-and-non-integer-power)).
`power(99999E-1, -1)` at precision 2 is `0.00010`. Only a subset context strips
the zeros, as GDA 1.70, page 56 (Appendix A, The X3.274 subset), prescribes, and
a subnormal result has fewer digits because its exponent is
$E_{\mathrm{tiny}}$.

*Tininess.* Tininess is judged on the exact power, before rounding: GDA 1.70,
page 53 (Exceptional conditions), raises Subnormal when the adjusted exponent is
below $E_{\min}$ "before any rounding", and Underflow when the result is also
inexact. The working arithmetic only sees the power rounded to $w$ digits, so
when the delivered result is exactly $10^{E_{\min}}$ the side of the exact power
is decided separately:

1. The power is recomputed at precision $w' = p + d(|n|) + 6$. Its relative
   error is below $10^{d(|n|) + 2 - w'}$, since it is at most $2|n|$ roundings of
   $\mathbf u_{w'}$.
2. The recomputed power is compared with
   $10^{E_{\min}}(1 \pm 10^{d(|n|) + 2 - w'})$.
3. A power outside that band is subnormal exactly when it is below
   $10^{E_{\min}}$. While the power is inside the band, $w'$ is doubled and the
   power recomputed, five attempts in all.

For $1/1.00000000000000000001$ at $p = 1$ and $E_{\min} = 0$ the exact result
$0.99999999999999999999$ is separated at $w' = 32$, so the result `1` raises
`Subnormal` and `Underflow`. The test is made only when tininess is detected
before rounding, as GDA does (GDA 1.70, page 53 (Exceptional conditions)).

### Correctly rounded `exp`, `ln`, `log10` and non-integer `power`

These functions return the correctly rounded result, which they decide by
certified interval arithmetic and a Ziv-style refinement loop.[^ziv] A result
is certified when an interval known to contain $f(x)$ lies inside its rounding
cell. For $f(x)$, with $x$ the operand (the base, for `power`, whose exponent
is $y$), the evaluation has five steps.

1. The exact cases are decided first and never reach the loop. They are
   $\exp 0 = 1$, $\ln 1 = 0$, $\log_{10} 10^k = k$, special operands, domain
   errors, and the cases `power` can decide exactly:
   - $x^{1/2}$, by `sqrt`;
   - powers of ten and $1^y$;
   - guaranteed overflow or underflow;
   - exact rational powers: $y = a/b$ in lowest terms with $x$ a perfect
     $b$-th power, such as $4^{1.5} = 8$. The root is taken before the power,
     so no intermediate is longer than the result;
   - $10^k$ to a non-integral $y$ with $ky$ an integer, which is the exact
     $10^{ky}$ in every rounding algorithm (in the source:
     `decimal_power_ten_noninteger_result`).

   The loop could never certify an exact result: it is a boundary of its
   rounding cell in the directed algorithms, and an exact midpoint is one in
   the half-way algorithms.
2. The input is enclosed: $x$ is converted to a binary interval $[x^-, x^+]$ at
   $w_{\mathrm{bits}}$ bits, the working precision of the evaluation, with
   directed rounding (`to_binary` towards $-\infty$ and $+\infty$), so that
   $x \in [x^-, x^+]$ exactly.
3. The output is enclosed: `interval` evaluates $f$ on this interval and returns
   an enclosure $[y^-, y^+] \ni f(x)$. For `log10` it divides $\ln$ by a
   cached enclosure of $\ln 10$; for `power` it evaluates $\exp(y \ln x)$
   through enclosures of $\ln x$.
4. A candidate is certified. A decimal approximation $\tilde y$ of $f(x)$ (the
   midpoint of the enclosure; `power` may use a decimal series evaluation) is rounded to
   the context, which gives $r$. The candidate is only a guess that the test
   below certifies. The result is $r$ when the whole enclosure lies strictly
   inside the rounding cell of $r$, and then the midpoint of the enclosure,
   which belongs to the cell, rounds to the same cell.

   `exp` therefore takes the midpoint as its candidate. When $|x| \ge 10^3$ the
   midpoint is a binary floating-point number of enormous exponent, and `exp` takes the series
   with the same number of digits instead. The candidate is converted to
   $\max(p + 8, \lfloor 0.31\,w_{\mathrm{bits}} \rfloor + 4)$ digits, so that
   the conversion error is below the radius of the enclosure and cannot carry
   the candidate onto a cell boundary that the enclosure itself avoids.

   Let $(\alpha, \beta)$ be the open interval of reals around $r$ that round
   to $r$. For the half-way algorithms its bounds are the two midpoints
   between $r$ and its neighbours $r^-$ and $r^+$ below and above it. For the
   directed algorithms it is $(r, r^+)$ or $(r^-, r)$. The real rounding cell
   of a directed algorithm is half-open, $[r, r^+)$ or $(r^-, r]$; the test
   uses the open interior, which is sufficient. The bounds $\alpha$ and
   $\beta$ are exact decimals. Each is enclosed in binary, with $\alpha^+$ the
   upper bound of the enclosure of $\alpha$ and $\beta^-$ the lower bound of
   the enclosure of $\beta$, and the result is accepted when
   $$
   \alpha \le \alpha^+ < y^- \le f(x) \le y^+ < \beta^- \le \beta ,
   $$
   which proves $\mathrm{round}(f(x)) = r$, where $\mathrm{round}$ is the
   rounding to the context. A second test rounds both bounds $y^-$ and $y^+$ of
   the enclosure, which are exact dyadic numbers, to the context. Since every
   rounding algorithm is monotone, $\mathrm{round}(y^-) = \mathrm{round}(y^+) = r$
   also proves $\mathrm{round}(f(x)) = r$.
5. Otherwise the evaluation is refined. The working precision grows,
   $w_{\mathrm{bits}} \leftarrow w_{\mathrm{bits}} + \max(32, \lfloor w_{\mathrm{bits}}/2 \rfloor)$,
   and the loop repeats. At most $L$ evaluations are made, where $L$ is the
   refinement limit of the `GdaContext` (`GdaContext::refinement_limit`,
   default twelve). From the start value $w_{\mathrm{bits},0} \ge 128$ below the
   increment is $\lfloor w_{\mathrm{bits}}/2 \rfloor \ge 64$, so each step
   multiplies the precision by about 1.5 and the last of twelve evaluations runs
   at roughly $1.5^{11} \approx 86$ times the starting precision.

The starting precision is $w_{\mathrm{bits},0} = \max(128, 4D + 64)$ bits, where
$D = \max(d(c), p)$, $d(c)$ is the number of digits of the coefficient $c$ of
$x$ and $p$ is the precision of the context. Four bits per decimal digit exceed
$\log_2 10 \approx 3.32$, so the input is carried without loss of decimal
information and 64 guard bits remain. For arguments with $\hat q = 0$ in a
wide, unclamped context with $p \le 64$, a cheaper first attempt uses about
$\frac{10}{3} D + 12$ bits and falls back to $w_{\mathrm{bits},0}$ if it cannot
certify.

The loop always stops, after at most $L$ evaluations (twelve by default). With
`with_refinement_limit(None)` the count is unbounded, but the loop still stops
when the working precision passes $\max(8\,000\,000,\ 256\,w_{\mathrm{bits},0})$
bits (at most $10^9$), with the same certification failure, so the work and the
memory stay bounded.

The loop certifies a result whenever $f(x)$ is neither a representable number
nor, for the half-way algorithms, a midpoint, and the refinement limit and the
resource bound are large enough. The reason is that the enclosure shrinks to a
point while $f(x)$ stays at a positive distance from every rounding boundary.
For `exp`, `ln` and `log10` the condition on $f(x)$ holds for every operand
that step 1 leaves. Representable numbers and midpoints are rational, so it is
enough that $f(x)$ is irrational:

- For `exp`, $x$ is rational and not 0. By the Lindemann–Weierstrass theorem
  $\mathrm{e}^x$ is transcendental, hence irrational.
- For `ln`, $x$ is rational and not 1. If $\ln x$ were rational, it would be
  nonzero, and $x = \mathrm{e}^{\ln x}$ would be transcendental by the same
  theorem, which a rational $x$ is not. So $\ln x$ is irrational.
- For `log10`, $\log_{10} x = \ln x / \ln 10$ is rational only for integral
  powers of ten, which step 1 decides.

If the refinement limit or the resource bound is exhausted, for example for a
`power` whose exact result is a midpoint and is not caught in step 1, the
`try_exp`, `try_ln`, `try_log10` and `try_power` functions return a
certification failure and the GDA functions return NaN with `InvalidOperation`.
An unproven result is never returned.

The GDA functions `exp`, `ln`, `log10` and `sqrt` pass a copy of the context
with `HalfEven` rounding, because the specification defines these functions as
correctly rounded with round-half-even regardless of the rounding of the
context (GDA 1.70, page 30 (exp); page 31 (ln and log10); page 39
(square-root)). `power` uses the rounding of the context, as the specification
and its test vectors require.

`power` reports a non-integer power as `Inexact` with $p$ digits even when the
power happens to be exact (in the source: `decimal_power_noninteger_gda_result`;
GDA 1.70, page 35 (power), calls every such result inexact). It never reports
`Clamped` unless the result rounds to zero. The padded form of a nonzero
result has an exponent of at most $E_{\max} - p + 1$, so no fold-down is left
to report, whatever route computed it (a square root for the exponent $0.5$,
an exact rational power, a power of ten, the certified loop). The exact result
is the correctly rounded one under every rounding algorithm, so a directed
algorithm never adds a unit in the last place: `power(1E-5, 1.2)` is `1E-6`
padded to $p$ digits with `Inexact` and `Rounded` in every rounding algorithm,
as `power.decTest` rows powx2039 and powx2040 show for $1^y$ in `ceiling`.

`exp`, `ln`, `log10` and `power` with a non-integer exponent accept only
contexts with $p$, $E_{\max}$ and $-E_{\min}$ at most 999,999
(`math_context_is_restricted`) and raise `InvalidContext` otherwise. This is
an implementation limit, decNumber's `DEC_MAX_MATH`, and not a rule of the GDA
operation text. The official
decTest suite requires it (`power.decTest` powx4001 to powx4005 and the
matching rows of `exp.decTest`, `ln.decTest` and `log10.decTest`), and GDA 1.70
permits it through the Invalid context condition, which covers a precision that
exceeds the capability of the implementation (GDA 1.70, page 52 (Exceptional
conditions)). The
[API page](../api/decimal_gda.md#implementation-limit-of-exp-ln-log10-and-power)
states the limit and the operands it applies to.

In subset arithmetic `ln` reproduces the result of the classic reference
algorithm, which can be one unit in the last place above the correctly rounded
one (in the source: `decimal_ln_subset_result`), because the legacy subset test
vectors encode that result.

[^ziv]: A. Ziv, "Fast evaluation of elementary mathematical functions with
    correctly rounded last bit", *ACM TOMS* 17(3), 1991. On ball arithmetic see
    J. van der Hoeven, "Ball arithmetic", 2009, and F. Johansson, "Arb: efficient
    arbitrary-precision midpoint-radius interval arithmetic", *IEEE Trans.
    Computers* 66(8), 2017.

### Coefficient representation and kernels

The kernel lives in `internal/decimal_kernel` and is shared with `decimal`
([why](#a-gda-package-independent-of-decimal)). A coefficient is either `Small(UInt64)` for values below $10^{18}$ or
an array of base-$10^9$ limbs with a cached digit count. Both are persistent:
operations never mutate operand limbs. Decimal limbs make digit counts,
trailing-zero removal, the half-unit comparison and the `ZeroFiveUp` last-digit
test constant-time or linear, without a binary-to-decimal conversion.
Multiplication and division choose among schoolbook, Karatsuba, Toom-3, a
dual-modulus NTT, Knuth's algorithm D, Burnikel–Ziegler and Newton reciprocal
division by limb count, with thresholds per target:

| Target | Karatsuba mul / square | Toom-3 | first NTT mul / square | Burnikel–Ziegler | Newton division |
| --- | ---: | ---: | ---: | ---: | ---: |
| native | 96 / 48 | 1,152 | 1,728 / 640 | from 2,816 | off |
| LLVM | 96 / 96 | 2,048 | 4,096 / 2,048 | 2,048 | 4,096 |
| Wasm, Wasm-GC, JS | 96 / 96 | 4,096 | 8,192 / 4,096 | 2,048 | 4,096 |

The thresholds are measured performance policy, not semantics: every kernel
returns the exact product or quotient, so the choice cannot change a result or
a flag. See [performance](../performance/decimal_gda.md) for the measurements.

## Correctness and invariants

- **Correct rounding.** Every finite result other than integer `power`, the
  [division case](#division) and the to-integral operations on integers longer
  than $p$ digits is correctly rounded: it is the exact result $x$ rounded once,
  to the returned result $\hat x$. Let $u$ be the unit in the last place of
  $\hat x$. Then $|\hat x - x| \le \frac12 u$ in the half-way algorithms and
  $< u$ in the directed algorithms and `ZeroFiveUp`, and
  $|\hat x - x|/|x| \le \frac12 10^{1-p}$ outside the subnormal range.
- **Ideal cohort.** An exact result is returned at the representable exponent
  nearest to its ideal exponent, so operations on exact data keep their
  exponent (`2.50 × 3 = 7.50`).
- **Independence of the flags.** The result $F(\vec x, C)$ of an operation on
  $\vec x$ in the context $C$ depends on $C$ only through its policy $\pi(C)$
  (see [Conditions, signals and traps](#conditions-signals-and-traps)): results
  never depend on the flags of the context or on the traps.
- **Flags algebra.** The flags of a context only grow, and after a threaded
  sequence of operations they are the union of the sets of conditions the
  operations raise.
- **Trap determinism.** At most one trap fires per operation, selected by a
  fixed total order; `Trapped` carries the same value as `Completed` would.
- **Proof before return.** A finite inexact result of `exp`, `ln`, `log10` or
  non-integer `power` is returned only together with a proof (Lemma 3 or 4 of the
  [rounding proofs](../../attachments/design_decimal_gda_rounding.typ)) that it
  is the correctly rounded result; a failure to prove it yields NaN and
  `InvalidOperation`.
- **Total order.** `compare_total` is a total order on triples (sign, then
  class, then value, then exponent, then payload), and `Decimal::compare` is
  a total preorder in which NaNs form one class above all other values.
- **Checked results.** The pinned `official` test suite and the legacy `official0`
  suite pass all their legal executable rows
  ([conformance](../conformance/decimal_gda.md)). These are
  finite sets of rows: no pinned row covers the tie in division in the
  half-way algorithms ([Division](#division)) or a to-integral operand longer
  than the precision.

## Alternatives rejected

- **A mutable or global current context.** Rejected because it makes results
  and flags depend on evaluation order and hidden state (see
  [the first design decision](#thread-status-through-gdaoutcome-not-global-state)).
- **Traps as errors.** Rejected because the GDA-defined result would be lost.
- **Sharing the engine with `decimal`.** Rejected because one standard's
  change could alter the other's results. A measured duplication is cheaper
  than an accidental semantic coupling.
- **Binary floating point for elementary functions with a fixed number of
  guard digits.** Rejected because no fixed number of guard digits guarantees
  correct rounding (the table-maker's dilemma); a proof with refinement does,
  and fails visibly when it cannot be completed.
- **Reducing every result.** Rejected because the exponent, and with it the
  quantum $10^q$, is part of a finite number in GDA. `reduce` removes the
  trailing zeros when the caller asks for it.

## Boundaries

- The package implements the GDA operations and nothing else: no
  trigonometric, hyperbolic or other functions outside the specification, and
  no IEEE 754 operations.
- It does not parse `.decTest` files, run test suites or read files; that is
  [`frontend/gda_expr`](../api/frontend/gda_expr.md) and the repository tools.
- It provides DPD interchange and no BID interchange.
- It gives no correct rounding for integer powers beyond the GDA
  requirement.
- It provides no mutable or global context, and contexts carry no
  identity: two contexts with the same fields are interchangeable.
- `ParseChecked` is a value-only adapter over the GDA to-number conversion. It
  maps `ArithmeticContext` to the engine context, so the precision, the
  rounding, the exponent limits and the clamp apply. The returned `Result`
  cannot carry the flags or traps of GDA; a caller that needs them uses
  [`to_number`](../api/decimal_gda.md#to_number) with a `GdaContext`.
- It stores no exponent beyond the
  [implementation limit on the exponents of a stored value](../api/decimal_gda.md#gda_value_e_max-gda_value_e_tiny):
  a finite number needs an exponent of at least $-2^{31}+3$ and an adjusted
  exponent of at most $2^{31}-2$, the range of the working context of the plain
  operators. The constructors reject a value outside it (they never replace it
  silently), context operations overflow or underflow against the context
  range, decided from the exact exponent, and the operations without a context
  overflow or underflow at the implementation limit.
