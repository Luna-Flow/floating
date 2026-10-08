# internal design

## Design goal

The binary, decimal and interval cores all reduce their hard steps to exact
integer arithmetic: aligning exponents, removing trailing zeros, dividing with
a rounding mode, enclosing a ratio between two dyadics. `internal` states
these steps as small `BigInt` functions with proved invariants, so that the
`consistency` tests can check each one against an oracle and the cores can
share what they have in common. It is internal so the cores can change the
helpers together without a public compatibility promise.

On the current branch the sharing is partial. The decimal cores use the
string splitter, `round_positive_div`, the power caches and `digits10`; every
core uses the refinement budget and `certified_failure`; `semantic` uses
`ExactRat`. The hot paths of `bin_float` and `decimal` round with their own
limb kernels (`BinCoeff` and `DecCoeff`), which implement the same rounding
table as `round_positive_div` but are not built on it, and several helpers
(`round_shift`, the factor removers, the `CertifiedDyadic` family, the
`result_lift2` combinators) are exercised only by tests. The table on the
[API page](../api/internal.md#purpose) lists the users of each helper.

## Mathematical background

### Integer division with remainder

For $n \ge 0$ and $d > 0$ there are unique integers $q, r$ with
$n = qd + r$ and $0 \le r < d$ (Euclidean division). Then
$q = \lfloor n/d \rfloor$, and $n/d$ is an integer exactly when $r = 0$. The
fractional part is $r/d \in [0, 1)$, and

$$
\frac{r}{d} \lesseqgtr \frac12 \iff 2r \lesseqgtr d .
$$

### Rounding to an integer

For a real $x$ and a rounding direction, $\circ(x)$ is the integer chosen
among $\lfloor x \rfloor$ and $\lceil x \rceil$: toward zero, toward
$+\infty$, toward $-\infty$, away from zero, or to the nearest with ties to the
even candidate.[^ieee]

[^ieee]: IEEE 754-2019, clause 4.3, defines the rounding-direction attributes;
    the integer case is the same definition with $\mathbb{Z}$ as the set of
    representable numbers.

### Dyadic enclosures

A dyadic number is $n \cdot 2^{-s}$ with $n \in \mathbb{Z}$, $s \ge 0$. For a
real $x$ and a scale $s$, the dyadics of scale $s$ around $x$ are
$\lfloor x 2^{s} \rfloor 2^{-s} \le x \le \lceil x 2^{s} \rceil 2^{-s}$, an
interval of width at most $2^{-s}$.

## Design decisions

### Magnitude and sign passed separately

`round_positive_div(n, d, negative, mode)` takes $n \ge 0$ and the sign of the
true quotient as a flag. Sign-magnitude is how the cores store their
coefficients, and directed rounding of a magnitude depends on the sign:
rounding $-2.5$ toward $-\infty$ *increases* the magnitude. Keeping the sign as
a separate argument makes the rule a single table and avoids negative
remainders, whose convention differs between languages.

### Powers of ten and five from a shared cache

Decimal scaling uses $10^{k}$ and the binary-decimal conversions use $5^{k}$
(because $10^{k} = 5^{k} 2^{k}$ and the factor $2^{k}$ is a shift). The
caches start with the 19 powers $k \le 18$ ($10^{18}$ is the largest power of
ten below $2^{63}$) and are extended on demand up to $k = 4096$; larger powers are computed directly on each call,
so that an extreme exponent cannot make the cache grow without bound.

### Digit count without strings

`digits10` starts from the estimate
$d_0 = \lfloor b \log_{10} 2 \rfloor + 1$, where $b$ is the bit length of
$|x|$, and corrects it by comparison with powers of ten. Since
$2^{b-1} \le |x| < 2^{b}$, the true digit count $d$ satisfies

$$
\lfloor (b-1) \log_{10} 2 \rfloor + 1 \;\le\; d \;\le\; \lfloor b \log_{10} 2 \rfloor + 1 = d_0 ,
$$

and because $\log_{10} 2 < 1$ the two bounds differ by at most one. So at most
one downward correction is ever needed (the upward loop guards against
floating-point error in the estimate), and the cost is a constant number of
`BigInt` comparisons plus one power of ten.

### Wide exponent parsing

A decimal context may set $e_{\max}$ anywhere in `Int`, and the context-free
`parse` applies no exponent range at all, so no cap inside `Int` is safe: a
literal exponent that is clamped to a smaller value can still be in range and
silently changes the number. `split_decimal_string_wide` therefore returns the
exponent $q$ as an `Int64`. The written exponent is read exactly up to
$10^{18}$ and saturates there; with at most $2^{31}$ fraction digits,
$|q| < 10^{18} + 2^{31}$, so the subtraction never overflows `Int64`. A
saturated $q$ lies far outside `Int` and so outside every exponent a value or
context can hold, which means a caller that compares $q$ (plus the digit
count) with `Int` and its context sees the same overflow or underflow as for
the exact exponent. `split_decimal_string` keeps its `Int` signature and
returns `None` when $q$ does not fit `Int`, rather than a different exponent.

### Canonical rationals

`ExactRat::new` divides by $\gcd(n, d)$ and makes the denominator positive.
With a canonical form, derived structural equality *is* equality of rational
numbers, which is what `semantic` needs to compare values across binary and
decimal representations.

### Ziv-style refinement budget

The certified elementary functions evaluate an enclosure at a working
precision $p_k$ and accept the result when both ends round to the same target
number (Ziv's strategy[^ziv]); otherwise they retry at a higher precision.
The budget fixes the schedule

$$
p_{k+1} = p_k + \max\bigl(32, \lfloor p_k / 2 \rfloor\bigr), \qquad k < L ,
$$

with $L = 12$ refinements by default. For $p_k \ge 64$ this is
$p_k + \lfloor p_k/2 \rfloor = \lfloor 3 p_k / 2 \rfloor$, geometric growth
with ratio $3/2$ up to the floor, so $p_L \approx p_0 (3/2)^{L}$ (about
$130\,p_0$ for $L = 12$ and $p_0 \ge 64$). For $p_k < 64$ the step is $32$
and $p_{k+1}/p_k = 1 + 32/p_k > 3/2$, so the ratio is at least $3/2$ (up to
the floor) at every step. If one attempt at
precision $p$ costs $C(p) \ge c\,p$ (at least linear), the total cost of
all attempts is dominated by the last one:

$$
\sum_{k=0}^{m} C(p_k) \le C(p_m) \sum_{j \ge 0} (2/3)^{j}
= 3\, C(p_m) \quad \text{when } C(p_k) \le (2/3)^{m-k} C(p_m),
$$

which holds, up to the floors in the schedule, for $C(p) = c\,p^{\alpha}$
with $\alpha \ge 1$ in the geometric phase.
Exhaustion is reported with `certified_failure`, which records the target and
final working precision, instead of returning a value that is not certified.

[^ziv]: A. Ziv, "Fast evaluation of elementary mathematical functions with
    correctly rounded last bit", *ACM TOMS* 17(3), 1991.

## Correctness and invariants

**Rounding table.** Let $n = qd + r$ with $0 \le r < d$ and
$x = (-1)^{\sigma} n/d$. Then $|\circ(x)| \in \{q, q+1\}$, with $q + 1$ only if
$r > 0$, and `round_positive_div` returns $|\circ(x)|$:

$$
\begin{aligned}
\text{toward zero:} &\quad |\circ(x)| = q, \\
\text{toward } +\infty: &\quad |\circ(x)| = q + [r > 0 \wedge \sigma = 0], \\
\text{toward } -\infty: &\quad |\circ(x)| = q + [r > 0 \wedge \sigma = 1], \\
\text{away from zero:} &\quad |\circ(x)| = q + [r > 0], \\
\text{nearest even:} &\quad |\circ(x)| = q + [2r > d \vee (2r = d \wedge q \text{ odd})] .
\end{aligned}
$$

*Proof.* $|x| = q + r/d$ lies in $[q, q+1)$. Toward zero takes the smaller
magnitude. Toward $+\infty$ takes the larger magnitude for a positive
non-integer and the smaller for a negative one; toward $-\infty$ is the
mirror image. Away from zero takes the larger magnitude for any non-integer.
For nearest, the distance to $q$ is $r/d$ and to $q+1$ is $1 - r/d$, so $q + 1$
is nearer iff $2r > d$, and $2r = d$ is the tie, broken toward the even one of
$q, q+1$, which is $q + 1$ iff $q$ is odd. $\square$

`round_shift(m, s, …)` is the case $d = 2^{s}$ with $q = m \gg s$ and
$r = m - (q \ll s)$, so the same table applies for $m \ge 0$. For $m < 0$ the
arithmetic shift gives $q = \lfloor m/2^{s} \rfloor < 0$ and $0 \le r < 2^{s}$,
and the "magnitude" table is then applied to a negative $q$; the result is
not $\pm|\circ(x)|$ (for example $m = -5$, $s = 1$, `TowardZero` gives $-3$).
The function does not check the sign, so callers must pass magnitudes. The `consistency` tests check
both functions against these formulas on ties and directed cases.

**Factor removal.** `remove_factor2(sig, e)` returns $(sig / 2^{t}, e + t)$ with
$t = \operatorname{ctz}(|sig|)$, so
$(sig / 2^{t}) \cdot 2^{e+t} = sig \cdot 2^{e}$ and the new significand is
odd. `remove_factor10` and `trim_trailing_decimal_zeros` preserve
$c \cdot 10^{e}$ in the same way, one factor of 10 per step; the latter stops
after `max_drop` steps.

**Enclosure.** `certified_dyadic_fraction(n, d, s)` returns
$\ell = \lfloor n 2^{s} / d \rfloor 2^{-s}$ and
$u = \lceil n 2^{s} / d \rceil 2^{-s}$; from
$\lfloor y \rfloor \le y \le \lceil y \rceil$ with $y = n 2^{s}/d$ we get
$\ell \le n/d \le u$ and $u - \ell \le 2^{-s}$, with equality $\ell = u$ iff
$y \in \mathbb{Z}$. The floor of a negative ratio is computed as
$-\lceil |n| / d \rceil$, so the enclosure is correct for both signs.
`certified_dyadic_div` rewrites
$a / b = (n_a 2^{s_b}) / (n_b 2^{s_a})$ with the sign moved to the numerator,
so it inherits the same bound. `round_down` and `round_up` are the same floor
and ceiling at a smaller scale, so $\text{round\_down}(x, s) \le x \le
\text{round\_up}(x, s)$.

**Budget.** The precision sequence is strictly increasing (each step adds at
least 32 bits) and at most `limit` refinements are made, so every refinement
loop that checks `available()` terminates.

**Abort contract.** `pow2`, `pow5`, `pow10` with a negative exponent,
`round_positive_div` with $n < 0$ or $d \le 0$, `ExactRat::new` with $d = 0$,
`exact_divide_by_power_of_ten` with a negative shift and a non-zero
coefficient, and dyadic constructors and roundings with a negative scale
abort: these are programmer errors inside the cores, never reachable from user
input. `round_shift` with a negative magnitude does not abort; it returns the
value described above.

## Alternatives rejected

- **Rounding via floating point.** Converting to `Double` to round a ratio
  loses exactness beyond 53 bits; all helpers stay in `BigInt`.
- **Signed division with remainder.** Truncating and flooring division
  differ for negative operands; sign-magnitude avoids the ambiguity.
- **A normalized `CertifiedDyadic`.** Normalizing after every operation costs
  a trailing-zero scan; enclosures are compared with `compare`, which does not
  need canonical forms.
- **An unbounded power cache.** Pathological exponents would retain huge
  `BigInt` values for the life of the process.

## Boundaries

- No floating-point formats, contexts or flags: the cores build them on these
  helpers.
- No decimal string formatting and no special values (`inf`, `nan`) in
  `split_decimal_string`.
- No public stability: the package is importable only inside
  `Luna-Flow/floating`.
- The power caches are process-wide mutable state, the only state in the
  package; they never change a result.
