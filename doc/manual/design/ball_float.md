# ball_float design

`ball_float` computes with sets of real numbers instead of single
approximations. This page states the mathematical contract, derives the
formulas the code uses, explains the choices behind them, and lists what the
package does not do. The [API reference](../api/ball_float.md) documents each
function; the [tutorial](../tutorial/ball_float.md) shows them in use.

## Design goal

A floating-point computation returns a number near the true result, with an
error that the caller has to estimate separately. `ball_float` returns an
interval that provably contains the true result, at any working precision, so
that the error bound is part of the value. Three requirements follow:

1. **Inclusion before tightness.** Every operation returns a superset of the
   exact image of its operands. A wider result is acceptable; a result that
   misses a possible value is a bug.
2. **Explicit semantics.** Precision, target format, flags and decorations are
   values passed in and returned, never process-global state (no hardware
   rounding-mode switching).
3. **Standard vocabulary.** Sets, relations and decorations follow IEEE
   1788-2015[^ieee1788], so results can be checked against its test corpus
   (see [conformance](../conformance/ball_float.md)).

[^ieee1788]: IEEE Std 1788-2015, *IEEE Standard for Interval Arithmetic*.
    The package follows its set-based flavor.

## Mathematical background

### Intervals and the inclusion property

An interval is a set
$\boldsymbol{x} = [\underline{x}, \overline{x}] = \{\xi \in \mathbb{R} :
\underline{x} \le \xi \le \overline{x}\}$ with
$\underline{x} \in \mathbb{R} \cup \{-\infty\}$,
$\overline{x} \in \mathbb{R} \cup \{+\infty\}$ and
$\underline{x} \le \overline{x}$, or the empty set $\emptyset$. Following the
set-based model of IEEE 1788, infinite endpoints only say that the set is
unbounded; the elements are always real. The whole line
$(-\infty, +\infty)$ is called Entire.

For a real function $f$ with domain $D_f \subseteq \mathbb{R}^n$, the *range*
over a box is

$$
f(\boldsymbol{x}) = \{ f(\xi) : \xi \in \boldsymbol{x} \cap D_f \},
\qquad \boldsymbol{x} = \boldsymbol{x}_1 \times \cdots \times \boldsymbol{x}_n ,
$$

and its *hull* $\operatorname{hull} f(\boldsymbol{x})$ is the smallest
interval containing it. An *interval extension* of $f$ is a map $F$ with
$f(\boldsymbol{x}) \subseteq F(\boldsymbol{x})$ for every box. Points outside
$D_f$ are ignored rather than reported as errors: $\sqrt{[-1, 4]} = [0, 2]$
and $\sqrt{[-2, -1]} = \emptyset$. Whether a domain violation occurred is
reported separately, by decorations.

