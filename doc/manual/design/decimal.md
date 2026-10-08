# decimal design

This page explains the arithmetic model of `Luna-Flow/floating/decimal`: what a
decimal floating-point number is, how cohorts and preferred exponents carry
information, how the interchange encodings pack digits into bits, how every
result is rounded exactly once, which error bounds follow, how the exponent
range is enforced, and how elementary functions are certified. The
[decimal API](../api/decimal.md) specifies each function; the
[decimal tutorial](../tutorial/decimal.md) shows them in use.

## Design goal

`decimal` implements the decimal arithmetic of IEEE 754-2019[^ieee] for any
precision, with three properties:

1. **Every context operation is correctly rounded.** The result is the exact
   mathematical result rounded once, in the selected direction, to the
   context's precision and exponent range — for the basic operations and for
   the elementary functions alike. The current implementation misses this goal
   in a few places, all near the underflow threshold or in the elementary
   functions; they are listed in [known deviations](#known-deviations).
2. **Nothing is lost silently.** The exponent of a result (its *quantum*), the
   sign of zero, NaN payloads and every exceptional condition are part of the
   returned value or of the returned `DecimalFlags`.
3. **No hidden state.** Precision, rounding, exponent range and flags are
   ordinary immutable values passed and returned explicitly, as everywhere in
   Luna-Flow.

[^ieee]: IEEE Std 754-2019, *Standard for Floating-Point Arithmetic*, clauses
3.3–3.5 (decimal formats and encodings), 4 (attributes and rounding), 5
(operations), 7 (exceptions) and 9 (recommended operations). The General
Decimal Arithmetic specification by M. F. Cowlishaw (version 1.70) gives the
same model in an arbitrary-precision form; its terms *coefficient*,
*adjusted exponent*, *Etiny* and *clamp* are used here.

## Mathematical background

### Decimal floating-point numbers

A decimal floating-point format with precision $p$ and adjusted-exponent range
$[e_{\min}, e_{\max}]$ is the set of numbers

$$
x = (-1)^s \cdot c \cdot 10^{q}, \qquad
s \in \{0,1\},\quad c \in \mathbb{Z},\ 0 \le c < 10^{p},\quad
E_{\text{tiny}} \le q \le E_{\text{top}},
$$

together with $\pm\infty$ and NaNs, where $c$ is the *coefficient*, $q$ the
*exponent* or *quantum*, and

$$
E_{\text{tiny}} = e_{\min} - p + 1, \qquad E_{\text{top}} = e_{\max} - p + 1 .
$$

The *adjusted exponent* of a non-zero $x$ is $\operatorname{adj}(x) = q +
\operatorname{digits}(c) - 1 = \lfloor \log_{10} |x| \rfloor$: it is the
exponent of $x$ written in scientific notation $d_0.d_1d_2\ldots \times
10^{\operatorname{adj}(x)}$. A non-zero $x$ is *normal* when
$\operatorname{adj}(x) \ge e_{\min}$ and *subnormal* otherwise; the smallest
positive subnormal is $10^{E_{\text{tiny}}}$ and the largest finite value is

$$
N_{\max} = (10^{p} - 1)\cdot 10^{E_{\text{top}}} = 10^{e_{\max}+1} - 10^{e_{\max}-p+1}.
$$

`DecimalContext` stores exactly $p$, $e_{\min}$, $e_{\max}$, the rounding mode,
`clamp` (whether exponents above $E_{\text{top}}$ are allowed; see
[clamping](#clamping)) and the tininess rule. The interchange formats are:

| Format | $p$ | $e_{\max}$ | $e_{\min}$ | $E_{\text{tiny}}$ | $E_{\text{top}}$ | bias $=-E_{\text{tiny}}$ | exponents $E_{\text{top}}-E_{\text{tiny}}+1$ |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| decimal32 | 7 | 96 | $-95$ | $-101$ | 90 | 101 | $192 = 3\cdot 2^{6}$ |
| decimal64 | 16 | 384 | $-383$ | $-398$ | 369 | 398 | $768 = 3\cdot 2^{8}$ |
| decimal128 | 34 | 6144 | $-6143$ | $-6176$ | 6111 | 6176 | $12288 = 3\cdot 2^{12}$ |

IEEE 754 fixes $e_{\min} = 1 - e_{\max}$, so the number of exponents is
$E_{\text{top}} - E_{\text{tiny}} + 1 = e_{\max} - e_{\min} + 1 = 2e_{\max}$;
the standard chooses $e_{\max} = 3 \cdot 2^{w-1}$ so that this count is
$3 \cdot 2^{w}$, which is exactly what two leading exponent bits taking the
values $0,1,2$ and $w$ further bits can encode (see [encodings](#interchange-encodings)).
The bias that turns $q$ into a non-negative stored exponent is
$-E_{\text{tiny}} = p - e_{\min} - 1$: for decimal64, $16 + 383 - 1 = 398$.

### Why decimal

A rational number $n/m$ in lowest terms has a finite expansion in base $b$ if
and only if every prime factor of $m$ divides $b$. For $b = 2$ the only
admissible denominators are powers of two; for $b = 10$ they are $2^{i}5^{j}$.
So every binary floating-point number has a finite decimal expansion, but
$0.1 = 1/(2\cdot 5)$ has none in binary: the `Double` nearest to it is

$$
0.1000000000000000055511151231257827021181583404541015625 = \frac{3602879701896397}{2^{55}} .
$$

Quantities defined in decimal — prices, rates, measurements, protocol fields —
are therefore represented exactly by decimal floating point, and decimal
rounding happens at the decimal places a person or a regulation specifies.
The price is a larger *wobble* (below) and more expensive digit arithmetic.

### Cohorts and quantum

The map $(s, c, q) \mapsto (-1)^s c\,10^{q}$ is not injective. All
representations of the same non-zero value form its *cohort*. If $c$ has $d$
digits and $k$ trailing zeros, the members are
$(c\cdot 10^{j},\, q - j)$ for $-k \le j \le p - d$, ignoring the exponent
range, so the cohort has $p - d + k + 1$ members. For example, $1000$ in
decimal32 ($c = 1$, $q = 3$, $d = 1$, $k = 0$) has the seven members
$1\text{E+}3, 10\text{E+}2, \ldots, 1000000\text{E-}3$. A zero has a member
for every exponent.

The cohort member carries information numeric equality does not: `12.30`
states two decimal places, `1.2E+3` states two significant digits. IEEE 754
therefore specifies, for each operation, a **preferred exponent**, and an exact
result is delivered in the member whose exponent is closest to it. The
preferred exponents follow from where the exact result naturally lives:

$$
\begin{aligned}
c_a 10^{q_a} \pm c_b 10^{q_b} &= \bigl(c_a 10^{q_a - m} \pm c_b 10^{q_b - m}\bigr)\,10^{m},
  & m &= \min(q_a, q_b),\\
c_a 10^{q_a} \cdot c_b 10^{q_b} &= (c_a c_b)\,10^{q_a + q_b},\\
c_a 10^{q_a} / c_b 10^{q_b} &= (c_a / c_b)\,10^{q_a - q_b},\\
\sqrt{c\,10^{q}} &= \sqrt{c\,10^{q - 2\lfloor q/2\rfloor}}\;10^{\lfloor q/2 \rfloor},\\
x\cdot y + z &: \ \min(q_x + q_y,\ q_z).
\end{aligned}
$$

For the sum and the product, the bracketed coefficient is an integer, so the
preferred exponent is attained whenever the exact coefficient fits in $p$
digits: `1.20 + 3.40 = 4.60` and `1.25 × 2.50 = 3.1250`. For the quotient the
exact result exists only when $c_a / c_b$ has a finite decimal expansion; it is
then moved toward $q_a - q_b$ as far as $p$ digits allow, so `2.400 / 1.2 =
2.00`. An inexact normal result always uses all $p$ digits, which is the
member with the smallest exponent; an inexact subnormal result ends at
$E_{\text{tiny}}$. `quantize` makes the exponent an explicit argument, and
`reduce_ctx`/`normalized` choose the member with the largest exponent.

```moonbit
///|
test "design: preferred exponents" {
  let ctx = @decimal.DecimalContext::decimal64()
  let d = fn(s : String) { @decimal.Decimal::from_string(s).unwrap() }
  inspect(d("1.20").add_ctx(d("3.40"), ctx).0, content="4.60")
  inspect(d("1.25").mul_ctx(d("2.50"), ctx).0, content="3.1250")
  inspect(d("2.400").div_ctx(d("1.2"), ctx).0, content="2.00")
  inspect(d("0.0400").sqrt_ctx(ctx).0, content="0.20")
  inspect(d("1.5").fma_ctx(d("2.0"), d("0.25"), ctx).0, content="3.25")
}
```

### Rounding directions

Let $x > 0$ be exact and let the target exponent be $t$ (the exponent that
leaves $p$ digits, or $E_{\text{tiny}}$ for a tiny result). Write

$$
x \cdot 10^{-t} = c + f, \qquad c \in \mathbb{Z}_{\ge 0},\ 0 \le f < 1 .
$$

Each rounding direction returns $c$ or $c + 1$ (times $10^{t}$); the choice
depends on $f$, the last digit of $c$ and the sign:

| Mode | IEEE name | returns $c+1$ when ($f > 0$) |
| --- | --- | --- |
| `Down` | roundTowardZero | never |
| `Up` | — | always |
| `Ceiling` | roundTowardPositive | $x > 0$ |
| `Floor` | roundTowardNegative | $x < 0$ |
| `HalfUp` | roundTiesToAway | $f \ge \tfrac12$ |
| `HalfDown` | — | $f > \tfrac12$ |
| `HalfEven` | roundTiesToEven | $f > \tfrac12$, or $f = \tfrac12$ and $c$ odd |
| `ZeroFiveUp` | — | $c \bmod 5 = 0$ |

For a negative $x$ the same rule is applied to $|x|$ and the sign restored, so
`Ceiling` and `Floor` swap. Every mode $\circ$ is **monotone**:
$x \le y \Rightarrow \circ(x) \le \circ(y)$. Monotonicity is what the
certification of elementary functions relies on.

### Error model

Let $x$ be in the normal range, $10^{e} \le |x| < 10^{e+1}$. Representable
numbers in that decade are spaced by one unit in the last place,
$\operatorname{ulp}(x) = 10^{e - p + 1}$. Rounding to nearest is off by at
most half of it, so

$$
\begin{aligned}
\frac{|\operatorname{fl}(x) - x|}{|x|}
  \le \frac{\tfrac12\, 10^{e-p+1}}{10^{e}} = \tfrac12\, 10^{1-p} =: u ,
\end{aligned}
\qquad\text{equivalently}\qquad
\operatorname{fl}(x) = x(1 + \delta),\ |\delta| \le u .
$$

The bound is approached, but not attained, near the bottom of a decade: for
$x = 10^{e} + \tfrac12\operatorname{ulp}(x)$ the relative error is
$\tfrac12 10^{1-p}/(1 + \tfrac12 10^{1-p}) < u$. Near the top, $|x|
\approx 10^{e+1}$, the same absolute error is only $\tfrac12 10^{-p}$ relative.
The ratio between the worst and the best relative error inside one decade is
therefore

$$
\frac{\tfrac12\,10^{1-p}}{\tfrac12\,10^{-p}} = 10 = \beta ,
$$

the *wobble* of base $\beta = 10$.[^wobble] In binary the wobble is 2, so for
the same storage decimal has a slightly worse worst-case relative error:
decimal64 has $u = \tfrac12 10^{-15} = 5\cdot 10^{-16}$, binary64 has $u =
2^{-53} \approx 1.1 \cdot 10^{-16}$. The directed modes have
$|\delta| < 10^{1-p} = 2u$. The machine epsilon, the distance from 1 to the
next larger number, is $10^{1-p}$ — `epsilon_contextual` returns it and
`next_plus(1)` in decimal64 is `1.000000000000001`. Below 1 the spacing is ten
times smaller: `next_minus(1)` is `0.9999999999999999`.

[^wobble]: Goldberg, "What every computer scientist should know about
floating-point arithmetic", *ACM Computing Surveys* 23(1), 1991, §1.2;
Higham, *Accuracy and Stability of Numerical Algorithms*, 2nd ed., SIAM 2002,
§2.1–2.2.

For a subnormal result the spacing is the fixed $10^{E_{\text{tiny}}}$, so
the error bound becomes absolute, $|\operatorname{fl}(x) - x| \le \tfrac12
10^{E_{\text{tiny}}}$. Because every context operation is correctly rounded,
the standard model $\operatorname{fl}(a \circ b) = (a \circ b)(1+\delta)$,
$|\delta| \le u$, holds for $+,-,\times,/,\sqrt{\ }$, `fma` and every
elementary function whose result is normal, so the classical forward and
backward error analyses of Higham carry over with $u = \tfrac12 10^{1-p}$.

## Design decisions

### One representation, many contexts

**Problem.** Applications need decimal32/64/128 and arbitrary precision, IEEE
semantics and GDA compatibility, without converting between types.

**Options.** One type per format (like hardware); one arbitrary-precision type
with the format carried by a context; a type parameterised by the format.

**Choice.** One `Decimal` type holding a sign, a coefficient of any length, an
exponent, a class, a NaN-kind bit and a working-precision field, and a
separate immutable `DecimalContext`. A decimal64 computation is a computation
under `DecimalContext::decimal64()`; the interchange encoders apply the format
context before encoding. This keeps the arithmetic in one place, lets a caller
work at 50 digits and round to decimal64 at the end, and matches the General
Decimal Arithmetic model. The precision field in the value serves only the
context-free operators and conversions.

### Round once, in one place

**Problem.** Double rounding — rounding an already rounded value again — can
change a correctly rounded result.

**Choice.** Every finite context result goes through one finalization routine
that receives an **exact** result $(s, C, Q)$, with $C$ possibly much longer
than $p$. Operation kernels compute exact integers; they never round. The
exceptions are operations whose exact result is infinite — division, square
root, elementary functions — which are described below; each of them still
decides the last digit from exact information.

A single rounding needs a single target exponent. With
$D = \operatorname{digits}(C)$, the exact value has adjusted exponent
$a = Q + D - 1$, and the correctly rounded result has exponent

$$
t = \max\bigl(a - p + 1,\ E_{\text{tiny}}\bigr),
$$

the first term keeping $p$ digits for a normal result and the second the
subnormal grid; the result is $\circ(C\,10^{Q-t})\,10^{t}$, followed by the
overflow check (on the value rounded to $p$ digits with unbounded exponent),
the subnormal/underflow flags and the fold-down.

The routine on the current branch does this in two steps instead. If
$Q < E_{\text{tiny}}$ it first rounds $C$ to the grid $10^{E_{\text{tiny}}}$
(shift $s_1 = E_{\text{tiny}} - Q$), then drops trailing zeros and rounds the
result to $p$ digits (shift $s_2 = a - p + 1 - E_{\text{tiny}}$ when that is
positive). For a subnormal result $s_2 \le 0$ and only the first rounding
happens, which is correct. For a *normal* result with $Q < E_{\text{tiny}}$
both shifts are positive, and rounding twice to nearest is not rounding once:
if the first rounding lands exactly on a midpoint of the second grid, the tie
rule of the second rounding decides a case the exact value had already
decided. In decimal32 ($E_{\text{tiny}} = -101$) the product
$3.000001\cdot 10^{-45} \times 1.500001\cdot 10^{-45} = 4500004500001\cdot
10^{-102}$ is first rounded to $450000450000\cdot 10^{-101}$ (the dropped
digit 1 is below half), which is the exact midpoint $4500004.5\cdot
10^{-96}$; `HalfEven` then gives $4.500004\cdot 10^{-90}$, whereas the exact
value lies above the midpoint and rounds to $4.500005\cdot 10^{-90}$. The
directed modes are unaffected: truncating (or rounding up) to a finer grid and
then to a coarser one is the same as truncating (rounding up) once, because
$\lfloor\lfloor y\,10^{-s_1}\rfloor 10^{-s_2}\rfloor = \lfloor y\,
10^{-s_1-s_2}\rfloor$ for every real $y \ge 0$.

#### How the rounding digit and sticky information are obtained

Rounding $C$ (a non-negative integer with $D$ digits) to $D - s$ digits divides
by a power of ten,

$$
C = Q \cdot 10^{s} + R, \qquad 0 \le R < 10^{s},
$$

and decides between $Q$ and $Q+1$ by comparing $2R$ with $10^{s}$. This single
comparison carries exactly the information of the classical *rounding digit*
and *sticky bit*. Write $R = r\,10^{s-1} + R'$ with rounding digit
$r \in \{0,\ldots,9\}$ and rest $0 \le R' < 10^{s-1}$. Then

$$
2R - 10^{s} = 2(r - 5)\,10^{s-1} + 2R' ,
$$

and since $0 \le 2R' < 2\cdot 10^{s-1}$:

$$
\begin{aligned}
r \ge 6 &\implies 2R - 10^{s} \ge 2\cdot 10^{s-1} > 0,\\
r = 5 &\implies \operatorname{sign}(2R - 10^{s}) = \operatorname{sign}(R'),\\
r \le 4 &\implies 2R - 10^{s} \le -2\cdot 10^{s-1} + 2R' < 0 .
\end{aligned}
$$

So $2R > 10^{s}$, $2R = 10^{s}$ and $2R < 10^{s}$ mean "above, at, below the
midpoint", which is all the half modes need; $R \ne 0$ is the sticky
information the directed modes need; and the last digit of $Q$ is all
`ZeroFiveUp` and `HalfEven` need. When $s \ge D$ the whole coefficient is
discarded, $Q = 0$, and only $s = D$ can reach the midpoint: the code then
compares $C$ with $5\cdot 10^{D-1}$. A carry that turns $10^{p}-1$ into
$10^{p}$ is removed by one exact division by 10 and an exponent increment.

`rounded` is raised whenever $s > 0$ and `inexact` whenever $R \ne 0$; trailing
zeros are dropped before rounding so that discarding zeros raises only
`rounded`.

#### Division

The quotient $a/b$ of two finite non-zero values takes one of three exact
routes, in this order.

1. *Divisor a power of ten.* The quotient is $a$ with a shifted exponent.
2. *Terminating quotient.* Reduce $c_a / c_b$ by $g = \gcd(c_a, c_b)$ to
   $c_a'/c_b'$. The quotient has a finite decimal expansion if and only if
   $c_b' = 2^{i}5^{j}$; with $k = \max(i, j)$,
   $$
   \frac{c_a'}{2^{i}5^{j}} = \frac{c_a'\,2^{k-i}\,5^{k-j}}{10^{k}},
   $$
   so the exact result is the integer $c_a' 2^{k-i}5^{k-j}$ with exponent
   $q_a - q_b - k$, handed to the finalizer like any exact result.
3. *Non-terminating quotient.* The result is certainly inexact. Let
   $a_c = \operatorname{adj}(c_a/c_b)$, found exactly by comparing $c_a$ with
   $c_b$ scaled by the right power of ten. Scaling the numerator (or the
   denominator) by $10^{p-1-a_c}$ makes the integer quotient have exactly $p$
   digits: $N = Q D + R$. The increment decision compares $2R$ with $D$ — the
   same midpoint test as above, now with the exact remainder as sticky
   information — so the quotient is rounded once.

The third route is used for normal results in extended contexts. For subnormal
results and subset contexts the code forms the integer quotient of
$c_a\,10^{k}$ by $c_b$ with $k = p + \operatorname{digits}(c_b) + 2$ (about
$\operatorname{digits}(c_a) + p + 2$ digits), rounds it with `ZeroFiveUp`,
and rounds again in the context mode to the precision. The context-free
operator `/` uses the same guarded scheme. By the `ZeroFiveUp` lemma below the
two roundings equal one rounding of the exact quotient, so $15/83294$ at five
digits is `0.00018009`.[^div-05up] A subnormal quotient still passes through
the finalizer, which rounds to the subnormal grid before it rounds to $p$
digits (see [Round once, in one place](#round-once-in-one-place)): in
decimal32, $1 / 1.9999999999998\cdot 10^{101} = 5.0000000000005\cdot
10^{-102}$ gives `0E-101` instead of `1E-101`.

[^div-05up]: Until upstream commit `fabf8d9` the guarded quotient was rounded
    in the context mode, which could manufacture a tie: $15/83294$ at five
    digits gave `0.00018008`.

`ZeroFiveUp` exists precisely to make such two-step schemes safe. If $x$ is
first rounded with `ZeroFiveUp` to $p + k$ digits ($k \ge 1$) and then with
any mode $\circ$ to $p$ digits, the result equals $\circ(x)$: an inexact
`ZeroFiveUp` result ends in a digit other than 0 and 5, so it is never a
$p$-digit number nor a $p$-digit midpoint, and it lies on the same side of
every $p$-digit number and midpoint as $x$. The proof is in the
attachment.[^attachment] The guarded division above relies on it. The
finalizer's pre-rounding to the subnormal grid does not; there the simpler
repair is to round once at the target exponent $t$ derived above.

#### Square root

Exact roots are detected first: after removing trailing zeros and making the
exponent even, the operand is $c'\,10^{2m}$, and $\sqrt{x}$ is a decimal if and
only if the integer $c'$ is a perfect square. Such a root is returned at the
member closest to the preferred exponent $\lfloor q/2 \rfloor$; if it has more
than $p$ digits it is rounded like any exact result. For every other operand
$\sqrt{x} = \sqrt{c'}\,10^{m}$ is irrational.

For the irrational case let the target exponent be $t = \max(E_{\text{tiny}},\
\lfloor \operatorname{adj}(x)/2 \rfloor - p + 1)$. The root has adjusted
exponent $\lfloor \operatorname{adj}(x)/2 \rfloor$: from $10^{a} \le x <
10^{a+1}$ follows $10^{a/2} \le \sqrt x < 10^{(a+1)/2}$, and both for even and
for odd $a$ the integer part of the exponent is $\lfloor a/2 \rfloor$. So $t$
leaves $p$ digits, or stops at the subnormal grid. When $q - 2t \ge 0$ the
operand is scaled to the integer $M = c\,10^{q - 2t}$ and
$r = \lfloor \sqrt{M} \rfloor$ is the truncated root at exponent $t$. When
$q - 2t < 0$ the code takes the integer root of $c$ (of $10c$ if $-(q-2t)$ is
odd) and divides it by $10^{\lceil -(q-2t)/2 \rceil}$; nested floors of a
positive real by positive integers compose, so this is again
$\lfloor \sqrt{x}\,10^{-t} \rfloor$. The integer root is computed with
Newton's iteration on integers,

$$
a_{k+1} = \left\lfloor \frac{a_k + \lfloor N / a_k \rfloor}{2} \right\rfloor ,
\qquad a_0 = 10^{\lceil \operatorname{digits}(N)/2 \rceil} > \sqrt{N},
$$

($N < 10^{\operatorname{digits}(N)}$ gives $\sqrt N < 10^{\operatorname{digits}(N)/2}
\le a_0$). Because $\lfloor (a + \lfloor y \rfloor)/2 \rfloor = \lfloor (a + y)/2
\rfloor$ for an integer $a$, the AM–GM inequality $\tfrac12(a + N/a) \ge \sqrt{N}$
gives $a_{k+1} \ge \lfloor \sqrt N \rfloor$; and $a_{k+1} < a_k$ exactly when
$a_k^2 > N$. The iterates therefore decrease strictly to
$\lfloor \sqrt N \rfloor$, where the iteration stops.

Since the root is irrational it is never exact and never a midpoint, so the
increment decision needs only the comparison $\sqrt{x}\,10^{-t} \gtrless r +
\tfrac12$, done exactly as $4M \gtrless (2r+1)^2$ (or
$4c \gtrless (2r+1)^2\,10^{-(q-2t)}$ in the second branch). Rounding directly
at the subnormal target exponent avoids rounding twice for tiny roots.

A root *can* be exactly halfway when it is exact but longer than $p$ digits:
$\sqrt{6.25} = 2.5$ at $p = 1$ gives `2` under `HalfEven` and `HalfDown` and
`3` under `HalfUp`. A halfway root $(r + \tfrac12)10^{t}$ squares to
$(2r+1)^2\cdot 25 \cdot 10^{2t-2}$, an odd coefficient with at least $2p+1$
digits when $r$ has $p$ digits ($r \ge 10^{p-1}$ gives $(2r+1)^2 \cdot 25 >
10^{2p}$). A normal halfway root therefore needs an operand with more than
$2p$ significant digits, and a subnormal one an operand below the format's
range. An operand that fits the format (at most $p$ digits, value at least
$10^{E_{\text{tiny}}}$) has a normal root whenever $e_{\min} \le 1 - p$, as in
all interchange formats, because $\sqrt{10^{E_{\text{tiny}}}} =
10^{(e_{\min}-p+1)/2} \ge 10^{e_{\min}}$; for such operands the three half
modes agree.

[^attachment]: [Rounding proofs for decimal](../../attachments/design_decimal_rounding.typ)
contains the full proofs of the double-rounding lemma, the overflow table, the
fold-down bound, the certification lemma and the NTT bound.

### Exponent range

The finalizer works on the rounded coefficient $C'$ with $p$ digits and
exponent $Q'$, i.e. on the value rounded with an unbounded exponent range.

#### Overflow

If $\operatorname{adj}(C' 10^{Q'}) > e_{\max}$ the result overflows. IEEE
754 §7.4 defines the delivered result as the rounding of the exact value in a
format with the same $p$ but unbounded exponent, then saturated: a direction
that never increases magnitude cannot leave the finite range, a direction
that may increase it goes to infinity. Hence, with
$N_{\max} = (10^{p}-1)10^{E_{\text{top}}}$:

| Mode | $x > 0$ | $x < 0$ |
| --- | --- | --- |
| `HalfEven`, `HalfUp`, `HalfDown`, `Up` | $+\infty$ | $-\infty$ |
| `Down` | $+N_{\max}$ | $-N_{\max}$ |
| `Ceiling` | $+\infty$ | $-N_{\max}$ |
| `Floor` | $+N_{\max}$ | $-\infty$ |
| `ZeroFiveUp` | $+N_{\max}$ | $-N_{\max}$ |

The half modes go to infinity because an overflowing exact value is at least
$N_{\max} + \tfrac12 10^{E_{\text{top}}}$ (anything smaller rounds to a
finite value and does not overflow), which is at or beyond the midpoint
between $N_{\max}$ and the next power of ten. `ZeroFiveUp` saturates because
the last digit of $N_{\max}$ is 9. Every overflow raises `overflow`,
`inexact` and `rounded`.

```moonbit
///|
test "design: overflow depends on the rounding direction" {
  let ctx = @decimal.DecimalContext::decimal64()
  let big = @decimal.Decimal::from_string("9E+384").unwrap()
  let ten = @decimal.Decimal::from_int(10)
  inspect(big.mul_ctx(ten, ctx).0, content="inf")
  let down = ctx.with_rounding(@def.RoundingMode::TowardZero)
  let (sat, flags) = big.mul_ctx(ten, down)
  inspect(sat, content="9.999999999999999E+384")
  inspect(flags.overflow && flags.inexact, content="true")
}
```

#### Subnormals, tininess and underflow

If the exact result needs an exponent below $E_{\text{tiny}}$, it is rounded
to the subnormal grid: the shift becomes $s = E_{\text{tiny}} - Q$ and the
rounding rule above applies with fewer than $p$ digits kept. The result is
**tiny** when its adjusted exponent is below $e_{\min}$, measured on the exact
value (`BeforeRounding`) or on the value rounded to $p$ digits with
unbounded exponent (`AfterRounding`, the default). The two rules differ only
for values just below $10^{e_{\min}}$ that round up to it. A tiny result raises
`subnormal`; a tiny **and** inexact result also raises `underflow`, as IEEE 754
§7.5 requires for default exception handling. A result that rounds to zero
gets exponent $E_{\text{tiny}}$ and `clamped`.

#### Clamping

With `clamp` (all interchange formats), exponents above $E_{\text{top}}$ are
not representable, because the encoding has room only for
$E_{\text{top}} - E_{\text{tiny}} + 1$ exponents. A result with $Q' >
E_{\text{top}}$ that did not overflow is **folded down**: the coefficient is
multiplied by $10^{Q' - E_{\text{top}}}$ and the exponent set to
$E_{\text{top}}$, raising `clamped`. This never needs more than $p$ digits:

$$
\operatorname{digits}(C') + (Q' - E_{\text{top}})
= \bigl(\operatorname{adj} - Q' + 1\bigr) + Q' - (e_{\max} - p + 1)
= \operatorname{adj} - e_{\max} + p \le p ,
$$

using $\operatorname{adj} \le e_{\max}$. The value is unchanged; only the
cohort member changes. In decimal32, `1E+96` is stored as `1000000E+90`.

```moonbit
///|
test "design: fold-down in decimal32" {
  let ctx = @decimal.DecimalContext::decimal32()
  let (x, flags) = @decimal.Decimal::from_string_ctx("1E+96", ctx)
  inspect(x.coefficient(), content="1000000")
  inspect(x.exponent10(), content="90")
  inspect(flags.clamped, content="true")
}
```

Zeros have no digits to pad, so their exponent is simply clamped into
$[E_{\text{tiny}}, E_{\text{top}}]$ (or $[E_{\text{tiny}}, e_{\max}]$ without
`clamp`), raising `clamped` when it changes.

### Flags as returned values

**Problem.** IEEE 754 status flags are sticky process state in hardware; GDA
adds traps. Hidden state conflicts with the Luna-Flow rule that semantics are
explicit, and makes concurrent or compositional code fragile.

**Choice.** Each context operation returns its own `DecimalFlags`.
`combine` is the field-wise OR, so flag sets form a commutative idempotent
monoid with identity `DecimalFlags::new()`: accumulating them over a pipeline
in any grouping gives the same set, which is exactly the sticky-flag
semantics without the state. `decimal_checked` packages that accumulation;
`decimal_gda` implements sticky status and traps as a separate model. The
five IEEE exceptions map to `invalid_operation`, `division_by_zero`,
`overflow`, `underflow` and `inexact`; the GDA conditions (`rounded`,
`subnormal`, `clamped`, `lost_digits`, `conversion_syntax`,
`division_impossible`, `division_undefined`, `invalid_context`) refine them.

### Quantize and same-quantum

`x.quantize(y)` returns the value of $x$ with exponent exactly $t = q_y$:

$$
\operatorname{quantize}(c\,10^{q},\, t) =
\begin{cases}
c\,10^{q-t} \cdot 10^{t} & q \ge t \text{ (exact padding)},\\
\circ\!\left(c\,10^{q - t}\right)\cdot 10^{t} & q < t \text{ (rounding)} .
\end{cases}
$$

The result must be representable *at that exponent*: the new coefficient must
have at most $p$ digits, $t$ must lie in $[E_{\text{tiny}}, e_{\max}]$ and the
result's adjusted exponent must not exceed $e_{\max}$. Otherwise the operation
is invalid. It never substitutes another exponent, because the exponent is
the contract (an amount quantized to cents must have two decimal places). The
only change of exponent is the fold-down of [clamping](#clamping): with
`clamp`, a target $t \in (E_{\text{top}}, e_{\max}]$ is accepted and the
result is stored at $E_{\text{top}}$ with `clamped`, exactly like any other
result in that range.
Rounding a coefficient up can add a digit ($9.99 \to 10.0$ at two digits of
precision), which is why the digit check comes after rounding.
`same_quantum` is the predicate $q_x = q_y$ (true for two infinities or two
NaNs); it is the test to use before combining values whose exponents must
agree.

### Interchange encodings

All three formats share one layout: a sign bit, a 5-bit *combination field*
$G$, $w$ *exponent continuation* bits and a *trailing significand* of $10J$
bits, where $p = 3J + 1$:

| Format | $w$ | $J$ | $1 + 5 + w + 10J$ |
| --- | ---: | ---: | ---: |
| decimal32 | 6 | 2 | 32 |
| decimal64 | 8 | 5 | 64 |
| decimal128 | 12 | 11 | 128 |

The biased exponent $E = q + \text{bias}$ has $w + 2$ bits whose top two bits
take only the values 00, 01, 10; this is the $3\cdot 2^{w}$ count derived
above.

**DPD.** The combination field holds the top two exponent bits and the
leading digit $d_0$: if $G = ab\,cde$ with $ab \ne 11$, the exponent bits are
$ab$ and $d_0 = cde \in [0,7]$; if $G = 11\,cd\,e$ with $cd \ne 11$, the
exponent bits are $cd$ and $d_0 = 8 + e$. $G = 11110$ is infinity and $G =
11111$ is NaN, the next bit distinguishing signaling from quiet. The other
$3J$ digits are stored in $J$ *declets*, 10 bits for 3 digits, by densely
packed decimal.[^dpd] Three digits have 1000 values and 10 bits 1024 codes,
an efficiency of $\log_2 1000 / 10 = 99.66\%$. Call a digit *small* if it is
0–7 (3 bits) and *large* if it is 8 or 9 (1 bit). The declet $pqr\,stu\,v\,wxy$
uses $v = 0$ for three small digits, which are then stored verbatim in
$pqr$, $stu$, $wxy$; $v = 1$ marks at least one large digit, and $wx$, then
$st$, say which. Counting by the number of large digits,

$$
\underbrace{8^3}_{v=0} = 512,\quad
\underbrace{3\cdot 2\cdot 8^2}_{v=1,\ wx\ne 11} = 384,\quad
\underbrace{3\cdot 2^2\cdot 8}_{wx=11,\ st\ne 11} = 96,\quad
\underbrace{2^3}_{wx=11,\ st=11} = 8,
$$

and $512 + 384 + 96 + 8 = 1000$. The first three cases use exactly 512, 384
and 96 codes. The last case has 32 codes for 8 values: $r$, $u$, $y$
carry the low bits of the three digits and $p$, $q$ are ignored, so **24 codes are redundant**: each
value with three large digits has four encodings, of which the one with
$pq = 00$ is canonical. Decoding accepts all four, `canonical()` rewrites them.
For example, `125` is the declet `0010100101` = `0x0A5` (three small digits)
and `999` is `0011111111` = `0x0FF`, also written `0x1FF`, `0x2FF`, `0x3FF`.

[^dpd]: M. F. Cowlishaw, "Densely packed decimal encoding", *IEE Proceedings —
Computers and Digital Techniques* 149(3), 2002. IEEE 754-2019 §3.5.2 gives
the encoding tables; the code implements them as Boolean formulas, and the
conformance corpus checks all 1024 declets.

**BID.** The coefficient is stored as a binary integer. If the two bits after
the sign are not 11, the next $w+2$ bits are the biased exponent and the
remaining $10J + 3$ bits the coefficient. Otherwise the exponent follows the
11 and the coefficient is $2^{10J+3}$ plus the remaining $10J+1$ bits ("100"
implied). Since $10^{7} - 1 < 2^{24}$, $10^{16}-1 < 2^{54}$ and
$10^{34}-1 < 2^{114}$, every coefficient fits; encodings with a coefficient
$\ge 10^{p}$ are non-canonical and decode to zero.

```moonbit
///|
test "design: redundant DPD declets decode and canonicalize" {
  let fmt = @decimal.DecimalInterchangeFormat::Decimal64
  let canonical = @decimal.DecimalInterchange::from_hex("#22300000000004FF", fmt).unwrap()
  let redundant = @decimal.DecimalInterchange::from_hex("#22300000000007FF", fmt).unwrap()
  inspect(canonical.to_decimal(), content="19.99")
  inspect(redundant.to_decimal(), content="19.99")
  inspect(redundant.is_canonical(), content="false")
  inspect(redundant.canonical().to_hex(), content="#22300000000004FF")
}
```

`DecimalInterchange` keeps the raw bits so that non-canonical input survives
until the caller decides to canonicalize; arithmetic is always on `Decimal`.

### Certified elementary functions

**Problem.** For transcendental $f$, $f(x)$ is irrational for almost every
decimal $x$, so it can only be approximated; a correctly rounded result needs
an approximation good enough to decide the rounding (the *table maker's
dilemma*).

**Options.** A fixed-precision evaluation with an a-priori error bound
(fast, but correctness then depends on the bound being right for every
function and argument); Ziv's adaptive strategy[^ziv] with rigorous error
bounds.

**Choice.** A Ziv loop over rigorous enclosures. For an operation $f$ and
input $x$:

1. Convert $x$ exactly into a binary interval: $\underline{x} =
   \nabla_w(x)$ and $\overline{x} = \Delta_w(x)$, `to_bin_float` with
   `TowardNegative` and `TowardPositive` at $w$ bits, so $x \in
   [\underline{x}, \overline{x}]$.
2. Evaluate $f$ on that interval with [`ball_float`](ball_float.md), which
   returns an interval $[L, U] \ni f(x)$ for every point of the input interval.
3. Convert $L$ and $U$ (dyadic, hence exact decimals) to `Decimal` exactly and
   round both with the target context. If both give the same representation
   (`compare_total` equal) and the same flags, return it.
4. Otherwise increase $w \leftarrow w + \max(32, \lfloor w/2 \rfloor)$ and
   repeat; after 12 evaluations report a certification failure.

The acceptance test is sound because rounding is monotone:
$L \le f(x) \le U$ implies $\circ(L) \le \circ(f(x)) \le \circ(U)$, and if the
outer two are the same representation, so is the middle one. The flags
transfer as well, provided $f(x)$ is not itself representable: then one
endpoint differs from the common result, so both are inexact, and
`overflow`, `subnormal` and `underflow` are monotone in $|f(x)|$ on an
interval that does not contain zero. Representable results are therefore
handled before the loop (below).

The initial working precision is $w_0 = \max(128,\ 4\max(D, p) + 64)$ bits,
where $D$ is the number of input digits: one decimal digit needs $\log_2 10
\approx 3.32 < 4$ bits, so $4\max(D,p)$ bits represent the input and the
target with margin, and 64 bits more cover the loss of the enclosure. The
schedule grows by a factor of about $3/2$ per step (exactly $w + \lfloor w/2
\rfloor$ once $w \ge 64$); the 12 evaluations use $w_0, w_1, \ldots, w_{11}$,
and the last one works with about $w_0 \cdot (3/2)^{11} \approx 86\,w_0$
bits.

Three kinds of inputs are decided outside the agreement test:

- **Exact results.** If $f(x)$ is a representable decimal and the enclosure
  is not a point, $L < f(x) < U$ round to different neighbours in a directed
  mode, forever. In a half mode both endpoints round to $f(x)$ itself, but
  with `inexact`, so the agreement test *accepts* the right value with wrong
  flags and with all $p$ digits instead of the preferred exponent: the
  soundness argument above assumed that $f(x)$ is not representable. The
  code detects a list of exact cases (`exp(0)`, `ln(1)`, $\log_{10} 10^{k}$,
  integer and half-integer arguments of `sinpi`/`cospi`/`tanpi`, odd
  quarter-integers of `tanpi`, `acos(1)`, integer arguments of
  `exp2`/`exp10`, $x^{1/2}$, integer powers, …); `ball_float` returns point
  intervals for exact binary results such as $\log_2 8 = 3$, $\log_2 0.125 =
  -3$, $\sqrt[3]{8} = 2$ and $\operatorname{hypot}(3, 4) = 5$. Exact results
  that neither recognises fall through: $\operatorname{hypot}(0.3, 0.4) =
  0.5$, $\sqrt[3]{0.008} = 0.2$ and $0.0016^{0.25} = 0.2$ come back in
  decimal64 `HalfEven` as `0.5000000000000000` and `0.2000000000000000` with
  `inexact`, and fail certification in the directed modes; $4^{1.5} = 8$
  through `power_ctx` exhausts the budget even in `HalfEven`. A complete
  test would check, before the loop, whether the rounded midpoint of the
  enclosure is an exact solution (for algebraic functions such as `hypot`,
  `rootn` and `power` with a rational exponent this is a finite integer
  computation).
- **Integer powers** are not certified at all: `power_ctx` with an integral
  exponent that does not fit in $p$ digits uses the General Decimal
  Arithmetic square-and-multiply with $p + \operatorname{digits}(n) + 2$
  working digits, each product rounded, and rounds the final product again.
  Its error is below one unit in the last place, but the result is not always
  correctly rounded: $3.339434^3 = 37.240765000\ldots$ is returned in
  decimal32 as `37.24076`.
- **Out-of-range results.** An enclosure such as $[0, \text{tiny}]$ has
  endpoints that round with different flags. Any value $\ge 10^{e_{\max}+2}$
  overflows identically, and any non-zero value
  $\le 10^{E_{\text{tiny}}-2} < \tfrac12 10^{E_{\text{tiny}}}$ rounds identically (to zero or to the
  smallest subnormal, depending only on the mode and sign), so far endpoints
  are replaced by such representatives; the binary test uses $3.322 >
  \log_2 10$ so the replacement is conservative. For `exp`, $x \ge
  3(e_{\max}+1)$ overflows because
  $x \log_{10} e \ge 3 \cdot 0.434\,(e_{\max}+1) > e_{\max}+1$, and $x \le -3\,|E_{\text{tiny}} - 1|$ underflows below
  $10^{E_{\text{tiny}}-1}$ by the same estimate. `power` bounds $y \log_2 x$
  with directed 128-bit arithmetic for the same purpose.

The elementary functions refuse contexts with $p$ or $|e|$ above 999,999
(`invalid_context`), which bounds the size of the exact endpoint conversions.

[^ziv]: A. Ziv, "Fast evaluation of elementary mathematical functions with
correctly rounded last bit", *ACM TOMS* 17(3), 1991; J.-M. Muller et al.,
*Handbook of Floating-Point Arithmetic*, 2nd ed., Birkhäuser 2018, ch. 12;
J. van der Hoeven, "Ball arithmetic", 2009, for the enclosure model.

### Coefficient kernels

**Problem.** Rounding at decimal positions needs fast division by powers of
ten and fast digit counts; large precisions need sub-quadratic
multiplication and division.

**Choice.** The package-private `DecCoeff` is either an inline `UInt` below
$10^{9}$ or a little-endian array of base-$10^{9}$ limbs with no leading zero
limb and a cached digit count. Base $10^9$ is the largest power of ten below
$2^{30}$, so a limb product is below $10^{18} < 2^{60}$; shifting by a
multiple of nine digits moves limbs, and `digits10` is a limb count plus the
digits of the top limb. `BigInt` appears only at the public boundary.

Multiplication dispatch:

| Shape | Algorithm | Cost |
| --- | --- | --- |
| one limb each | inline | $O(1)$ |
| many zero limbs ($n_a' n_b' \cdot 4 < n_a n_b$ non-zero limbs) | sparse products | $O(n_a' n_b')$ |
| $n_{\text{long}} > 2 n_{\text{short}}$ | balanced blocks of the short length | $\frac{n_{\text{long}}}{n_{\text{short}}} M(n_{\text{short}})$ |
| small | Comba columns / schoolbook | $O(n^2)$ |
| from the Karatsuba threshold | Karatsuba | $O(n^{\log_2 3}) = O(n^{1.585})$ |
| from the Toom-3 threshold | Toom-3 | $O(n^{\log_3 5}) = O(n^{1.465})$ |
| from the NTT threshold | two-prime NTT | $O(n \log n)$ |

The Comba kernel accumulates a column of $n$ limb products in a `UInt64`
only when $\min(n_a,n_b) \le 18$: a column sum plus incoming carry is at most
$18(10^{9}-1)^{2} + 2\cdot 10^{10} < 1.8\cdot 10^{19} < 2^{64}$, while 19
products could exceed $2^{64} \approx 1.845\cdot 10^{19}$.

The NTT splits the coefficients into base-$10^4$ digits and convolves them
modulo the primes $p_1 = 998\,244\,353 = 119\cdot 2^{23} + 1$ and $p_2 =
754\,974\,721 = 45 \cdot 2^{24} + 1$, both of which have $2^{23}$-th roots of
unity, so transforms up to length $2^{23}$ exist. A convolution coefficient
is a sum of at most $m = \min(n_a, n_b)$ products of digits below $10^{4}$,
hence below $m \cdot 9999^{2}$; it is recovered exactly from its residues by
the Chinese remainder theorem,

$$
z = r_1 + p_1 \bigl((r_2 - r_1)\, p_1^{-1} \bmod p_2\bigr),
$$

as long as $m \cdot 9999^{2} < p_1 p_2 \approx 7.54 \cdot 10^{17}$, i.e.
$m < 7.5 \cdot 10^{9}$ — always true below the transform limit. Base $10^{9}$
digits would need $m\cdot 10^{18} < p_1p_2$, impossible for any $m \ge 1$,
which is why the NTT uses smaller digits. When the bounds do not hold the
kernel falls back to Toom-3.

Division uses one-limb division, Knuth's Algorithm D,[^knuth]
Burnikel–Ziegler recursive division, or Newton reciprocal division. Newton
computes $r \approx S/d$ for $S = B^{n+1}$ by
$r_{k+1} = \lfloor r_k (2S - d r_k)/S \rfloor$: with $r_k = S/d - \varepsilon_k$
one gets $S/d - r_{k+1} \approx d\,\varepsilon_k^{2}/S$, so the number of
correct limbs doubles per step. The iteration must increase monotonically
from below; if it does not, or the final quotient correction takes more than
$2n+8$ steps, the routine falls back to Burnikel–Ziegler, which itself falls
back to Algorithm D on unsupported shapes.

[^knuth]: D. E. Knuth, *The Art of Computer Programming*, vol. 2, 3rd ed.,
§4.3.1 (Algorithm D) and §4.3.3; R. Brent and P. Zimmermann, *Modern Computer
Arithmetic*, Cambridge 2010, §1.3–1.4 and §2.4 (NTT); C. Burnikel and
J. Ziegler, "Fast recursive division", MPI-I-98-1-022, 1998.

The crossovers are measured per target and stored in target-specific files:

| Target | Karatsuba mul / square | Toom-3 | first NTT mul / square | Burnikel–Ziegler | Newton |
| --- | ---: | ---: | ---: | ---: | ---: |
| native | 96 / 48 | 1,152 | 1,728 / 640 | from 2,816 | disabled |
| LLVM | 96 / 96 | 2,048 | 4,096 / 2,048 | 2,048 | 4,096 |
| Wasm / Wasm-GC / JS | 96 / 96 | 4,096 | 8,192 / 4,096 | 2,048 | 4,096 |

(limbs of nine digits). On native the NTT threshold also depends on the
transform length — 1,728, 2,816, 4,608, 7,680, then 8,192 limbs for
multiplication and 640, 1,040, 1,824, 3,648, 7,296, then 8,192 for squaring —
and the Burnikel–Ziegler entry moves to 5,120 and 10,240 limbs for larger
block lengths. These are dispatch boundaries: they change cost, never results.
The native Newton path is implemented and tested but disabled, because native
measurements do not show a crossover.

## Correctness and invariants

- **Representation.** A finite `Decimal` has $c \ge 0$; `DecCoeff` limbs are
  canonical (no leading zero limb, exact digit count). A zero's sign is kept
  in the sign bit; `coefficient()` never carries a sign.
- **Single rounding.** Every context result of `+`, `-`, `×`, `fma`,
  `sqrt`, quantize, the conversions and (for normal results) `/` is the exact
  result rounded once, provided the exact exponent is at least
  $E_{\text{tiny}}$; certified elementary results are correctly rounded
  whenever they are returned, and a failure is reported, never approximated.
  The exceptions are listed under [known deviations](#known-deviations).
- **Error bound.** For normal results of those operations,
  $\operatorname{fl}(x) = x(1+\delta)$ with $|\delta| \le \tfrac12 10^{1-p}$ in
  the half modes and $|\delta| < 10^{1-p}$ in the directed modes.
- **Exactness is visible.** `inexact` is raised if and only if the returned
  value differs from the exact result; `rounded` whenever digits were dropped.
  Undetected exact elementary results violate the "only if" direction.
- **Cohort preservation.** An exact result that fits is returned at the
  preferred exponent; `quantize` either returns exponent $q_y$ or fails.
- **Flags.** `combine` is associative, commutative and idempotent with
  identity `new()`.
- **Ordering.** `compare` is a total preorder (NaNs equal to each other and
  above every number, $-0 = +0$); `compare_total` is a total order on
  representations and refines `compare` on non-NaN values.
- **Encodings.** Decoding then encoding canonical bits is the identity;
  encoding then decoding a value that fits the format is the identity,
  including cohort, sign of zero and NaN payload (DPD).
- **Complexity.** Comparison, addition, shifts and one-limb division are
  $O(n)$ in limbs; multiplication and division follow the dispatch table.

### Known deviations

These behaviours of the current branch contradict the goals above. Each is
reproduced in the [API reference](../api/decimal.md) next to the operation.

| Area | Behaviour | Cause |
| --- | --- | --- |
| finalization | a normal result whose exact exponent is below $E_{\text{tiny}}$ is rounded twice (half modes) | pre-rounding to the subnormal grid, [above](#round-once-in-one-place) |
| `div_ctx` | a subnormal quotient is rounded twice (half modes) | the finalization above, applied after the guarded quotient |
| elementary functions | undetected exact results carry `inexact` (half modes) or fail certification (directed modes) | the agreement test assumes $f(x)$ is not representable |
| integer powers | not always correctly rounded when the power needs more than $p$ digits | GDA square-and-multiply with rounded products |
| `atan2_ctx` | aborts on an infinite operand; $\operatorname{atan2}(\pm 0, -0)$ is an invalid NaN | missing special cases before the enclosure |
| `cosh_ctx`, `log2_ctx` | $\cosh(-\infty)$ and $\log_2(+\infty)$ are invalid NaNs | missing special cases |
| `ln_ctx`, `log10_ctx` | $\log(\pm 0) = -\infty$ without `division_by_zero` | follows General Decimal Arithmetic, not IEEE 754 §9.2.1 |
| `scaleb_ctx` | overflow is $\pm\infty$ in every rounding mode; zero results are not clamped | own finalizer instead of the shared one |
| parsing | exponents beyond $\pm 1.5\cdot 10^{9}$ are clamped silently | the shared decimal-string splitter caps the exponent |
| BID NaN | payloads are kept by leading digits of the value's precision | payload written at the value's precision |

The proofs of the midpoint test, the `ZeroFiveUp` double-rounding lemma, the
overflow table, the fold-down bound, the certification lemma and the kernel
bounds are collected in the attachment:

[Rounding proofs for decimal](../../attachments/design_decimal_rounding.typ)

The [conformance page](../conformance/decimal.md) records the finite evidence
(fixed IEEE corpus, exhaustive declet check, MPFR-certified elementary rows,
four targets).

## Alternatives rejected

- **A binary `BigInt` coefficient.** Rounding at a decimal position needs a
  division by $10^{s}$ and a digit count at every operation; with a binary
  coefficient both are expensive, with base-$10^{9}$ limbs they are limb moves
  and one small division.
- **Ambient context and sticky flags.** Rejected for explicitness and
  composability; the flags monoid gives the same information.
- **A `compare` that aborts on NaN.** Sorting and generic `Compare` code would
  abort on data containing NaN. The current `compare` is a total preorder and
  IEEE semantics are available through `compare_checked`, `compare_ctx`,
  `compare_signal_ctx` and `compare_total`.
- **Fixed-precision transcendental kernels with an analytic error bound.**
  Faster for small precisions, but a correctness proof per function and per
  precision; the enclosure loop is correct by construction and its failure
  mode is explicit.
- **One package for IEEE and GDA.** Sticky status, traps and trap precedence
  change the type of every operation; they live in `decimal_gda`.
- **Normalizing every result.** Losing the cohort would make `12.30` and
  `12.3` indistinguishable and break quantum-sensitive protocols.

## Boundaries

`decimal` deliberately does not:

- keep sticky status or traps (use `decimal_checked` or `decimal_gda`);
- round the context-free operators to a context: `*` is exact, `+` and `/`
  round to the operand precision only, and none applies an exponent range;
- guarantee correct rounding of integer powers longer than $p$ digits, or the
  exact flags of exact elementary results it does not recognise (see
  [known deviations](#known-deviations));
- guarantee that elementary-function certification succeeds: after the
  refinement budget (which, at its last steps, works with very wide numbers
  and can take a long time) it reports `CertificationFailure` (`try_*_ctx`) or NaN
  with `invalid_operation` (`*_ctx`);
- evaluate elementary functions in contexts with precision or exponents above
  999,999;
- preserve NaN payloads through binary conversions, or keep a BID NaN payload
  whose value precision differs from the format precision;
- expose its coefficient representation, kernel selection or thresholds;
- claim conformance beyond the finite evidence on the
  [conformance page](../conformance/decimal.md).
