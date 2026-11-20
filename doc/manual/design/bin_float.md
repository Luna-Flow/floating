# bin_float design

`bin_float` implements IEEE 754 binary floating-point arithmetic at any
precision. This page explains the mathematics behind it: the value set, the
rounding functions and the error model they satisfy, how each operation
decides the correctly rounded result from exact integer data, how the
exponent range, tininess and the status flags are handled, why the IEEE
remainder is exact, how decimal conversion and the elementary functions are
certified, and why the fast integer kernels cannot change a result. The
[API reference](../api/bin_float.md) lists the callable surface and the
[tutorial](../tutorial/bin_float.md) shows it in use.

## Design goal

Every operation of `bin_float` returns the value that IEEE 754-2019 requires
of a correctly rounded operation, $\circ(f(x))$ for the exact real
$f(x)$, together with exactly the IEEE status flags, for every precision $p$
from 1 to $2^{28}$ bits and every exponent range up to $\pm(2^{30}-1)$. The
same code serves two audiences: arbitrary-precision numerics that need
dyadic values far beyond `Double`, and bit-exact emulation of binary16,
binary32, binary64 and binary128 including subnormals, the five rounding
directions and both tininess rules. There is no hidden state: precision,
rounding and range travel in an immutable `BinaryContext`, and flags travel
back as a value. The basic operations, conversions and `pown` meet this
goal unconditionally; the certified elementary functions meet it for every
value they return, with the budget failures and the one undetected family of
exact results described under
[Certified elementary functions](#certified-elementary-functions).

## Mathematical background

### Dyadic values and the stored triple

A finite `BinFloat` denotes the dyadic rational

$$
x = (-1)^s \cdot c \cdot 2^{e}, \qquad s \in \{0, 1\},\ c \in \mathbb{N},\ e \in \mathbb{Z},
$$

where $c$ is a `BinCoeff` and $e$ is `exponent2()`. The representation is
canonical: if $c \ne 0$ then $c$ is odd, and if $c = 0$ then $e = 0$. Every
dyadic rational has exactly one such form (factor out
$2^{\nu_2(c)}$), so two finite values are numerically equal exactly when
their signs (for nonzero values), coefficients and exponents agree. The
exponent of the leading bit is

$$
\operatorname{top}(x) = \lfloor \log_2 |x| \rfloor = e + \operatorname{bits}(c) - 1,
$$

and every comparison, range check and rounding decision below is phrased in
terms of $\operatorname{top}$ and $\operatorname{bits}$ instead of floating
logarithms. Each value also carries a precision $p$ with
$\operatorname{bits}(c) \le p$; it records the format the value belongs to
and is the default precision of plain operations on it.

### The IEEE 754 binary formats

A binary interchange format with $k$ bits has a sign bit, a $w$-bit biased
exponent field $E$ and a $(p-1)$-bit trailing significand field $T$
(IEEE 754-2019 clause 3.4).[^ieee] With $e_{\max} = 2^{w-1} - 1$, the bias
$e_{\max}$ and $e_{\min} = 1 - e_{\max}$, an encoding means

$$
v = \begin{cases}
(-1)^s\, 2^{E - e_{\max}} \bigl(1 + T\, 2^{1-p}\bigr) & 1 \le E \le 2^w - 2 \quad\text{(normal)},\\
(-1)^s\, 2^{e_{\min}} \bigl(0 + T\, 2^{1-p}\bigr) & E = 0 \quad\text{(subnormal or zero)},\\
(-1)^s\, \infty & E = 2^w - 1,\ T = 0,\\
\mathrm{NaN} & E = 2^w - 1,\ T \ne 0.
\end{cases}
$$

[^ieee]: IEEE Std 754-2019, *IEEE Standard for Floating-Point Arithmetic*:
    clause 3 (formats), 4.3 (rounding-direction attributes), 5 (operations),
    6 (infinities, NaNs, signed zero), 7 (default exception handling).

| Format | $k$ | $w$ | $p$ | $e_{\max}$ | $e_{\min}$ | largest $\Omega$ | smallest normal | smallest subnormal |
| --- | ---: | ---: | ---: | ---: | ---: | --- | --- | --- |
| binary16 | 16 | 5 | 11 | 15 | −14 | $65504$ | $2^{-14}$ | $2^{-24}$ |
| binary32 | 32 | 8 | 24 | 127 | −126 | $(2-2^{-23})2^{127}$ | $2^{-126}$ | $2^{-149}$ |
| binary64 | 64 | 11 | 53 | 1023 | −1022 | $(2-2^{-52})2^{1023}$ | $2^{-1022}$ | $2^{-1074}$ |
| binary128 | 128 | 15 | 113 | 16383 | −16382 | $(2-2^{-112})2^{16383}$ | $2^{-16382}$ | $2^{-16494}$ |

Forgetting the encoding, the finite values of the format are

$$
F(p, e_{\min}, e_{\max}) = \{\, M \cdot 2^{q} : M \in \mathbb{Z},\ |M| < 2^{p},\ q \ge e_{\min} - p + 1,\ |M| 2^{q} < 2^{e_{\max}+1} \,\}.
$$

A `BinaryContext` is exactly this triple plus a rounding direction and a
tininess rule. Its $e_{\min}$ and $e_{\max}$ are leading-bit exponents, so a
normal number has $e_{\min} \le \operatorname{top}(x) \le e_{\max}$, and the
grid below $2^{e_{\min}}$ has the fixed quantum

$$
\eta = 2^{e_{\min} - p + 1},
$$

the smallest positive subnormal. Missing bounds are replaced by the
implementation range $\pm(2^{30}-1)$, which is large enough that every
exponent arithmetic step fits a 64-bit intermediate and every stored exponent
an `Int`; `binary_precision_max` $= 2^{28}$ keeps $e_{\min} - p + 1$ in range
too.

### Rounding functions

For $x \in \mathbb{R}$ let $x^- = \max\{y \in F : y \le x\}$ and
$x^+ = \min\{y \in F : y \ge x\}$, extending $F$ by $\pm\infty$ beyond
$\pm\Omega$ for the moment. The six rounding directions of
`BinaryRoundingMode` are the maps $\mathbb{R} \to F \cup \{\pm\infty\}$

$$
\begin{aligned}
\operatorname{RD}(x) &= x^-, \qquad \operatorname{RU}(x) = x^+, \\
\operatorname{RZ}(x) &= \operatorname{sign}(x)\,|x|^-, \qquad \operatorname{RA}(x) = \operatorname{sign}(x)\,|x|^+, \\
\operatorname{RNE}(x) &= \text{the nearer of } x^-, x^+, \text{ the one with even } M \text{ on a tie}, \\
\operatorname{RNA}(x) &= \text{the nearer of } x^-, x^+, \text{ the one of larger magnitude on a tie},
\end{aligned}
$$

where RA (`RoundAwayFromZero`) is not an IEEE attribute but the GDA
"round-up" mode that `@lf_arith.RoundingMode` shares with the decimal cores.
Two properties of every $\circ$ above carry most of the proofs on this page:

$$
\text{(R1)}\ \ x \in F \implies \circ(x) = x, \qquad\qquad \text{(R2)}\ \ x \le y \implies \circ(x) \le \circ(y).
$$

(R1) holds because $x^- = x^+ = x$ on $F$. (R2) holds because each $\circ(x)$
is one of the two neighbours of $x$ chosen by a rule that only moves from
$x^-$ to $x^+$ as $x$ increases through a cell $[x^-, x^+]$.

### The standard error model

Let $u = 2^{-p}$ be the unit roundoff. Take $x$ with
$2^{t} \le |x| < 2^{t+1}$, $t \ge e_{\min}$ (the normal range) and $|x|$
below the overflow threshold of the rounding direction (otherwise the result
is an infinity and no relative bound holds). The points of $F$ in that binade
are spaced $2^{t-p+1}$ apart, and $2^{t+1}$ belongs to $F$ or is the overflow
point, so

$$
\begin{aligned}
|\operatorname{RN}(x) - x| &\le \tfrac12\, 2^{t-p+1} = 2^{t-p} \le 2^{-p} |x| = u|x|, \\
|\operatorname{RD}(x) - x|,\ |\operatorname{RU}(x) - x| &< 2^{t-p+1} \le 2u|x|,
\end{aligned}
$$

where RN is RNE or RNA. Writing $\circ(x) = x(1 + \delta)$ gives the standard
model

$$
\operatorname{fl}(a \circ b) = (a \circ b)(1 + \delta), \qquad |\delta| \le u \ \text{(nearest)}, \quad |\delta| < 2u \ \text{(directed)}.
$$

The nearest bound sharpens to $|\delta| \le u/(1+u)$ by dividing by
$|\circ(x)|$ instead of $|x|$.[^higham] Below $2^{e_{\min}}$ the spacing is the
constant $\eta$, so the error is absolute: $|\operatorname{RN}(x) - x| \le
\eta/2$ and $|\operatorname{RD}(x) - x| < \eta$. Both regimes together give
the model with an underflow term,

$$
\operatorname{fl}(a \circ b) = (a \circ b)(1 + \delta) + \epsilon, \qquad |\delta| \le u,\quad |\epsilon| \le \tfrac{\eta}{2},\quad \delta\epsilon = 0,
$$

for nearest rounding ($2u$ and $\eta$ for directed rounding). Addition and
subtraction never need $\epsilon$: if $a, b \in F$ then both are integer
multiples of $\eta$, so is $a \pm b$, and a multiple of $\eta$ below
$2^{e_{\min}}$ lies in $F$. Hence a subnormal sum is exact, which is why
gradual underflow keeps $a - b = 0 \iff a = b$.[^kahan]

[^higham]: N. J. Higham, *Accuracy and Stability of Numerical Algorithms*,
    2nd ed., SIAM 2002, §2.2; D. Goldberg, "What every computer scientist
    should know about floating-point arithmetic", *ACM Computing Surveys*
    23(1), 1991.

[^kahan]: J.-M. Muller et al., *Handbook of Floating-Point Arithmetic*, 2nd
    ed., Birkhäuser 2018, §2.1 and §4.3.

Correct rounding is a stronger property than the model: the result is the
one point $\circ(f(x))$, not merely some point within $u$. Every value
`bin_float` returns is that point, so the model above holds for every
operation, including the elementary functions.

## Design decisions

### Round once from exact data

**Problem.** A result must equal $\circ(r)$ for the exact real $r$, but $r$
may need far more bits than $p$ (a product of two $p$-bit numbers has $2p$),
or infinitely many (a quotient, a square root, $e^x$).

**Options.** Compute in a wider format and round again, as hardware without
FMA does; or keep a fixed number of guard bits; or decide the rounding from
exact information.

**Choice.** Every operation computes an exact description of $r$ and calls
one finalizer. For dyadic results (sum, difference, product, `fma`,
`scaleb`, `remainder`, conversion) the description is the exact integer
magnitude $m$ and exponent $e$ with $r = \pm m 2^{e}$. The finalizer picks the
shift

$$
\sigma = \max\bigl(\operatorname{bits}(m) - p,\ (e_{\min} - p + 1) - e,\ 0\bigr),
$$

the larger of the precision shift and the shift onto the subnormal grid, and
splits $m 2^{-\sigma} = q + f$ with $q = \lfloor m 2^{-\sigma} \rfloor$ and
$0 \le f < 1$ into three items of data:

$$
q, \qquad g = [\,f \ge \tfrac12\,] = \text{bit } \sigma - 1 \text{ of } m, \qquad t = [\,f \notin \{0, \tfrac12\}\,] = [\,\nu_2(m) < \sigma - 1\,].
$$

These are the classical round and sticky bits, read from the coefficient by
`test_bit` and `ctz` without building any shifted copy. They determine
every rounding direction: with $q_0$ the last bit of $q$,

| Direction | increment $q$ when |
| --- | --- |
| RNE | $g \wedge (t \vee q_0)$ |
| RNA | $g$ |
| RZ | never |
| RU | $(g \vee t) \wedge s = 0$ |
| RD | $(g \vee t) \wedge s = 1$ |
| RA | $g \vee t$ |

*Derivation.* $f > \frac12 \iff g \wedge t$, $f = \frac12 \iff g \wedge \neg
t$, and $f > 0 \iff g \vee t$. RNE rounds the magnitude up when $f > \frac12$,
or when $f = \frac12$ and $q$ is odd; that is $(g \wedge t) \vee (g \wedge \neg
t \wedge q_0) = g \wedge (t \vee q_0)$. The directed rows round the magnitude up
exactly when $f > 0$ and the direction points away from zero for the sign
$s$. Inexactness is $g \vee t$.

**Why.** Because $\sigma$ already includes the subnormal shift, a tiny result
is rounded once, directly from $m$, to the grid $\eta \mathbb{Z}$. Rounding
first to $p$ bits and then to the subnormal grid would be a double rounding:
a value just above a midpoint of the coarse grid can be pushed onto that
midpoint by the first rounding and then rounded the wrong way by the second.
A carry out of $q$ (when $q + 1 = 2^p$) only raises $\operatorname{top}$ by
one; the result is re-normalized and the overflow test below is applied to
the rounded value.

**The three paths of the finalizer, and why the normalization chain is skipped.** `binary_round_dyadic` takes one of three paths. (1) *Exact exit:* if $\operatorname{bits}(m) \le p$ and $e_{\min} \le \operatorname{top} \le e_{\max}$ (the context range, clamped to the implementation range), then $r = m 2^{e}$ is representable: $e \ge e_{\min} - p + 1$, so the shift $\sigma$ is $0$, nothing is rounded and no flag is raised; this holds for bounded and unbounded contexts alike. (2) *Precision path:* if the shift onto the subnormal grid is not larger than the precision shift, the precision rounding already uses the final $\sigma$, so its result is the final result and the rounding is done once; its top bit is also the "rounded top" that the tininess rule after rounding and the overflow test need. (3) *Range path:* otherwise the value is split again at the range shift, and the precision rounding is kept only to supply the rounded top. In all three paths the stored value is built by `binary_finite_in_range`: the coefficient has at most $p$ bits (a carry out of $q$ gives a power of two, which is even and is stripped to $1$), its top bit is at least $e_{\min} - p + 1$ and at most $e_{\max}$ (overflow is tested first), so the general normalization has nothing left to do except stripping trailing zeros: the implementation-range underflow, the re-rounding of excess bits and the overflow test of `normalize_finite` cannot fire. The tests keep copies of the old core and compare value and flags on random corpora and at the exponent limits.

### Division from quotient and remainder

**Problem.** $a/b$ with $a = c_a 2^{e_a}$, $b = c_b 2^{e_b}$ is a rational
$N/D \cdot 2^{e}$ ($N = c_a$, $D = c_b$, $e = e_a - e_b$) whose binary
expansion is usually infinite.

**Choice.** First the exact leading exponent: with
$k = \operatorname{bits}(N) - \operatorname{bits}(D)$,
$\lfloor \log_2 (N/D) \rfloor$ is $k$ if $N \ge D 2^{k}$ and $k - 1$
otherwise, one integer comparison. That fixes the target exponent
$\tau = \max(\operatorname{top} - p + 1,\ e_{\min} - p + 1)$, and then one
integer division

$$
N 2^{e - \tau} = q D + r, \qquad 0 \le r < D
$$

gives $q$ directly, and the remainder gives the rounding data:
$f = r/D$, so

$$
g = [\,2r \ge D\,], \qquad t = [\,r \ne 0 \wedge 2r \ne D\,].
$$

No approximation of $N/D$ is involved; the rounding is decided by the sign of
$2r - D$. When $e - \tau < 0$ the shift is moved to the denominator, and a
quotient below one unit is decided by comparing $2N$ with $D 2^{\tau - e}$
without forming it.

### Square root from an integer root and a midpoint test

**Problem.** $\sqrt{c 2^{e}}$ is irrational unless $c 2^{e}$ is a square.

**Choice.** The leading exponent is $\lfloor \operatorname{top}(x)/2 \rfloor$
(floor division), which fixes $\tau$ as above. Write the radicand as
$X = c\, 2^{e - 2\tau}$, so $\sqrt{x} = \sqrt{X}\, 2^{\tau}$. An exact integer
square root gives $s = \lfloor \sqrt{X} \rfloor$ with remainder $X - s^2$;
the root is exact iff the remainder is zero. Otherwise the rounding data
come from the midpoint $s + \frac12$:

$$
\sqrt{X} \gtrless s + \tfrac12 \iff X \gtrless \bigl(s + \tfrac12\bigr)^2 \iff 4X \gtrless (2s+1)^2,
$$

an exact comparison of integers (with the power of two moved to the other
side when $X$ is fractional). So $g = [4X \ge (2s+1)^2]$ and
$t = \neg\text{exact} \wedge [4X \ne (2s+1)^2]$. When $X$ is an integer the
right side is odd and the left even, so the root is never exactly a midpoint;
this is the classical fact that $\sqrt{x}$ of a $p$-bit number is never a
$(p+1)$-bit midpoint.[^muller-sqrt] The equality branch is still kept,
because an operand with more bits than the context precision can make
$\sqrt{X}$ an exact midpoint (for example $\sqrt{9/4} = 3/2$ rounded to one
bit).

[^muller-sqrt]: Muller et al., *Handbook of Floating-Point Arithmetic*,
    §5.3 and §7.6.

### Exponent range, overflow and underflow

**Overflow** is decided on the rounded value: if the rounded result has
$\operatorname{top} > e_{\max}$, the operation overflows, which is IEEE 754's
"after rounding" rule (clause 7.4). From the rounding table this happens at
the thresholds

$$
\begin{aligned}
\text{RNE, RNA:}\quad & |r| \ge 2^{e_{\max}}\bigl(2 - 2^{-p}\bigr) = \Omega + \tfrac12 \operatorname{ulp}(\Omega), \\
\text{RA, and RU for } r>0, \text{ RD for } r<0:\quad & |r| > \Omega, \\
\text{RZ, and RU for } r<0, \text{ RD for } r>0:\quad & \text{never to } \infty,
\end{aligned}
$$

because a value in $(\Omega, \Omega + \frac12\operatorname{ulp})$ rounds to
nearest down to $\Omega$, while the tie $\Omega + \frac12\operatorname{ulp}$
goes to the even neighbour $2^{e_{\max}+1}$, which lies outside $F$. An
overflowing result is $\pm\infty$ for the first two groups and $\pm\Omega$ for
the third, always with `overflow` and `inexact`. In binary16,
$\Omega = 65504$ and $\frac12\operatorname{ulp}(\Omega) = 16$:

```moonbit
///|
test "binary16 overflow threshold under nearest rounding" {
  let ctx = @bin_float.BinaryContext::binary16()
  let (below, below_flags) = @bin_float.BinFloat::from_int(65519).round_ctx(ctx)
  let (at, at_flags) = @bin_float.BinFloat::from_int(65520).round_ctx(ctx)
  inspect("\{below} \{below_flags.overflow()}", content="2047p5 false")
  inspect("\{at} \{at_flags.overflow()}", content="inf true")
}
```

**Tininess.** A nonzero result is tiny when it lies strictly between
$\pm 2^{e_{\min}}$. IEEE 754-2019 (clause 7.5) allows two readings, and
`TininessDetection` selects one:

$$
\text{before rounding: } |r| < 2^{e_{\min}}; \qquad \text{after rounding: } |\circ_{p,\infty}(r)| < 2^{e_{\min}},
$$

where $\circ_{p,\infty}$ rounds to $p$ bits with an unbounded exponent range.
The finalizer computes $\operatorname{top}(r)$ exactly and, for the
after-rounding rule, a second split of the same magnitude at the precision
shift alone. The two readings differ only for $r$ just below $2^{e_{\min}}$
that rounds up to it at $p$ bits: for binary16, $r = 2^{-14} - 2^{-27}$ is
tiny before rounding but rounds at 11 bits to $2^{-14}$, which is not tiny.

**Underflow flag.** Under default exception handling the underflow flag is
raised for a tiny result only when it is also inexact. The finalizer returns
no flags at all for an exact result, so an exact subnormal (for example any
subnormal difference, as shown above) raises nothing. The `binary16` product
$2^{-14} \times (1 - 2^{-11})$ shows the full rule: the exact value
$2^{-14} - 2^{-25}$ is tiny under both readings, lies halfway between two
subnormals of spacing $2^{-24}$, rounds to the even neighbour $2^{-14}$, the
smallest normal, and raises `underflow` and `inexact`, although the encoded
result `0x0400` is normal.

```moonbit
///|
test "underflow is raised for a tiny inexact result that rounds to normal" {
  let format = @bin_float.BinaryInterchangeFormat::Binary16
  let smallest_normal = @bin_float.BinaryInterchange::from_hex("0400", format)
    .unwrap()
    .to_bin_float()
  let below_one = @bin_float.BinaryInterchange::from_hex("3BFF", format)
    .unwrap()
    .to_bin_float()
  let (product, flags) = smallest_normal.mul_ctx(below_one, format.context())
  inspect(product.to_interchange(format).0.to_hex(), content="0400")
  inspect("\{flags.underflow()} \{flags.inexact()}", content="true true")
}
```

**Far below the range.** A result certainly smaller than $\eta/2$ in
magnitude (decided from exponent bounds without forming it, for example
$2^{-10^9} \cdot 2^{-10^9}$) rounds to $\pm 0$ or $\pm\eta$ according to the
direction, with `underflow` and `inexact`. A result certainly above the range
goes to the overflow result.

**Exact results in the subnormal range.** An elementary function whose exact
result is the dyadic $m \cdot 2^{n}$ ($2^{n}$ for `exp2` of an integer, the
exact power of `pow` with a dyadic result) passes it to the finalizer as the
pair $(m, n)$. It does not build a `BinFloat` first: a `BinFloat` made from
$(1, n)$ at one bit has its smallest value at $2^{e_{\min}}$, so $2^{n}$ with
$n < e_{\min}$ was flushed to zero before any context could round it, although
it is exactly representable at $p \ge 2$. The after-rounding rule uses
$\circ_{p,\infty}$ with no exponent range at all, not an unbounded context,
which still has gradual underflow at the implementation limit
$2^{e_{\min}}$.

**One layer for the new recommended functions.** The defects of the range
audit (an exact power of two flushed by a one-bit `BinFloat::make`, a shortcut
returning before a signaling NaN is seen, an unbounded context used as a
range-free rounding) were each a pattern that a function could write again.
`exp2m1`, `exp10m1`, `log2p1` and `log10p1`, and the families that follow in
[#235](https://github.com/Luna-Flow/floating/issues/235), therefore take four
decisions from one internal file (`elementary_range.mbt`): the NaN and pole
results (`binary_nan_unary`, `binary_pole_result`, a signaling NaN first); an
exact result rounded as a dyadic by the finalizer, never built as a
`BinFloat` (`binary_integer_result`, `binary_pow2_minus_one_integer`); the
overflow decision of $b^x - 1$ from certified bounds of $\log_2 b$
(`binary_positive_exp_minus_one_overflow`, including the window
$x \log_2 b \in [e_{\max} + 1, e_{\max} + 2)$ and, for base 2,
$x > e_{\max} + 1$ with $x - (e_{\max} + 1) \ge 2^{-(e_{\max} + 1) + 1}$);
and one Ziv driver (`binary_ziv_round`). For an integer $n$ with $n \ge p + 2$
the value $2^n - 1$ lies in the open interval between the midpoint under $2^n$
and $2^n$, where every value rounds alike in each direction, so a
representative of the same binade stands for it and the huge integer is never
formed; below $p + 2$ bits it is exact or a tie and is rounded as it is.

`rsqrt`, `compound` and `powr` (second family of
[#235](https://github.com/Luna-Flow/floating/issues/235)) add no new
rounding logic: each reduces to an operation that already owns the exact cases
and the range decision, after the special values of §9.2.1. $1/\sqrt{x}$ is
`rootn(x, -2)`, $x^y$ for $x > 0$ is `pow`, and $(1 + x)^n$ is `pown` of the
exact sum $1 + x$ whenever that sum fits in $2^{26}$ bits. The one decision
of its own is the tiny rule of `compound`: for $|n x| < 2^{-(p + 9)}$ the exact
value is $1 + \delta$ with $|\delta| < 2^{-(p+8)}$, far inside the window
around $1$ bounded by the breakpoints $1 - 2^{-(p+1)}$ and $1 + 2^{-p}$, so the
result is $1$ or its neighbour by direction alone and equals the rounding of
the surrogate $1 \pm 2^{-(p+3)}$, which `binary_round_dyadic` takes through
the same finalizer as any exact value.

`asinpi`, `acospi`, `atanpi` and `atan2pi` (third and last family of
[#235](https://github.com/Luna-Flow/floating/issues/235)) are
$\operatorname{asin}(x)/\pi$, $\operatorname{acos}(x)/\pi$,
$\operatorname{atan}(x)/\pi$ and $\operatorname{atan2}(y, x)/\pi$: the existing
certified enclosures of the angle divided by a certified enclosure of $\pi$,
rounded by the Ziv driver. By Niven's theorem the only exact (dyadic) values are
the constants of §9.2.1 and $\operatorname{atanPi}(\pm 1) = \pm 1/4$,
$\operatorname{atan2Pi}(\pm a, \pm a) = \pm 1/4, \pm 3/4$, which are rounded as
dyadics; $1/6$, $1/3$ and $2/3$ are rational but not breakpoints, so the loop
terminates on them. The range hazards are anchors, decided before the loop by
`binary_tiny_argument_result` from a certified distance: $\operatorname{atanPi}(x)
= \pm(1/2 - \delta)$ with $\delta < 2^{-t}$ for $|x| \ge 2^t$, $t \ge p + 8$;
$\operatorname{acosPi}(x) = 1/2 \mp \delta$ with $\delta < |x|/2$ for a tiny
$|x|$; and $\operatorname{atan2Pi}(y, x)$ at $\pm 1/2$ ($D \ge p + 8$) and $\pm 1$
($D \le -(p + 8)$, $x < 0$), where $D$ is the difference of the leading-bit
exponents, so that the ratio $y/x$ (whose exponent can be $\pm 2^{31}$) is never
formed. For $x > 0$ and a ratio so small that $t/\pi$ lies below a quarter of the
smallest subnormal the result is the tiny nonzero result of the direction.
Everything else is the enclosure $\operatorname{atan}(t)/\pi$ (or
$1 - \operatorname{atan}(t)/\pi$) at a working precision above the operands'.

### Handover: the range layer and how to add a function

The recommended functions of §9.2 were added in three families on one layer
(`library/src/bin_float/elementary_range.mbt`) and the helpers it builds on
(`binary_round_dyadic` and `binary_round_precision_only` in
`context_arithmetic.mbt`; `binary_certified_inexact_target_rounding`,
`binary_inexact_inner_endpoint` and `binary_tiny_argument_result` in
`elementary_certified.mbt`). Their purpose is to make the defect class of the
range audit ([#271](https://github.com/Luna-Flow/floating/issues/271) to
[#316](https://github.com/Luna-Flow/floating/issues/316)) impossible to write
again: `BinFloat::make(c, e, w)` at a width $w$ flushes every value below
$2^{e_{\min} - (w - 1)}$, so a result or a helper value must never be built that
way; exact results are rounded as dyadics, and a value that clusters at a
representable anchor is decided by its certified distance to it.

The layer exposes (all internal):

| name | use |
| --- | --- |
| `binary_nan_unary(value, context)` | NaN operand: quiet NaN, `invalid` for a signaling one; call first |
| `binary_pole_result(negative, context)` | $\pm\infty$ with `divideByZero` |
| `binary_integer_result(n, context)` | an integer result rounded as a dyadic |
| `binary_pow2_minus_one_integer(n, context)` | $2^n - 1$ for any integer $n \ne 0$ |
| `binary_saturated_minus_one(context)` | $-1 + \varepsilon$ decided by direction |
| `binary_positive_exp_minus_one_overflow(...)` | certain overflow of $b^x - 1$ from certified $\log_2 b$ |
| `binary_ziv_round(operation, context, bounds_at)` | the Ziv driver: `bounds_at(work)` returns a certified enclosure of an inexact result |
| `binary_round_dyadic(negative, coefficient, exponent, context)` | an exact value, both tininess rules, overflow, subnormals |
| `binary_round_precision_only(...)` | the $p$-bit rounding with no range (for after-rounding tininess) |
| `binary_tiny_argument_result(anchor, above, scale, context)` | a result within $2^{scale}$ of a representable anchor, above or below it, decided by direction |
| `binary_tiny_nonzero_result(negative, context)` | a nonzero result below a quarter of the smallest subnormal |

To add a function: (1) write the special-value table of §9.2.1 and Table 9.1
from the PDF text and quote it in the file header and the tests; (2) check a
NaN first (`binary_nan_unary`), a signaling NaN before any shortcut; (3) list the
exact results (by Niven-type arguments or direct algebra) and return them
through `binary_round_dyadic`; (4) find the anchors and the ranges that cluster
(a tiny or huge argument, an extreme ratio) and decide them with
`binary_tiny_argument_result` with a proved bound on the distance; (5) write the
enclosure for `binary_ziv_round`, with the working precision at least the
operand precision plus 16 and the operation known to be inexact; (6) add the
`try_*_ctx`, `*_ctx` and plain forms, the `BinFloatResult` wrappers and the
`mpfr_expr` operation; (7) test against a model that does not use the code under
test (an exact rational, an anchor table, the result at precision $p + 150$), at
the subnormal limit of the implementation and of a few bounded formats, in every
rounding direction and both tininess modes; (8) add the MPFR operation to
`tools/generate_mpfr_random_oracle.c` as a new family appended after the existing
operations (the rows of older families stay byte for byte), generate range
boundary rows in `tools/range_boundary_rows.py`, run 1,000,000 native and 100,000
cases on each other backend and the boundary sweep, and add a few boundary rows
to `testdata/bin_float/random-regressions.txt`; (9) document the function, its
evidence and, for a defect of the oracle, the finding.

The oracle is not the specification. Findings about MPFR 4.2.2 (Homebrew bottle,
arm64) made while doing this, each documented in `testdata/bin_float/README.md`:
`mpfr_sqrt` returns a wrong ternary value or a result on the wrong side for some
odd-exponent operands near the output precision (the generator checks every
`sqrt` row with an exact product and draws again); `mpfr_compound_si` is not
correctly rounded for a negative $n$ in the directed modes nor near the ends of
the exponent range (the generator rounds the exact rational with
`mpfr_set_q`; the library was right in every one of 2,017 rows proved by
independent rational arithmetic); `mpfr_rec_sqrt(-0)` is $+\infty$ by MPFR's own
convention where §9.2.1 says $-\infty$ (the expected value follows the standard);
`mpfr_atan2pi` takes time that grows with the exponent difference of its
operands (not a wrong answer: rows over 100,000 binades apart are not
generated).

### Signed zeros and NaNs

An exact zero sum $a + b = 0$ with $a, b$ of opposite sign is $+0$ in every
direction except RD, where it is $-0$; $(-0) + (-0) = -0$ (clause 6.3).
Products and quotients take the exclusive-or of the signs. A NaN operand
yields the first NaN operand, quieted, with its sign and payload
(clause 6.2.3 allows any input NaN), and `invalid_operation` is raised exactly
when an operand is a signaling NaN or the operation is invalid on its own
($\infty - \infty$, $0 \cdot \infty$, $0/0$, $\infty/\infty$,
$\sqrt{x<0}$, $\operatorname{remainder}(\infty, y)$,
$\operatorname{remainder}(x, 0)$). Flags are values: `combine` is the
bitwise OR, so the flags of a computation form a commutative idempotent
monoid and can be accumulated in any order, which a global sticky register
cannot offer to concurrent code.

The elementary functions take the signs of their special values from
IEEE 754-2019 §9.2.1, which reads the sign of a zero operand: for example
$\operatorname{atan2}(\pm 0, -0) = \pm\pi$ but $\operatorname{atan2}(\pm 0, +0) = \pm 0$,
$\operatorname{tanpi}(n)$ has the sign of
$\operatorname{sinpi}(n)/\operatorname{cospi}(n)$, and $(-0)^y$ and
$(-\infty)^y$ are negative exactly for an odd integral $y$.

### Classes of a value

IEEE 754-2019 clause 5.7.2 defines `class(x)` with ten values, which the
`def` package spells as `IeeeClass`. Zeros, infinities and NaNs are read from
the stored class and sign (a signaling NaN is the flag the value keeps). The
normal/subnormal split is the one rule of clause 3.4: a nonzero finite $x$ is
normal when $2^{e_{\min}} \le |x|$, that is when the exponent of its leading
bit is at least $e_{\min}$, and subnormal otherwise. A `BinFloat` stores no
$e_{\min}$ (it has only a precision), so `class_of`, `is_normal` and
`is_subnormal` take the `BinaryContext`, the same way `Decimal` takes a
`DecimalContext`. The leading-bit exponent is computed from the coefficient's
bit length and the exponent, so the test is exact and independent of the
precision; no rounding happens and no flag is raised. `is_finite`,
`is_infinite` and `is_nan` need no context. `class_of` is a total function: the
ten classes partition every `BinFloat`, and `Decimal::class_name` is the text of
the same partition for `Decimal`.

### Format conversion

`convert_format` is `round_ctx` in the destination format's context, so the
conversion inherits the one rounding step of the dyadic finalizer: a destination
with at least the precision and range of the source is exact (the value
needs at most $p_{\text{source}} \le p_{\text{destination}}$ bits and its exponent
is inside the wider range), and a narrower one rounds once, with the flags of
clause 7. The only extra step is the payload of a NaN: `round_ctx` keeps the
whole payload of a `BinFloat`, but a format holds $p - 2$ payload bits below the
quiet bit, so the payload is masked to its low bits, which makes the result the
value that decoding `to_interchange` returns and keeps the clause 6.2.3
round trip (narrower to wider to the same narrower format) exact. The
independent oracle is Berkeley TestFloat: all twelve pairs among binary16, 32,
64 and 128 in the gate, five rounding directions and both tininess rules for
the narrowing pairs; a widening pair does not round, so it is one task.

### Far-apart operands in addition

**Problem.** $2^{10^9} + 2^{-10^9}$ is exact as a dyadic number, but forming
it needs a two-billion-bit coefficient.

**Choice.** When the leading exponents differ by more than $p + 3$, the sum
is formed on the grid with unit $\upsilon = 2^{e(\text{high}) - p - 3}$, where
$e(\text{high})$ is the exponent of the last bit of the larger operand, so
$\upsilon \le 2^{\operatorname{top}(\text{high}) - p - 3}$. The larger operand
$H\upsilon$ is exact on that grid; of the smaller operand only the integer
part $L$ of its value in units $\upsilon$ enters, and if anything below
$\upsilon$ was discarded the magnitude becomes $2(H \pm L) + 1$ (for
subtraction $2(H - L - 1) + 1$) in units of $\upsilon/2$, that is, one sticky
bit at the half unit.

**Why it is exact for rounding.** The result has
$\operatorname{top} \ge \operatorname{top}(\text{high}) - 1$, because the
smaller operand is below $2^{\operatorname{top}(\text{high}) - p - 2}$. The
last retained bit of the rounded result therefore has position at least
$\operatorname{top}(\text{high}) - p$ (more on the subnormal grid), and its
round bit at least $\operatorname{top}(\text{high}) - p - 1$. The true sum
and the substitute both lie strictly inside the same open interval
$\bigl((H \pm L)\upsilon, (H \pm L + 1)\upsilon\bigr)$ (or are equal when
nothing was discarded), and that interval lies between two consecutive
multiples of $\upsilon \le 2^{\operatorname{top}(\text{high}) - p - 3}$, at
least two bit positions below the round bit. So $q$ and $g$ agree, and $t$ is
set in both cases exactly when something nonzero was discarded. The argument
does not need the larger operand to have at most $p$ bits. For subtraction,
$H - (L + \varepsilon) = (H - L - 1) + (1 - \varepsilon)$ with
$0 < 1 - \varepsilon < 1$, so the same substitution applies to the borrowed
form. The complete argument, including the subnormal shift, is in the
attachment below.

### Fused multiply-add

`fma_ctx` forms the product $c_x c_y 2^{e_x + e_y}$ exactly as a value whose
precision equals its own bit length, and passes it to the addition finalizer,
so $x y + z$ is rounded once (clause 5.4.1). The difference from two
roundings is the point of the operation: for $a = \operatorname{RN}(0.1)$ in
binary64, the rounding error $a \cdot a - \operatorname{RN}(a \cdot a)$ is
lost by `mul_ctx` followed by `sub_ctx` (the second operation sees two equal
numbers) but `fma_ctx(a, a, -RN(a*a))` returns it exactly,
$-8.33\ldots \cdot 10^{-19}$. That the result is exact is Dekker's theorem:
the error of a rounded-to-nearest product is itself in $F$ when no underflow
occurs (precisely, when $e_a + e_b \ge e_{\min} - p + 1$ for the exponents of
the last bits of $a$ and $b$, so the exact product lies on the grid of
$F$).[^dekker] If the product exponent leaves the `Int` range, the product
either certainly overflows, or it is so small that it acts as a sticky bit
next to a nonzero addend; the code places a single bit $p + 9$ positions
below the addend's last bit, which by the far-operand argument above rounds
identically. With a zero addend such a product is the tiny result of the
underflow rule.

[^dekker]: T. J. Dekker, "A floating-point technique for extending the
    available precision", *Numerische Mathematik* 18, 1971; Muller et al.,
    §4.4.

### IEEE remainder is exact

**Claim.** If $x, y \in F$ (same precision $p$, same range) and $y \ne 0$,
then $r = x - n y$ with $n = \operatorname{RNE}_{\mathbb{Z}}(x/y)$ lies in
$F$.

**Proof.** Write $x = M_x 2^{q_x}$, $y = M_y 2^{q_y}$ with
$|M_x|, |M_y| < 2^p$ and $q_x, q_y \ge e_{\min} - p + 1$. By the choice of
$n$, $|r| \le |y|/2$. If $n = 0$ then $r = x$. Otherwise $|x/y| \ge \frac12$,
so $|r| \le |y|/2 \le |x|$. Now $r$ is an integer multiple of
$2^{\min(q_x, q_y)}$.

- If $q_x \ge q_y$: $r = k 2^{q_y}$ with $|k| 2^{q_y} \le |M_y| 2^{q_y}/2$,
  so $|k| < 2^{p-1}$.
- If $q_x < q_y$: $r = k 2^{q_x}$ with $|k| 2^{q_x} \le |x| = |M_x| 2^{q_x}$,
  so $|k| < 2^{p}$.

In both cases $|k| < 2^p$, the exponent is at least $e_{\min} - p + 1$, and
$|r| \le \max(|x|, |y|) \le \Omega$, so $r \in F$. $\square$

The implementation never forms $n$, which can have $2^{30}$ bits. With
$X = |x| 2^{-m}$, $Y = |y| 2^{-m}$, $m = \min(q_x, q_y)$ (integers), it
computes $X \bmod 2Y$ by modular exponentiation of $2^{q_x - q_y}$ when
$q_x > q_y$. Writing $X = Q (2Y) + R$, $0 \le R < 2Y$, gives
$\lfloor X/Y \rfloor = 2Q + [R \ge Y]$, so $R$ alone yields both
$X \bmod Y$ and the parity of $\lfloor X/Y \rfloor$, which is all the
ties-to-even choice of $n$ needs. The exact $r$ then goes through the usual
finalizer; by the claim, no rounding happens for operands of the context's
format.

### Neighbours, scaling and integral values

`next_up_ctx(x)` adds a positive step $2^{\pi - 2}$ to $x$ and rounds toward
$+\infty$, where $\pi = \min(e_{\min} - p,\ e(x),\ \operatorname{top}(x) - p)$.
Every gap between consecutive points of $F$ next to $x$ is at least
$2^{\min(e_{\min} - p + 1,\ \operatorname{top}(x) - p)}$ and $x$ itself is a
multiple of $2^{e(x)}$, so $x < x + 2^{\pi - 2} < x^{+}$ for $x \in F$, and
by the definition of RU the result is the least point of $F$ above $x$. The
same argument works for an $x$ with more than $p$ bits, which is why such
operands are accepted. The flags of this internal addition are discarded,
because `nextUp` is quiet (clause 5.3.1) even when it steps from $\Omega$ to
$+\infty$.

`scaleb_ctx(x, n)` is the finalizer applied to $(c, e + n)$: exact in the
normal range, correctly rounded with underflow and overflow outside it.
`logb_ctx` returns $\operatorname{top}(x)$, which is exact and correct for
subnormal $x$ because $\operatorname{top}$ is computed on the integer
coefficient. The integral roundings use the same round and sticky bits with
$\sigma = -e$ (the bits below the binary point); `to_int_ctx` and its
siblings round first and then compare the integer with the target range,
reporting `invalid_operation` instead of returning an implementation-defined
sentinel.

### Decimal conversion

**Parsing.** `from_string_ctx` reads $D \cdot 10^{k}$ exactly ($D$ an integer
without trailing zeros). For $|k|$ up to
$\max\bigl(400, \lfloor (3n + p)/2 \rfloor + 64\bigr)$ ($n$ the number of
digits) it is rounded exactly: $D \cdot 5^{k} \cdot 2^{k}$ by the dyadic
finalizer for $k \ge 0$, and $D / 5^{|k|} \cdot 2^{k}$ by the division
finalizer for $k < 0$. Beyond that bound it uses directed enclosures
$[\operatorname{RD}_w(D)\operatorname{RD}_w(10^k), \operatorname{RU}_w(D)\operatorname{RU}_w(10^k)]$
at a working precision $w$, doubled until both ends round to the same value
with the same flags. The bound makes the loop terminate. The rounding
breakpoints of a direction are the points of $F$ (directed modes) or the
midpoints between them (nearest modes); both are dyadic with at most $p + 1$
significant bits. For $k \ge 0$ the odd part of $D 10^{k}$ is a multiple of
$5^{k}$, and $5^{k} > 2^{2.32 k} > 2^{p+2}$ beyond the bound, so the value
is no breakpoint: $k > \lfloor (3n+p)/2 \rfloor + 64 > (p+2)/2.32$. For
$k < 0$, $|k| > 1.5n$ gives $5^{|k|} > 10^{n} > D$, so $5^{|k|} \nmid D$ and
$D/10^{|k|}$ is not even dyadic. The points where a flag changes (the
overflow threshold, $2^{e_{\min}}$ for tininess, the points of $F$ for
inexactness) are dyadic with at most $p + 1$ significant bits as well. A
value that is none of these has a positive distance to all of them, and the
enclosure, whose relative width is $O(2^{-w})$, eventually lies strictly
between two of them, so some $w$ certifies it; with no count limit
(`BinaryContext::with_refinement_limit(None)`) the loop ends by itself once
$w$ passes the work cap below. Values whose
binary logarithm is certainly beyond the range, estimated with
$\log_2 10$ and a safety margin, overflow or underflow without any
arithmetic, so `1e100000000` costs nothing.

**Hexadecimal parsing.** The value of a hexSequence is the integer of its hex
digits times a power of two, so it is exactly a dyadic rational and no
enclosure is needed: `from_hex_ctx` parses once (the grammar function is shared
with `from_hex`) and hands the integer and the binary exponent to the same
dyadic finalizer as the arithmetic operations, which applies the rounding
direction, the exponent range, subnormals and the tininess rule, and returns
the flags. A binary exponent beyond the 32-bit range is saturated: the value is
then above $2^{2^{31}-1}$ or below $2^{-2^{31}+b}$ ($b$ the number of bits of
the integer), outside every exponent range, so it overflows or underflows
exactly as the saturated one does. `from_hex` keeps its own range check (a
parse error beyond the 32-bit range) and its results for every in-range
sequence.

**Fixed digits.** `to_decimal_string_ctx(x, d)` needs
$\operatorname{round}(x / 10^{E - d + 1})$ with $E = \lfloor \log_{10}|x|
\rfloor$. $E$ starts from $\lfloor \operatorname{top}(x) \log_{10} 2 \rfloor$,
which is within one of the answer, and is corrected by comparing $|x|$ with
$10^{E+1}$, first through directed bounds of the power and, when they
straddle, exactly. The quotient is formed exactly as an integer division when
its operands have at most $2^{20}$ bits, so ties and exact results are
recognised; otherwise directed enclosures are widened until both ends round
to the same integer, which terminates because such a quotient is neither an
integer nor a half-integer. A carry into a new leading digit
($9.99 \to 10.0$) increments $E$ and repeats.

**Shortest output.** Let $I(x)$ be the set of reals that round to $x$ under
RNE in the context; it is an interval containing $x$. For each digit count
$n$, the two $n$-digit decimals next to $x$ (truncated and rounded away from
zero) are candidates, and a candidate is accepted when parsing it returns
$x$, that is when it lies in $I(x)$. Acceptance is monotone in $n$: if the
$n$-digit truncation $d_n$ lies in $I(x)$, the $(n+1)$-digit truncation
satisfies $d_n \le d_{n+1} \le x$ (in magnitude), so it lies in the interval
too, and likewise for the upper neighbour. So the least accepted $n$ is found
by bisection on $[1, \lceil p \log_{10} 2 \rceil + 2]$, an upper bound at
which a candidate is always accepted.[^shortest] If both candidates are
accepted, the nearer one is chosen, then the even one, which is the nearest
decimal of that length. For binary64 this reproduces the host formatter on
every value tested.

[^shortest]: The digit count $\lceil p \log_{10} 2 \rceil + 1$ suffices for
    round trip (Matula 1968; Goldberg 1991, Theorem 15); the extra digit is a
    margin for the bisection's upper end.

### Certified elementary functions

**Problem.** For $f = \exp, \ln, \sin, \ldots$ the value $f(x)$ is
transcendental and must be rounded correctly without knowing it.

**Options.** Fixed polynomial approximations with a proven error bound (fast,
but tied to one precision); Ziv's strategy of evaluating with an a priori
error bound and retrying at a higher precision when the rounding is
ambiguous;[^ziv] or interval evaluation.

**Choice.** A Ziv loop whose error bound is not estimated but computed: every
elementary function evaluates an enclosure $[L, U] \ni f(x)$ in which every
internal operation is rounded downward for $L$ and upward for $U$ at a
working precision $w$. If

$$
\circ(L) = \circ(U) \quad\text{and}\quad \operatorname{flags}(L) = \operatorname{flags}(U),
$$

the common value is returned, otherwise $w$ grows. **The value is sound by
(R2):** $L \le f(x) \le U$ implies $\circ(L) \le \circ(f(x)) \le \circ(U)$,
so equal ends force $\circ(f(x)) = \circ(L)$.

The flags need a separate argument. Overflow and tininess (under either rule)
depend only on $|r|$ through a threshold, so on one side of zero they are
monotone: if $L$ and $U$ (which have the same sign once they round to the
same nonzero value) agree, every $r \in [L, U]$ agrees with them.
Inexactness is not monotone: it is false exactly on $F$. If $L < U$ round to
the same value $v$ with `inexact`, then $f(x)$ is inexact *unless*
$f(x) = v \in F$. The loop cannot tell these apart, so the flags are right
only if every input whose exact result lies in $F$ is caught before the
loop. That is why the exact cases below are filtered, and why an exact case
that is missed shows up as a spurious `inexact` (nearest rounding) or as a
budget failure (directed rounding, where $L$ and $U$ round to different
neighbours of $v$).

The enclosures come from series with rigorous tails and from monotone
reductions. For $\exp$ on $[0, 1/8]$, the terms $t_k = x^k/k!$ satisfy
$t_{k+1}/t_k = x/(k+1) \le 1/8$, so after the last summed term $t_n$

$$
\sum_{j > n} t_j \le t_n \sum_{i \ge 1} 8^{-i} = \frac{t_n}{7} \le 2\, t_n,
$$

and the code stops once $t_n < 2^{-(w+8)}$ and adds $2 t_n$ (rounded upward)
to the upper sum; the lower sum of positive terms is already a lower bound.
Larger arguments are halved $r$ times and the result squared $r$ times,
which is monotone on positive numbers and therefore keeps the enclosure;
$e^{-x} = 1/e^{x}$ handles negative arguments. For $\ln v$ with
$v \in [1, 2]$ the series is

$$
\ln v = 2 \operatorname{artanh} z = 2 \sum_{k \ge 0} \frac{z^{2k+1}}{2k+1}, \qquad z = \frac{v - 1}{v + 1} \in \bigl[0, \tfrac13\bigr],
$$

with tail $\sum_{k \ge m} z^{2k+1}/(2k+1) \le \frac{z^{2m+1}}{2m+1} \cdot
\frac{1}{1 - z^2}$, the bound the code adds. The trigonometric functions
reduce $x$ by an enclosure of $\pi/2$ (the cached binary-splitting $\pi$, see
"Where $\pi$ comes from" below) at
$w \ge p + \max(0, \operatorname{top}(x) + 1) + 96$ bits, so the quadrant
$k = \operatorname{round}(x / (\pi/2))$ is the same integer at both ends of
the enclosure; otherwise the attempt is repeated at a higher precision. This
is the Payne–Hanek idea realised by brute precision instead of a stored table
of $2/\pi$; its cost grows with $\log_2|x|$, so inputs needing more than
$10^6$ bits are refused with `ResourceLimit` rather than run for minutes.

**Budget.** The loop starts at $w_0 = p + 64$ (for some functions at the
operand precision plus 16 when that is larger) and steps
$w_{i+1} = w_i + \max(32, \lfloor w_i/2 \rfloor)$, at most $L$ attempts, where
$L$ is the refinement limit of the context (`BinaryContext::refinement_limit`,
default $12$; a value below $1$ counts as $1$). For binary64 and $L = 12$ the
sequence is $117, 175, 262, \ldots, 10053$ bits, and a hard-to-round input
that needs more than that fails with a `CertificationFailure` carrying the
refinement count; `Some(n)` with a larger $n$ certifies it.

With $L$ = `None` the count is unbounded, but the loop is not: it stops, with
the same `CertificationFailure`, when $w$ exceeds
$\max(8\,000\,000,\ 256\,w_0)$ bits (capped at $10^9$ so $w$ fits `Int32`),
and a trigonometric argument that needs more than $8\,000\,000$ bits for its
reduction is still refused with `ResourceLimit` whatever the limit. So `None`
cannot allocate without bound: each step costs $O(M(w))$ for the working
precision $w \le$ the cap, and the number of steps is at most
$\log_{1.5}(\text{cap}/w_0)$. A result that sits at distance
$\delta$ from a breakpoint needs $w \approx \log_2(1/\delta)$, so the default
$L = 12$ decides everything farther than about $2^{-10000}$ from a breakpoint
at binary64 and `None` extends that to the cap. Functions without a context
argument (the `BallFloat` enclosures) keep $12$. The exact fallback of the
integer power `pown` (12 Ziv rounds, then an exact product) cannot fail and
is not governed by the limit.

**Termination.** Ziv's argument has two parts. First, $f(x)$ must not be a
breakpoint of $\circ$ (a point of $F$, a midpoint, or a flag threshold), all
of which are dyadic. For a nonzero dyadic $x$, $e^{x}$, $\sin x$, $\cos x$,
$\tan x$, the hyperbolic functions, their inverses and $\ln x$ ($x \ne 1$)
are transcendental by Lindemann–Weierstrass. For $2^x$, $10^x$, $\log_2 x$
and $\log_{10} x$ irrationality is enough and elementary: $2^{a/b}$ with
$b \nmid a$ is irrational, so $2^x$ is dyadic only for integral $x$, and
$\log_2 x = a/b$ forces $x = 2^{a/b}$, a power of two; likewise $10^x$ and
$\log_{10} x$ are dyadic only at integral $x \ge 0$ and at $x = 10^k$. For
the $\pi$-scaled functions Niven's theorem shows that integral, half-integral
and (for `tanpi`) quarter-integral arguments are the only dyadic
exceptions.[^niven] For `pow` and `rootn` the exceptions are characterised
under *Exact powers and roots* below. The exceptions are filtered before the
loop: $e^0 = 1$, $\ln 1 = 0$, $\log_2 2^k = k$, $2^n$ for integral
$|n| < 2^{31}$, $\sin(\pm 0)$, the $\pi$-scaled cases, $10^n$ for
integral $0 \le n \le \max(4096, p)$ (beyond that the odd part $5^n$ has more
than $p + 1$ bits, so $10^n$ is not a breakpoint), $\log_{10} 10^n$ for every
$n \ge 1$, dyadic powers and exact roots, and so on.

Second, the enclosure must shrink onto $f(x)$ fast enough. The series stop
when the next term is below $2^{-(w+8)}$ or $2^{-(w+12)}$ in *absolute*
value, which is fine for arguments of moderate size; the width then is
$O(2^{-w})$ relative to $f(x)$, a non-breakpoint has a positive distance to
every breakpoint, and some $w$ certifies it. Tiny arguments need the two
measures under *Tiny arguments* below. How large $w$ must be is the
table maker's dilemma: no useful a priori bound is known for arbitrary $p$,
so the budget is a resource limit, not a correctness condition. When it runs
out the `try_*` form reports a `CertificationFailure` with the stage, the
reason and the last $w$, and the total forms return a quiet NaN with
`invalid_operation`; neither returns an uncertified value. The pinned MPFR
corpus never exhausts it.

**Exact powers and roots.** An integral exponent with $|y| < 2^{31}$ goes to
`pown`. A larger integral $y$ needs no filter: for $x = c \cdot 2^e$ with
$c > 1$ odd, $c^{|y|}$ has more than $2^{31} > p + 1$ bits, and a power of two
$2^{ey}$ lies outside every exponent range, so neither is a breakpoint. Every
other exponent is $y = m / 2^k$ with $m$ odd and $k \ge 1$. If $x^y$ is
rational, so is $q = x^{|y|}$, and $x^{|m|} = q^{2^k}$; comparing the
exponents of $2$ and of each odd prime gives $q = a \cdot 2^f$ with $a$ odd,
$e|m| = f \cdot 2^k$ and $c^{|m|} = a^{2^k}$. Since $|m|$ is odd,
$2^k \mid e$ and every prime exponent of $c$ is divisible by $2^k$, so
$c = r^{2^k}$ and $q = r^{|m|} \cdot 2^{e|m|/2^k}$. Conversely these values are
exact. So a rational `pow` result exists exactly under these two divisibility
conditions; for $m > 0$ it is the dyadic $q$, and for $m < 0$ it is $1/q$,
which is dyadic only when $r = 1$. Every other `pow` result is irrational.
`binary_pow_exact_dyadic` computes the dyadic results and rounds them once,
unless the odd part $r^m$ would need more than $2p + 64$ bits (then it has
more than $p + 1$ significant bits and is not a breakpoint). The same argument
with $1/|n|$ in place of $|y|$ shows that $\operatorname{rootn}(x, n)$ is
rational exactly when $|n| \mid e$ and $c = r^{|n|}$; `rootn` returns
$\pm r \cdot 2^{e/|n|}$ rounded once for $n > 0$, and for $n < 0$ the correctly
rounded quotient $1 / (\pm r \cdot 2^{e/|n|})$, which division decides with
the right `inexact` flag although it need not be dyadic. The perfect-power
test has no size limit. It first takes square roots with remainder for every
factor $2$ of the degree, stopping at the first nonzero remainder, and then
the floor of the remaining odd root: by bisection while the root has at most
64 bits, otherwise by integer Newton steps $r \leftarrow \lfloor ((d-1) r +
\lfloor c / r^{d-1} \rfloor) / d \rfloor$ started just above the root, which
decrease monotonically to $\lfloor c^{1/d} \rfloor$; one power $r^d$ then
decides exactness. A coefficient with at most $d$ bits other than $1$ is
rejected at once, because $r \ge 2$ gives $r^d \ge 2^d$.

A negative base with an integral exponent beyond the `pown` range is
evaluated as $\pm|x|^y$. Negation is an exact symmetry of $\circ$ that swaps
the two directed modes, $\circ_{\mathrm{RD}}(-v) = -\circ_{\mathrm{RU}}(v)$, so
for an odd $y$ the code rounds $|x|^y$ with RD and RU exchanged and negates.

**Tiny arguments.** For small enough $|x|$ (about $2^{-p/2}$ for the odd
functions, $2^{-p}$ for $e^x$) the result lies closer to a representable
number $a$ than the target spacing: $a = x$ for the odd functions, $a = 1$ for
$e^x$, $\cos$, $\cosh$. An enclosure whose series stops after its first term then
has $a$ itself as one end ($U = x$ for $\sin$, $L = 1$ for $e^x$), and that
end rounds without `inexact` while the other end rounds with it, so the
acceptance test alone would only pass once $w$ separates $f(x)$ from $a$, at
$w \approx \log_2(1/|x|)$ or more. Two measures remove the dependence on $|x|$.

*Inner endpoints.* Every result that reaches the loop is known not to be a
breakpoint. For every function other than `pow` and `rootn`,
`binary_certified_inexact_target_rounding` replaces an end $E$ that could be a
breakpoint (an odd coefficient of at most $p + 1$ bits) by
$E' = E \pm 2^{e_E - s}$ toward the inside of the enclosure, with
$s = \max(1, p + 3 - \operatorname{bits}(c_E))$. If the leading bit of $E$ is
$2^t$, breakpoints near $E$ are at least $2^{t - p - 1}$ apart and the offset is
at most $2^{t - p - 2}$, so no breakpoint lies in $(E, E']$. Since
$f(x) \ne E$, either $f(x)$ lies beyond $E'$ or between $E$ and $E'$, and in the
second case it shares the open cell between breakpoints with $E'$ and rounds
like it. So $\circ(E') = \circ(U')$ with equal flags still forces
$\circ(f(x))$ and its flags, and the test passes as soon as the enclosure is
narrower than the spacing, independently of $|x|$. `pow` uses inner
endpoints whenever its exactness test (above) has shown that the result is
irrational, not dyadic, or wider than $p + 1$ bits, so a tiny exponent with
$x^y$ closer to $1$ than the target spacing is certified too
($2^{2^{-16000}}$ in binary128 is $1$ with `inexact`). The test leaves a few
cases with a power-of-two base undecided (an exponent of magnitude at least
$2^{31}$, or a scale outside the 32-bit range); those keep the plain
acceptance test.

*Tiny-argument bounds.* Some enclosures (for $\sinh$, $\tanh$ via
$e^x - e^{-x}$, and for $\operatorname{asinh}$, $\operatorname{atanh}$,
$\operatorname{asin}$, $\tan$, `expm1`, `log1p`) straddle the neighbour of
$a$ until $w \approx 3\log_2(1/|x|)$. For $|x| \le 1/2$ the series give
one-sided bounds with a known side: $0 < x - \sin x$, $0 < \tan x - x$,
$0 < \operatorname{asin} x - x$, $0 < \sinh x - x$, $0 < x - \tanh x$,
$0 < x - \operatorname{asinh} x$, $0 < \operatorname{atanh} x - x$, each at
most $|x|^3$ (for $x > 0$, mirrored for $x < 0$), and $0 < 1 - \cos x$,
$0 < \cosh x - 1$, $0 < \operatorname{expm1}(x) - x$,
$0 < x - \operatorname{log1p}(x)$, each at most $x^2$. With $|x| < 2^T$,
`binary_tiny_argument_result` uses the enclosure $[a, a + 2^{\sigma}]$ or
$[a - 2^{\sigma}, a]$ with $\sigma = 3T$ (respectively $2T$), raised to at
least $t_a - p - 8$, when $\sigma < t_a - p - 3$ ($2^{t_a}$ the leading bit of
$a$), and rounds it with inner endpoints. The condition implies
$|x| < 2^{-(p+3)/2} \le 1/2$, so the bounds apply, and the enclosure is
at most a quarter of the breakpoint spacing at $a$ wide. When $a$ is a
breakpoint, both ends lie in the cell next to $a$ and the result is decided
before the loop; otherwise (an argument wider than $p + 1$ bits) the loop runs
as usual. With both measures `sin` and `atan` of $2^{-6000}$ at 53 bits and
$e^{2^{-20000}}$ are certified in every rounding mode.

`rootn` keeps the plain test, and `pow` uses it only for the few results its
exactness test cannot classify. For `rootn` it suffices: its enclosure
is $e^{\ln(x)/n}$ at a working precision above the operand precision $q$, and
$|\ln x| / |n| > 2^{-(q + 31)}$ for $x \ne 1$ and $|n| \le 10^9$, so an end at
$1$ disappears after an attempt or two. `pow` evaluates $e^{y \ln x}$, where
$y$ can be arbitrarily small: an exponent so small that $x^y$ lies closer to
$1$ than the target spacing gives an enclosure with $L = 1$ at every
affordable $w$. That is why `pow` moves such an end inward once its exactness
test has excluded a breakpoint, as described under inner endpoints; for
example $2^{2^{-16000}}$ in binary128 is then $1$ with `inexact`.

[^niven]: I. Niven, *Irrational Numbers*, 1956, Corollary 3.12: if $r$ is
    rational and $\sin(\pi r)$ is rational, then
    $\sin(\pi r) \in \{0, \pm\frac12, \pm 1\}$; similarly for $\cos$, and
    $\tan(\pi r) \in \{0, \pm 1\}$. The value $\pm\frac12$ needs $r$ with
    denominator 6 or 3, which is not dyadic.

[^ziv]: A. Ziv, "Fast evaluation of elementary mathematical functions with
    correctly rounded last bit", *ACM TOMS* 17(3), 1991; for interval
    evaluation see W. Tucker, *Validated Numerics*, Princeton 2011, and
    F. Johansson, "Arb: efficient arbitrary-precision midpoint-radius interval
    arithmetic", *IEEE Trans. Computers* 66(8), 2017.

**Integer powers.** `pown_ctx` computes $x^n$ by an addition chain at
$w = p + \operatorname{bits}(n) + \operatorname{bits}(p) + 4$ bits with
round-to-nearest. Each chain step $a_k = a_i + a_j$ multiplies two
approximations; if $x^{a} \prod (1 + \delta)^{E(a)}$ describes the error
structure, then $E(a_k) = E(a_i) + E(a_j) + 1$ and $E(1) = 0$, so by
induction $E(a) \le a - 1$. The computed value is therefore
$x^n (1 + \theta)$ with $|\theta| \le \gamma_{n-1} = (n-1)u_w/(1 - (n-1)u_w)$
in Higham's notation, which is below $2^{\operatorname{bits}(n)}$ units in the
last place of the $w$-bit result. The code uses the radius
$2^{\operatorname{bits}(n) + 2}$ units (one more factor of two for a negative
power, whose reciprocal adds $n$ further factors), builds the interval, and
accepts when both ends round alike, by the same (R2) argument. When 12
attempts (with $w$ doubled between them) do not certify, the exact power
$c^n 2^{ne}$ is formed and rounded, so the result is correctly rounded in
every case. A power certainly outside the range is decided first from
certified $\log_2$ bounds; powers of two and powers whose exact value fits
in $p$ bits are computed exactly. The Ziv path therefore only sees $c^n$ with
$c > 1$ odd and more than $p$ bits, or $1/c^n$, which is not dyadic: neither
is in $F$, so the `inexact` it reports is right (the flag argument above). A
$c^n$ with exactly $p + 1$ bits is a midpoint; the enclosure then never
certifies under nearest rounding and the exact fallback decides it.

**hypot.** `hypot` forms $a^2 + b^2$ exactly from the coefficients and takes
one correctly rounded square root, so it needs no loop; the cost is the
alignment shift between the two squares. For $|a| \ge |b| > 0$,
$|a| < \sqrt{a^2 + b^2} \le |a| + b^2 / (2|a|)$. Write $|a| = c \cdot 2^e$ with
leading bit $2^t$ and $g = 2^{\min(e,\, t - p - 1)}$: $|a|$ and every rounding
breakpoint near it are multiples of $g$, so when $b^2 < 2|a|g$ no breakpoint
lies in $(|a|, |a| + b^2/(2|a|)]$ and every such $b$ gives the same rounded
result and flags. $|b| < g/8$ is enough, and `binary_hypot_negligible_operand`
then replaces $b$ by $g/8$, which keeps the shift at about twice the operand
and target precisions however far apart the exponents are
($\operatorname{hypot}(1, 2^{-600000}) = 1$ with `inexact`). A shift above
$10^6$ bits is still refused as a `certification_failure`; after the
replacement it needs a precision near $500\,000$ bits.

**`atan`, `asin`, `acos` and `atan2`: one evaluation chain for the pair.** The
enclosure of $\operatorname{atan}$ over a pair $[a, b]$ is computed by one
chain, not by one chain per endpoint. $\operatorname{atan}$ is odd and
increasing, so $L = \operatorname{lower}(\operatorname{atan}\,a)$ and
$U = \operatorname{upper}(\operatorname{atan}\,b)$ enclose $\operatorname{atan}$ on
the whole pair. For $0 \le a \le b$ and $b > 1/2$ the reduction is
$\operatorname{atan}\,x = 2 \operatorname{atan}\, r(x)$ with
$r(x) = x / (1 + \sqrt{1 + x^2}) = \tan(\operatorname{atan}(x)/2)$, which is
increasing on $x \ge 0$ (it is a composition of increasing maps). Hence
$[r^-(a), r^+(b)] \ni r(x)$ for every $x \in [a, b]$, where $r^-(a)$ divides
$a$ rounded down by an upper bound of $1 + \sqrt{1 + a^2}$ and $r^+(b)$ divides
$b$ rounded up by a lower bound of $1 + \sqrt{1 + b^2}$; the bounds of the
denominator are directed squares, sums and square roots, each monotone on
nonnegative numbers. The reduced pair is again nonnegative and ordered, so the
recursion is a chain (two levels at most, because $r(x) < 1$ and
$r(1) < 1/2$), and the Taylor series runs once, with its lower track on the
lower end and its upper track on the upper end. A negative pair $[a, b]$ is
$-[-b, -a]$; a pair that contains zero is widened to $[-m, m]$ with
$m = \max(-a, b)$, which contains it. The old code evaluated the series once
for $|x| \le 1/2$, twice up to $4/3$ and four times above (a lower and an upper
call per reduction level); a point argument now costs one series at every
size.

**Large arguments.** The square $x^2$ of the reduction leaves the exponent range
for $|x| \ge 2^{2^{29}}$, so for a leading bit of $x$ of at least $2w + 2$ the
reduction is formed without it: with $y = 1/x$,
$r(x) = 1 / (y + \sqrt{1 + y^2})$ and
$1 + y \le y + \sqrt{1 + y^2} \le 1 + y + y^2$, hence
$1/(1 + y + y^2) \le r(x) \le 1/(1 + y)$, evaluated with directed reciprocals
of $x$; the relative gap is below $2y \le 2^{-2w-1}$. An infinite end of a pair
(a quotient of `atan2` that overflowed) is bounded by $\pi/2$ rounded in the
matching direction. The test `atan_single_evaluation_wbtest.mbt` covers
$3 \cdot 2^e$ for $e$ on both sides of $2^{29}$ and near $2^{30}$, both signs and
three rounding directions, against $\pi/2$ from the cached constant; the public
results equal those of the previous code there.

For $\operatorname{asin}$ the pair is the ratio $f(x) = x / \sqrt{1 - x^2}$,
increasing on $(-1, 1)$. With $\sqrt{1 - x^2} \in [\rho^-, \rho^+]$ on the
operand pair (directed roots of directed $1 - x^2$), the lower end is
$a / \rho^-$ if $a < 0$ and $a / \rho^+$ if $a \ge 0$, the upper end is
$b / \rho^-$ if $b \ge 0$ and $b / \rho^+$ if $b < 0$, which replaces the
eight directed quotients and the search for their minimum and maximum. For
$\operatorname{atan2}$ and $\operatorname{atan2Pi}$ the ratio $y / x$ of a
rectangle with $x$ of one strict sign takes its extremes at the corners
selected by the signs of the ends of $y$ (four directed divisions replace the
eight of the previous search). The soundness of the new evaluation is tested
against the previous functions, kept as test-only copies, evaluated at 128 more
bits (`atan_single_evaluation_wbtest.mbt`); the Ziv loops take the same number
of attempts on that corpus. A pair that is wide because the operand is (`asin`
close to $1$) can come out up to about 1.4 times wider than before, because the
alternating-series bracket pairs the lower track with the terms of the other
end; narrow pairs differ by a few units in the last place.

**The arctangent leaf in fixed point.** On $[0, \tfrac12]$ the series is evaluated as $\arctan x = x - R(x)$ with $R(x) = x^3/3 - x^5/5 + x^7/7 - \cdots$, increasing in $x$, so on a pair $[a, b]$ the enclosure is $[\,a - R^{+},\ b - R^{-}\,]$ with $R^{-} \le R(a)$ and $R(b) \le R^{+}$. $R$ is computed with integers of $F = w + q + 20 + \operatorname{bits}(w)$ fractional bits, where $q = -\operatorname{top}(b)$: a lower chain $P^{-}_k \le a^{2k+1} 2^F$ by floors and an upper chain $P^{+}_k \ge b^{2k+1} 2^F$ by ceilings (each step multiplies by a floor or ceiling of the square and shifts, and a floor of a product of lower bounds, or a ceiling of a product of upper bounds, keeps the bound), then $T^{-}_k = \lfloor P^{-}_k / (2k+1) \rfloor$ and $T^{+}_k = \lceil P^{+}_k / (2k+1) \rceil$ by a division by a single word. For terms decreasing in size the partial sum after an odd number of terms is at least $R$ and after an even number at most $R$; with $A = \sum_{k \text{ odd}} T^{+}_k$, $B = \sum_{k \text{ even}} T^{-}_k$, $C = \sum_{k \text{ odd}} T^{-}_k$ and $D = \sum_{k \text{ even}} T^{+}_k$ this gives $R^{+} = A - B$ (odd partial sum, upper terms added, lower terms subtracted) and $R^{-} = C' - D$ (even partial sum, $C'$ without the last odd term), and the loop stops at an odd $k$ whose $T^{+}_k$ is below two units. Every floor or ceiling loses at most one unit and $x^2 \le \tfrac14$, so the chain errors stay below two units, each term is within three, and the whole enclosure within $1.5 F$ units of $2^{-F}$, which the 20 and $\operatorname{bits}(w)$ guard bits cover relative to $x \ge 2^{-q}$. For $q \ge w/2 + 8$ the series is not run: $0 \le R(x) \le x^3/3$ and $x^3/3 < x\, 2^{-w-14}$, so the enclosure is $[\,a - b^3/3,\ b\,]$. Where the previous floating-point leaf ran four rounded `BinFloat` operations per term, a term is now two integer products and two single-word divisions: instructions retired for `atan`, `asin`, `acos` and `atan2` fall by 2.1 to 2.5 times at 53, 128 and 512 bits. The tests keep the floating-point leaf as a copy and check that the new enclosure contains the old one at 128 more bits (points, neighbouring and wide pairs, a pair starting at zero) and at both sides of the threshold $q = w/2 + 8$.

**Where $\pi$ comes from.** The binary-splitting $\pi$ of this package is
cached per working precision. `BinFloat` $+\infty$ `.try_atan_ctx` returns the
correctly rounded $\pi/2$ from that cache, so `decimal` and `ball_float` obtain
$[\operatorname{RD}(\pi), \operatorname{RU}(\pi)]$ from two calls (rounding
downward and upward) and a scaling by $2$, which is exact: the same interval,
bit for bit, as $4\,[\operatorname{RD}(\operatorname{atan} 1),
\operatorname{RU}(\operatorname{atan} 1)]$, since scaling by a power of two
commutes with directed rounding. No public function was added for it.

**`sinh`, `cosh` and `tanh` from one `exp`.** With $[L, U] \ni e^{x}$ from one kernel call and $0 < L$, the enclosure of $e^{-x}$ is $[1/U, 1/L]$ with directed divisions (the reciprocal is decreasing); if $L$ is not positive (an underflowed enclosure) the kernel is called on $-x$ as before. $\sinh$ and $\cosh$ then combine the four ends as before. For $\tanh = s / c$ with $0 < c_0 \le c \le c_1$ and $s \in [s_0, s_1]$ the quotient is increasing in $s$ and, for $s \ge 0$, decreasing in $c$ (the reverse for $s < 0$), so the extremes are $s_0 / c_1$ if $s_0 \ge 0$ and $s_0 / c_0$ otherwise (lower end), $s_1 / c_0$ if $s_1 \ge 0$ and $s_1 / c_1$ otherwise (upper end): two divisions instead of eight. At arguments where $e^{|x|}$ leaves the exponent range the enclosures are the same as before ($\sinh$, $\cosh$) or $[0, \infty]$ instead of a NaN end ($\tanh$), and the public results did not change in the tests at those arguments.

**Corners by sign.** The product of two intervals $[a_0, a_1] \cdot [b_0, b_1]$ is no longer the minimum and maximum of four rounded products. With $a$ nonnegative, the smallest $a b$ over the box is $a_0 b_0$ if $b_0 \ge 0$ and $a_1 b_0$ otherwise (take the smallest $b$, then the $a$ that suits its sign), and the largest is $a_1 b_1$ if $b_1 \ge 0$ and $a_0 b_1$ otherwise; a nonpositive $a$ is $-|a|$ and a mixed $a$ with a sign-definite $b$ swaps the roles; two mixed intervals still take the four corners. The quotient by a positive interval $[d_0, d_1]$ has the lower end $n_0 / d_1$ if $n_0 \ge 0$ and $n_0 / d_0$ otherwise, and the upper end $n_1 / d_0$ if $n_1 \ge 0$ and $n_1 / d_1$ otherwise. Directed rounding is monotone, so the rounded exact extreme equals the extreme of the rounded corners. One thing is not monotone: the sign of a zero end depends on which of several equal candidates the old code kept, so when an end is zero the old four-candidate form is used and the results stay bit-identical.

**Trigonometric functions: no reduction near zero, one series for a point.** If both ends of the argument enclosure lie strictly inside $(-\pi/4, \pi/4)$ (the lower bound of $\pi/4$ is half the lower bound of $\pi/2$, exact), then $x / (\pi/2) \in (-\tfrac12, \tfrac12)$ at both ends, the nearest integer is $0$ for both, the product $0 \cdot \pi/2$ is $0$ and the reduced argument is the input itself; the division by $\pi/2$ and the multiplication back are skipped, and the result is the one of the general path. When the reduced pair is a point (equal ends) the series is evaluated once and its two ends are used for both bounds, as evaluating twice gives the same value; `tan` takes the quotient corner by the sign of the cosine enclosure (a negative cosine uses $n / d = (-n) / (-d)$). The same point shortcut is used in `exp2`, `exp10`, `pow`, `rootn`, `log1p`, `asinh`, `acosh`, `atanh`, `expm1`-based `exp2m1` and `exp10m1`, and `compound`: `binary_bounds_at_ends` takes the lower end of the evaluation at the lower argument and the upper end of the evaluation at the upper argument, and evaluates once when the two arguments are equal.

**`rootn` and `rsqrt` by one integer root.** For $2 \le |n| \le 32$ (within the gate described below) the result is rounded in one step, without a Ziv loop. For a positive $x = c 2^{e}$ with $2^t \le x < 2^{t+1}$, the top bit of $x^{1/n}$ is $k = \lfloor t/n \rfloor$ ($t + 1 \le n (k + 1)$ because $t < n (k + 1)$ are integers); the top bit of $x^{-1/n}$ is $-k - 1$, or $-\lceil t/n \rceil$ when $c = 1$ ($x = 2^t$ exactly), by the same inequality on $1/x$. With $T$ the exponent of the last place of the rounded result (the subnormal grid included), take $g = T - 1$ (half a unit) and the integer
$y = \lfloor x 2^{-n g} \rfloor$ (for $x^{1/n}$) or $\lfloor 2^{-n g} / x \rfloor$ (for $x^{-1/n}$);
since $\lfloor v^{1/n} \rfloor = \lfloor \lfloor v \rfloor^{1/n} \rfloor$ for real $v \ge 0$ (an integer $r$ has $r^n \le v$ exactly when $r^n \le \lfloor v \rfloor$), $r_2 = \lfloor y^{1/n} \rfloor$ (the integer square root kernel for $n = 2$, the integer Newton root otherwise) is $\lfloor |x|^{\pm 1/n} / 2^{g} \rfloor$. The retained part is $r_2 \gg 1$, the round bit is the low bit of $r_2$, and the sticky bit is "the root is not exactly $r_2 2^{g}$", which holds unless $y$ was exact (no dropped bits, no remainder) and $y = r_2^n$: a boundary of any rounding direction is a multiple of half a unit, so a root strictly between $r_2$ and $r_2 + 1$ is on the same side of every boundary as $r_2$ with the sticky bit set. `binary_round_pack` then decides the result and the flags as for the square root, including the subnormal range and the tininess rule after rounding (a second root on the unbounded grid when it differs). The integer has about $n (p + 2)$ bits and the Newton steps of its root raise a number of that size to the power $n - 1$, so the path is used only where it is measurably faster than the certified `exp(ln(x) / n)` loop, which gets the fast `exp` and `ln` kernels from about 1500 bits on. Instructions retired, loop divided by integer root: for $n \le 12$ the integer root wins at every precision measured (53 to 32768 bits) by 2.4 to 300 times; for $13 \le n \le 32$ it wins by 6.7 to 49 times up to 1024 bits, but at 2048 bits $n = 16$ gains only 1.6 times, $n = 20$ 1.1 times, and $n = 24$ and $n = 32$ are 1.3 and 2.2 times slower. The gate is therefore $|n| \le 12$, or $|n| \le 32$ with context precision at most 1024 bits, and the loop elsewhere; the tests compare the public result with the loop on both sides of each bound. The exact roots of perfect powers are still decided before either path. Instructions retired per call (53, 128, 512 bits): `rsqrt` 57, 23 and 35 times fewer, `rootn` with $n = 3$ 2.1, 3.6 and 11 times fewer.

### Trigonometric functions of huge arguments

`sin`, `cos` and `tan` of an argument $x$ with $2^{k-1} \le |x| < 2^k$ reduce $x$ modulo
$\pi/2$, which cancels the top $k$ bits of $x$: the reduction needs $\pi$ to
$p + k + 96$ bits for a result of $p$ bits. The reduced argument lies in
$(-\pi/4, \pi/4)$ and the series needs only the precision of the result, so
for $k > 256$ the enclosure of the reduced argument is rounded outward to
$p + 96$ bits before the series (the reduction and the series are separate
precisions). The working precision of the reduction is limited to
8,000,000 bits, so that every argument of the decimal operand range
($10^{999999} < 2^{3321929}$) is evaluated; a larger work size is a
`ResourceLimit` certification failure. The `decimal` driver passes a huge
integer operand to `BinFloat` exactly (an integer $c \cdot 10^e$ is a dyadic
rational) at the result precision, and `ball_float` evaluates a point interval
by two directed evaluations without the rational index computation.

The cost grows faster than linearly in $k$ because $\pi$ at $k$ bits is
computed by binary splitting with a quasi-linear product (a call recomputes
$\pi$: the cache keeps no entry above 65,536 bits). Native release build, one
call of `Decimal::sin_ctx` in decimal64 (`cos` and `tan` cost the same), `p = 53`
for the binary rows, on a quiet machine, measured at commit `bdba3fd` (2026-11-20; later
multiplication work may lower the numbers by a few percent):

| operation | seconds | instructions retired | peak memory |
| --- | --- | --- | --- |
| $\pi$ at 1,000,000 bits | 1.5 | 31.1e9 | 14.6 MB |
| $\pi$ at 2,000,000 bits | 4.5 | 119.6e9 | 20.3 MB |
| $\pi$ at 3,400,000 bits | 12.7 | 340.1e9 | 28.4 MB |
| `sin` of `1E+300000` | 3.8 | 88.3e9 | 17.2 MB |
| `sin` of `1E+600000` | 12.8 | 341.5e9 | 22.4 MB |
| `sin` of `1E+999999` | 34.9 | 936.7e9 | 33.5 MB |

The series change alone, `sin(2^k)` with $p = 53$ (origin/main before and after):

| $k$ | before, seconds | before, instructions | after, seconds | after, instructions |
| --- | --- | --- | --- | --- |
| 50,000 | 0.40 | 10.2e9 | 0.01 | 0.19e9 |
| 100,000 | 2.05 | 53.2e9 | 0.02 | 0.62e9 |
| 200,000 | 8.82 | 232.2e9 | 0.08 | 2.19e9 |
| 400,000 | 164 (loaded machine) | not measured | 0.30 | 7.78e9 |

The rows from `1E+300000` upward are in the opt-in table
`testdata/decimal/ieee/rows/huge_trig_extreme.txt`
(`python3 tools/run_huge_trig_extreme.py`); the full gate has the `1E+100000`
class.

### Asymptotically fast elementary kernels (implemented, with open items)

*Status: design and results for [#18](https://github.com/Luna-Flow/floating/issues/18).
The constants (`pi`, `ln 2`, `ln 10` by binary splitting), the `exp`
enclosure, the `ln` enclosure and the `sin` and `cos` enclosures are
implemented and merged; the AGM alternative, `tan`, and the further
reductions listed at the end of the section are design only. The measured
figures are baselines or results of the implemented part; the figures marked
"projection" come from a cost model fitted to them and are replaced by
measurements as each step lands. The final measurement of the merged kernels is
in "Measured result" below. All arguments in this section are paper arguments;
none is mechanized.*

**Problem.** Every enclosure above is built from a Taylor or artanh series
whose terms are $w$-bit numbers, so one evaluation costs
$O(w / \log w)$ full multiplications, that is $O(w\, M(w) / \log w)$. At
$w \approx 8200$ bits on the native target `exp` takes 17.8 ms, `ln` 164 ms
and `sin` 64 ms (before the fixed-point `ln` and `sin` branches), while the
$8192 \times 8192$-bit product takes 43 µs: `exp` is about 400 products.
The constants are worse when cold: `pi` takes 742 ms, `ln 2` 297 ms and
`ln 10` 146 ms at 8192 bits, which a call without a cached constant pays in
full (MPFR on the same machine: 0.09 ms for `pi`, 0.29 ms for `ln 2`).

**Options.** (1) Binary splitting of the series of a rational argument,
$O(M(w) \log^2 w)$. (2) Bit-burst: split the argument into chunks of
doubling length, evaluate the exponential of each chunk by a series with
few terms (the later the chunk, the smaller it is), multiply the results:
$O(M(w) \log^2 w)$ with binary splitting inside and, with the plain
fixed-point series inside, one cheap unbalanced product per term
(measured: $8192 \times 64$ bits 1.8 µs, $\times 1024$ bits 6.9 µs,
$\times 8192$ bits 43 µs). (3) Newton iteration for `ln` on top of `exp`.
(4) The arithmetic-geometric mean (AGM) for `ln` and `pi`,
$O(M(w) \log w)$ with large constants. (5) More halving and squaring: the
squarings cost one full product each and lose a bit each, so it does not
scale.

**Choice.** Keep the Ziv loop, its working precisions and the exact cases
untouched (see [Certified elementary functions](#certified-elementary-functions)).
Replace only the function that produces the enclosure $[L, U]$ for a given
$w$, and only from a per-target precision threshold upward. Every new
kernel is a pure function $(x, w) \mapsto [L, U]$ of exactly the type the
loop already consumes (`binary_exp_bounds`, `binary_ln_bounds`,
`binary_trigonometric_bounds`, and the constants), so `exp2`, `exp10`,
`sinh`, `cosh`, `pow`, `rootn` and the logarithm family inherit the
speed-up, and the recommended functions of
[#235](https://github.com/Luna-Flow/floating/issues/235) (`compound`, `powr`,
`exp2m1`, `exp10m1`, `log2p1`, `log10p1`, `rSqrt`, the $\pi$-scaled inverses)
are written on the same layer. A kernel returns `None` for any precondition it
cannot verify, and the caller then runs the existing path, so correctness
never depends on the new code covering a case.

*Integer enclosures.* All new kernels work on non-negative integers in
units of $2^{-F}$ with $F = w + g$, using only `BinCoeff` operations
(`mul`, `add`, `sub_checked`, shifts, `div_rem_checked`, `compare`,
`bit_length`), which exist on every target, so the same source runs on
native, LLVM, Wasm, Wasm-GC and JavaScript. A quantity $E$ is carried as a
pair $(\ell, u)$ of integers with the invariant
$\ell \le E \cdot 2^{F} \le u$. Every step produces a new pair from the old
ones by monotone operations on non-negative numbers, so the invariant is
proved step by step, and the final width $u - \ell$ is a computed integer,
not an estimate. The last step converts to
`BinFloat::make(coeff, exp, w, mode=TowardNegative / TowardPositive)`, which is
what the existing fixed-point series already does.

**Shared fixed-point toolkit.** The kernels below share one private layer,
`elementary_toolkit.mbt` (issue
[#368](https://github.com/Luna-Flow/floating/issues/368)); each piece states its
error bound once, and the kernel sections add only what is specific to their
series. The extraction is a pure refactor: every kernel returns the same
enclosure $(L, U)$ as before, bit for bit and `None` in the same cases, which
`elementary_toolkit_digest_wbtest.mbt` checks with one digest per kernel and
working precision (a corpus around every per-target threshold, the multiples of
$\ln 2$ and $\pi/2$, tiny and large arguments) against a table generated on
the kernels before the extraction.

1. *Directed conversion* (`fixed_scaled_floor`, `fixed_scaled_exact`,
   `fixed_shift`, `fixed_enclosure`). A fixed-point integer $N$ stands for
   $N / 2^{F}$. `fixed_scaled_floor` rounds toward $-\infty$ and loses less
   than one unit; `fixed_scaled_exact` is `None` unless the scaling is exact;
   `fixed_enclosure` turns an integer pair $(\ell, u)$ into floats rounded
   outward (lower end `TowardNegative`, upper end `TowardPositive`), swapping
   the ends for a negative result.
2. *Bounded cache* (`BoundedCache[V]`: `find`, `insert`, capacity as a
   parameter, oldest entry dropped first). It replaces the three ad-hoc caches
   (constants, 6 entries per constant; `exp` tables, 24 sets; factorial
   coefficients, 64 entries). A cached value is a pure function of its key, so
   a hit returns the value a recomputation returns.
3. *Term-by-term stage* (`fixed_series_step`, `fixed_exp_series`). With
   $y = N / 2^{s} < 1$, $t_0 = 2^{F}$ and
   $t_i = \lfloor \lfloor t_{i-1} N / 2^{s} \rfloor / i \rfloor$, the exact
   term $\tau_i = 2^{F} y^i / i!$ satisfies $t_i \le \tau_i < t_i + 3$ (the
   deficit $d_i$ obeys $d_i < d_{i-1} y / i + 1/i + 1$). `fixed_exp_series`
   sums until a term is below $2^{8}$ and returns the sum, the last term and
   its index; the exact value is within $t_n + 3n + 3$ above the sum. The
   fixed `exp` stage and the bit-burst `exp` stage use it with their own slack
   constants (4 and 3), and the burst `sin`/`cos` stage uses the step for the
   real and imaginary parts of $e^{iy}$. `binary_ln_unit_fixed_bounds` and
   `binary_sin_cos_fixed_series` stay apart: their recurrences are in $z^2$ and
   $x^2$ with different divisors and different tail proofs (an artanh series
   with ratio $z^2 \le 1/9$, an alternating series), not the recurrence above.
4. *Binary splitting* (`SplitState`, `split_combine`, `split_combine_t`). A
   state on $[from, to)$ is $(p, q, q\_shift, t)$ with $p = \prod p(k)$,
   $q = \prod q'(k)$, the power of two of $q(k) = q'(k) 2^{e(k)}$ kept apart in
   $q\_shift = \sum e(k)$, and $t = q\, 2^{q\_shift} \cdot$ (partial sum), merged as
   $t = t_{\mathrm{left}}\, q_{\mathrm{right}} 2^{q\_shift_{\mathrm{right}}} +
   p_{\mathrm{left}}\, t_{\mathrm{right}}$. The constants (artanh and
   Chudnovsky series) use $q\_shift = 0$, the series of $e^{N/2^s}$ uses
   $q\_shift = s$ per index from 1 (`split_exp_state`). All of it is exact
   integer arithmetic, so the partial sum is the exact rational
   $t / (q\, 2^{q\_shift})$ and the error bound of a kernel is the bound of its
   omitted tail alone. The complex stage of `sin`/`cos` (`SplitComplexState`)
   keeps its own type because it carries two components and rotates the right
   component by $i^{\mathrm{leaves}_{\mathrm{left}}}$ before the merge; it
   shares `split_combine_t` and the products of $p$, $q$ and $q\_shift$.
   `fixed_split_terms` gives the number of terms for which the omitted tail of
   $\sum N^k / (k!\, 2^{sk})$ is below two units (the proof is in its
   comment).
5. *Rectangular splitting* (`rect_plan`, `rect_powers`, `rect_sum`,
   `rect_inverse_factorials`). For a series $\sum_{i<N} c_i r^i$ with
   nonnegative integer coefficients, $r = a / 2^{F} < 2^{-k}$, $k \ge 4$, and
   $N = b m$ terms, the powers $p_j = \lfloor p_u p_v / 2^{F} \rfloor$
   ($u + v = j$) satisfy $p_j \le 2^{F} r^j < p_j + 2$. With
   $P_\beta = \sum_{j<m} c_{\beta m + j} p_j$, $\mathrm{Acc}_{b-1} = P_{b-1}$ and
   $\mathrm{Acc}_\beta = P_\beta + \lfloor p_m \mathrm{Acc}_{\beta+1} / 2^{F}
   \rfloor$, the sum satisfies $\mathrm{Acc}_0 \le 2^{F} \sum c_i r^i$ and
   its deficit $\varepsilon_\beta$, in the units of the common denominator of
   the $c_i$, obeys
   $\varepsilon_\beta < 2 \sum_j c_{\beta m + j} + 2\,\mathrm{Acc}_{\beta+1} / 2^{F} +
   1 + r^m \varepsilon_{\beta+1}$. The coefficient sequence is the parameter:
   `rect_inverse_factorials` gives $c_i = N!/i!$ for $e^r$ (deficit below 8
   units of $N!$, the constant 10 of `binary_exp_taylor_fixed`); the next
   kernels pass $c_i = D/(2i+1)$ with a common multiple $D$ (the odd
   reciprocals of $\ln$ and $\arctan$) or $N!/(2i)!$ and $N!/(2i+1)!$ (sine
   and cosine, whose alternating signs the caller splits into a positive and a
   negative series in $r^2$ with nonnegative coefficients). The block size
   minimizes a cost estimate (`rect_block_size`) and never changes a result
   bound; `rect_factorial_terms` is the term count for factorial decay.
6. *Reduction by $\ln 2$* (`fixed_exp_reduce`, `fixed_exp_finish`), the
   integer reduction and the closing units of the bit-burst and the table
   `exp`, described in the next two sections, and the chunk schedule of the
   bit-burst (`fixed_burst_chunks`), used by the `exp` and the `sin`/`cos`
   kernels.

The guard-bit constants (`binary_exp_fixed_guard_bits` 16,
`binary_exp_table_guard_bits` 16, `binary_exp_burst_guard_bits` 48 and the
64 extra bits of the `sin`/`cos` burst) stay separate on purpose: they are
tuned per kernel (they set the width of the final enclosure, which the width
checks compare with the working precision), and changing one changes the
enclosure, which this refactor must not do. The mutation hooks (`BurstMutation`, `BurstLnMutation`,
`BurstTrigMutation`) stay in the kernels, since they name the kernel's own
proof obligations.

**`exp`, by ln 2 reduction and bit-burst.** For finite $x \neq 0$ with
$|x| < 2^{30}$ (larger magnitudes are decided before the loop or fall back),
let $n = \lfloor x / \ln 2 \rfloor$, found from the cached enclosure of
$\ln 2$ at $G = F + \operatorname{bits}(n) + 2$ bits. Let $L = \lfloor 2^{G}
\ln 2 \rfloor / 2^{G}$ (a dyadic lower bound with $0 \le \ln 2 - L \le
2^{1-G}$) and $R = x - nL$, computed exactly. If $R < 0$ or $R \ge 1$ the
integer $n$ is corrected by one and $R$ recomputed. Put $R_t = \lfloor 2^{F} R
\rfloor / 2^{F}$ and $\delta = (x - n \ln 2) - R_t$. Then
$-|n|\,2^{1-G} \le \delta \le 2^{-F}$ for $n \ge 0$ (mirrored for $n < 0$), so
$|\delta| \le 2^{-F}$ by the choice of $G$, and since $0 \le R_t < 1$

$$
e^{x} = 2^{n}\, e^{R_t}\, e^{\delta}, \qquad
1 - 2^{-F} \le e^{\delta} \le 1 + 2 \cdot 2^{-F}.
$$

The factor $e^\delta$ costs at most $2 \cdot 3 = 6$ units at the end
(because $e^{R_t} < 3$), and no sign handling or reciprocal is needed because
$R_t \ge 0$.

Write $R_t = \sum_j y_j$ with $y_j = N_j / 2^{b_{j+1}}$ the bits of $R_t$ at
positions $(b_j, b_{j+1}]$ after the binary point, $0 = b_0 < b_1 < \dots$,
and $b$ growing geometrically (factor about 4, first chunk about 16 bits; the
constants are tuned per target). Then $y_j < 2^{-b_j}$, $N_j < 2^{b_{j+1} -
b_j}$, and $e^{R_t} = \prod_j e^{y_j}$.

*Stage kernel.* For $y = N / 2^{s} < 1$ let $t_0 = 2^{F}$ and
$t_i = \lfloor \lfloor t_{i-1} N / 2^{s} \rfloor / i \rfloor$ (the second floor
is absent for $i = 1$), and let $\tau_i = 2^{F} y^i / i!$ be the exact terms.
By induction $t_i \le \tau_i$ (both floors round down), and the deficit
$d_i = \tau_i - t_i$ satisfies $d_1 < 1$ and
$d_i < (d_{i-1}\, y + 1)/i + 1$, hence $d_2 < 2$ and
$d_i < 4/3 + 1 < 3$ for $i \ge 3$ (this is the argument of the
fixed-point series already in `elementary_fixed_exp.mbt`, with $y < 1$ in
place of $y \le 1/8$). Stop at the first $n$ with $t_n < 2^{8}$. For
$n \ge 1$ the ratio of consecutive exact terms is at most $y/(n+1) \le 1/2$,
so $\sum_{i > n} \tau_i \le \tau_n \cdot \frac{1/2}{1 - 1/3} < \tau_n <
t_n + 3$. With $S = \sum_{i=0}^{n} t_i$,

$$
S \;\le\; 2^{F} e^{y} \;\le\; S + t_n + 3n + 3 =: S + e_y,
\qquad e_y < 2^{8} + 3n + 3 .
$$

Then $(\ell, u) \mapsto (\lfloor \ell\, S / 2^{F} \rfloor,\; \lceil u\,(S + e_y) /
2^{F} \rceil)$ folds the stage into the running product: $e^{y}$ and the
partial product are in the stated intervals, both are non-negative, and
multiplication is monotone on non-negative numbers, so the new pair satisfies
the invariant. Each stage adds at most $e_y + 2$ units of relative width, so
with at most $J$ stages the final width is below
$J (2^{8} + 3 n_{\max} + 5) + 6$ units, about $2^{15}$ units for
$w = 8192$; $g = 48$ guard bits therefore keep the enclosure within
$2^{-(w+7)}$ relative width, which is the width of the current series. The
kernel computes the true width and returns `None` when it exceeds that bound.

*Cost.* A stage with $m$-bit numerator at position $b$ needs
$n_b \approx F / (b + \log_2 n_b)$ terms, each a product of the shrinking term
by an $m$-bit integer, a shift and a division by a one-limb integer. For
$w = 8192$ the first chunk (16 bits) needs about 880 terms, the chunk at 65 to
261 bits about 120, the chunk at 261 to 1045 bits about 31, and the last chunks
fewer than 10. The early chunks have too many terms for the fixed-point loop;
they are evaluated by **binary splitting** of $\sum_{i<n} N^i / (i!\, 2^{si})$
with exact integers $(P, Q, T)$,
$T = T_L Q_R 2^{s\,|R|} + P_L T_R$, $P = P_L P_R$, $Q = Q_L Q_R$. The enclosure
then has no accumulated rounding: $\ell = \lfloor 2^{F} T / (Q 2^{sn}) \rfloor$,
$u = \ell + 3$ once $n$ is large enough that $N^n 2^{F} < n!\, 2^{sn}$ (an
integer comparison on bit lengths), because then the tail is at most
$2\, \tau_n < 2$ units. A stage is estimated (not yet measured) at 8 to 14 full
products independent of $N$, a fixed-point stage with $n$ terms costs $n$ unbalanced
products, so the crossover per stage is at $n$ of a few tens of terms.

*Implementation (`elementary_burst_exp.mbt`).* The kernel
`binary_exp_bounds_burst` follows the construction above with these choices:
$g = 48$ guard bits; chunk boundaries at $16, 64, 256, \dots$ (first chunk 16
bits, factor 4); a chunk is evaluated by binary splitting when its term count
(from the integer bound on $2^F N^n < n!\, 2^{sn}$, using
$\log_2 n! \ge \sum_{i \le n} (\operatorname{bits}(i) - 1)$) is at least 40, and
by the fixed-point series otherwise; `ln 2` is requested at the next multiple
of 64 above $G + 2$. The reduced argument comes from one Euclidean division of
$x 2^G$ by $\lfloor 2^G \ln 2 \rfloor$, so $0 \le R < \ln 2$ with no
correction loop. The kernel declines (`None`, and the series runs) for
$|x| < 2^{-65}$ or $|x| \ge 2^{30}$, when $|n| \ge 2^{29}$ (the result
exponent would approach the limit of the exponent range), when $x$ has bits
below $2^{-G}$, and when the computed width exceeds $2^{-(w+6)}$ of the value.
(Below the table kernel's ceiling, next section, the table kernel is tried first.) It is used from a per-target working precision, kept with the coefficient
thresholds: 1024 bits on Native and LLVM, 640 on Wasm and Wasm-GC, 256 on
JavaScript (the kernel is slower than the series below roughly 1000 bits on
Native, 600 on Wasm-GC; on JavaScript it wins already at 256). The three
chunk constants were swept on Native; in a repeat on a quiet machine the chosen
point (16, factor 4, split at 40 terms) was the fastest at 8256 bits (1.5 ms
against 1.6 to 2.3 ms for the other tried settings) and within about 15 % of the
fastest at 2112 bits.

*Evidence for the `exp` kernel.* White-box tests
(`elementary_burst_exp_wbtest.mbt`): the enclosure at $w$ contains the series
enclosure at $w + 256$ for every argument the kernel accepts in a corpus of
224 values of 60 to 2000 bits with $|x|$ from $2^{-60}$ to $2^{30}$, and for
arguments next to multiples of $\ln 2$, to
$2^{29} - 1$ and to $1 - 2^{-k}$; it is no wider than the series enclosure at
$w$; and `exp_ctx` returns the same value and flags as the Ziv loop run on the
series alone, in four rounding directions. Three deliberately wrong variants
are caught by the containment test: a bias of 64 units in every stage, 40 terms
fewer in the binary-splitting stages, and `ln 2` taken with 128 bits fewer for
an argument near $2^{27}$. Two obligations are not exercised by such tests: the
slack of the fixed-point stages and the units for $\delta$ are dominated by
the much larger worst-case terms of the other stages, so an enclosure without
them still contains the value; their justification is the paper argument
above, not the tests. MPFR 4.2.2 comparison: 35,040 rows (precisions 256 to
4096, four rounding directions, arguments from $2^{-60}$ to $2^{28}$ and next
to multiples of $\ln 2$) all match; the output is byte-identical on Native,
Wasm, Wasm-GC and JavaScript; the random differential run (`elem`) agrees on
100,000 cases on Native and 20,000 on each other target.

*Measured (native, release, this machine).* Kernel only, $w = p + 64$ bits,
$x \approx 0.7$: 20 ms to 1.97 ms at 8256 bits, 3.3 ms to 0.67 ms at 4160, 594
to 220 µs at 2112, 112 to 87 µs at 1088; below 1000 bits it is slower (37 to
41 µs at 576). End to end, `just bench external quick --ops exp` paired and
alternating with `origin/main` (four rounds, the quiet ones last), floating
time per call: 8192 bits 20.2 and 20.4 ms against 1.78 and 1.69 ms (paired
ratios 9.1 to 12.1), 2048 bits 508 and 517 µs against 187 and 196 µs (2.1 to
2.7), and 53 and 512 bits unchanged within the noise of the machine (0.92 to
1.19). Against the stored MPFR reference of that tool the ratio of the
8192-bit call moves from about 95 to about 8 on the machine of the run (the
machine reads about 1.4 times slower than the stored run, so the drift
corrected values are about 66 and 5.6).

*Ceiling.* At 8192 bits the kernel takes the time of 35 to 45 full-size products
(43 µs each) and spends most of it in products and divisions of $w$-bit
numbers. With a
multiplication and division kernel three times faster, and everything else
unchanged, a first estimate (not measured) is 0.6 to 0.8 ms at 8192 bits and
60 to 80 µs at 2048 bits, which is about 3 to 4 times the MPFR reference
(213 µs and 17 µs). The remaining gap would be allocation and the small-integer
steps of the fixed-point stages.

**`exp`, by tables and rectangular splitting (medium precision).** Below
a per-target working precision (1536 to 3072 bits, see below) the enclosure of
$e^x$ comes from `binary_exp_bounds_table` (`elementary_table_exp.mbt`), the
scheme of Johansson, *Efficient implementation of elementary functions in the
medium-precision range*, ARITH 22 (2015), arXiv:1410.7176, on the integer
arithmetic of `BinCoeff`. Let $F = w + g$ rounded up to a multiple of 64
($\ge 128$; multiples of 256 above 1024), so $g \ge 16$. The reduction to
$R_t = \lfloor 2^F R \rfloor / 2^F \in [0, \ln 2)$ and the residual factor
$e^{\delta}$ are those of the bit-burst kernel above (3 units below, 6 above
in units of $2^{-F}$, valid because $e^{R_t} < 3$), the very code of
`fixed_exp_reduce` and `fixed_exp_finish` (toolkit piece 6). The Taylor series
of the remainder is the rectangular splitting of toolkit piece 5 with the
coefficients $N!/i!$; its error bound is stated there and not repeated below. Then, with
$K = k_1 + k_2$ ($(k_1,k_2) = (7,7)$ for $F \le 256$, $(6,6)$ up to 1024,
$(6,5)$ above),

$$
R_t = \frac{j_1}{2^{k_1}} + \frac{j_2}{2^{K}} + r,\qquad
j_1 = \lfloor 2^{k_1} R_t \rfloor,\quad
j_2 = \Bigl\lfloor 2^{K}\bigl(R_t - \tfrac{j_1}{2^{k_1}}\bigr)\Bigr\rfloor,\quad
0 \le r < 2^{-K},
$$

all three parts exact multiples of $2^{-F}$, so $e^{R_t} = T_1[j_1]\, T_2[j_2]\,
e^{r}$ with $T_1[j] = e^{j/2^{k_1}}$ ($j \le \lfloor 2^{k_1} \ln 2 \rfloor$) and
$T_2[j] = e^{j/2^{K}}$ ($j < 2^{k_2}$).

*Tables.* Built lazily, one set per value of $F$ (at most 24 sets are kept),
each entry an integer enclosure $L \le 2^{F} e^{j/2^k} \le H$ taken from the
certified kernels already in the library (`binary_exp_bounds_untabled`, the
bit-burst or series path, at $F + 8$ bits): $L = \lfloor 2^F \cdot \mathrm{low}
\rfloor$, $H = \lfloor 2^F \cdot \mathrm{high} \rfloor + 1$. A table is therefore
as certified as the kernels it comes from, and a test recomputes every entry of
two table sets from the series at $F + 256$ bits. The tables are not hard-coded.

*Taylor series of $r$.* Write $r = a / 2^F$, $0 \le a < 2^{F-K}$ (so
$r < 2^{-K}$, $K \ge 11$ in the shapes above). The number of terms $N$ is the
least with $K N + \sum_{i \le N} (\operatorname{bits}(i) - 1) \ge F + 1$; as
$N! \ge 2^{\sum (\operatorname{bits}(i)-1)}$ and the ratio of consecutive terms
is below $1/2$, the tail satisfies $\sum_{i \ge N} r^i/i! \le 2 r^N/N! \le
2^{-F}$: at most one unit. The sum is evaluated by the rectangular
(Paterson–Stockmeyer) splitting of toolkit piece 5, with $N$ rounded up to
$N' = b m$, the integer coefficients $C_i = N'!/i!$ (computed once per $N'$) and
one final division, $E = \lfloor \mathrm{Acc}_0 / N'! \rfloor$; the powers
$p_j$ and the recurrence for $\mathrm{Acc}_\beta$ are those defined there, with
$e_j := 2^F r^j - p_j < 2$ (so $e_0 = e_1 = 0$).

*Error of the series.* The exact counterpart is $\mathrm{Acc}^*_0 = N'!\, 2^F
\sum_{i<N'} r^i/i!$, and every computed quantity is a lower bound of its exact
counterpart. Let $\varepsilon_\beta = \mathrm{Acc}^*_\beta - \mathrm{Acc}_\beta$
in units of $N'!$. The deficit of $P_\beta$ is $\sum_{j\ge 2} C_{\beta m+j}
e_j / N'! < 2 \sum_{j \ge 2} 1/(\beta m + j)! \le 2(e - 2) < 1.44$ ($e_0 = e_1
= 0$). In the Horner step the error of $p_m$ contributes $e_m
\mathrm{Acc}^*_{\beta+1} / (2^F N'!) < 2 e^{r} < 3.4$ (because
$\mathrm{Acc}^*_{\beta+1} \le N'!\, 2^F e^{r}$), the propagated error
$p_m \varepsilon_{\beta+1} / 2^F < \varepsilon_{\beta+1}/16$, and the floor less
than one unit. So $\varepsilon_\beta < 1.44 + 3.4 + 1 + \varepsilon_{\beta+1}/16$,
whence $\varepsilon < 6.2 \cdot 16/15 < 7$ for every block. The final floor
loses less than one more unit, and the tail at most one:

$$
E \;\le\; 2^F e^{r} \;<\; E + 10 .
$$

*Assembly.* With the table entries (already in units of $2^{-F}$),
$\mathrm{low} = \lfloor \lfloor L_1 L_2 / 2^F \rfloor E / 2^F \rfloor - 3$ and
$\mathrm{high} = \lfloor \lfloor H_1 H_2 / 2^F \rfloor + 1) (E + 10) / 2^F
\rfloor + 1 + 6$. All factors are positive, so the floor-and-add-one products
are monotone enclosures; the final enclosure is then rounded outward to $w$
bits. The kernel declines (the older paths run) in the same cases as the
bit-burst kernel ($|x| < 2^{-65}$, $|x| \ge 2^{30}$, $|n| \ge 2^{29}$, $x$ with
bits below $2^{-G}$) and when the width exceeds $2^{-(w+6)}$ of the value. The
width of the enclosure is a few dozen units of $2^{-F}$ (the series 10, the
tables 2 each, the reduction 9, the products another factor up to 2), far
below the $2^{F-w-6}$ units the check allows.

*Why results are bit-identical.* The kernel only supplies an enclosure of $e^x$
to the Ziv loop of `exp_ctx` and of the functions built on it (`exp2`, `exp10`,
`expm1`, `pow`, `compound`, `powr`, the hyperbolic functions, the decimal
elementary functions). Correct rounding is unique, so any valid enclosure gives
the same value and flags; a different enclosure can only change how many
precision steps the loop takes. The proof obligation is therefore exactly the
validity of the enclosure, which the analysis above establishes and the
white-box tests check against the series at $w + 256$ bits.

*Evidence.* `elementary_table_exp_wbtest.mbt`: containment of the series
enclosure at $w + 256$ for up to 256 arguments of $2^{-60}$ to $2^{30}$ at working
precisions 53 to 1000, positive and negative; arguments equal to table nodes
$j/2^{k_1}$, $j/2^K$ and one unit below and above them (remainder at or
just off a table boundary); multiples of $\ln 2$ up to $n = 10^6$;
the Taylor stage on $a \in \{0, 1, 2, 2^{F-K} - 1, 2^{F-K-1}, \text{random}\}$ at
$F$ from 80 to 2100 with its width at most 10 units; every entry of two table
sets; declined arguments. 

*Measured (release, this machine, kernel only, $x \approx 0.7$).* Native:
53 bits 7 µs against 10 µs for the series; 100 bits 2.5 against 5.6; 300 bits
4.9 against 12.6 (bit-burst 24); 1000 bits 20 against 42 (burst 69); 2000 bits
94 against 111 (burst 143); 3000 bits 245 against 208. The crossovers (table
kernel first up to 1792 bits on Native and LLVM, 2048 on Wasm, 1536 on Wasm-GC,
3072 on JavaScript) are per-target constants beside the bit-burst threshold.
Above them the bit-burst kernel (from its own threshold) and the series
are unchanged. The cost of the table kernel is dominated by a few
dozen `BinCoeff` operations of 100 to 250 ns each at these sizes, and by the
size of the integer coefficients $N'!/i!$ above 2000 bits, which is why it
loses there.

**`ln`, by verified Newton step.** Write $v = m\, 2^{k}$ with
$m \in [2^{-1/2}, 2^{1/2})$, so $\ln v = k \ln 2 + \ln m$. Take any dyadic
$y_0$ with about $w/2 + 16$ bits (from the same function at half the
precision, recursively, down to the existing series). Correctness does not
depend on how good $y_0$ is, only the speed does. Let $[E_\ell, E_u]$ be the
enclosure of $e^{y_0}$ from the kernel above and
$q_\ell = m / E_u$, $q_u = m / E_\ell$ (directed divisions). Since
$\ln$ is monotone, $\ln m = y_0 + \ln(m / e^{y_0}) \in y_0 + [\ln q_\ell, \ln q_u]$,
and for $|u| \le 1/2$ one has $u - u^2 \le \ln(1 + u) \le u$, so

$$
\ln m \in \bigl[\, y_0 + (q_\ell - 1) - (q_\ell - 1)^2,\;\; y_0 + (q_u - 1) \,\bigr]
$$

whenever $|q_\ell - 1|, |q_u - 1| \le 1/2$ (checked at run time, else `None`).
If $|\ln m - y_0| \le 2^{-(w/2+8)}$ the quadratic term is below
$2^{-(w+14)}$ and the width is that of $E$. Adding $k \ln 2$ uses the exact
integer product of $k$ with the dyadic bounds of $\ln 2$. For $|m - 1| <
2^{-16}$ the existing artanh series has $O(w/16)$ terms and stays in use. The
cost is that of one `exp` at $w$ plus the recursive call at about $w/2$
(about $1.5$ times one `exp` in total) plus two divisions. Projection at
8192 bits: 3 to 6 ms, against 164 ms today (41 ms projected for the fixed-point
branch).

*Implementation of the `ln` step (`elementary_burst_ln.mbt`).*
`binary_ln_unit_burst_bounds` encloses $\ln v$ for $1 + 2^{-16} < v \le 2$
(the unit enclosure that `binary_ln_bounds` adds $k \ln 2$ to). With
$\mathrm{inner} = w + \max(0, 2 - \operatorname{top}(v - 1))$ bits, so that an
argument near 1 keeps $w$ significant bits of the result, $y_0$ is the lower
end of the enclosure of $\ln v'$ at $\mathrm{inner}/2 + 16$ bits, where $v'$ is
$v$ rounded to that many bits (the same function one level down, so the
recursion ends in the series below the threshold); $[E_\ell, E_u]$ is the `exp`
kernel at $\mathrm{inner} + 8$ bits; the two divisions and the final
operations use $\mathrm{inner} + 24$ bits with directed rounding, and the result
is rounded outward to $w$ bits. It declines (and the series runs) for
$v \le 1 + 2^{-16}$ or $v > 2$, when $|q - 1| > 1/2$, and when the width of the
result exceeds 8 units of $2^{-\mathrm{inner}}$. The thresholds, kept with the
other coefficient-kernel thresholds, are 1152 bits on Native and LLVM, 1280 on
plain Wasm and on JavaScript and 576 on Wasm-GC (the kernel is slower than the
fixed-point series below roughly 1000 bits on Native, 500 on Wasm-GC and 1200 on
Wasm and JavaScript).

*Evidence for the `ln` step.* White-box tests
(`elementary_burst_ln_wbtest.mbt`): for every argument of a corpus of 158
values in $(1, 2]$ (random, near 1 down to $2^{-100}$, near 2, 3/2, 5/4) that the
kernel accepts, the enclosure at $w$ contains the series enclosure at $w + 256$;
it is no wider than the series enclosure at $w$; `ln_ctx` returns the same value
and flags as the Ziv loop on the series alone in four rounding directions; and
the kernel declines out of range. Two deliberately wrong variants are caught:
a bias of 8 units in the lower end, and a poor start value (about $w/8$ bits)
with the quadratic term dropped. A poor start value with the quadratic term
kept only widens the enclosure and the test checks that it is still valid. One
obligation is not reached by the tests: dropping the quadratic term with the
real start value is not detected, because $u^2 \approx 2^{-(w+26)}$ is below the
width of the `exp` enclosure; its justification is the paper argument
($u - u^2 \le \ln(1+u)$ for $u \ge -1/2$), not the tests. MPFR 4.2.2
comparison: 13,200 rows (precisions 256 to 4096, four rounding directions,
arguments with binary exponents from $-1000$ to $10^5$, near 1 and near
powers of two; the threshold was set to 256 for this run so that every row used
the kernel) all match, and the output is byte-identical on Native, Wasm, Wasm-GC
and JavaScript.

*Measured for the `ln` step (native, release, this machine, on the 64-bit limbs,
the Karatsuba and the division of #324, #326 and #328).* Kernel only,
$w = p + 64$ bits, $v$ random in $[1, 2)$, against the fixed-point series of #319
(the machine was loaded, the ratios are the figure): 23.0 ms to 2.24 ms at 8256
bits (10.3 times), 3.27 ms to 0.75 ms at 4160 (4.4), 581 to 309 µs at 2112 (1.9),
equal at 1024; slower below about 1000 bits (0.5 to 0.8 times at 384 to 768).
End to end, `just bench external quick --ops ln` paired and alternating with
`origin/main`, four rounds on a loaded machine (load average about 10), the
floating time per call: 8192 bits 27.0, 25.6, 25.6 and 28.0 ms against 2.43,
2.40, 2.57 and 2.44 ms (paired ratios 11.1, 10.7, 10.0 and 11.5), 2048 bits 695,
565, 639 and 856 µs against 300, 295, 378 and 365 µs (2.3, 1.9, 1.7 and 2.35),
512 and 53 bits unchanged (0.98 to 1.07 at 53 bits, 0.99 to 1.36 at 512 bits,
where the code path is the old one and the machine was noisy). The raw ratio to the
stored MPFR medians (floating time of the day over the stored MPFR median) of the
8192-bit call goes from 221 to 243 to 21 to 22, and of the 2048-bit call from 37
to 57 to 20 to 25. MPFR re-measured on the machine at that time reads 1.9 to 2.0
times slower than the stored run at 8192 bits and 1.65 times at 2048 bits (the
load), so the drift-corrected ratios are about 10.7 to 11.4 at 8192 bits and
about 12 to 15 at 2048 bits; an earlier run on a quiet machine gave
11.5 to 13.6 at 8192 bits (on the previous division kernel).

*AGM alternative.* $\ln s = \pi / (2\, \mathrm{AGM}(1, 4/s)) - m \ln 2$ for
$s = v\, 2^{m} > 2^{w/2}$ costs about $\log_2 w$ iterations of one product and
one square root. With today's kernels (`sqrt_ctx` 128 µs, product 43 µs at
8192 bits) this is 2.7 to 3.2 ms, no better than the Newton step within the
model's error, because our square root is 29 times and our product 13 times
slower than MPFR's (4.4 and 3.2 µs on the same machine, secondary evidence).
It also needs a rigorous bound for the truncation error of the formula (the
$O(s^{-2})$ term, derived from the theta-function formula
$\ln(1/q) = \pi / \mathrm{AGM}(\theta_2^2(q), \theta_3^2(q))$, attributed to
Sasaki and Kanada, see the evidence note at the end of this section[^brent-agm]),
which this page does not yet provide. It is therefore the second choice,
taken up only if the Newton step measures slower than the projection.

**`sin` and `cos`, by complex bit-burst.** With $H = \lfloor 2^{G} \pi/2
\rfloor / 2^{G}$, $G = F + \operatorname{bits}(n) + 2$, the quadrant integer
$n = \operatorname{round}(x / H)$ and $R = x - nH$ (exact, $|R| \le 0.8$ after
a correction of $n$), the true reduced argument $r = x - n \pi/2$ satisfies
$|r - R| \le |n|\,2^{1-G} \le 2^{-F}$. Sine and cosine are 1-Lipschitz, so
$\sin r \in \sin R \pm 2^{-F}$ and likewise for the cosine; truncating
$|R|$ to $F$ bits costs one more unit. The quadrant $n \bmod 4$ maps
$(\sin r, \cos r)$ to the result, as in `binary_reduced_trigonometric_bounds`.
For $y = N/2^s < 1$ the real and imaginary parts of the series of
$e^{iy}$ are the even and odd terms of the same sequence $t_i$ as above, with
signs $(-1)^{\lfloor i/2 \rfloor}$, so a stage costs the same as an `exp` stage
and gives both $\cos y$ and $\sin y$. The deficits satisfy the same bound
$d_i < 3$, and each of the two alternating series has terms that decrease in
size ($y^2 / ((i+1)(i+2)) < 1$), so the tail after $t_n < 2^{8}$ is at most
$t_n + 3$ in size and the enclosure is $S_{\mathrm{cos}}$ or $S_{\mathrm{sin}}
\pm (t_n + 3n + 3)$. Stages are folded by rotation,
$(C, S) \leftarrow (C c - S s,\; S c + C s)$, with four products and interval
bounds on non-negative integers; all partial angles lie in $[0, 0.8]$, so all
four factors are non-negative and the difference of bounds is checked to be
non-negative. Because the merge costs four full products per stage, the stages
are fewer than for `exp` (factor 4 to 8 between chunk boundaries), and the last
stage computes only the requested one of the two values. For $|R| < 2^{-16}$
the existing series stays. Projection at 8192 bits: 4 to 6 ms, against 64 ms
today (16 ms projected for the fixed-point branch); `tan` and the
$\pi$-scaled functions follow.

*Implementation of the `sin` and `cos` step (`elementary_burst_trig.mbt`).*
`binary_trig_bounds_burst` (hooked into `binary_trigonometric_bounds` for `sin`
and `cos`; `tan` keeps the series) follows the construction above for
$2^{-64} \le |x| < 2^{4096}$. With $F_0 = w + 112$ and
$G = F_0 + \max(1, \operatorname{top}(x)) + 2$, the nearest integer $n$ to
$|x| / H$, $H = \lfloor 2^{G} \pi/2 \rfloor / 2^{G}$, comes from one Euclidean
division of integers, $R = |x| - nH$ is exact with $|R| \le H/2$, and the
true reduced argument $r = |x| - n\pi/2$ satisfies
$|r - R| \le n\, 2^{1-G} \le 2^{-(F_0+1)}$. The working scale is
$F = w + 48 + \mathrm{lz}$ with $\mathrm{lz} = \max(0, 2 - \operatorname{top}(R))$
(declined above 64, so $R$ near a multiple of $\pi/2$ keeps $w$ significant
bits of a sine), and $R_t = \lfloor 2^{F} |R| \rfloor / 2^{F}$ satisfies
$|r - \operatorname{sign}(R) R_t| \le 1.5 \cdot 2^{-F}$, so by the Lipschitz
bound the sine and cosine of $r$ are within 2 units of those of
$\operatorname{sign}(R) R_t$. $R_t$ is cut into chunks at 16, 64, 256, ... bits as
for `exp`. A chunk is a *ball*: a midpoint and a radius in units of $2^{-F}$.
The fixed-point stage sums the even terms of the series of $e^{iy}$ for the
cosine and the odd ones for the sine, with signs $+ - + - \dots$ in each, from
the same sequence $t_i$ as in the `exp` stage (deficit below 3); each of the two
alternating series decreases in size, so each sum is within $3n + t_n + 3$ of
its value. The binary-splitting stage keeps a complex state: the leaf of an index
$i \ge 1$ is $(0, N)$ (the factor $i N$), $p = N^{\mathrm{leaves}}$,
$q = \prod i$, and
$t = t_L q_R 2^{s\,\mathrm{len}_R} + i^{\mathrm{leaves}_L} p_L t_R$, where
multiplying by $i^m$ only permutes and negates the two components; the partial
sums are exact rationals, the floors lose less than 1 unit, and the omitted
terms are below 2 units, so each part is a ball of radius 2. The product of two
balls with midpoints $a, b$ and radii $\alpha, \beta$ has midpoint
$\lfloor a b / 2^F \rfloor$ and radius
$\lceil (a \beta + b \alpha + \alpha \beta)/2^F \rceil + 2$, and the stages are
folded by rotation, $C' = C c - S s$ and $S' = S c + C s$ (four ball products;
the first stage is not multiplied at all), with the midpoint of the difference
required to be non-negative. The quadrant $n \bmod 4$ and the signs of $x$ and
$R$ select which component is the result. It declines for $|x| < 2^{-64}$,
$|x| \ge 2^{4096}$, when the reduced argument is smaller than $2^{-62}$, and
when the width exceeds $2^{-(w+5)}$ of the value. The thresholds are 1536 bits on
Native and LLVM, 2112 on plain Wasm, 640 on Wasm-GC and 256 on JavaScript (the
kernel is slower than the series below roughly 1500 bits on Native, 2000 on
Wasm and 600 on Wasm-GC; on JavaScript it wins from 256).

*Evidence for the `sin` and `cos` step.* White-box tests
(`elementary_burst_trig_wbtest.mbt`): for every argument the kernel accepts
in a corpus of 354 values (60 to 2000 bits, $|x|$ from $2^{-60}$ to $2^{100}$,
both signs, and the neighbourhood of nine multiples of $\pi/2$ for four
precisions) and for both functions, the enclosure at $w$ contains the series
enclosure at a precision 256 bits higher (and high enough for the series to
certify the quadrant); it is no wider than the series enclosure; `sin_ctx` and
`cos_ctx` return the value and flags of the series enclosure rounded at twice
the precision, in four rounding directions; and the kernel declines out of its
range. Three deliberately wrong variants are caught: a bias of $2^{64}$ units in
every stage, 40 terms fewer in the binary-splitting stages, and $\pi$ taken with
200 bits fewer for an argument near $2^{40}$. A bias below about $2^{40}$ units
is absorbed by the 48 guard bits and the final rounding, so the tests cannot see
it; likewise the radius of the fixed-point stages and the 2 units of the angle
error are dominated by worst-case terms elsewhere, so removing them leaves an
enclosure that still contains the value: their justification is the paper
argument above, not the tests. MPFR 4.2.2 comparison: 23,424 rows for each of
`sin` and `cos` (precisions 256 to 4096, four rounding directions, arguments from
$2^{-60}$ to $2^{1000}$, and neighbours of multiples of $\pi/2$; the thresholds
were set to 256 for this run so that every row used the kernel) all match, and
the output is byte-identical on Native, Wasm, Wasm-GC and JavaScript.

*Measured for the `sin` and `cos` step (native, release, this machine, with the
Karatsuba limbs and the division of #326 and #328).* Kernel only, $w = p + 40$
bits, $x \approx 0.7$ for the sine and $x \approx 16$ to $32$ for the cosine, against the
reduction and fixed-point series of #321: sine 8.37 ms to 1.39 ms at 8256 bits,
1.58 ms to 0.57 ms at 4160, 338 to 239 µs at 2112, equal at 1536; cosine
5.31 ms to 1.20 ms at 8256, 1.01 ms to 0.47 ms at 4160; slower below about
1500 bits (0.5 to 0.9 times at 256 to 1280). End to end,
`just bench external quick --ops sin` paired and alternating with
`origin/main`, four rounds on a quiet machine, floating time per call: 8192 bits
6.92, 6.66, 6.73 and 6.66 ms against 1.47, 1.32, 1.29 and 1.38 ms (paired
ratios 4.7, 5.1, 5.2 and 4.8), 2048 bits 282, 288, 276 and 268 µs against 203,
195, 183 and 204 µs (1.4, 1.5, 1.5 and 1.3), and 512 and 53 bits unchanged
(0.89 to 1.12, the old code path). The raw ratio to the stored MPFR medians
(floating time of the day over the stored MPFR median) of the 8192-bit call goes
from 34 to 35 to 6.5 to 7.4, and of the 2048-bit call from 19 to 20 to 13 to 14;
the machine reads about 1.45 times slower than the stored run (MPFR re-measured on
it), so the drift-corrected ratios are about 4.5 to 5.1 at 8192 bits and about
9 to 10 at 2048 bits.

**Constants by binary splitting.** `pi`, `ln 2` and `ln 10` are computed once
per working precision and cached, but a first call pays the cold cost above.
Binary splitting gives $O(M(w) \log^2 w)$ with rigorous bounds:

$$
\pi = \frac{426880\sqrt{10005}\, Q}{T}, \qquad
\ln 2 = 18\,\operatorname{artanh}\tfrac1{26} - 2\,\operatorname{artanh}\tfrac1{4801}
+ 8\,\operatorname{artanh}\tfrac1{8749}, \qquad
\ln 10 = 3 \ln 2 + 2\operatorname{artanh}\tfrac19 ,
$$

where $(P, Q, T)$ come from the Chudnovsky series (alternating, about 46
bits per term) and $\operatorname{artanh}(1/k) = \sum_j 1/((2j+1)k^{2j+1})$.

*Implementation (`elementary_constants_split.mbt`).* The state of a series on
an index range is $(p, q, t)$ with $p = \prod p(k)$, $q = \prod q(k)$ and
$t = q \cdot (\text{partial sum})$, combined as
$t = q_R t_L + p_L t_R$; the `artanh` series has $p(j) = 2j - 1$ and
$q(j) = (2j + 1) k^2$, which telescope to $1/((2j+1) k^{2j})$, and the
Chudnovsky series has $p(k) = (6k-5)(2k-1)(6k-1)$,
$q(k) = k^3\, 640320^3 / 24$ and the leaf $t = \pm p(k)(A + Bk)$. Only the
Chudnovsky $t$ is signed, so a sign-and-magnitude wrapper over the unsigned
`BinCoeff` suffices and the code is the same on every target. The partial sum
$t/q$ is exact; the only roundings are the final directed divisions and
$\sqrt{10005}$ (directed `sqrt_ctx`), done at $w + 16$ bits, and the result is
rounded outward to $w$ bits.

*Tail bounds.* For $\operatorname{artanh}(1/k)$ with $K = k^2$ take
$N$ terms with $K^N \ge 2^{F+9}$, $F = w + 16$ (using
$\lfloor \log_2 K \rfloor$): the first omitted term is at most
$2^{-(F+9)}$ and the omitted terms are positive and shrink by at least $1/K \le
1/4$, so they sum to less than $2^{-(F+8)}$, which is added to the upper end.
For Chudnovsky the ratio of the factorial parts of consecutive terms is
$8(6k+1)(6k+3)(6k+5)/(k+1)^3 \le 1728$, the linear factor grows by at most
41.11 from $k = 0$ to $1$ and by less than 2 after that, and
$640320^3 > 2^{57.8}$, so the ratios are below $2^{-41.7}$ and then $2^{-46.1}$,
the terms decrease in size, alternate in sign, and the first is below $2^{24}$.
The omitted sum from index $N$ is therefore at most the size of term $N$, below
$2^{-17 - 46(N-1)}$, which is at most $2^{-(F+4)}$ for $N = \lfloor F/46
\rfloor + 3$. Then $S \in [(t - e)/q, (t + e)/q]$ for the integer
$e = \lfloor q / 2^{F+4} \rfloor + 1$, and $\pi$ is enclosed by dividing
$426880 \sqrt{10005}\, q$ by $t \pm e$ with directed rounding. The
identities were checked numerically to 60 digits.

*Evidence.* Tests (`elementary_constants_split_wbtest.mbt`): the new enclosure
at $w$ contains the old series enclosure at $w + 256$ (an independent
computation) for $w$ from 64 to 1024; it is no wider than the old enclosure at
$w$ up to 2048; enclosures at $w$ and $w + 300$ nest up to 20000 bits; and
removing terms (a test hook) makes the containment test fail, so the tail
count is checked and not just assumed. A one-off comparison against MPFR 4.2.2
(`mpfr_const_pi`, `mpfr_const_log2`, `mpfr_log(10)` at $2w + 64$ bits) at 64,
100, 257, 1000, 4096, 8192, 30000 and 100000 bits found every enclosure
containing the MPFR value, one to two units of the last place wide. All
`bin_float` tests pass on native, wasm, wasm-gc and js, `just pr` passes, and
30000 (native) and 10000 (each of wasm, wasm-gc, js) random `elem` cases agree
with MPFR.

*Measured (native, release, cold enclosure at $w = p + 64$, this machine).*
`pi` 449 ms to 0.67 ms at $p = 8192$, 14 ms to 71 µs at 2048, 0.93 ms to 15 µs
at 512; `ln 2` 178 ms to 1.33 ms, 5.6 ms to 156 µs, 0.36 ms to 32 µs;
`ln 10` (with `ln 2` cached) 89 ms to 0.99 ms, 2.8 ms to 114 µs, 0.18 ms to
26 µs. At $p = 64$ the splitting is already 3 to 19 times faster, on wasm-gc
and js as well (js at 8192 bits: `pi` 0.63 ms, `ln 2` 0.67 ms), so the
threshold `binary_constants_split_min_precision` is 64 on every target. Warm
(cached) calls are unchanged. A first `sin` or `ln` at 8192 bits used to pay
the series cost on top of the warm time (about 450 ms for `pi`, about 180 ms
for `ln 2`); now a cold call costs at most about 7 ms more than a warm one
(`sin` 53.4 ms cold against 53.6 ms warm, `ln` 101.9 ms against 94.3 ms at
8192 bits).

The cache itself is unchanged. The design asks for requests for `ln 2` at a
canonical precision (the next multiple of 64 above
$F + \operatorname{bits}(n) + 2$) so that `exp`, `ln` and the trigonometric
reduction share entries instead of evicting each other; that belongs to the
`exp` kernel, which is the first caller with such an irregular precision, and
is not part of the constants step.

**Working-precision schedule and the Ziv loop.** The attempt precisions
$w_0 = p + 64$, $w_{i+1} = w_i + \max(32, \lfloor w_i/2 \rfloor)$ and the
budget of 12 attempts are unchanged. Each attempt picks the old or the new
kernel by comparing $w$ with a per-target constant and, for `ln` and the
sine, by the argument (the near-1 and tiny-argument cases above); a kernel that
returns `None` or an enclosure wider than the old series' falls through to the
old kernel at the same $w$. So an attempt never certifies less than before, and
the exact cases, the tiny-argument measures, the inner-endpoint rounding and
the flag argument of the loop are untouched. The result of a call is the
correctly rounded value whenever either path certifies, hence identical to the
current result; they can differ only in which inputs exhaust the budget, which
the corpus comparison below counts. The faster attempts make a longer budget
affordable, which is the point of
[#15](https://github.com/Luna-Flow/floating/issues/15): the limit is a policy
of the loop and does not interact with the kernels.

**Allocation and targets.** `BinCoeff` values are immutable, so each term of
a fixed-point stage allocates four arrays of up to $w/32$ limbs (product,
shift, quotient, sum); on native these are included in the measured unit costs
above (shift 0.2 µs, one-limb division 1.5 µs, addition 0.3 µs at 8192 bits).
A fused in-place multiply-shift-divide loop on a mutable limb array would
remove most of that for the non-JavaScript targets, and is a later optimization
behind the same function, not part of the design. On JavaScript `BinCoeff` is a
`bigint`: products, shifts and divisions are the engine's, with a larger
constant per operation and an asymptotically faster product, so the stage
boundaries and every threshold are measured separately on native, LLVM, Wasm,
Wasm-GC and JavaScript and kept next to the coefficient-kernel thresholds. The
source of the kernels is shared; only the constants differ.

**Evidence the new path must produce.** Each kernel carries its own
invariant tests: containment of the enclosure of the old path at $w + 256$
bits in the new enclosure at $w$ (an independent computation), the width bound,
and boundary cases (arguments at chunk boundaries, $R$ near $0$ and $1$, the
corrections of $n$, huge $|n|$, tiny and near-1 arguments). The end-to-end
check compares every result bit for bit with the old path and with MPFR on a
seeded random corpus plus the existing boundary corpus on all four targets,
and a deliberately biased kernel (one unit too narrow) must make the tests fail.

**Limits of the speed-up.** The model reaches algorithmic parity with MPFR
(`exp` at 8192 bits is about 65 to 100 products in MPFR and, projected, about
50 to 80 here), so
the remaining gap is the product kernel: 43 µs against 3.2 µs at 8192 bits,
a factor 13 (4 µs against 0.31 µs, a factor 12, at 2048 bits). Ratios to MPFR
at 8192 bits in the same run (MPFR: `exp` 326 µs, `ln` 177 µs, `sin` 291 µs):
today 55, 930 and 220; projected from this design about 6 to 11 for `exp`, 17
to 34 for `ln` and 14 to 21 for `sin`. A ratio below 10 at 8192 bits is
therefore within reach for `exp` only if the product kernel also improves.

**Measured result.** On main `8badc55` (all four kernels merged), Apple M4,
native, release, load average 1.3 to 3, three runs of
`just bench external quick --ops exp ln sin --binary-precisions 2048 8192` agreeing within
1 to 10 %, and a second check on `952600f` within 3 %: floating time over the
stored MPFR median is 6.0 to 6.6 (`exp`), 12.5 (`ln`) and 12.2 (`sin`) at 2048
bits, and 3.2 (`exp`), 10.6 (`ln`) and 5.8 (`sin`) at 8192 bits. The MPFR time
measured on the same machine at the same moment was within 6 % of the stored
one, so raw and drift-corrected ratios differ by at most 6 %. Two cells are
below 10 times MPFR; `ln` at 2048 and 8192 bits and `sin` at 2048 bits are above
it. This is one machine and the native target only: the Wasm, Wasm-GC and
JavaScript targets were not compared with MPFR. The projections above are
superseded by these numbers; the remaining gap is the multiplication and
division kernel and allocation, not the algorithm.

**Evidence checked and still to confirm.** The references were checked against
the sources on 2026-11-19. Brent, *J. ACM* 23(2), 1976, 242-251, exists as cited,
but it contains the AGM and ascending Landen transformation methods with cost
$O(M(n)\log n)$ (the logarithm by Landen transformations of incomplete elliptic
integrals); it contains neither bit-burst nor theta functions, nor the nome, and
it credits the $O(M(n)\log^2 n)$ bound to Brent, "The complexity of
multiple-precision arithmetic" (Proc. Seminar on Complexity of Computational
Problem Solving, 1975, pp. 126-165), which was not read. So the footnote below
supports the AGM logarithm only, and the bit-burst attribution is to be
replaced by that 1975 paper (not yet read). The formula with the theta
functions, $\ln(1/q) = \pi / \mathrm{AGM}(\theta_2^2(q), \theta_3^2(q))$, is
attributed to Sasaki and Kanada, *J. Inf. Process.* 5(4), 1982, 247-250, on the
authority of later notes by Brent (secondary sources); its normalization of the
nome (Brent's notes use $q^4$ and point out a typo in the $q$ form of the
Borwein book) and its truncation bound have not been checked against the
original, which the owner will obtain. Nothing in the design or in the code
depends on them (the AGM is not used until its truncation bound is derived and
proved here). The 1-ulp and 2-ulp widths quoted above come from the MPFR
comparison, which is secondary evidence for the enclosures; the proof is the
integer-bound argument in this section.

[^brent-agm]: R. P. Brent, "Fast multiple-precision evaluation of elementary
    functions", *J. ACM* 23(2), 1976 (bit-burst and the AGM logarithm; citation
    to be confirmed against the paper). The
    sharp truncation bound has to be derived from the theta series before the
    AGM is used. MPFR's `log.c` documents the same algorithm and is secondary
    evidence only.

### The coefficient kernel

**Problem.** Precision costs integer multiplication and division of
$p$-bit numbers, and $p$ ranges from 1 to $2^{28}$.

**Choice.** The kernel is the internal package [`internal/bin_kernel`](internal/bin_kernel.md); `BinCoeff` is a newtype over its `Coeff`. `Coeff` stores up to 128 bits inline and larger values as
little-endian 64-bit limbs (a host `bigint` on JavaScript), and dispatches on
the operand length $n$ in 64-bit limbs. Every threshold below is in 64-bit
limbs:

| Product or square | Native, LLVM | Wasm, Wasm-GC |
| --- | ---: | ---: |
| schoolbook product below | 32 | 32 |
| Karatsuba product from | 32 | 32 |
| Karatsuba product on 32-bit limbs from | never | 160 |
| Karatsuba square from | 36 | off |
| square on 32-bit limbs from | never | 80 |
| Toom-3 product from (balanced, where the NTT does not fit) | 4096 | 2048 |
| two-prime NTT product from | 4096 | 2048 |
| NTT square from | 3584 | 1536 |

LLVM takes the Native values, which are unmeasured there. A product with
$m > 2n$ limbs is cut inside the Karatsuba into $n$-limb blocks; a short
operand against a long one beyond the NTT cutoff uses the NTT overlap-add.
Squaring is a word-range Karatsuba square (three half-size squares $a_0^2$,
$a_1^2$ and $(a_0 - a_1)^2$ instead of three products) on Native and LLVM, and
the NTT square above its cutoff; Wasm keeps the 32-bit-limb route from 80
limbs, where a 64-bit product costs four `i64.mul`.

Operands with at least 4 limbs of which at most one eighth are nonzero use a
sparse product of the nonzero limbs. Division uses a loop over half-limbs for a
divisor below $2^{32}$, Knuth's algorithm D on 64-bit digits (32-bit digits on
Wasm) below 96 divisor limbs, Burnikel–Ziegler recursion from 96 with leaves of
up to 64 limbs, and never the Newton reciprocal (the routine stays for tests);
GCD switches from the binary (Stein) algorithm to Lehmer batches above two
limbs. The thresholds are measured, per target, by the benchmark suite; they
are policy, not semantics. The 32-bit view of the storage exists only for the
Wasm routes above.

A Lehmer round is valid only when its single-word digits come from the same
bit window of both operands: digits taken from each operand's own top limb
have unrelated scales, and the cofactors they produce subtract only a small
multiple of the smaller operand per round. Each round therefore keeps
$a \ge b$, runs Euclid on the leading 63 bits of $a$ and the bits of $b$ in the
same window, and takes one division step $a \bmod b$ instead when $b$ has no
bits in that window (then $a / b \ge 2^{62}$) or when the cofactor matrix would
make an operand negative or shrink neither. Every matrix applied has
determinant $\pm 1$, so the gcd is unchanged, and a long $a$ is reduced
modulo a short $b$ in one step however different their lengths are; below
eight limbs of $b$ the loop finishes with plain Euclid.

**Why exactness is preserved.** Schoolbook, Karatsuba and Toom-3 evaluate
integer polynomial identities, for example

$$
(a_1 B + a_0)(b_1 B + b_0) = a_1 b_1 B^2 + \bigl[(a_1 + a_0)(b_1 + b_0) - a_1 b_1 - a_0 b_0\bigr] B + a_0 b_0,
$$

and Toom-3 (evaluation at $0, 1, -1, 2, \infty$) interpolates with exact
divisions by 2 and 3 of signed intermediates known to be multiples, so they are exact integer computations. The NTT is
the only modular step. It splits each operand into 16-bit digits, so each
coefficient of the digit convolution is at most

$$
\min(n_a, n_b)\,(2^{16} - 1)^2 < 2^{23} \cdot 2^{32} = 2^{55}
$$

for transform lengths up to $2^{23}$. It computes the convolution modulo the
primes $p_1 = 998244353 = 119 \cdot 2^{23} + 1$ and
$p_2 = 754974721 = 45 \cdot 2^{24} + 1$, both of which have $2^{23}$-th roots
of unity, and recombines by the Chinese remainder theorem, which is unique
in $[0, p_1 p_2)$ with $p_1 p_2 \approx 2^{59.4} > 2^{55}$. So the recombined
coefficients are the exact integers. The length check precedes every
transform; a longer product uses overlapping blocks of admissible length or
falls back to Toom-3. Division paths return $(q, r)$ with $n = qd + r$ and
$0 \le r < d$ by construction; the Newton path corrects its approximate
quotient with the remainder and aborts if more than two corrections would be
needed, which would indicate a bug rather than a numerical event. Because all
paths compute the same integers, the choice of algorithm cannot change any
rounded result, flag or encoding.

### Ordering NaN in `compare`

**Problem.** MoonBit's `Compare` trait asks for a three-way comparison that
sorting and ordered maps can rely on. IEEE comparison is a partial order:
NaN is unordered with everything, itself included.

**Options.** (1) Abort on NaN, as earlier versions did; every sort of data
that might contain a NaN then becomes a crash. (2) Use IEEE `totalOrder`,
which is total but distinguishes $-0 < +0$ and puts negative NaNs below
$-\infty$, so `compare` would disagree with numerical equality on zeros.
(3) Keep the numerical order on numbers and put all NaNs in one class above
it.

**Choice.** Option (3). Define the key $\kappa(x) = (0, x)$ for a number and
$\kappa(\mathrm{NaN}) = (1, 0)$, ordered lexicographically; `compare(x, y)`
is the comparison of $\kappa(x)$ and $\kappa(y)$, with $-0$ and $+0$ mapped to
the same number. A comparison of keys in a totally ordered set is reflexive,
transitive and total, so `compare` is a total preorder; it is not
antisymmetric ($-0$ and $+0$, or two NaNs with different payloads, compare
equal but are different values), which `Compare` does not require. The cost is
that `nan > 1` is true under `<`, so code that needs IEEE semantics must use
`compare_checked` (error on NaN), `compare_quiet` / `compare_signaling`
(four-valued, with flags) or `total_order`. Structural `==` stays the derived
`Eq`, because it is the only equality that is a congruence for every method
(precision and payload included).

## Correctness and invariants

- **Canonical form.** Every finite value produced by the API has $c$ odd or
  $c = 0, e = 0$, and $\operatorname{bits}(c) \le$ its precision; stored
  exponents never saturate (a saturated exponent is classified as overflow or
  underflow first).
- **Correct rounding.** For every arithmetic operation, conversion and
  elementary function and every context, the returned finite value equals
  $\circ(r)$ for the exact real result $r$, with the range rules above. By
  (R1), $\circ(r) = r$ and no flag is raised whenever $r \in F$; `round_ctx`
  is idempotent.
- **Flags.** `inexact` iff $\circ(r) \ne r$;
  `overflow` implies `inexact`; `underflow` iff tiny (per the context rule)
  and inexact; `division_by_zero` only for an exact infinite result of finite
  operands;
  `invalid_operation` iff a quiet NaN was produced from non-NaN operands or a
  signaling NaN was consumed. Exceptions to the last rule: `min`, `max`,
  $\operatorname{pow}(x, \pm 0)$, $\operatorname{pown}(x, 0)$ and
  $\operatorname{pow}(1, y)$ accept a signaling NaN without the flag.
  `combine` is associative, commutative and idempotent.
- **Error model.** Consequently, in the normal range,
  $|\circ(r) - r| \le u|r|$ for nearest and $< 2u|r|$ for directed rounding,
  with the absolute term $\eta/2$ (respectively $\eta$) below
  $2^{e_{\min}}$, and subnormal sums and differences are exact.
- **Monotonicity.** Each operation is monotone in each argument where the
  real function is, because it is $\circ \circ f$ with $\circ$ monotone; in
  particular RD and RU results bracket the exact value, which `ball_float`
  and the directed square roots of `sqrt_ctx` rely on.
- **Exactness theorems.** `remainder`, `scaleb` in the normal range,
  `copy_sign`, `neg`, `abs`, `logb` and decoding are exact; the integral
  roundings never need a second rounding; `fma(a, b, -RN(ab))` is exact
  without underflow.
- **Complexity.** Addition is linear in the operand length (and independent
  of the exponent gap, by the far-operand rule); multiplication follows the
  kernel table, $O(n^2)$ to $O(n \log n)$; division and square root cost a
  constant number of multiplications of the same size at large $n$;
  `remainder` costs $O(\log(q_x - q_y))$ modular multiplications; an
  elementary function evaluates its series at the working precision $w$, and
  because $w$ grows geometrically the total cost of all attempts is within a
  constant factor of the last one.

The longer proofs (the far-operand addition rule, `nextUp`, the remainder
reduction, the Ziv acceptance test and the NTT bound) are collected in the
attachment.

[Rounding and exactness proofs for bin_float](../../attachments/design_bin_float_rounding_proofs.typ)

## Alternatives rejected

- **Host `Double` for anything but `from_double`.** Routing binary16,
  binary32 or binary128 through `Double` double-rounds, loses signaling NaNs
  on some targets and cannot represent binary128 at all. Interchange encoding
  is done on `BinCoeff` bit patterns instead.
- **A fixed number of guard bits.** Three guard bits suffice for addition of
  two $p$-bit operands, but not for division, square root, conversions from
  decimal or operands wider than the context. Deciding from exact integer data
  (round, sticky, remainder sign, midpoint comparison) works for all of them
  with one finalizer.
- **Rounding to $p$ bits, then to the subnormal grid.** This double rounding
  produces wrong subnormal results; the finalizer shifts once to the coarser
  of the two positions.
- **Ziv with an estimated error bound.** It requires a separate error analysis
  for every function and every reduction, and a mistake in it silently returns
  a wrong last bit. Outward-rounded enclosures make the bound a computed
  quantity, at the cost of evaluating every operation twice.
- **Global flags and rounding state.** IEEE 754 describes flags as sticky
  global state. A returned `BinaryFlags` value composes with pure code,
  concurrent code and the `Result` style of `@lf_arith`, and `combine`
  recovers the sticky behaviour where wanted.
- **`compare` aborting on NaN, or `compare` as `totalOrder`.** See
  [Ordering NaN in `compare`](#ordering-nan-in-compare).

## Boundaries

`bin_float` deliberately does not:

- provide interval or ball arithmetic: enclosures are internal to the
  certification loops; `ball_float` builds midpoint–radius arithmetic on top
  of `BinFloat`;
- implement IEEE 754 alternate exception handling (traps, substitution) or
  sticky global flags: flags are returned values;
- implement decimal floating-point (`decimal`, `decimal_gda`) or the
  non-binary IEEE operations on them;
- promise any NaN payload for a newly generated NaN (it uses payload 0), or
  propagate payloads of more than one input;
- guarantee completion of an elementary function within any time for every
  input: certification has a budget, and an exhausted budget is reported, not
  hidden;
- expose limb layout, thresholds or transform parameters: they may change
  without notice as long as every result, flag and encoding stays the same;
- claim conformance beyond the finite corpus recorded in
  [conformance](../conformance/bin_float.md).
