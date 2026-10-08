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
back as a value.

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
$2^{t} \le |x| < 2^{t+1}$ and $t \ge e_{\min}$ (the normal range). The
points of $F$ in that binade are spaced $2^{t-p+1}$ apart, so

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
one point $\circ(f(x))$, not merely some point within $u$. All of
`bin_float` is built to return that point, so the model above holds for every
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

### Far-apart operands in addition

**Problem.** $2^{10^9} + 2^{-10^9}$ is exact as a dyadic number, but forming
it needs a two-billion-bit coefficient.

**Choice.** When the leading exponents differ by more than $p + 3$, the
smaller operand is truncated at position
$\operatorname{exp}(\text{high}) - p - 3$ and everything below is replaced by one sticky bit: the integer part
$L$ of the truncated low operand enters exactly, and if anything was
discarded the magnitude becomes $2(H \pm L) + 1$ (for subtraction
$2(H - L - 1) + 1$) at half the unit.

**Why it is exact for rounding.** The result has
$\operatorname{top} \ge \operatorname{top}(\text{high}) - 1$, so the rounding
position is at least $\operatorname{top}(\text{high}) - p$ and the round bit
at least one below it, while every discarded bit lies at or below
$\operatorname{top}(\text{high}) - p - 3$. The discarded part therefore
changes neither $q$ nor $g$, only whether $t$ is set, and the substitute bit
sets $t$ exactly when something nonzero was discarded. For subtraction,
$H - (L + \varepsilon) = (H - L - 1) + (1 - \varepsilon)$ with
$0 < 1 - \varepsilon < 1$, so the same substitution applies to the borrowed
form. The complete argument, including the subnormal shift, is in the
attachment below.

### Fused multiply-add

`fma_ctx` forms the product $c_x c_y 2^{e_x + e_y}$ exactly as a value whose
precision equals its own bit length, and passes it to the addition finalizer,
so $x y + z$ is rounded once (clause 5.4.1). The difference from two
roundings is the point of the operation: for $a = \operatorname{RN}(0.1)$ in
binary64, $\operatorname{RN}(a \cdot a) - a \cdot a$ is lost by
`mul_ctx` followed by `sub_ctx` (the second operation sees two equal numbers)
but `fma_ctx(a, a, -RN(a·a))` returns it exactly, $-8.33\ldots \cdot 10^{-19}$.
That the result is exact is Dekker's theorem: the error of a rounded product
is itself in $F$ when no underflow occurs.[^dekker] If the product exponent
leaves the `Int` range, the product either certainly overflows, or it is so
small that it acts as a sticky bit next to a nonzero addend; the code places a
single bit $p + 8$ positions below the addend's last bit, which by the
far-operand argument above rounds identically.

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
is no breakpoint. For $k < 0$, $5^{|k|} > 10^{n} > D$ beyond the bound, so
$5^{|k|} \nmid D$ and $D/10^{|k|}$ is not even dyadic. A value that is no
breakpoint has a positive distance to every breakpoint, and the enclosure
width tends to zero as $w$ grows, so some $w$ certifies it. Values whose
binary logarithm is certainly beyond the range, estimated with
$\log_2 10$ and a safety margin, overflow or underflow without any
arithmetic, so `1e100000000` costs nothing.

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

the common value is returned, otherwise $w$ grows. **This is sound by
(R2):** $L \le f(x) \le U$ implies $\circ(L) \le \circ(f(x)) \le \circ(U)$,
so equal ends force $\circ(f(x)) = \circ(L)$. The flags agree as well,
because overflow, tininess and inexactness are monotone in the same way on
one side of zero; the test compares them explicitly instead of relying on
this.

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
reduce $x$ by an enclosure of $\pi/2$ (from $\pi = 4 \arctan 1$, itself
enclosed by the arctangent series after argument halving) at
$w \ge p + \max(0, \operatorname{top}(x) + 1) + 96$ bits, so the quadrant
$k = \operatorname{round}(x / (\pi/2))$ is the same integer at both ends of
the enclosure; otherwise the attempt is repeated at a higher precision. This
is the Payne–Hanek idea realised by brute precision instead of a stored table
of $2/\pi$; its cost grows with $\log_2|x|$, so inputs needing more than
$10^6$ bits are refused with `ResourceLimit` rather than run for minutes.