Every public operation of `BallFloat` is meant to be an interval extension;
the few inputs where the current code is not are listed under
[Known limitations](#known-limitations). Composition then gives the result
that justifies the package:

> **Fundamental theorem of interval arithmetic.**[^moore] If an expression is
> evaluated with an interval extension for each operation, the result contains
> the value of the expression at every point of the input box where the
> expression is defined.

[^moore]: R. E. Moore, *Interval Analysis*, Prentice-Hall, 1966; and Moore,
    Kearfott, Cloud, *Introduction to Interval Analysis*, SIAM, 2009, Thm. 5.1.

*Proof.* By induction on the expression. A variable $\xi_i$ evaluates to
$\boldsymbol{x}_i \ni \xi_i$. For $e = g(e_1, \dots, e_k)$, let $\xi$ be a
point where $e$ is defined; then each $e_j$ is defined at $\xi$ and, by the
induction hypothesis, $y_j = e_j(\xi) \in E_j$, the interval value of $e_j$.
Since $g$ is defined at $(y_1, \dots, y_k)$ and $G$ extends $g$,

$$
\begin{aligned}
e(\xi) = g(y_1, \dots, y_k)
  &\in g(E_1 \times \cdots \times E_k) && y_j \in E_j \\
  &\subseteq G(E_1, \dots, E_k) = E(\boldsymbol{x}) && G \text{ is an interval extension.}
\end{aligned}
$$

$\square$ The full argument, with the lemmas below, is in the attachment:

[Inclusion proofs for ball_float](../../attachments/design_ball_float_inclusion.typ)

### Outward rounding

Endpoints are `BinFloat` numbers with $p$ significant bits, so exact endpoint
values must be rounded. Write $F_p$ for the $p$-bit binary numbers and

$$
\operatorname{RD}_p(a) = \max\{ f \in F_p : f \le a \}, \qquad
\operatorname{RU}_p(a) = \min\{ f \in F_p : f \ge a \}.
$$

Three properties follow directly from these definitions:

$$
\begin{aligned}
&\text{(i)}\quad \operatorname{RD}_p(a) \le a \le \operatorname{RU}_p(a), \\
&\text{(ii)}\quad a \le b \implies \operatorname{RD}_p(a) \le \operatorname{RD}_p(b) \text{ and } \operatorname{RU}_p(a) \le \operatorname{RU}_p(b), \\
&\text{(iii)}\quad \min_{s \in S} \operatorname{RD}_p(s) = \operatorname{RD}_p(\min S), \quad \max_{s \in S} \operatorname{RU}_p(s) = \operatorname{RU}_p(\max S).
\end{aligned}
$$

(ii) holds because the set maximized for $\operatorname{RD}_p(b)$ contains the
one for $\operatorname{RD}_p(a)$; (iii) follows from (ii), since the minimum
over $S$ is attained at $\min S$. Hence, if $L \le \inf A$ and
$U \ge \sup A$ for a set $A$,

$$
A \subseteq [L, U] \subseteq [\operatorname{RD}_p(L), \operatorname{RU}_p(U)].
$$

This is the only way rounding enters the package: each operation computes a
lower bound $L$ and an upper bound $U$ of the exact range and stores
$\operatorname{RD}_p(L)$ and $\operatorname{RU}_p(U)$. Property (iii) means
it does not matter whether candidates are rounded before or after taking the
minimum; the code rounds the extremal candidate once (`quantize_interval`).

The width added by rounding is at most one unit in the last place per
endpoint. For $2^{e} \le |a| < 2^{e+1}$ the $p$-bit numbers near $a$ are
spaced $\operatorname{ulp}_p(a) = 2^{e-p+1}$ apart, so
$\operatorname{RU}_p(a) - a < \operatorname{ulp}_p(a) \le 2^{1-p}|a|$, and
likewise for $\operatorname{RD}_p$. For a sum with exact range
$[S_\ell, S_u]$:

$$
\begin{aligned}
\operatorname{RU}_p(S_u) - \operatorname{RD}_p(S_\ell)
  &\le (S_u + \operatorname{ulp}_p(S_u)) - (S_\ell - \operatorname{ulp}_p(S_\ell)) \\
  &\le w(\boldsymbol{x}) + w(\boldsymbol{y}) + 2^{1-p}\bigl(|S_u| + |S_\ell|\bigr),
\end{aligned}
$$

using $S_u - S_\ell = w(\boldsymbol{x}) + w(\boldsymbol{y})$. Widths
therefore grow additively through a computation, plus a relative $2^{1-p}$
per rounding. The relative bound needs $a$ inside the normal range of
`BinFloat`, $2^{e_{\min}} \le |a| < 2^{e_{\max}+1}$ with
$e_{\min} = -(2^{30} - 1)$ and $e_{\max} = 2^{30} - 1$. Below $2^{e_{\min}}$
the directed kernels round on a subnormal grid, and the error is only bounded
absolutely, by $2^{e_{\min} - p + 1}$; above the range an upper endpoint
becomes $+\infty$. Both happen only for magnitudes near $2^{\pm 2^{30}}$.

### Endpoint formulas

`BallFloat` stores the two endpoints (see
[Endpoints, not midpoint and radius](#endpoints-not-midpoint-and-radius)), so
each operation is a formula in the endpoints.

**Sum and difference.** $\xi + \eta$ is increasing in both arguments and
$\xi - \eta$ is increasing in $\xi$ and decreasing in $\eta$, so the extremes
over the box are at the corners that make each argument extreme in the right
direction:

$$
\begin{aligned}
\boldsymbol{x} + \boldsymbol{y} &= [\underline{x} + \underline{y},\ \overline{x} + \overline{y}], &
\boldsymbol{x} - \boldsymbol{y} &= [\underline{x} - \overline{y},\ \overline{x} - \underline{y}].
\end{aligned}
$$

**Product.** For fixed $\eta$, $\xi \mapsto \xi\eta$ is affine, so its extrema
over $\boldsymbol{x}$ lie at $\underline{x}$ or $\overline{x}$; applying the
same argument to $\eta$ gives

$$
\boldsymbol{x}\boldsymbol{y} = [\min S, \max S], \qquad
S = \{\underline{x}\,\underline{y},\ \underline{x}\,\overline{y},\ \overline{x}\,\underline{y},\ \overline{x}\,\overline{y}\}.
$$

The sign pattern decides which elements of $S$ can be extremal. If
$\underline{x}, \underline{y} \ge 0$ the product is increasing in both
arguments, so the range is $[\underline{x}\,\underline{y},
\overline{x}\,\overline{y}]$; the other single-sign cases follow from
$\xi\eta = (-\xi)(-\eta) = -((-\xi)\eta)$, which gives the table used by
`multiplication_bounds`:

| $\boldsymbol{x}$ | $\boldsymbol{y}$ | lower | upper |
| --- | --- | --- | --- |
| $\ge 0$ | $\ge 0$ | $\underline{x}\,\underline{y}$ | $\overline{x}\,\overline{y}$ |
| $\le 0$ | $\le 0$ | $\overline{x}\,\overline{y}$ | $\underline{x}\,\underline{y}$ |
| $\ge 0$ | $\le 0$ | $\overline{x}\,\underline{y}$ | $\underline{x}\,\overline{y}$ |
| $\le 0$ | $\ge 0$ | $\underline{x}\,\overline{y}$ | $\overline{x}\,\underline{y}$ |
| other (one of them has $0$ in its interior) | | $\min(\underline{x}\,\overline{y}, \overline{x}\,\underline{y})$ | $\max(\underline{x}\,\underline{y}, \overline{x}\,\overline{y})$ |

The first four rows cover the cases where both operands have constant sign
(an operand with a zero endpoint, such as $[0, 2]$, has constant sign; when
two rows apply they give the same products). The last row covers the five remaining cases,
in which at least one operand straddles 0. Say
$\underline{x} < 0 < \overline{x}$. The minimum of $S$ is $\le 0$, because
$\underline{x}\,\eta$ and $\overline{x}\,\eta$ have opposite signs for any
$\eta$. If it were attained at $\underline{x}\,\underline{y} < 0$, then
$\underline{y} > 0$, hence $\overline{y} \ge \underline{y}$ gives
$\underline{x}\,\overline{y} \le \underline{x}\,\underline{y}$; if at
$\overline{x}\,\overline{y} < 0$, then $\overline{y} < 0$ and
$\overline{x}\,\underline{y} \le \overline{x}\,\overline{y}$. Either way the
minimum is also attained at $\underline{x}\,\overline{y}$ or
$\overline{x}\,\underline{y}$ (and a minimum of 0 at
$\underline{x}\,\underline{y}$ means $\underline{y} = 0$, so
$\underline{x}\,\overline{y} \le 0$ as well). The maximum and the case where
$\boldsymbol{y}$ straddles 0 are symmetric. So two products suffice for the
four single-sign rows and four for the rest.

For unbounded intervals all four products are formed with
$0 \cdot \infty := 0$. This is the right limit for the set-based model: if
$\underline{x} = 0$ and $\overline{y} = +\infty$, the products
$\xi\eta$ with $\xi \downarrow 0$ and $\eta$ fixed tend to 0, while the
unbounded growth is already represented by the other corners
($\overline{x}\,\overline{y} = \pm\infty$ when $\overline{x} \ne 0$).

**Division.** IEEE 1788 defines $\boldsymbol{x}/\boldsymbol{y} =
\operatorname{hull}\{\xi/\eta : \xi \in \boldsymbol{x}, \eta \in
\boldsymbol{y}, \eta \ne 0\}$. When $0 \notin \boldsymbol{y}$, $1/\eta$ is
continuous and decreasing on $\boldsymbol{y}$, so $1/\boldsymbol{y} =
[1/\overline{y}, 1/\underline{y}]$ and $\boldsymbol{x}/\boldsymbol{y} =
\boldsymbol{x} \cdot (1/\boldsymbol{y})$; the code evaluates the selected
endpoint quotients directly with directed division instead of rounding twice.
When $0 \in \boldsymbol{y}$:

- $\boldsymbol{y} = \{0\}$: no admissible $\eta$, the result is $\emptyset$.
- $\underline{y} < 0 < \overline{y}$, $\boldsymbol{x} \ne \{0\}$: $\eta$
  approaches 0 from both sides, so $\xi/\eta$ is unbounded in both directions:
  Entire.
- $\boldsymbol{y} = [0, \overline{y}]$ with $\overline{y} > 0$ and
  $\underline{x} \ge 0$, $\boldsymbol{x} \ne \{0\}$: as $\eta \downarrow 0$
  with $\xi = \overline{x} > 0$, $\xi/\eta \to +\infty$, and the smallest
  quotient is $\underline{x}/\overline{y}$ (0 when $\overline{y} = +\infty$),
  so the result is $[\underline{x}/\overline{y}, +\infty)$. The cases
  $\overline{x} \le 0$ and $\boldsymbol{y} = [\underline{y}, 0]$ are mirror
  images, obtained from $\xi/\eta = (-\xi)/(-\eta) = -((-\xi)/\eta)$. If
  $\boldsymbol{x}$ straddles 0, both signs are unbounded: Entire.
- $\boldsymbol{x} = \{0\}$ and $\boldsymbol{y} \ne \{0\}$: every admissible
  quotient is 0.
- An Empty operand gives Empty.

### From midpoint–radius to endpoints

Users often know a value as $c \pm r$. `BallFloat::new(c, r, precision=p)`
rounds the center to nearest, $\tilde c = \operatorname{RN}_p(c)$, and stores

$$
[\tilde c - R,\ \tilde c + R], \qquad
R = \operatorname{RU}_p\bigl(\operatorname{RU}_p(r) + \operatorname{RU}_p(|c - \tilde c|)\bigr).
$$

*Claim:* $[c - r, c + r] \subseteq [\tilde c - R, \tilde c + R]$. For
$|\xi - c| \le r$,

$$
\begin{aligned}
|\xi - \tilde c| &\le |\xi - c| + |c - \tilde c| && \text{triangle inequality} \\
&\le \operatorname{RU}_p(r) + \operatorname{RU}_p(|c - \tilde c|) && \text{property (i)} \\
&\le R && \text{property (i) again.}
\end{aligned}
$$

The endpoints $\tilde c \pm R$ are then formed exactly (they may have more
than $p$ bits). `with_precision` uses the same construction with the current
center and radius, and a caller-chosen rounding mode for the center. The
construction is sound but not idempotent: whenever $\tilde c \ne c$, the
displacement $|c - \tilde c|$ is added on both sides, so rebuilding an
interval whose center needs more than $p$ bits widens it (see
[Tightness](#correctness-and-invariants)). The
converse view is exact: `center` returns $(\underline{x} + \overline{x})/2$
and `radius` returns $(\overline{x} - \underline{x})/2$, which are dyadic and
need no rounding (the radius is rounded up only if it underflows the
exponent range), so $[\text{center} - \text{radius}, \text{center} +
\text{radius}]$ is exactly the stored interval. `Show` prints this pair.

### The dependency problem

The fundamental theorem treats every occurrence of a variable as an
independent point. For $\boldsymbol{x} = [1, 2]$,

$$
\boldsymbol{x} - \boldsymbol{x} = [1 - 2,\ 2 - 1] = [-1, 1] \supsetneq \{0\} = \{\xi - \xi : \xi \in \boldsymbol{x}\}.
$$

The result is correct (it contains 0) but not tight: interval subtraction is
the extension of $(\xi, \eta) \mapsto \xi - \eta$, and the box
$\boldsymbol{x} \times \boldsymbol{x}$ contains $(1, 2)$ and $(2, 1)$. In
general only $f(\boldsymbol{x}) \subseteq F(\boldsymbol{x})$ holds. A second
theorem of Moore's gives equality, in exact arithmetic and for continuous
operations, when each variable occurs at most once in the expression; the
condition is sufficient, not necessary ($\boldsymbol{x} \cdot \boldsymbol{x}$
is exact for $\boldsymbol{x} = [1, 2]$). The same effect explains $\boldsymbol{x}\boldsymbol{x} \supsetneq
\boldsymbol{x}^2$ for $0 \in \operatorname{int}\boldsymbol{x}$
($[-1, 2]\cdot[-1, 2] = [-2, 4]$ but $[-1, 2]^2 = [0, 4]$) and
*subdistributivity*, $\boldsymbol{x}(\boldsymbol{y} + \boldsymbol{z})
\subseteq \boldsymbol{x}\boldsymbol{y} + \boldsymbol{x}\boldsymbol{z}$. For
this reason the package provides single-occurrence operations — `square`,
`pown`, `fma`, `hypot`, `cancel_minus` and the elementary functions — whose
results are hulls of the true range (up to rounding) rather than products of
independent factors. Interval values also do not form a group under addition:
`cancel_minus` is the operation that undoes an addition, since
$(\boldsymbol{x} + \boldsymbol{y}) - \boldsymbol{y} \ne \boldsymbol{x}$ in
general.

### Elementary functions: monotonicity, critical points and poles

For a continuous function the range over an interval is an interval, and its
endpoints are attained at the endpoints of $\boldsymbol{x}$ or at critical
points inside it. The package uses three patterns.

- **Monotone functions** (`exp`, `exp2`, `exp10`, `expm1`, `ln`, `log2`,
  `log10`, `log1p`, `sqrt`, `sinh`, `tanh`, `asinh`, `acosh`, `atanh`,
  `asin`, `atan`, and the decreasing `acos`): the range over
  $\boldsymbol{x} \cap D_f$ is $[f(\underline{x}), f(\overline{x})]$ (swapped
  for decreasing $f$), so only the endpoints are evaluated, the lower one
  rounded down and the upper one rounded up. A domain boundary inside the
  interval is replaced by the limit there ($\ln \xi \to -\infty$ as
  $\xi \downarrow 0$).
- **Functions with known extrema.** `cosh` has its minimum 1 at 0. `pown`
  with even exponent has minimum 0 at 0. `sin` attains $+1$ at
  $\xi = k\pi/2$ with $k \equiv 1 \pmod 4$ and $-1$ at $k \equiv 3$; `cos`
  attains $+1$ at $k \equiv 0$ and $-1$ at $k \equiv 2$. Between two
  consecutive critical points both functions are monotone, so with
  $K = \{k \in \mathbb{Z} : k\pi/2 \in \boldsymbol{x}\}$

  $$
  \sin(\boldsymbol{x}) \subseteq [m, M], \qquad
  m = \begin{cases} -1 & \exists k \in K,\ k \equiv 3 \\ \min(\sin\underline{x}, \sin\overline{x}) & \text{otherwise,} \end{cases}
  \qquad
  M = \begin{cases} 1 & \exists k \in K,\ k \equiv 1 \\ \max(\sin\underline{x}, \sin\overline{x}) & \text{otherwise.} \end{cases}
  $$

  The code encloses $K$ by $[\lceil q^-(\underline{x}) \rceil,
  \lfloor q^+(\overline{x}) \rfloor]$, where $q^- \le 2\xi/\pi \le q^+$ are
  computed from a certified enclosure $[\pi^-, \pi^+]$ of $\pi$. This set can
  only be too large: a spurious critical point widens the result to $\pm 1$,
  a missed one would break inclusion. When it has four or more elements every
  residue occurs. `sinpi`, `cospi` and `tanpi` use the exact critical points
  $k/2$,
  computed from the dyadic endpoints without any approximation of $\pi$.
- **Poles.** $\tan$ is continuous and increasing between consecutive poles
  $(2k+1)\pi/2$. If $K$ contains an odd index the interval may contain a pole
  and the result is Entire; otherwise it is $[\tan\underline{x},
  \tan\overline{x}]$. For `tanpi`, where the pole positions are exact, a pole
  at an endpoint gives a half-unbounded result instead. Negative powers and
  division handle the pole at 0 by the rules of the previous sections.

`pow_interval(x, y)` on the domain $\xi > 0$ (and $\xi = 0$, $\eta > 0$) writes
$\xi^\eta = \exp(\eta u)$ with $u = \ln \xi$. The map $(u, \eta) \mapsto \eta u$
is bilinear, so by the corner argument used for products its extrema over the
box $[\ln \underline{x}, \ln \overline{x}] \times \boldsymbol{y}$ are at the
corners, and $\exp$ is increasing: the extrema of $\xi^\eta$ are among the four
corner values. When $\underline{x} = 0$, $u \to -\infty$ and the corner values
become the limits $0$ (for $\eta > 0$) and $+\infty$ (for $\eta < 0$). The
code also adds the value 1 when the box crosses $\xi = 1$ or $\eta = 0$; such
a box contains a point where $\eta u = 0$, so $e^0 = 1$ already lies between
the extreme corner values and the extra candidate is redundant but harmless. `atan2` is handled the same way with the axis crossings as
additional candidates, and with the result $[-\pi, \pi]$ when the box crosses
the branch cut on the negative $\xi$ axis.

### Certified evaluation of transcendental endpoints

$e^{\underline{x}}$ is not a dyadic number, so an endpoint needs a rational
enclosure $L \le f(a) \le U$ of the exact value, after which
$\operatorname{RD}_p(L)$ is a valid lower endpoint by property (i). The
kernels of this package build $L$ and $U$ with exact rational arithmetic and
directed `BinFloat` operations at a work precision $w > p$:

- **exp.** For $2^{e} \le |a| < 2^{e+1}$ the argument is halved
  $k = \max(0, e + 4)$ times so that $a' = |a|/2^k < 2^{-3}$, the Taylor
  series $\sum_j t_j$, $t_j = a'^j/j!$, is summed with directed rounding, and
  the result is squared $k$ times in interval arithmetic,
  $e^{a} = (e^{a/2^k})^{2^k}$. If the enclosure of $e^{a'}$ has relative width
  $\varepsilon$, its square has relative width
  $(1+\varepsilon)^2 - 1 \approx 2\varepsilon$, so the $k$ squarings cost
  about $k$ bits; the code reserves $w = p + 64 + 2k$. The series is cut
  after a term $t_n$ with $n \ge 1$; every later ratio is
  $t_{j+1}/t_j = a'/(j+1) \le \tfrac18 \cdot \tfrac12 = \tfrac1{16}$, so
  $$
  \sum_{j > n} t_j \le t_{n+1}\sum_{i \ge 0} 16^{-i} = \tfrac{16}{15} t_{n+1} \le 2 t_{n+1},
  $$
  and $2t_{n+1}$ is added to the upper sum. Negative arguments use
  $e^{-a} = 1/e^{a}$. Arguments with $|a| < 2^{-(p+16)}$ give
  $[1, 1 + 2^{-p}]$ or $[1 - 2^{-p}, 1]$ before rounding, since
  $0 < e^{|a|} - 1 < 2|a|$ and $0 < 1 - e^{-|a|} < |a|$. For $|a| \ge 2^{30}$
  the result is $[\text{largest finite}, +\infty)$ or
  $[0, \text{smallest positive}]$ directly: the largest finite `BinFloat` is
  below $2^{e_{\max}+1} = 2^{2^{30}}$, and $e^{2^{30}} = 2^{2^{30}/\ln 2}
  \approx 2^{1.44 \cdot 2^{30}}$ exceeds it; the smallest positive value at
  precision $p \le 2^{28}$ is at least $2^{-(2^{30} + 2^{28})}$, which exceeds
  $e^{-2^{30}}$.
- **ln.** For $a = m \cdot 2^{e}$ with $m \in [1, 2)$,
  $\ln a = \ln m + e \ln 2$, and $\ln m = 2\operatorname{artanh} z =
  2\sum_k z^{2k+1}/(2k+1)$ with $z = (m-1)/(m+1) \in [0, 1/3]$; $\ln 2$ is the
  same series at $m = 2$. The ratio of consecutive terms is
  $z^2 (2k+1)/(2k+3) \le z^2 \le 1/9$, so the omitted tail is at most
  $t' \sum_{i \ge 0} 9^{-i} = \tfrac98 t'$ for the first omitted term $t'$,
  and after doubling at most $\tfrac94 t' \le 3t'$, which is what the code
  adds.
- **π.** Machin's formula $\pi = 16\arctan\tfrac15 - 4\arctan\tfrac1{239}$ with
  alternating series, whose truncation error is bounded by the first omitted
  term.
- **sin, cos.** The argument is reduced by the quadrant
  $q = \lfloor 2a/\pi + 1/2 \rfloor$, computed with both $\pi^-$ and $\pi^+$;
  if the two disagree the work precision is raised. The reduced argument
  $r = a - q\pi/2 \in [-\pi/4, \pi/4]$ (as a rational interval) is fed to
  Taylor series, and the quadrant maps $(\sin r, \cos r)$ to
  $(\sin a, \cos a)$. The initial work precision is $p + 96$ plus the number
  of integer bits of $|a|$, so that reducing a huge argument keeps enough
  bits.[^reduction]

[^reduction]: Payne–Hanek reduction would avoid the extra bits; this package
    instead raises the work precision and caps it with the resource cutoff
    described under the total and `try_` forms.

The trigonometric and arctangent kernels add a Ziv-style
acceptance test.[^ziv] Since $\operatorname{RD}_p$ is monotone,

$$
\operatorname{RD}_p(L) = \operatorname{RD}_p(U) \implies
\operatorname{RD}_p(L) \le \operatorname{RD}_p(f(a)) \le \operatorname{RD}_p(U) = \operatorname{RD}_p(L),
$$

so when both $\operatorname{RD}$ and $\operatorname{RU}$ of $L$ and $U$ agree,
the endpoints are the correctly directed roundings of $f(a)$. Otherwise the
work precision $w$ grows to $w + \max(32, w/2)$; at most 12 work precisions
are tried (`CertifiedRefinementBudget`). The exp and log kernels skip the test and keep
$\operatorname{RD}_p(L)$, $\operatorname{RU}_p(U)$, which are always valid
and, with their guard bits ($p + 64 + 2k$ for `exp`, $p + 24$ for `ln`,
$p + 32$ for `log2`), almost always tight. The `try_` forms, and the total
forms of `expm1`, `log1p`, `sinpi`, `cospi`, `tanpi`, `pow_interval`,
`hypot` and `atan2` (which try them first), delegate the endpoints to the certified `try_*_ctx` functions of
[`bin_float`](bin_float.md), evaluated in unbounded contexts rounded toward
$-\infty$ and $+\infty$. The total hyperbolic functions and `asin`/`acos`
evaluate their defining formulas in interval arithmetic at 64 to 192 extra
bits, which is valid by the fundamental theorem. Validity is not tightness:
$(e^{\xi} - e^{-\xi})/2$ subtracts two enclosures of numbers near 1, each
about $2^{-w}$ wide, so for $|\xi| \ll 2^{-w+p}$ the relative width of the
result is about $2^{-w}/|\xi|$, far above $2^{-p}$. The same cancellation
affects `tanh`, `asinh` and `atanh` near 0.

[^ziv]: A. Ziv, "Fast evaluation of elementary mathematical functions with
    correctly rounded last bit", *ACM TOMS* 17(3), 1991; J.-M. Muller et al.,
    *Handbook of Floating-Point Arithmetic*, 2nd ed., Birkhäuser, 2018, §10.

### The IEEE 1788 decoration model

A bare interval result says where the values lie, not whether the function was
defined. IEEE 1788 attaches a *decoration* to each result of evaluating $f$ on
a box $\boldsymbol{x}$:

| Decoration | Property $p_d(f, \boldsymbol{x})$ |
| --- | --- |
| `com` | $\boldsymbol{x}$ is non-empty and bounded, $\boldsymbol{x} \subseteq D_f$, $f$ is continuous at each point of $\boldsymbol{x}$, and the result is bounded |
| `dac` | $\boldsymbol{x}$ is non-empty, $\boldsymbol{x} \subseteq D_f$ and $f \vert_{\boldsymbol{x}}$ is continuous |
| `def` | $\boldsymbol{x}$ is non-empty and $\boldsymbol{x} \subseteq D_f$ |
| `trv` | always true |
| `ill` | the value is NaI, not an interval |

The decorations are totally ordered by strength, $\text{com} > \text{dac} >
\text{def} > \text{trv} > \text{ill}$, because each property implies the
next (continuity of $f$ at each point of $\boldsymbol{x}$ implies continuity
of the restriction, but not conversely: `atan2` restricted to a box lying on
its branch cut from above is continuous, while `atan2` is not). A decorated
operation $g$ applied to decorated inputs
$(\boldsymbol{y}_j, d_j)$ returns

$$
d = \min(d_1, \dots, d_k, d_g), \qquad d_g = \text{strongest } d \text{ with } p_d(g, \boldsymbol{y}_1 \times \cdots \times \boldsymbol{y}_k).
$$

*Why the minimum is sound.* Suppose $\boldsymbol{y}_j$ was produced by $f_j$
on $\boldsymbol{x}$ with property $p_{d_j}$, and $g$ has $p_{d_g}$ on the box
of the $\boldsymbol{y}_j$. If $d \ge \text{def}$, each $f_j$ is defined on
$\boldsymbol{x}$ with values in $\boldsymbol{y}_j$ (inclusion property), and
$g$ is defined on those values, so $g \circ (f_1, \dots, f_k)$ is defined on
$\boldsymbol{x}$. If $d \ge \text{dac}$, the same holds for continuity,
because a composition of continuous functions is continuous. Boundedness for
`com` is a property of the final result and is checked on it. By induction
the decoration of a whole expression is a true statement about the expression
on the input box. This is what interval existence proofs need: for example,
if $\boldsymbol{x}$ is bounded and $F(\boldsymbol{x}) \subseteq \boldsymbol{x}$
with decoration at least `dac`, the function is continuous on the compact
non-empty interval $\boldsymbol{x}$ and maps it into itself, so Brouwer's
theorem gives a fixed point in $\boldsymbol{x}$. Boundedness matters:
$\xi \mapsto \xi + 1$ maps Entire into itself, continuously, without a fixed
point. Without the
decoration, $\sqrt{[-1, 4]} = [0, 2]$ would wrongly suggest that $\sqrt{\cdot}$
is defined on $[-1, 4]$.

The package computes $d_g$ from the operands by the domain tests listed in the
[API reference](../api/ball_float.md#decorated-intervals): division
by an interval containing 0, a logarithm reaching $\xi \le 0$, `sqrt` below 0,
a pole of `tanpi` or of a negative-degree `rootn` in the argument and so on
give `trv`; `atan2` across its branch cut gives `def` (defined but
discontinuous) and touching the cut from above gives `dac`. Set operations
(`intersection`, `convex_hull`, `cancel_*`) are not point functions and always
give `trv`. The result is made canonical: an empty result is always `trv`
(the properties above require a non-empty box), and `com` on
an unbounded result becomes `dac` (this is how overflow is reported). NaI,
the result of an invalid decorated construction, absorbs every operation, and
is distinct from $\emptyset$, which is a valid set.

### Relations: certainly and possibly

An interval stands for an unknown point, so a comparison of two intervals
asks a quantified question. Two quantifiers give the useful relations:

$$
\begin{aligned}
\forall \xi \in \boldsymbol{x}, \forall \eta \in \boldsymbol{y} : \xi < \eta
  &\iff \sup\boldsymbol{x} < \inf\boldsymbol{y} \iff \overline{x} < \underline{y}
  && \texttt{definitely\_lt} \\
\exists \xi \in \boldsymbol{x}, \exists \eta \in \boldsymbol{y} : \xi = \eta
  &\iff \boldsymbol{x} \cap \boldsymbol{y} \ne \emptyset \iff \underline{x} \le \overline{y} \wedge \underline{y} \le \overline{x}
  && \texttt{maybe\_eq}
\end{aligned}
$$

For the first line, "$\Leftarrow$" is $\xi \le \overline{x} < \underline{y}
\le \eta$. For "$\Rightarrow$": if $\overline{x}$ and $\underline{y}$ are
finite they are elements, so $\overline{x} < \underline{y}$; if
$\overline{x} = +\infty$ or $\underline{y} = -\infty$, a large $\xi$ or a
small $\eta$ violates $\xi < \eta$, and the endpoint test is false as well. The second line is the
nonempty intersection of two intervals. "Possibly less" is the negation of
"certainly not less", so the two families are dual: `definitely_lt(x, y)` is
false exactly when some pair satisfies $\xi \ge \eta$. With empty operands the
universal statements would be vacuously true, which would let a caller prove
anything from an empty enclosure; the `definitely_*` relations therefore
return false for empty operands, whereas the IEEE 1788 relation `precedes`
($\forall\xi\,\forall\eta: \xi \le \eta$) is defined to be vacuously true.

The set relations (`subset`, `interior`, `disjoint`, `set_equal`) and the
IEEE 1788 orders (`less`: $\forall\xi\,\exists\eta\, \xi \le \eta$ and
$\forall\eta\,\exists\xi\, \xi \le \eta$, which reduces to comparing both
endpoint pairs) are evaluated by endpoint comparisons in the same way. None of
these relations is a total order, and the trait method
`@lf_arith.Contains::contains(x, y)` is set inclusion
$\boldsymbol{y} \subseteq \boldsymbol{x}$, matching the enclosure reading of
the [`arithmetic`](https://lunaflow.cn/en/arithmetic/) traits.

## Design decisions

### Endpoints, not midpoint and radius

*Problem.* A ball can be stored as endpoints $[\underline{x}, \overline{x}]$
(inf–sup) or as a midpoint and radius $\langle m, r\rangle$, as in Arb.[^arb]

*Midpoint–radius arithmetic.* With $x = m_x + \delta_x$, $|\delta_x| \le r_x$
and likewise for $y$:

$$
\begin{aligned}
x + y &= (m_x + m_y) + (\delta_x + \delta_y), & |\delta_x + \delta_y| &\le r_x + r_y, \\
xy - m_x m_y &= m_x\delta_y + m_y\delta_x + \delta_x\delta_y, & |xy - m_x m_y| &\le |m_x| r_y + |m_y| r_x + r_x r_y .
\end{aligned}
$$

With a rounded midpoint $m = \operatorname{RN}_p(m_x \circ m_y)$, the rounding
error $|m - m_x \circ m_y| \le 2^{-p}|m|$ is added, so

$$
r_{x+y} = \operatorname{RU}\bigl(r_x + r_y + 2^{-p}|m|\bigr), \qquad
r_{xy} = \operatorname{RU}\bigl(|m_x| r_y + |m_y| r_x + r_x r_y + 2^{-p}|m|\bigr).
$$

These are cheap (the radius needs only a few bits), but the product radius
overestimates: for $\boldsymbol{x} = \boldsymbol{y} = \langle 1, 1\rangle =
[0, 2]$ it gives $\langle 1, 3\rangle = [-2, 4]$ while the exact product is
$[0, 4]$. Rump showed that the width can grow by a factor up to $1.5$ per
multiplication compared to inf–sup.[^rump]

*Options.* (a) midpoint–radius storage with low-precision radii; (b) endpoint
storage with full-precision endpoints; (c) both.

*Chosen: (b).* IEEE 1788 is defined on endpoints, half-unbounded and empty
sets have no midpoint–radius form, and the hulls in the
[endpoint formulas](#endpoint-formulas) are exact before rounding, so
inf–sup results are as tight as the precision allows. The cost is that both
endpoints carry $p$ bits, so wide intervals at high precision store many
useless bits. The midpoint–radius *view* (`new`, `center`, `radius`,
`with_precision`) is kept for users who reason in $c \pm r$, with exact
conversions derived [above](#from-midpointradius-to-endpoints).

[^arb]: J. van der Hoeven, "Ball arithmetic", 2009; F. Johansson, "Arb: efficient
    arbitrary-precision midpoint-radius interval arithmetic", *IEEE Trans.
    Computers* 66(8), 2017.

[^rump]: S. M. Rump, "Fast and parallel interval arithmetic", *BIT* 39(3),
    1999.

### Exact candidates, one directed rounding

*Problem.* Endpoint candidates can be computed with directed rounding at each
step, or exactly and rounded once.

*Chosen.* Sums and products of `BinFloat` endpoints are formed exactly (the
coefficient grows to hold them), and `quantize_interval` applies one
$\operatorname{RD}_p$/$\operatorname{RU}_p$ at the end; by property (iii) the
result is the tightest $p$-bit enclosure of the exact hull. Division and
square root, whose exact results are not dyadic, are computed directly with
directed rounding at precision $p$. The rule needs two safeguards, described
next: bounded alignment of far-apart addends and outward clamping at the edge
of the exponent range.

### Far addends: bound endpoint sums by precision

*Problem.* Adding $A = 2^{10^9}$ and $s = 2^{-10^9}$ exactly aligns the two
coefficients and builds a two-billion-bit number (about 750 MB for one
interval addition, issue #24).

*Chosen.* Let $t(v)$ be the exponent of the leading bit of $v$, $e(A)$ the
exponent of the last bit of the larger addend $A$,
$M = \max(65536, \operatorname{prec}(A), \operatorname{prec}(s))$ and
$c = \min(e(A), t(A) - M)$. If $t(s) < c - 2$, the small addend is replaced by
a sticky surrogate $s' = \operatorname{sign}(s)\,2^{c-2}$ when $s$ pushes the
sum in the rounding direction of the endpoint being computed, and by $s' = 0$
otherwise. Then:

- **Soundness, for every precision.** $|s| < 2^{t(s)+1} \le 2^{c-2}$. An upper
  endpoint with $s > 0$ gets $A + 2^{c-2} > A + s$; with $s < 0$ it gets
  $A > A + s$. Lower endpoints are symmetric. So the directed sum stays on the
  required side of the exact sum, which is all the inclusion property needs.
- **No loss of tightness when $p \le M$.** The $p$-bit numbers near $A$ are
  multiples of $2^{t(A) - p}$, and $t(A) - p \ge t(A) - M \ge c$, so no
  $p$-bit number lies strictly between $A$ and $A \pm 2^c$; both $A + s$ and
  $A + s'$ fall in the same gap and round to the same endpoint (Lemma 7 of the
  attachment).

The alignment now costs at most about $M$ bits beyond the width of $A$,
independent of the exponent gap. The surrogate is also used for the
nearest-rounded sums inside `center`, where it is not exact; this is the
source of the limitation noted in [Correctness](#known-limitations).

### Outward clamping at the exponent range

`BinFloat` has a finite (very wide) exponent range. An exact candidate beyond
it cannot be stored, so the exact helpers take the direction of the endpoint
being built: lower endpoints clamp toward $-\infty$, upper endpoints toward
$+\infty$, radii round up, and exponent sums are computed in 64 bits and
saturated. This keeps, for example, $\exp([10^9, 10^9])$ an enclosure
$[\text{largest finite}, +\infty)$ instead of collapsing it.

### Contexts and double rounding

`BallContext` carries a target precision $q$ and exponent range;
`apply_ctx` rounds endpoints outward into it and the `*_ctx` operations
compute at the operands' precision $p$ and then apply the context. Rounding
twice is harmless for directed rounding when $q \le p$:

$$
\operatorname{RD}_q(\operatorname{RD}_p(a)) = \operatorname{RD}_q(a) \quad (q \le p),
$$

because $F_q \subseteq F_p$ (a $q$-bit significand is a $p$-bit one padded with
zeros): every $f \in F_q$ below $a$ is in $F_p$, hence below
$\operatorname{RD}_p(a)$, and conversely. So `x.add_ctx(y, ctx)` equals a
single outward rounding of the exact sum into the context whenever the
operands are at least as precise as the context. Overflow is resolved in the
enclosing direction: an upper endpoint above the range becomes $+\infty$, a
positive lower endpoint becomes the largest finite number (still below the
true value). Underflow rounds outward on the subnormal grid, so a tiny
positive upper bound becomes the smallest subnormal and never 0. The flags
are returned, never stored globally.

### Total and `try_` forms

*Problem.* Certified evaluation can fail: the refinement budget may run out,
or an argument may be too large to reduce. Aborting would break long
computations; returning a silent wide interval hides a lost guarantee of
tightness.

*Chosen.* Both. The total forms return a valid fallback enclosure
($[-1, 1]$ for `sin`/`cos`, Entire for `tan`, $[-\pi, \pi]$ for `atan2`,
the composed formula for `pow`, `hypot` and `rootn`, the range bounds
$[-1, +\infty)$ for `expm1`), which keeps the inclusion property; the `try_`
forms return an `ArithmeticError` with a certification detail (operation,
stage, reason, precision). Trigonometric reduction is capped: when the larger
endpoint magnitude is at least $2^{\max(65536, 4p)+1}$, reduction would need
more than that many bits, so the total forms return the fallback immediately
and the `try_` forms report a resource limit.

### Decorations in a separate type

*Problem.* Decorations cost a field and a minimum per operation, and most
users do not need them.

*Chosen.* `BallFloat` is the bare set; `BallFloatDecorated` wraps it with a
decoration and the NaI state. Bare operations stay cheap and simple, and the
decorated type cannot be mixed with bare values by accident.

### Precision as a tag

Each interval carries a precision tag; binary operations use the larger tag.
This keeps a sequence of operations at the precision of its most precise
input without a context argument, which is what a set-valued type needs to
compose with operators (`x + y`). A `BallContext` is used when a specific
format must be imposed.

## Correctness and invariants

**Representation invariant.** A non-empty `BallFloat` has non-NaN endpoints,
$\underline{x} \le \overline{x}$, $\underline{x} \ne +\infty$,
$\overline{x} \ne -\infty$ and precision $\ge 1$; every construction path
ends in `store_interval`, which checks this and aborts otherwise. Empty is a
flag with endpoints $(+\infty, -\infty)$.

**Inclusion.** Each public operation $F$ of `BallFloat` satisfies
$f(\boldsymbol{x}) \subseteq F(\boldsymbol{x})$, by the endpoint formulas and
Corollary 2 for arithmetic, by the critical-point analysis and certified
endpoint enclosures for elementary functions, and by the fallbacks for
uncertified cases (the exceptions are listed under known limitations). By the
fundamental theorem, so does every composition.

**Tightness.** Basic arithmetic, `square`, `pown`, `fma`, `abs`, `minimum`,
`maximum`, `intersection`, `convex_hull` of non-empty operands and
`sqrt_interval` return the outward rounding of the exact hull, so each
endpoint is within one ulp of optimal. Trigonometric and arctangent endpoints
are correctly directed roundings when certified; the other elementary
functions are usually within a few ulps. Not tight: fallbacks; `pown` with
$n < -4096$ and 0 inside (Entire); the total hyperbolic functions for
$|\xi| \lesssim 2^{-190}$ (cancellation, see above); and everything that
goes through the center–radius rebuild of `with_precision`, which can widen
by one ulp per side even at an unchanged precision. At 53 bits,
$[1, 1 + 2^{-52}]$ has center $1 + 2^{-53}$, which needs 54 bits; rounding it
to 1 and adding the displacement $2^{-53}$ to the radius gives
$[1 - 2^{-52}, 1 + 2^{-52}]$. This affects `with_precision`, `normalized`,
`convex_hull` with an Empty operand and the checked capabilities; it is
tracked in [#69](https://github.com/Luna-Flow/floating/issues/69), with a fix proposed in [#91](https://github.com/Luna-Flow/floating/pull/91). The
`Floating` law "normalizing keeps the value" therefore holds for `BallFloat`
only as an enclosure: $\boldsymbol{x} \subseteq
\operatorname{normalized}(\boldsymbol{x})$.

**Decorations.** The decoration of a result is a true statement about the
function evaluated, by the induction argument above.

**Complexity.** Arithmetic performs at most four endpoint products or two
sums, $O(M(p))$ for $p$-bit endpoints with multiplication cost $M(p)$, plus
alignment of at most about $65536 + p$ bits for sums. Elementary functions sum
series of $O(w)$ terms at work precision $w = p + O(1)$ (plus the
integer bits of the argument for trigonometric reduction), with up to 12
refinements growing $w$ geometrically.

**Evidence.** Package tests check directed endpoints, the far-addend and
exponent-range cases, decorations and relations; the pinned ITF1788 corpus
runs 4,656 cases in strict mode (see [conformance](../conformance/ball_float.md)).

### Known limitations

The following inputs currently lose part of the input set, round or flag a
result incorrectly, or return a set other than the specified one. Each is
tracked in an issue with a proposed fix that is not merged yet; they are
documented here so that callers can avoid them.

- `with_precision` (and therefore `normalized`) rebuilds a bounded interval
  from `center()`, which uses the far-addend surrogate with
  round-to-nearest. For endpoints more than about $2^{16}$ binary orders of
  magnitude apart and a new precision large enough to store the surrogate
  exactly (more than about 65536 bits), the result can lose the smaller
  endpoint. Tracked in [#44](https://github.com/Luna-Flow/floating/issues/44); a fix is proposed in [#68](https://github.com/Luna-Flow/floating/pull/68).
- `midpoint_ctx` does not apply the context's $e_{\max}$ and never raises
  `overflow`. It also rounds to nearest twice (to $p$ bits, then onto the
  subnormal grid), so a subnormal midpoint can be the wrong neighbour: with
  $p = 4$, $e_{\min} = -2$, the center $2^{-6} + 2^{-20}$ gives 0 instead of
  $2^{-5}$. Tracked in [#46](https://github.com/Luna-Flow/floating/issues/46) and [#70](https://github.com/Luna-Flow/floating/issues/70); a fix is proposed in [#91](https://github.com/Luna-Flow/floating/pull/91).
- `apply_ctx` raises `underflow` only when the subnormal-grid step is
  inexact, not for every tiny inexact endpoint as IEEE 754 does. Tracked in
  [#71](https://github.com/Luna-Flow/floating/issues/71); a fix is proposed in [#91](https://github.com/Luna-Flow/floating/pull/91).
- `pow_nat_checked(Empty, 0)` returns $\{1\}$ (the power loop starts from
  $\{1\}$ without checking the base), whereas `pown(Empty, 0)` is Empty.
  Tracked in [#72](https://github.com/Luna-Flow/floating/issues/72); a fix is proposed in [#91](https://github.com/Luna-Flow/floating/pull/91).

## Alternatives rejected

- **Midpoint–radius storage** (Arb-style): cheaper radii, but overestimating
  products and no representation for half-unbounded sets; see
  [above](#endpoints-not-midpoint-and-radius).
- **Hardware `Double` endpoints with switched rounding modes:** fixed
  precision, process-global state, and rounding-mode control is not available
  on every MoonBit target.
- **Round to nearest and inflate by one ulp** ("epsilon inflation"): simpler,
  but about one ulp wider per endpoint than directed rounding, and only valid
  for operations whose nearest-rounded result is known to be within one ulp,
  which excludes most elementary function kernels.
- **Aborting on uncertified elementary functions:** a single hard argument
  would stop a whole computation; the `try_` forms cover callers who need the
  failure.
- **Treating division by zero-containing intervals as an error:** IEEE 1788
  defines these results as sets (Entire, half-unbounded or empty), and
  extended division is what makes interval Newton methods work.

## Boundaries

The package deliberately does not:

- provide the IEEE 1788 reverse operations (`sqrRev`, `mulRevToPair`, …) or
  two-output division;
- promise tight results: fallbacks and the dependency problem may widen
  enclosures arbitrarily;
- define a total order on intervals, or treat `Eq` as set equality;
- convert decimal data outward on its own: `from_double` and `exact` enclose
  binary values, and enclosing a decimal literal is the caller's job (see the
  [tutorial](../tutorial/ball_float.md#enclose-a-decimal-constant));
- implement intervals over decimal endpoints, complex balls, interval vectors
  or matrices, or Taylor models;
- report status through global flags: flags come back from `*_ctx` calls and
  decorations travel with values.
