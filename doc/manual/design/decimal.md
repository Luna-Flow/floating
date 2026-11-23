# decimal design

The arithmetic model of `Luna-Flow/floating/decimal` represents decimal values
with a coefficient, an exponent and a sign, then rounds each context result
once. Its cohort preserves the chosen exponent, while a context defines
precision, rounding direction and exponent range. This page derives those rules,
the interchange encodings and the certification of elementary functions. The
[API](../api/decimal.md) specifies each function; the
[tutorial](../tutorial/decimal.md) shows them in use.

## Design goal

`decimal` implements the decimal arithmetic of IEEE 754-2019[^ieee] for any
precision, with three properties:

1. **Every context operation is correctly rounded.** The result is the exact
   mathematical result rounded once, in the selected direction, to the
   context's precision and exponent range — for the basic operations and for
   the elementary functions alike. The current implementation misses this goal
   in two places (integral rounding of operands longer than $p$ digits, huge
   exponents in text); they
   are listed in [known deviations](#known-deviations).
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

The checked ParseChecked adapter follows IEEE 754-2019 4.3 and 5.12.2. Text
conversion uses the supplied rounding-direction attribute and context exponent
range. parse_checked returns the converted value through Result. To inspect
exception flags such as overflow, use `Decimal::from_string_ctx`.

## Mathematical background

### Decimal floating-point numbers

A decimal floating-point format with precision $p$ and adjusted-exponent range
$[e_{\min}, e_{\max}]$ is the set of numbers

$$
x = (-1)^s \cdot c \cdot 10^{q}, \qquad
s \in \{0,1\},\quad c \in \mathbb{Z},\ 0 \le c < 10^{p},\quad
E_{\text{tiny}} \le q \le E_{\text{top}},
$$

together with $\pm\infty$ and NaNs. Here $c$ is the *coefficient* and $q$ is
the *exponent*. The *quantum* is $10^q$, and

$$
E_{\text{tiny}} = e_{\min} - p + 1, \qquad E_{\text{top}} = e_{\max} - p + 1 .
$$

Contexts require $1 \le p \le 999\,999\,999$,
$-999\,999\,999 \le e_{\min} \le 0$ and
$0 \le e_{\max} \le 999\,999\,999$. A shared constructor helper validates
these bounds and computes $E_{\text{tiny}}$ and $E_{\text{top}}$; invalid
parameters return an error naming the invalid field. These are the adopted
decNumber `decContext.h` limits and keep context-derived exponent sums within
`Int`. GDA 1.70 specifies no fixed context limits and requires a balanced
range; this library does not enforce that separate balance rule.

The *adjusted exponent* of a non-zero $x$ is $\operatorname{adj}(x) = q +
\operatorname{digits}(c) - 1 = \lfloor \log_{10} |x| \rfloor$: it is the
exponent of $x$ written in scientific notation $d_0.d_1d_2\ldots \times
10^{\operatorname{adj}(x)}$. A non-zero $x$ is *normal* when
$\operatorname{adj}(x) \ge e_{\min}$ and *subnormal* otherwise; the smallest
positive subnormal is $10^{E_{\text{tiny}}}$ and the largest finite value is

$$
N_{\max} = (10^{p} - 1)\cdot 10^{E_{\text{top}}} = 10^{e_{\max}+1} - 10^{e_{\max}-p+1}.
$$

`DecimalContext` stores the precision $p$, $e_{\max}$ (and $e_{\min} = 1 - e_{\max}$,
IEEE 754-2019 3.3), the rounding direction and two limits
(`refinement_limit`, `elementary_precision_limit`) that bound the elementary
functions. Every context is an IEEE format: its
exponents above $E_{\text{top}}$ are not allowed (see [clamping](#clamping)) and
tininess is detected before rounding. The library's own working contexts, which
are not formats, are private. The interchange formats are:

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
The trade-off is a larger *wobble* (below) and more expensive digit arithmetic.

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
$E_{\text{tiny}}$. `quantize_ctx` makes the exponent an explicit argument, and
`normalized` chooses the member with the largest exponent.

For conversion from a character sequence, IEEE 754-2019 5.2 selects the
least possible exponent for an inexact result. Thus parsing `1.0001` at
precision 3 gives `1.00`, and `99999` gives `1.00E+5`, since a carry into
$10^p$ still leaves $p$ digits; an exact result uses the representable cohort
member closest to the preferred exponent (parsing `1.000` at precision 3 also
gives `1.00`).

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

The kernels implement eight algorithms. A context selects one of the five
that IEEE 754-2019 4.3 names (public `DecimalRoundingMode`: `RoundTowardZero`
is `Down`, `RoundTowardPositive` is `Ceiling`, `RoundTowardNegative` is
`Floor`, `RoundTiesToAway` is `HalfUp`, `RoundTiesToEven` is `HalfEven`); `Up`,
`HalfDown` and `ZeroFiveUp` are working modes of the library (directed bounds of
the certified functions, the guard digit of division) that no context can
select. The table uses the kernel names.

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

the *wobble* of base $\beta = 10$.[^wobble] In binary the wobble is 2, so
for the same storage decimal has a slightly worse worst-case relative error:
decimal64 has $u = \tfrac12 10^{-15} = 5\cdot 10^{-16}$, binary64 has $u =
2^{-53} \approx 1.1 \cdot 10^{-16}$. The directed modes have
$|\delta| < 10^{1-p} = 2u$. The machine epsilon, the distance from 1 to the
next larger number, is $10^{1-p}$ — `epsilon_contextual` returns it and
`next_up_ctx(1)` in decimal64 is `1.000000000000001`. Below 1 the spacing is ten
times smaller: `next_down_ctx(1)` is `0.9999999999999999`.

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

**Choice.** One `Decimal` type holds a sign, a coefficient of any length, an
exponent, a class, a NaN-kind bit and the precision of the value. An immutable
`DecimalContext` supplies the parameters for contextual operations. A decimal64
computation uses `DecimalContext::decimal64()`; interchange encoders apply the
format context before encoding. One representation keeps arithmetic in one
place and lets a caller work at 50 digits before rounding to decimal64. It also
matches the General Decimal Arithmetic model. The precision of the value sets
the precision used by context-free operators and conversions only.

### Round once, in one place

**Problem.** Double rounding — rounding an already rounded value again — can
change a correctly rounded result.

**Choice.** Every finite context result goes through one finalization routine
that receives an **exact** result $(s, C, Q)$, with $C$ possibly much longer
than $p$. Operation kernels compute exact integers; they never round. The
exceptions are operations whose exact result is infinite — division, square
root, elementary functions — and two whose exact result would be needlessly
long — a sum with a far smaller addend and an integer power — which are
described below; each of them still decides the last digit from exact
information.

A single rounding needs a single target exponent. With
$D = \operatorname{digits}(C)$, the exact value has adjusted exponent
$a = Q + D - 1$, and the correctly rounded result has exponent

$$
t = \max\bigl(a - p + 1,\ E_{\text{tiny}}\bigr),
$$

the first term keeping $p$ digits for a normal result and the second the
subnormal grid; the result is $\circ(C\,10^{Q-t})\,10^{t}$, followed by the
overflow check (on the value rounded to $p$ digits with unbounded exponent),
the underflow flag and the fold-down.

The routine rounds to the subnormal grid only when $t = E_{\text{tiny}} > Q$.
It tests this condition as $Q + \max(0, D - p) < E_{\text{tiny}}$. Then the
exact value is below $10^{e_{\min}}$, and $C$ is rounded once with shift
$E_{\text{tiny}} - Q$. Every other coefficient is rounded once to $p$ digits
only, even when $Q < E_{\text{tiny}}$.

Rounding a normal result first to the subnormal grid $10^{E_{\text{tiny}}}$ and
then to $p$ digits can change the answer. The first rounding may land exactly
on a midpoint of the second grid, leaving the tie rule to decide a case the
exact value already decided. In decimal32, where $E_{\text{tiny}} = -101$,
consider
$3.000001\cdot 10^{-45} \times 1.500001\cdot 10^{-45} =
4500004500001\cdot 10^{-102}$. The first rounding drops digit 1, which is
below half, and gives $450000450000\cdot 10^{-101}$. That is the exact
midpoint $4500004.5\cdot 10^{-96}$. A second `HalfEven` rounding gives
$4.500004\cdot 10^{-90}$, while rounding the exact product once gives
$4.500005\cdot 10^{-90}$ because it lies above the midpoint.

The directed modes would be unaffected because, for every real $y \ge 0$ and
integers $s_1, s_2 \ge 0$,
$\lfloor\lfloor y\,10^{-s_1}\rfloor 10^{-s_2}\rfloor =
\lfloor y\,10^{-s_1-s_2}\rfloor$.

#### Addition with a far smaller addend

When one addend $\ell$ lies far below the other, $h$, the exact sum can have
many more digits than the result keeps. Let $t$ be the target exponent of $h$
alone and $g = \min(q_h,\ t - 2)$. Every digit of $h$ lies on the grid
$10^{g}$, and so does every rounding boundary of the sum: the grid $10^{t}$,
its midpoints, and the grid $10^{t-1}$ with its midpoints, which a
cancellation can reach. If $0 < |\ell| < 10^{g}$, the sum $h + \ell$ lies
strictly between the same two neighbours on that grid as the short value
$h \pm 10^{g-1}$, with the sign of $\ell$. `add_ctx`
rounds that value once instead of the exact sum; result and flags are the
same in every mode. With precision 7, $1598617.000000000001 - 2\cdot
10^{-12}$ is `1598616` under `Down`, and $6.0000005\cdot 10^{-73} +
10^{-101}$ is `6.000001E-73` under `HalfEven`.

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

The finalizer raises `rounded` whenever $s > 0$ and `inexact` whenever
$R \ne 0$. It drops trailing zeros before rounding, so discarding only zeros
raises `rounded` alone.

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
   Whether the quotient terminates is decided before any gcd is formed: with
   $c_b = 2^{a}5^{b}u$ and $u$ prime to 10, it terminates if and only if $u$
   divides $c_a$ (the reduced denominator $c_b/\gcd(c_a, c_b)$ contains no prime
   of $u$ exactly when the gcd takes all of $u$, and $u$ is coprime to the
   factors 2 and 5 of $c_b$). The valuations $a$ and $b$ are read from the
   lowest limb when both are below 9, so for a divisor prime to 10 (the usual
   case) the test is $c_b \mid c_a$, one division of limb arrays. Only a
   terminating quotient runs the gcd route above. A non-terminating one, which
   is nearly every division of random operands, used to pay a gcd of the two
   coefficients (quadratic, hundreds of allocations at 34 digits) to learn
   that it has no exact result.
3. *Non-terminating quotient.* The result is certainly inexact. Let
   $a_c = \operatorname{adj}(c_a/c_b)$, found exactly by comparing $c_a$ with
   $c_b$ scaled by the right power of ten. Scaling the numerator (or the
   denominator) by $10^{p-1-a_c}$ makes the integer quotient have exactly $p$
   digits: $N = Q D + R$. The increment decision compares $2R$ with $D$ — the
   same midpoint test as above, now with the exact remainder as sticky
   information — so the quotient is rounded once.

The third route is used for normal results. For subnormal
results the code forms the integer quotient of
$c_a\,10^{k}$ by $c_b$ with $k = p + \operatorname{digits}(c_b) + 2$ (about
$\operatorname{digits}(c_a) + p + 2$ digits), rounds it with `ZeroFiveUp`,
and rounds that guarded quotient once more in the context mode, straight to
its final grid: $p$ digits, or $10^{E_{\text{tiny}}}$ for a subnormal
quotient. The context-free operator `/` uses the same guarded scheme. By the
`ZeroFiveUp` lemma below the two roundings equal one rounding of the exact
quotient, so $15/83294$ at five digits is `0.00018009`,[^div-05up] and in
decimal32 $1 / 1.9999999999998\cdot 10^{101} = 5.0000000000005\cdot
10^{-102}$ gives `1E-101`.

[^div-05up]: Rounding the guarded quotient in the context mode instead could
    manufacture a tie: at five digits the guarded quotient of $15/83294$
    would end in an exact half unit, and half-even would return `0.00018008`.

`ZeroFiveUp` exists precisely to make such two-step schemes safe. If $x$ is
first rounded with `ZeroFiveUp` to $p + k$ digits ($k \ge 1$) and then with
any mode $\circ$ to $p$ digits, the result equals $\circ(x)$: an inexact
`ZeroFiveUp` result ends in a digit other than 0 and 5, so it is never a
$p$-digit number nor a $p$-digit midpoint, and it lies on the same side of
every $p$-digit number and midpoint as $x$. The proof is in the
attachment.[^attachment] The guarded division above relies on it; the
finalizer needs no such lemma, because it rounds once at the target exponent
$t$ derived above.

#### Plain sums, products and quotients

The general route of `add_ctx`, `sub_ctx`, `mul_ctx` and `div_ctx` normalizes
the exact result, finalizes it and returns flags, through temporaries that are
records and tuples: a 34-digit sum made 20 allocations, a product 14 and a
quotient 38. Most operations need none of that machinery. When both operands are
finite and nonzero, the context has a precision $p$, and the result is neither
absorbed, nor subnormal, nor beyond the range, nor folded down by the clamp,
the result is the exact result rounded once to $p$ digits, with `inexact`
raised when a nonzero digit was discarded and no other flag.

The predicates are those of the finalizer turned around. The exact result has
adjusted exponent $a$; the plain path requires $e_{\min} \le a \le e_{\max} - 1$.
Then the result is not tiny (no subnormal rounding, no `underflow`), and a carry
of the rounding into $10^{p}$ raises the adjusted exponent to at most $e_{\max}$,
so it cannot overflow; the exponent of the rounded result is $a - p + 1$ or one
more after a carry, never below $E_{\text{tiny}}$. For an exact result with
fewer than $p$ digits the exponent is the exponent of the exact result, and in
a clamping context the plain path requires it not to exceed
$e_{\max} - p + 1$ (otherwise the finalizer folds the digits down, which the
general route does). A sum also requires that the smaller adjusted exponent is
not below $\hat e_1 - p + 1$ (no operand is absorbed; that case keeps its own
sticky route) and a nonzero exact sum (the sign of a zero sum depends on the
rounding direction); a product and a quotient require nonzero operands. A
quotient with a finite decimal expansion is left to the general route, because
its exponent follows the ideal-exponent rules.

The direct sum path forms the sum in one limb array and rounds it in place; a product
is the exact product rounded at the digit count. A quotient is one division of
$c_a \cdot 10^{k}$ with $k = \max(0, p + 2 + n_b - n_a)$ ($n_a$, $n_b$ the digit
counts of the coefficients), which has at least $p + 2$ digits, rounded with
`ZeroFiveUp` and then once to $p$ digits, which by the `ZeroFiveUp` lemma above equals one
rounding of the exact quotient in every mode. The remainder test of that
division tells a terminating quotient from a non-terminating one; for the cheap
cases (equal coefficients, a divisor of one limb) the test is made before the
division, so that an exact quotient does not pay for a division it discards. The flag
sets are shared constants, like the empty set (`DecimalFlags` is an immutable
record compared by value). A 34-digit `add_ctx` makes 5 allocations and 1,739
instructions instead of 20 and 4,427, `mul_ctx` 8 and 2,500 instead of 14 and
3,251, `div_ctx` 13 and 3,840 instead of 38 and 9,212.

The general route defines the behavior; the direct paths must return the same
result and flags. The white-box test compares both routes on random operands of 1 to
130 digits, with mixed signs, cancellations, exponent gaps and carries, for
every rounding direction, in clamped and unclamped formats with tight and
storage-wide exponent ranges and operands at both ends of the range.

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
$\lfloor \sqrt{x}\,10^{-t} \rfloor$. The integer root is computed by the
kernel (Zimmermann's Karatsuba square root from three limbs, see *Coefficient
kernels*); the iteration it replaced, and that the tests keep as the reference,
is Newton's iteration on integers,

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
IEEE 754-2019 7.4 defines the delivered result as the rounding of the exact value in a
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
  let down = ctx.with_rounding(@decimal.DecimalRoundingMode::RoundTowardZero)
  let (sat, flags) = big.mul_ctx(ten, down)
  inspect(sat, content="9.999999999999999E+384")
  inspect(flags.overflow() && flags.inexact(), content="true")
}
```

#### Subnormals, tininess and underflow

If the exact value is below $10^{e_{\min}}$ and needs an exponent below
$E_{\text{tiny}}$, it is rounded once to the subnormal grid: the shift becomes
$s = E_{\text{tiny}} - Q$ and the rounding rule above applies with fewer than
$p$ digits kept. The result is **tiny** when its adjusted exponent is below
$e_{\min}$, measured on the exact value. IEEE 754-2019 7.5 requires this for
decimal formats ("tininess is detected before rounding"). With $p = 3$ and
$e_{\min} = 0$, $0.9951$ and
$0.99951$ are both tiny (their subnormal-grid result is `1.00`). A tiny and
inexact result raises `underflow`, as required for default exception handling
by IEEE 754-2019 7.5. A result that rounds to zero gets exponent
$E_{\text{tiny}}$.

#### Clamping

In every context, exponents above $E_{\text{top}}$ are
not representable, because the encoding has room only for
$E_{\text{top}} - E_{\text{tiny}} + 1$ exponents. A result with $Q' >
E_{\text{top}}$ that did not overflow is **folded down**: the coefficient is
multiplied by $10^{Q' - E_{\text{top}}}$ and the exponent set to
$E_{\text{top}}$. This never needs more than $p$ digits:

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
  inspect(flags.inexact(), content="false")
}
```

Zeros have no digits to pad, so their exponent is simply clamped into
$[E_{\text{tiny}}, E_{\text{top}}]$.

A zero is the one result `quantize_ctx` can accept with a target exponent above
$E_{\text{top}}$: the target may be as high as $e_{\max}$. Since an IEEE
format contains only exponents through $E_{\text{top}}$ (IEEE 754-2019 3.3),
`quantize_ctx` folds the zero exponent down to $E_{\text{top}}$, as it does for
other results. The bound follows from the one-digit coefficient,
$e_{\max} - \operatorname{digits} + 1 = e_{\max}$. The reference
implementation calls `decFinalize` from `decQuantizeOp` at this bound and
lowers the exponent in its clamp branch. Until 0.12, the fold in this package
was controlled by the `with_clamp_fold` option.

### Flags as returned values

**Problem.** IEEE 754 status flags are sticky process state in hardware; GDA
adds traps. Hidden state conflicts with the Luna-Flow rule that semantics are
explicit, and makes concurrent or compositional code fragile.

**Choice.** Each context operation returns its own `DecimalFlags`.
`combine` is the field-wise OR, so flag sets form a commutative idempotent
monoid with identity `DecimalFlags::new()`: accumulating them over a pipeline
in any grouping gives the same set, which is exactly the sticky-flag
semantics without the state. `DecimalFlags` is an immutable record compared by value, so the identity is
one shared value and `combine` returns the other operand when one is clear:
no flag set is allocated for an operation that raises nothing. `decimal_checked` packages that accumulation;
`decimal_gda` implements sticky status and traps as a separate model. The
five IEEE exceptions are `invalid_operation`, `division_by_zero`,
`overflow`, `underflow` and `inexact`; `DecimalFlags` has exactly these and
`not_computed`. The GDA conditions (`rounded`, `subnormal`, `clamped`,
`lost_digits`, `conversion_syntax`, `division_impossible`, `division_undefined`,
`invalid_context`) belong to `decimal_gda`.

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
only change of exponent is the fold-down of [clamping](#clamping): a target $t \in (E_{\text{top}}, e_{\max}]$ is accepted and the
result is stored at $E_{\text{top}}$, exactly like any other
result in that range.
Rounding a coefficient up can add a digit ($9.99 \to 10.0$ at two digits of
precision), which is why the digit check comes after rounding.
`same_quantum` is the predicate $q_x = q_y$ (true for two infinities or two
NaNs); it is the test to use before combining values whose exponents must
agree.

### Conversion to integers

`to_int_ctx` and its three siblings (IEEE 754-2019 5.4.1 and 5.8) share one
function that rounds a finite value $c\,10^{q}$ to an integer in the direction
of the context and checks the range, so the four types differ only in their
limits. A value with $q \ge 0$ is an integer already; one with $q < 0$ is
$c / 10^{-q}$ rounded by the same decision function that rounds decimal
results (the kernel's rounding decisions: increment or not from the discarded
digits and the mode), and `changed` is whether anything was discarded.
The power of ten is never formed. An integer of 21 or more digits is out of
range for every type ($2^{64}$ has 20 digits), so
$\operatorname{digits}(c) + q > 20$ is decided before any arithmetic, and a fraction with more than
$\operatorname{digits}(c) + 1$ places is the same as one with exactly that many:
the value is below $0.1$, and the rounding decision only needs to know that the
remainder is nonzero and below one half, so the shift is clamped to
$\operatorname{digits}(c) + 1$. `1E+999999` and `1E-999999` therefore cost
as much as `1E+3` and `1E-3`. The invalid operation is signaled for a NaN, an
infinity and an out-of-range result, and then only: `exact` adds `inexact`
when `changed`, nothing else is ever raised (no `rounded`, no clamping: the
result is not a decimal), and a negative value that rounds to zero converts to
`0`.

### Conversions between formats

`convert_format`, `from_binary_ctx` and `to_binary_ctx` (IEEE 754-2019 5.4.2)
each round the exact source value once in the destination's context and return
the flags of that rounding.
Decimal to decimal is `apply_ctx` of the format's context, so the preferred
exponent $Q(\text{source})$ is the one the normalization keeps when the value
fits. Binary to decimal does not form the expansion $c\,2^e$, whose cost grows
with $|e|$: it takes the first $p + 1$ significant digits of $|x|$, truncated, from
the correctly rounded digit string of `Binary::to_decimal_string_ctx`, appends a
sticky digit $1$ when digits were dropped, and rounds that decimal once with
`apply_ctx`. A rounding of a decimal depends on the digits beyond the kept ones
only as zero, below half, a tie or above half, and the surrogate (the digits and
the sticky digit) lies strictly inside the unit after the truncated digits as $x$
does, so for every kept length up to $p$ (fewer digits for a subnormal result, so
nothing is rounded twice) the result and its flags are those of $x$, and the
tininess of the unrounded value is the one of $x$ (same leading digit). An exact
value has no sticky digit; its trailing zeros are dropped and an integer takes
exponent 0, the preferred exponent, or, when it has more than $p$ digits, the
member closest to it (IEEE 754-2019 5.2): zeros are appended up to $p + 1$ digits,
and the zero that `apply_ctx` rounds away leaves the $p$-digit member with the
exponent closest to 0 (`1E+20` in decimal64 is `1000000000000000E+5`, flagged
rounded). The digits are not
formed for a value whose estimate
$\lfloor 0.30103\,(\operatorname{bits} + e)\rfloor$ lies more than two beyond
$e_{\max}$ or three below $E_{\text{tiny}}$, which stands for every such value in
the rounding (overflow, or a result of zero or the least subnormal). A binary exponent
beyond $2^{22}$ is refused. Decimal to binary is the exact decimal text rounded by
`Binary::from_string_ctx`, which is correctly rounded for any exponent and is
checked against MPFR; the corpus runs both directions through the MPFR rows of
`mpfr_strtofr` and `mpfr_get_str` and through exact rows for every pair of
decimal32/64/128 and binary16/32/64/128 (`tools/generate_decimal_conversion_rows.py`).
A NaN keeps its sign and the payload it can hold ($p - 1$ digits, $p - 2$ bits),
and a signaling NaN is quieted with the invalid operation exception.

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
Computers and Digital Techniques* 149(3), 2002. IEEE 754-2019 3.5.2 gives
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
   \nabla_w(x)$ and $\overline{x} = \Delta_w(x)$, `to_binary` with
   `RoundTowardNegative` and `RoundTowardPositive` at $w$ bits, so $x \in
   [\underline{x}, \overline{x}]$.
2. Evaluate $f$ on that interval with [`interval`](interval.md), which
   returns an interval $[L, U] \ni f(x)$ for every point of the input interval.
3. Convert $L$ and $U$ (dyadic, hence exact decimals) to `Decimal` exactly and
   round both with the target context. If both give the same representation
   (`total_order_compare` equal) and the same flags, return it.
4. Otherwise increase $w \leftarrow w + \max(32, \lfloor w/2 \rfloor)$ and
   repeat; after $L$ evaluations report a certification failure, where $L$ is
   the refinement limit of the context (`DecimalContext::refinement_limit`,
   twelve by default; a value below one counts as one). With
   `with_refinement_limit(None)` the count is unbounded, but the loop stops, with
   the same failure, when $w$ exceeds $\max(8\,000\,000,\ 256\,w_0)$ bits (at
   most $10^9$), so the work and the memory stay bounded. The default changes no
   result.

The acceptance test is sound because rounding is monotone:
$L \le f(x) \le U$ implies $\circ(L) \le \circ(f(x)) \le \circ(U)$, and if the
outer two are the same representation, so is the middle one. The flags
transfer as well, provided $f(x)$ is not itself representable: then one
endpoint differs from the common result, so both are inexact, and
`overflow` and `underflow` are monotone in $|f(x)|$ on an
interval that does not contain zero. Representable results are therefore
handled before the loop (below).

The initial working precision is $w_0 = \max(64,\ \lfloor 3.321929\,\max(D, p)
\rfloor + 31)$ bits, where $D$ is the number of input digits: one decimal digit
needs $\log_2 10 = 3.3219280\ldots < 3.321929$ bits, so $\lfloor 3.321929\,
\max(D,p) \rfloor$ bits represent the input and the target, and 31 guard bits
more cover the loss of the enclosure. The
schedule grows by a factor of about $3/2$ per step (exactly $w + \lfloor w/2
\rfloor$ once $w \ge 64$); the 12 evaluations use $w_0, w_1, \ldots, w_{11}$,
and the last one works with about $w_0 \cdot (3/2)^{11} \approx 86\,w_0$
bits.

Three kinds of inputs are decided outside the enclosure-agreement test. Exact results
need their preferred exponent and flags; integer powers use exact integer
information; range-limit results can be decided by representatives; and
non-integral powers use one composed enclosure.


If $f(x)$ is a representable decimal and the enclosure
  is not a point, $L < f(x) < U$ round to different neighbours in a directed
  mode, forever. In a half mode both endpoints round to $f(x)$ itself, but
  with `inexact`, so the agreement test would *accept* the right value with
  wrong flags and with all $p$ digits instead of the preferred exponent: the
  soundness argument above assumed that $f(x)$ is not representable. The
  code therefore detects exact cases before the loop (`exp(0)`, `ln(1)`,
  $\log_{10} 10^{k}$, integer and half-integer arguments of
  `sinpi`/`cospi`/`tanpi`, odd quarter-integers of `tanpi`, `acos(1)`,
  integer arguments of `exp2`/`exp10`, $x^{1/2}$, integer powers, …). For
  the algebraic functions this is a finite integer computation: `rootn`
  strips the trailing zeros of the coefficient, aligns the exponent to a
  multiple of the degree $n$ and tests the integer $n$-th root (Newton's
  iteration from above) of the result, so $\sqrt[3]{0.008} = 0.2$; `hypot`
  forms $x^2 + y^2$ exactly when the adjusted exponents of the operands differ
  by at most $p + 2$ (beyond that, $\sqrt{x^2+y^2} - |x| \approx y^2/(2|x|)$
  is below the last digit the result could have) and tests it with the exact
  square root, so $\operatorname{hypot}(0.3, 0.4) = 0.5$; a zero operand
  gives the other operand's magnitude. `interval` returns point intervals
  for exact binary results such as $\log_2 8 = 3$, $\log_2 0.125 = -3$ and
  $4^{1.5} = 8$. A power whose exact value is representable in decimal but not
  in binary is decided in decimal instead: the exponent is reduced to $p/q$ in
  lowest terms — a decimal exponent is $c \cdot 10^{-k}$, so $q$ keeps only the
  twos and fives the coefficient cannot cancel — and the result is exact
  exactly when $x^{p/q}$ is a decimal. By Bézout there are integers $a, b$
  with $ap + bq = 1$, so $x^{1/q} = (x^{p/q})^{a} x^{b}$ is rational whenever
  $x^{p/q}$ is, and a rational $q$-th root of a decimal is again a decimal
  (its denominator divides a power of ten). The test therefore writes
  $x = r \cdot 10^{qe}$ with $r$ an integer keeping fewer than $q$ trailing
  zeros, decides whether $r$ is a perfect $q$-th power by a bisection over
  the root's digit count, and only then raises the root to $p$ (the
  reciprocal of the root, for a negative exponent). Every intermediate is
  then no longer than the result, so $0.0016^{0.25} = 0.2$, $32^{0.2} = 2$ and
  $(2^{1200} \cdot 10^{-1200})^{1.5} = 2^{1800} \cdot 10^{-1800}$ at
  precision 1000 are all decided at once, although $x^{3}$ in the last one has
  1084 digits. Only a value of at most $p + 1$ significant digits can sit on a
  rounding boundary — a representable value in the directed modes, a
  midpoint in the half modes — so the search covers exactly those and leaves
  a longer exact value, which lies strictly inside its rounding cell, to the
  enclosure.

Integer powers are not certified; they are rounded once from exact
  integer information. `pow_ctx` with an integral exponent $n$ that does
  not fit in $p$ digits first runs the General Decimal Arithmetic
  square-and-multiply with $p + \operatorname{digits}(n) + 2$ working
  digits. That scheme only ever discards zero digits of an exact power, so
  it reports `inexact` exactly when the true power is inexact, and it gives
  exact powers their GDA cohort and flags. An inexact
  result is then replaced by the correctly rounded one. With $c$ the
  coefficient stripped of trailing zeros, if $|n| \cdot
  \operatorname{digits}(c) \le \max(4p, 64)$ the exact power $c^{|n|}$ is
  formed and rounded once (a negative $n$ divides once, correctly rounded).
  Otherwise $c^{|n|}$ has more than $p + 1$ significant digits and no
  trailing zero, so it is never a $p$-digit number or midpoint; lower and
  upper bounds from square-and-multiply in `Down` and `Up` at a working
  precision of $p + \operatorname{digits}(n) + 8$ digits, doubled on each
  attempt, are refined until they round to the same representation. So
  $3.339434^3 = 37.240765000\ldots$ is `37.24077` in decimal32. If the
  bounds leave the working exponent range, the GDA result is kept; its error is below one unit in the last
  place. A power that the exponent bounds place below
  $10^{E_{\text{tiny}}-2}$ (including an exact power of ten below
  $10^{E_{\text{tiny}}}$) is not evaluated: it rounds like any non-zero value
  below $\tfrac12 10^{E_{\text{tiny}}}$, to zero in the nearest modes and to
  $\pm 10^{E_{\text{tiny}}}$ when the rounding direction is away from zero
  for its sign (IEEE 754-2019 7.5).

An enclosure such as $[0, \text{tiny}]$ has
  endpoints that round with different flags. Any value $\ge 10^{e_{\max}+2}$
  overflows identically, and any non-zero value
  $\le 10^{E_{\text{tiny}}-2} < \tfrac12 10^{E_{\text{tiny}}}$ rounds identically (to zero or to the
  smallest subnormal, depending only on the mode and sign), so far endpoints
  are replaced by such representatives; the binary test uses $3.322 >
  \log_2 10$ so the replacement is conservative. `exp`, `exp2` and `exp10`
  share one range decision. For $b^x$ with
  $b \in \{e, 2, 10\}$ let $k \ge 1/\log_{10} b$ be the integer 3, 4 or 1.
  Then $x \ge k\,(e_{\max}+1)$ gives
  $b^x = 10^{x \log_{10} b} \ge 10^{e_{\max}+1}$, above the largest finite
  number $(10^p - 1)\,10^{e_{\max}-p+1}$, so the overflow result of the
  rounding direction applies (IEEE 754-2019 7.4); and $x \le -k\,(1 -
  E_{\text{tiny}})$ gives $b^x \le 10^{E_{\text{tiny}}-1}$, below half of
  the smallest subnormal and, as $E_{\text{tiny}} \le e_{\min}$, tiny before
  and after rounding, so the result is zero or the smallest subnormal by
  direction with `inexact` and `underflow` (IEEE 754-2019 7.5). The comparison
  is exact and the margin is the whole slack between $k$ and $1/\log_{10} b$:
  an argument between the true boundary and the threshold is not decided here
  but by the Ziv loop, which is sound there because the threshold is at most
  $4\,(1 - E_{\text{tiny}})$ with $E_{\text{tiny}} \ge -1999997$, far below
  the exponent range of the binary enclosure. Without the decision a very
  negative argument (for `exp2`, beyond $2^{31}$ binades) has the enclosure
  $[0, \text{tiny}]$ and never certifies. The conformance page records tests
  on both sides of each threshold and at results just inside and outside the
  range, in all eight rounding directions. `power` bounds $y \log_2 x$
  with directed 128-bit arithmetic for the same purpose.

For a positive base the Ziv loop
  evaluates $x^y = \exp(y \ln x)$ in interval arithmetic: one `ln` enclosure,
  one interval product and one `exp` enclosure, instead of the four corners
  times two directions (eight correctly rounded binary powers) of
  `interval`'s `try_pow`. The loop needs an enclosure, not tight
  endpoints, and correct rounding makes the delivered value independent of
  the enclosure's width, so the result, cohort and flags are those of the
  tighter evaluation. The composition loses about
  $\lceil \log_2 |y \ln x| \rceil$ bits of relative accuracy, because the
  relative error of $\exp(t)$ is the absolute error of $t$. The initial
  working precision therefore grows by a bound of that quantity, taken from
  the adjusted exponents of $x$ and $y$ ($|\ln x| \le \ln 10\,(|\operatorname{adjusted}(x)| + 1)$
  and $|y| < 10^{\operatorname{adjusted}(y)+1}$), so the first attempt usually
  decides when this bound is sufficient.


`exp2m1`, `exp10m1`, `log2p1` and `log10p1`, along with the later IEEE 754-2019
9.2 families, share three range and exact-result rules. An exact result is
formed as an exact decimal, rounded once by the context and then moved to the
cohort member nearest the preferred exponent, using the cohort rule of `power`.
A context that cannot hold the value
rounds it with its own flags; a result whose certified bracket of $\log_2$
lies above $\log_2 10\,(e_{\max}+2)$ or below
$\log_2 10\,(E_{\text{tiny}}-2)$ rounds like the representative
$10^{e_{\max}+2}$ or $10^{E_{\text{tiny}}-2}$
using a certified logarithmic range bound; every other result comes from the
Ziv loop above. No result is a
zero or an infinity chosen because the argument is small or large: a tiny
result is the rounding of its certified endpoints, so subnormals, `Underflow`
under the before-rounding rule and the sign of a zero are those of the
context.

The four functions evaluate `expm1(x ln b)` and `log1p(x) / ln b` on the
input interval ($\ln 2$ and $\ln 10$ as certified `interval` intervals).
Both primitives are series in $x$, so the relative width of the enclosure is a
few units of the working precision for every legal operand, down to
$x = 10^{-1\,999\,996}$; no tiny-argument anchor is needed because the slopes
$\ln b$ and $1/\ln b$ are irrational. Before the loop:


$b^x$ is rational only for an integer $x$ ($2^r$ and $10^r$
  are irrational for a non-integer rational $r$), and $\log_b(1+x)$ is
  rational only when $1+x = b^k$. For $0 < |n| \le 4(p+2)$ the value $2^n-1$,
  $10^n-1$, $-(1-2^{-m})$ or $-(1-10^{-m})$ is formed and rounded once; $k$
  is found from $x$ without forming $1+x$ ($x+1$ a power of two, compared
  first on its lowest nine digits; all nines; a coefficient $10^m - 5^m$ or
  $10^m - 1$ with $m$ fraction digits). The preferred exponent is 0
  (IEEE 754-2019 9.2.2), so `exp2m1(4)` is `15` and `log2p1(-0.50)` is `-1`.

For an integer $n > 4(p+2)$, $2^n$ has $D \ge p+3$ digits and
  every rounding boundary of a $D$-digit integer is a multiple of the even
  number $5 \cdot 10^{D-p-1}$; neither $2^n$ (no factor 5) nor the odd
  $2^n - 1$ is one, so both lie in one open rounding cell and `exp2m1(n)` is
  `exp2(n)`. $10^n - 1$ lies above the midpoint $10^n - 5 \cdot 10^{n-p-1}$
  and below $10^n$, where an enclosure can never separate it from the
  representable $10^n$; the representative $10^n - 10^{n-p-2}$ has the same
  rounding and is formed instead of a number of $n$ digits. Towards $-1$,
  for $x \le -(p+2)$ (base 10) or $x \le -(4p+8)$ (base 2) the value is
  $-1 + \delta$ with $0 < \delta \le 10^{-(p+2)}$ and rounds like
  $-(1 - 10^{-(p+2)})$, as for `expm1`.

$x \ge \lceil 3.322\,(e_{\max}+2) \rceil$ (base 2) or
  $x \ge e_{\max}+2$ (base 10) gives the overflow result of the context.

For $|x| \le 10^{-5}$ all four satisfy
  $0 < |f(x)| < 3|x|$ with the sign of $x$, so $|x| < 10^{E_{\text{tiny}}-3}$
  puts $f(x)$ below $10^{E_{\text{tiny}}-2}$, where it rounds like the
  representative $\pm 10^{E_{\text{tiny}}-2}$ that the enclosure would use
  for its endpoints. The result is that rounding, decided without converting
  $x$ to binary (the conversion of $10^{-1\,999\,997}$ alone costs about a
  second).

For $|x| < 10^{-(p+11)}$, write
  $x = m\,10^{q}$; then $f(x) = c\,x\,(1 + d)$ with $c = \ln b$ or $1/\ln b$
  and $|d| \le 2.31|x|$, so $f(x)/10^{q}$ lies in
  $c\,m\,[1 - 2^{k}, 1 + 2^{k}]$ for $2^{k} \ge 4|x|$. The endpoints of that
  enclosure have a few dozen digits, where the binary endpoints of $f(x)$
  itself would expand to about $0.7|q|$ digits; scaled back by $10^{q}$ they
  are rounded with the context and accepted under the same agreement test as
  the loop, which decides the rare value too close to a rounding boundary.
  The certified $\ln 2$ and $\ln 10$ intervals are kept per working
  precision. Both only change the cost: on 10,000 random rows of each function
  the executed instructions fell from 57 to 12 (`exp2m1`), 60 to 14
  (`exp10m1`), 102 to 17 (`log2p1`) and 102 to 18 (`log10p1`) billion, the
  level of `exp` (13) and `log1p` (18).

$x = -1$ is $-\infty$ with `division_by_zero` and
  $x < -1$ is invalid for `log2p1` and `log10p1` (Table 9.1). Near $-1$ an
  operand of $D$ digits keeps $1 + x \ge 10^{-D}$, which $w_0$ resolves,
  as for `log1p`.


`rSqrt`, `compound` and `powr` take their exact results from the exact-case
path, and none of them expands a binary endpoint near an extreme power of ten.


`rsqrt(x)` terminates exactly when
$x = 2^{2i}5^{2j}$: with
  $c$ the coefficient stripped of trailing zeros and $e$ its exponent, $c$ is
  $2^a$ or $5^b$ with $a$ (or $b$) and $e$ even, and the value is
  $5^{a/2}10^{-(e+a)/2}$ or $2^{b/2}10^{-(e+b)/2}$. It is formed when it has
  at most $p + 1$ digits and given the preferred exponent
  $-\lfloor Q(x)/2 \rfloor$ (IEEE 754-2019 9.2.2); a longer one ends in a 5 or a non-zero
  even digit beyond the $(p+1)$-th place, so it is neither representable nor a
  midpoint, and the enclosure decides it. Every other $x$ is written
  $x = s\,10^{2k}$ with $s \in [1, 100)$: the Ziv loop encloses
  $1/\sqrt{s}$, whose endpoints are moderate, and multiplies them by
  $10^{-k}$ (an exponent shift) before the context rounds them, under the same
  agreement test. An operand $10^{-1\,999\,997}$ costs what $1$ costs.

`compound(x,n)` uses the special values of IEEE 754-2019 9.2.1 (with $x < -1$
  invalid also for $n = 0$, Table 9.1). For a tiny $x$,
  $(1+x)^n - 1$ has the sign of $nx$ and
  $|(1+x)^n - 1| \le |nx|\,e^{|nx|} < 10^{\operatorname{adj}(x) + 12}$ for
  $|n| \le 2^{31}$, so a bound decides a one-sided
  neighbour of 1 and $1 + x$ (up to two million digits) is never formed.
  Otherwise $1 + x = c\,10^{e}$ is formed exactly ($c$ without trailing
  zeros, $d$ digits, exponent $\min(0, Q(x))$ before stripping). For $n > 0$,
  $c^n$ has more than $\max((d-1)n, 0.301n)$ digits and no trailing zero, so
  beyond $p + 1$ digits it is neither representable nor a midpoint; shorter
  powers are formed and rounded once with the preferred exponent
  $\lfloor n \min(0, Q(x)) \rfloor$. For $n < 0$, $c^{n}$ terminates only
  for $c = 2^a$ or $5^b$ (the values $5^{a|n|}10^{-(a+e)|n|}$ and
  $2^{b|n|}10^{-(b+e)|n|}$), formed while they have at most $p + 2$ digits.
  Every other case is the Ziv loop on $\exp(n \operatorname{log1p}(x))$
  ($\operatorname{log1p}$ of $x$ itself, so $1 + x$ is never rounded), after
  `decimal_range_from_log2_bracket` on $n \operatorname{log1p}(x)/\ln 2$
  whenever $|n| \max(\operatorname{adj}(x) + 2, -Q(x), 1)$ does not already
  keep the result inside the range. `Int32`'s minimum $-2^{31}$ is taken as an
  `Int64`. `pown(1 + x, n)` is not used: when this function was written, its
  exponents beyond the machine count gave wrong values and some negative ones
  a spurious `Clamped` for a base near 1 (issues [#348](https://github.com/Luna-Flow/floating/issues/348)
  and [#350](https://github.com/Luna-Flow/floating/issues/350), since fixed).
  Instead, the Ziv loop evaluates $\exp(n\operatorname{log1p}(x))$ without
  forming $1 + x$.

`powr(x,y)` follows the invalid pairs listed in IEEE 754-2019 9.2.1: $(\pm 0, \pm 0)$,
  $(+\infty, \pm 0)$, $(1, \pm\infty)$ and $x < 0$, and a NaN result for a NaN
  operand even when $y = \pm 0$. Two cases are not stated and are read as
  follows: $x < 0$ with $y$ a quiet NaN is invalid (the NaN rule is
  stated "for $x \ge 0$"), and $+\infty^{y}$ for $y \ne 0$ and $x^{\pm\infty}$
  for $x \notin \{0, 1\}$ follow $e^{y \ln x}$ by continuity. Every remaining
  pair has $x \ge 0$, where $x^y$ is the same function as `pow`, and the
  preferred exponents agree ($\lfloor y Q(x) \rfloor$), so the result is
  `power` on $|x|$ (a $-0$ is passed as $+0$, where `pow` would apply its
  odd-integer sign rule).


`asinPi`, `acosPi`, `atanPi` and `atan2Pi` evaluate
$\operatorname{asin}(x)/\pi$, $\operatorname{acos}(x)/\pi$,
$\operatorname{atan}(x)/\pi$ and $\operatorname{atan2}(y, x)/\pi$ in the
existing Ziv driver, with $\pi$ enclosed as $[\operatorname{RD}(\pi), \operatorname{RU}(\pi)]$
taken from the cached binary-splitting constant of `binary` (twice the
correctly rounded $\pi/2$ of `atan(+inf)`, the same interval as
$4\operatorname{atan}(1)$ bit for bit) and the angle
enclosure divided by it (error: the angle, $\pi$ and the division, about
4 ulp relative).


By Niven's theorem a rational $x$ has a rational
  $\operatorname{asin}(x)/\pi$ or $\operatorname{acos}(x)/\pi$ only at
  $0, \pm\tfrac12, \pm 1$ and a rational $\operatorname{atan}(x)/\pi$ only at
  $0, \pm 1$, so the dyadic exact results are those of IEEE 754-2019 9.2.1 and
  $\operatorname{atanPi}(\pm 1) = \pm\tfrac14$,
  $\operatorname{atan2Pi}(\pm a, \pm a) = \pm\tfrac14, \pm\tfrac34$. They are
  built by the exact-case path at the preferred exponent 0 (IEEE 754-2019 9.2.2).
  $\pm\tfrac16$, $\tfrac13$ and $\tfrac23$ do not terminate, so they sit
  strictly inside a rounding cell and the loop decides them. No Pi function
  is anchored at a tiny argument: $x/\pi$ is irrational and nowhere near a
  representable value.

These are the only inexact results that approach the representable anchors
$\pm\tfrac12$ and $\pm 1$, and the distance does not
  depend on the digits of the operand, so a $w_0$ that grows with $D$ cannot cover it.
  A bound decides each case on one side of the anchor:
  $\operatorname{atanPi}(x) = \pm(\tfrac12 - \delta)$ with
  $0 < \delta < 1/(\pi|x|) < 10^{-\operatorname{adj}(x)}$ for a large $|x|$;
  $\operatorname{acosPi}(x) = \tfrac12 - \operatorname{asin}(x)/\pi$ with
  distance at most $|x|/2 < 10^{\operatorname{adj}(x)+1}$ for a tiny $|x|$ (the
  easy one to miss: $\operatorname{acos}$ of a tiny $x$ is near the irrational
  $\pi/2$, but $\operatorname{acosPi}$ is near the representable $\tfrac12$,
  below it for $x > 0$ and above for $x < 0$); $\operatorname{atan2Pi}(y, x)$
  with $D = \operatorname{adj}(y) - \operatorname{adj}(x)$ is
  $\pm(\tfrac12 \mp \delta)$ with $\delta < 10^{1-D}$ for a large ratio
  (below $\tfrac12$ in magnitude for $x > 0$, above for $x < 0$), and
  $\pm(1 - \delta)$ with $\delta < 10^{D+1}$ for $x < 0$ and a small ratio.
  The guard (error exponent below the anchor's adjusted exponent minus $p + 3$)
  picks the threshold; between it and
  the moderate range the enclosure resolves the gap at the working precision.
  The tests compare every anchored result with the plain loop in all eight
  rounding modes, on both sides.

For $|x| \le 10^{-4}$, $\operatorname{asin}(x)/x \in
  [1, 1 + x^2]$ and $\operatorname{atan}(x)/x \in [1 - x^2, 1]$, and the same
  holds for $\operatorname{atan2Pi}(y, x)$ with $x > 0$ and the ratio $y/x$.
  Once $x^2 < 2^{-(8\max(D,p)+400)}$ the loop encloses the moderate value
  $(s/\pi)(1 \pm 2^{-k})$ with $s = x\,10^{-\operatorname{adj}(x)}$ (or the
  quotient of the two scaled mantissas) and shifts the endpoints by
  $10^{\operatorname{adj}(x)}$ before the context rounds them, as for `rsqrt`
  (`decimal_certified_scaled_result`): an operand $10^{-1\,999\,996}$ costs
  what $10^{-300}$ costs, where the exact decimal endpoints of a binary
  number near $2^{-6.6\cdot 10^6}$ have about two million digits (an
  unscaled `asinpi(7E-9999)` took more than a minute in a debug build before
  this path existed). For $\operatorname{atan2Pi}(y, x)$ with $x > 0$ the
  derivation is: $\operatorname{atan2Pi}(y, x) = \operatorname{sign}(y)
  \operatorname{atan}(r)/\pi$ with $r = |y/x| = (s_y/s_x)\,10^{D}$, where
  $s_y, s_x \in [1, 10)$ are the operands scaled by their adjusted exponents
  and $D = \operatorname{adj}(y) - \operatorname{adj}(x)$, so
  $r < 10^{D+1}$; for $r \le 1$, $\operatorname{atan}(r)/r \in [1 - r^2, 1]$,
  hence $\operatorname{atan}(r)/\pi = (s_y/(s_x \pi))\,10^{D}(1 - e)$ with
  $0 \le e \le r^2 < 10^{-t}$, $t = -(2D + 2)$, and the loop encloses the
  moderate factor $(s_y/(s_x\pi))(1 - 2^{-k})$, $k \le 3.32\,t$, and shifts
  it by $D$. The path is taken when $3t \ge 8\max(D_{\text{digits}}, p) + 400$,
  where it is decidable; the derivation itself needs only $t > 0$.
  The operands of every other case are first multiplied by
  $10^{-\operatorname{adj}(x)}$ (the ratio, hence the angle, is unchanged),
  so operands with exponents of millions of digits and a moderate ratio cost
  what moderate operands cost. `library/src/decimal/atan2pi_scaled_wbtest.mbt` and the
  generated rows of `tools/generate_decimal_atan2pi_scaled_rows.py` (Python
  `decimal` at 450 digits, a cross-check only) cover ratios on both sides of
  the condition, both signs of $y$ and of $x$ (for $x < 0$ the result is
  $\pm(1 - \operatorname{atan}(r)/\pi)$, next to $\pm 1$, and takes the other
  anchored path), the four formats and all eight rounding directions;
  replacing $1 - 2^{-k}$ by $1 + 2^{-k}$ or the condition by $t > 0$ makes
  rows fail (checked by mutation).

#### Operands of extreme exponent and the cost of a first attempt

The following paths keep the cost of a call independent of the size of its
operands' exponents while preserving correctly rounded results.

- *Conversion to binary.* For $x = c\,10^{-s}$ the quotient $\lfloor c\,2^{u} /
  10^{s} \rfloor$ is formed once, with $u = p + 3 + \lceil s \log_2 10 \rceil$
  (so $10^s < 2^{u-p-3}$ and the quotient keeps at least $p + 3$ bits: two bits
  below the target position and a sticky bit), made odd when the remainder is
  not zero; the remainder test is a multiplication, not a second division, and
  the lower and upper bound of a ball come from the same quotient. For
  $|{\rm exponent}_{10}| \ge 4096$ the exact $5^s$ (rebuilt on every call above
  the power cache) is replaced by a lower and an upper bound $m\,2^{k}$ with
  $m$ of $p + \text{bits}(c) + 80$ bits, made by binary powering with a
  directed trim after every product; the two bounds are rounded in the
  requested mode and the result is kept only if they agree (monotonicity of
  rounding), otherwise the exact conversion decides, so the result is the exact
  conversion bit for bit. For a negative exponent the quotient of the bounds is
  used only when $2 s > 4\,\text{bits}(c)$, where $5^s > c$ guarantees that the
  division is inexact (the sticky bit is set).
- *First working precision.* $\max(64, \lfloor 3.321929\,\max(D, p) \rfloor +
  31)$ bits instead of $\max(128, 4 \max(D, p) + 64)$: the schedule grows by a
  factor of 1.5 when an enclosure does not decide, so a low start costs an
  attempt and never a result. On 16,536 rows (exp, exp2, exp10, expm1, the
  inverse functions of $\pi$ and atan2Pi, five formats) the number of operand
  conversions was 14,489 before and 14,490 after.
- *Tiny arguments of exp, exp2, exp10, expm1 and log1p.* For $|x| < 10^{t}$,
  $t \le -1$: $|b^x - 1| \le |x|\ln b\,e^{|x| \ln b} < 10^{t+1}$ for
  $b \in \{e, 2, 10\}$ ($\ln b < 2.31$, $e^{0.231} < 1.3$) with the sign of $x$, so
  the result is $1$ plus or minus less than $10^{t+1}$, one-sided next to the
  representable 1 and decided by a one-sided bound once
  $t + 1 < -(p + 3)$; and $\operatorname{expm1}(x) - x = x^2/2 + \dots > 0$,
  $x - \operatorname{log1p}(x) = x^2/2 - \dots > 0$, both below $x^2$ for
  $0 < |x| < 1/2$, so expm1 lies above $x$ and log1p below it, within
  $10^{2t}$. Rows on both sides of the thresholds, both signs, three formats and
  all eight directions have independently computed expected values; flipping a
  side makes rows fail.
- *Exact tests before the loop.* An exact $n$-th root of a decimal needs
  $\text{exponent} \bmod n = 0$ once trailing zeros are removed ($c\,10^{\text{shift}}$
  with $0 < \text{shift} < n$ and $\min(v_2(c), v_5(c)) = 0$ has $v_2$ or $v_5$
  equal to the shift, not a multiple of $n$), and the root comes from the kernel
  (square roots first for even degrees, Newton from the root of the leading
  digits); `atan2` forms the exact ratio only when $2D < -(p + 4)$ with
  $D = \operatorname{adj}(y) - \operatorname{adj}(x)$, the necessary condition of the
  tiny-argument decision; `compound` does not form $1 + x$ when $x$ is an
  integer multiple of 10 with $\operatorname{adj}(x) \ge p + 2$ (the sum ends in 1:
  no power of 2, 5 or 10) or for $n > 0$ when $\operatorname{adj}(x) < -(p + 2)$
  (more than $p + 2$ digits); `sqrt` reuses the remainder of the integer root.
- *Negative integer power.* For $n = |{\rm count}|$, $|b|^n \in [10^{n\,lb},
  10^{n\,ub})$ with $lb = \operatorname{adj}(b)$, $ub = lb + 1$, hence
  $1/|b|^n \in (10^{-n\,ub}, 10^{-n\,lb}]$: it overflows when $-n\,ub > e_{\max}$ and
  lies below half of the smallest subnormal when $-n\,lb \le E_{\text{tiny}} - 2$;
  the exponent product of the exact path is formed in 64 bits.

#### Outward-rounded endpoints

The Ziv driver turns the two binary endpoints $L \le U$ of an enclosure into
decimals and rounds both to the context. Expanding $c \cdot 2^{-s}$ exactly
costs $c \cdot 5^{s}$, about $0.7 s$ digits, which is quadratic in the decimal
exponent of the argument under a wide-range context (`1E-999990` took more than
80 s in `expm1`). For a non-degenerate enclosure the driver instead rounds $L$
down and $U$ up to $D = \max(p + 12,\ 0.3\,b + 4)$ digits, $b$ being the bit
length of the endpoint coefficients (so a refined enclosure is never widened
beyond about one binary ulp). The powers $5^{s}$ and $2^{s}$ are computed by
binary powering with a directed trim to $D + 4$ digits after every product:
$O(\log s)$ products of $D$-digit numbers, independent of $s$.

*Soundness.* Every trim moves towards the chosen side (down for the lower
magnitude bound, up for the upper one, with signs swapped for negative
endpoints), and products of positive bounds are bounds, so by induction the
computed power brackets the exact power, and $L' \le L \le U \le U'$. Rounding
to the context is monotone, so $\mathrm{rnd}(L') = \mathrm{rnd}(U')$ implies
$\mathrm{rnd}(x)$ is that value for every $x \in [L, U]$, and the flags are
compared as before. The guard digits only affect tightness, not soundness.
A degenerate enclosure ($L = U$, binary-exact) keeps the exact expansion, and
infinite, zero and out-of-range endpoints are converted as before. A certified
result is unchanged; only an enclosure that straddles a rounding boundary at a
distance below $10^{-D}$ relative is refused one step earlier, and the next
refinement widens $D$ with the binary precision.

The elementary functions and the `pow` family refuse contexts with $p$ or $|e|$ above 999,999 for an ordinary operand (the precision part is the field `elementary_precision_limit` of the context, `Some(999_999)` by default and `None` for no limit, an escape entry with no guarantee of time or memory); the special operands and the exact points of IEEE 754-2019 9.2.1 are answered first, in every context, and the limit is tested before the first step that computes
(`not_computed`, and `Err` of the certification-failure kind in the `try_` forms; the decNumber limit, see the `decimal_gda` design page),
which bounds the size of the exact endpoint conversions.

[^ziv]: A. Ziv, "Fast evaluation of elementary mathematical functions with
correctly rounded last bit", *ACM TOMS* 17(3), 1991; J.-M. Muller et al.,
*Handbook of Floating-Point Arithmetic*, 2nd ed., Birkhäuser 2018, ch. 12;
J. van der Hoeven, "Ball arithmetic", 2009, for the enclosure model.

### Coefficient kernels

**Problem.** Rounding at decimal positions needs fast division by powers of
ten and fast digit counts; large precisions need sub-quadratic
multiplication and division.

**Choice.** `DecCoeff`, defined in the internal package
`internal/decimal_kernel` that `decimal` shares with `decimal_gda` (neither
package exposes it), is either a `Small(UInt64)` below $10^{18}$ or a
little-endian array of base-$10^{9}$ limbs with no leading zero limb and a
cached digit count. The package holds only status-free integer arithmetic;
the finalizer, flags and contexts stay in each decimal package (see
[the shared kernel](decimal_gda.md#a-gda-package-independent-of-decimal)). Base $10^9$ is the largest power of ten below
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

The NTT splits the coefficients into base-$10^5$ digits and convolves them
modulo the primes $p_1 = 998\,244\,353 = 119\cdot 2^{23} + 1$ and $p_2 =
754\,974\,721 = 45 \cdot 2^{24} + 1$, both of which have $2^{23}$-th roots of
unity, so transforms up to length $2^{23}$ exist. A convolution coefficient
is a sum of at most $m = \min(n_a, n_b)$ products of digits below $10^{5}$,
hence below $m \cdot 99999^{2}$; it is recovered exactly from its residues by
the Chinese remainder theorem,

$$
z = r_1 + p_1 \bigl((r_2 - r_1)\, p_1^{-1} \bmod p_2\bigr),
$$

as long as $m \cdot 99999^{2} < p_1 p_2 = 753\,649\,251\,896\,000\,513$, i.e.
$m < 7.5 \cdot 10^{7}$. The transform limit $2^{23}$ allows at most
$m = 2^{22}$, and $2^{22} \cdot 99999^{2} = 41\,942\,201\,143\,394\,304 <
p_1 p_2$, so the bound always holds below the transform limit (the kernel
checks it before every transform). Base $10^{9}$
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

The integer square root with remainder $(s, \rho)$, $N = s^2 + \rho$ and
$0 \le \rho \le 2s$, is Zimmermann's `SqrtRem`[^zimmermann] on limbs. With $n$
limbs, $\ell = \lfloor (n-1)/4 \rfloor$ limbs per block and $X = 10^{9\ell}$,
write $N = H X^2 + a_1 X + a_0$ with $a_1, a_0 < X$; the root $s'$ and
remainder $\rho'$ of $H$ come from the recursion, $(q, u) =
\operatorname{divrem}(\rho' X + a_1,\, 2s')$, $s = s' X + q$ and
$\rho = u X + a_0 - q^2$, and if $\rho < 0$ then $\rho \leftarrow \rho + 2s - 1$ and
$s \leftarrow s - 1$. The report proves that this is correct, with this single
correction, when the top part $H = a_3 X + a_2$ has $a_3 \ge X/4$. With
$\ell \le (n-1)/4$ the block $a_3$ has at least $\ell + 1$ limbs, so $a_3 \ge X$
for every radicand with a non-zero top limb and no scaling is needed (the binary
kernel scales its radicand by an even power of two because its blocks are
halves of an even limb count). The quotient is at most $X$ (because
$\rho' \le 2s'$ and $a_1 < X \le 2s'$), and a quotient of exactly $X$ is capped to
$X - 1$ with $2s'$ added to $u$. The division by $2s'$ is the division of
$\lfloor D/2 \rfloor$ by $s'$ (the remainder is $2r + (D \bmod 2)$), so $2s'$ is
never formed and cannot carry out of the limbs of $s'$; the divisor is
normalized for Algorithm D. Up to four limbs the base case takes a root of at
most 18 digits from a double estimate corrected with exact limb arithmetic, and
the word root covers one and two limbs. The Karatsuba root is faster than the
Newton iteration from three limbs on, so there is no crossover to a Newton path:
at 3, 8, 32, 128 and 512 limbs it takes 2,096, 6,465, 15,369, 66,536 and 594,956
instructions against 7,967, 24,168, 74,345, 341,256 and 3,627,494. The square of
the quotient block is a schoolbook product up to 16 limbs and the kernel's
square above. For rounding, the scalar entry returns the root and how the
remainder compares with it (zero; at most $s$; above $s$), since
$N > (s + \tfrac12)^2$ iff $\rho > s$, without building the remainder. The
white-box tests compare it with the Newton reference for every length from 3 to
70 limbs, squares and their neighbours, powers of ten, every recursion depth
from 0 to 6, a class that caps the quotient and a class built to take the
correction step.

[^zimmermann]: P. Zimmermann, "Karatsuba Square Root", INRIA research report
RR-3805, 1999 (the algorithm and its proof, with the condition $a_3 \ge X/4$);
Brent and Zimmermann, *Modern Computer Arithmetic*, Algorithm 1.12 (§1.5.1).

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
The native Newton path is implemented and tested but disabled because native
measurements do not show a crossover.

## Correctness and invariants

- **Representation.** A finite `Decimal` has $c \ge 0$; `DecCoeff` limbs are
  canonical (no leading zero limb, exact digit count). A zero's sign is kept
  in the sign bit; `coefficient()` never carries a sign.
- **Single rounding.** Every context result of `+`, `-`, `×`, `/`, `fma`,
  `sqrt`, `scaleb`, quantize and the conversions is the exact result rounded
  once, in the normal and in the subnormal range; integer powers are
  correctly rounded; certified elementary results are
  correctly rounded whenever they are returned, and a failure is reported,
  never approximated. The exceptions are listed under
  [known deviations](#known-deviations).
- **Error bound.** For normal results of those operations,
  $\operatorname{fl}(x) = x(1+\delta)$ with $|\delta| \le \tfrac12 10^{1-p}$ in
  the half modes and $|\delta| < 10^{1-p}$ in the directed modes.
- **Exactness is visible.** `inexact` is raised if and only if the returned
  value differs from the exact result; `rounded` whenever digits were dropped.
- **Cohort preservation.** An exact result that fits is returned at the
  preferred exponent; `quantize_ctx` either returns exponent $q_y$ or fails.
- **Flags.** `combine` is associative, commutative and idempotent with
  identity `new()`.
- **Ordering.** `compare` is a total preorder (NaNs equal to each other and
  above every number, $-0 = +0$); `total_order_compare` is a total order on
  representations and refines `compare` on non-NaN values.
- **Encodings.** Decoding then encoding canonical bits is the identity;
  encoding then decoding a value that fits the format is the identity,
  including cohort, sign of zero and NaN payload (DPD and BID).
- **Complexity.** Comparison, addition, shifts and one-limb division are
  $O(n)$ in limbs; multiplication and division follow the dispatch table.

### Known deviations

No behaviour of the current branch contradicts the goals above. A deviation
found later is listed here, reproduced in the
[API reference](../api/decimal.md) next to the operation, and tracked in a
GitHub issue together with the pull request that proposes a fix.

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
  IEEE semantics are available through `compare_checked`, `compare_quiet`,
  `compare_signaling` and `total_order_compare`.
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
- guarantee that elementary-function certification succeeds: after the
  refinement limit of the context (twelve by default, `with_refinement_limit`;
  the last steps work with very wide numbers and can take a long time) it reports `CertificationFailure` (`try_*_ctx`) or NaN
  with `invalid_operation` (`*_ctx`);
- evaluate elementary functions of an ordinary operand in contexts with
  precision or exponents above 999,999 (special operands and the exact points
  of IEEE 754-2019 9.2.1 are answered first, in every context);
- preserve NaN payloads through binary conversions;
- expose its coefficient representation, kernel selection or thresholds;
- claim conformance beyond the finite evidence on the
  [conformance page](../conformance/decimal.md).