**Budget.** The loop starts at $w_0 = p + 64$ and steps
$w_{i+1} = w_i + \max(32, \lfloor w_i/2 \rfloor)$, at most 12 attempts. For
binary64 the sequence is $117, 175, 262, \ldots, 10053$ bits. Ziv's argument
for termination is that $f(x)$ is not a breakpoint of $\circ$: by
Lindemann–Weierstrass, $e^{x}$, $\ln x$, $\sin x$, $\cos x$, $\tan x$ and
their inverses are transcendental at every nonzero algebraic (in particular
dyadic) argument other than the trivial exceptions, while breakpoints are
dyadic. The exceptions are filtered before the loop: $e^0 = 1$,
$\ln 1 = 0$, $\log_2 2^k = k$, $2^n$ for integral $n$, $\sin(\pm 0)$,
integral and half-integral arguments of `sinpi` and `cospi`,
$\operatorname{tanpi}(\pm 1/4) = \pm 1$, $10^n$ for integral $n$, $\log_{10}
10^n = n$, and so on. For the $\pi$-scaled functions Niven's theorem shows
that these are the only dyadic results.[^niven] A
non-breakpoint has a positive distance to every breakpoint, so a large
enough $w$ certifies it. How large $w$ must be is the table maker's dilemma:
no useful a priori bound is known for arbitrary $p$, so the budget is a
resource limit, not a correctness condition. When it runs out the `try_*`
form reports a `CertificationFailure` with the stage, the reason and the last
$w$, and the total forms return a quiet NaN with `invalid_operation`; neither
returns an uncertified value. The pinned MPFR corpus never exhausts it.
One family of exceptions is not filtered on the current branch: `pow` with a
non-integral exponent other than $1/2^k$ whose result is nevertheless dyadic,
such as $16^{3/4} = 8$. Under nearest rounding the enclosure still certifies
the right value but `inexact` is raised; under a directed rounding the
loop cannot certify and returns a `CertificationFailure`.

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

**Integer powers.** `pow_int_ctx` computes $x^n$ by an addition chain at
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
doublings do not certify, the exact power $c^n 2^{ne}$ is formed and rounded,
so the result is correctly rounded in every case. A power certainly outside
the range is decided first from certified $\log_2$ bounds, and powers whose
exact value fits in $p$ bits are computed exactly, which also guarantees that
the Ziv path only sees inexact results.

### The coefficient kernel

**Problem.** Precision costs integer multiplication and division of
$p$-bit numbers, and $p$ ranges from 1 to $2^{28}$.

**Choice.** `BinCoeff` stores up to 128 bits inline and larger values as
little-endian 32-bit limbs (a host `bigint` on JavaScript), and dispatches
on the shorter operand length $n$ in limbs:

| Product | Native | LLVM | Wasm, Wasm-GC |
| --- | ---: | ---: | ---: |
| schoolbook below | 96 | 96 | 96 |
| Karatsuba from | 96 | 96 | 96 |
| Toom-3 from | 2048 | 2048 | 4096 |
| two-prime NTT multiply from | 2048 | 2048 | 4096 |
| NTT square from | 768 | 768 | 3072 |
| recursive square from | 512 | 768 | 768 |

Sparse operands (few nonzero limbs) use a sparse product, and operands with
$m > 2n$ limbs are cut into $n$-limb blocks. Division uses a one-limb loop,
Knuth's algorithm D below 48 divisor limbs, Burnikel–Ziegler recursion from
48 and a Newton reciprocal from 1024; GCD switches from the binary (Stein) algorithm to
Lehmer batches above four limbs. The thresholds are measured, per target, by
the benchmark suite; they are policy, not semantics.

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

## Correctness / invariants

- **Canonical form.** Every finite value produced by the API has $c$ odd or
  $c = 0, e = 0$, and $\operatorname{bits}(c) \le$ its precision; stored
  exponents never saturate (a saturated exponent is classified as overflow or
  underflow first).
- **Correct rounding.** For every arithmetic operation, conversion and
  elementary function and every context, the returned finite value equals
  $\circ(r)$ for the exact real result $r$, with the range rules above. By
  (R1), $\circ(r) = r$ and no flag is raised whenever $r \in F$; `round_ctx`
  is idempotent.
- **Flags.** `inexact` iff $\circ(r) \ne r$; `overflow` implies `inexact`;
  `underflow` iff tiny (per the context rule) and inexact; `division_by_zero`
  only for an exact infinite result of finite operands; `invalid_operation`
  iff a quiet NaN was produced from non-NaN operands or a signaling NaN was
  consumed. `combine` is associative, commutative and idempotent.
- **Error model.** Consequently, in the normal range,
  $|\circ(r) - r| \le u|r|$ for nearest and $< 2u|r|$ for directed rounding,
  with the absolute term $\eta/2$ (respectively $\eta$) below
  $2^{e_{\min}}$, and subnormal sums and differences are exact.
- **Monotonicity.** Each operation is monotone in each argument where the
  real function is, because it is $\circ \circ f$ with $\circ$ monotone; in
  particular RD and RU results bracket the exact value, which `ball_float`
  and `sqrt_bounds_for_precision` rely on.
- **Exactness theorems.** `remainder`, `scaleb` in the normal range,
  `copy_sign`, `neg`, `abs`, `logb`, `to_integral_*` and decoding are exact;
  `fma(a, b, -RN(ab))` is exact without underflow.
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
