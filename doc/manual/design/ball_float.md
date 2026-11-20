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
than $p$ bits). The construction is sound but not idempotent: whenever
$\tilde c \ne c$, the displacement $|c - \tilde c|$ is added on both sides, so
rebuilding an interval whose center needs more than $p$ bits widens it (see
[Tightness](#correctness-and-invariants)). `normalized` accepts that;
`with_precision` does not use the construction at all. It rounds the endpoints
outward directly, which encloses the input at every precision and is the
tightest representable enclosure, so it has no rounding-mode argument. The
converse view inside the package is exact: the center is
$(\underline{x} + \overline{x})/2$ and the half-width $(\overline{x} -
\underline{x})/2$, which are dyadic and need no rounding (the half-width is
rounded up only if it underflows the exponent range), so
$[\text{center} - \text{half-width}, \text{center} + \text{half-width}]$ is
exactly the stored interval. `Show` prints this pair. The public observers are
not this pair: IEEE 1788-2015 12.12.8 defines `mid` as the center rounded to
the format and `rad` as the smallest number of the format with the interval
inside $[m - r, m + r]$ for that rounded $m$. The half-width around the exact
center is too small when the center is not representable (it was returned as
`radius` before 0.12, [issue 477](https://github.com/Luna-Flow/floating/issues/477)),
so `radius` measures from `midpoint`: it is the larger of $m - \underline{x}$ and
$\overline{x} - m$, rounded up.

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
this reason the package provides single-occurrence operations — `sqr`,
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

`pow(x, y)` on the domain $\xi > 0$ (and $\xi = 0$, $\eta > 0$) writes
$\xi^\eta = \exp(\eta u)$ with $u = \ln \xi$. The map $(u, \eta) \mapsto \eta u$
is bilinear, so by the corner argument used for products its extrema over the
box $[\ln \underline{x}, \ln \overline{x}] \times \boldsymbol{y}$ are at the
corners, and $\exp$ is increasing: the extrema of $\xi^\eta$ are among the four
corner values. When $\underline{x} = 0$, $u \to -\infty$ and the corner values
become the limits $0$ (for $\eta > 0$) and $+\infty$ (for $\eta < 0$). The
code also adds the value 1 when the box crosses $\xi = 1$ or $\eta = 0$; such
a box contains a point where $\eta u = 0$, so $e^0 = 1$ already lies between
the extreme corner values and the extra candidate is redundant but harmless.

`atan2` is handled the same way: the result is $[-\pi, \pi]$ when the box
crosses the branch cut on the negative $\xi$ axis, and otherwise the extrema
over the box are at corners, as the next section shows.

### One evaluation per bound

A bound of an interval result needs one directed evaluation, not the two
(down and up) of which half used to be discarded, and often not even a second
endpoint. Directed rounding is monotone: if $a \ge b$ then
$\mathrm{RD}(a) \ge \mathrm{RD}(b)$ and $\mathrm{RU}(a) \ge \mathrm{RU}(b)$.
So the lower bound $\min_i \mathrm{RD}(f(c_i))$ over candidate points $c_i$
equals $\mathrm{RD}(f(c^*))$ where $c^*$ minimises $f$ itself, and likewise
for the upper bound. The results are therefore bit-identical to the
evaluation of every candidate in both directions; only the argument that
$c^*$ is the minimiser has to be written down, once per case.

| Operation | Evaluations before | After |
| --- | --- | --- |
| interval division | 4 `div_ctx` | 2 (one directed quotient per bound) |
| `sqrt` | 4 `sqrt_ctx` | 2 |
| product, one factor straddling zero, the other sign-definite | 4 products | 2 |
| product with an unbounded factor | 8 products | 4 (the coefficient product of a finite pair is shared by both directions) |
| `pown`, even exponent, negative or zero-containing interval | 4 or 3 `pown_ctx` | 2 |
| `try_atan2` | 8 to 16 `try_atan2_ctx` | 2 |
| `try_sinpi`, `try_cospi` | 4 | 2 (also 2 with one extremum inside, 0 with an extremum of each kind) |
| `try_sin`, `try_cos` | 8 exact-rational series per refinement round, plus $\pi$ per round | 2 correctly rounded binary evaluations, and one $\pi$ enclosure |
| `try_tan` | 8 series per round, plus $\pi$ per round | 2 evaluations, and one $\pi$ enclosure |

**Division and square root.** The lower bound of $\boldsymbol{x} /
\boldsymbol{y}$ is one quotient of two endpoints (chosen by the signs, see
the corner argument above) rounded down, the upper bound one quotient rounded
up. The square root needs $\sqrt{\underline{x}}$ rounded down and
$\sqrt{\overline{x}}$ rounded up.

**Products.** If $\boldsymbol{a}$ straddles zero and $\boldsymbol{b} \ge 0$
($\boldsymbol{b} \ne [0, 0]$), then $a \mapsto ab$ is nondecreasing for each
$b \ge 0$ and $b \mapsto ab$ is nondecreasing for $a \ge 0$ and
nonincreasing for $a \le 0$, so the minimum is $\underline{a}\,\overline{b}$
and the maximum $\overline{a}\,\overline{b}$ (the other three sign cases are
mirror images). Two factors that both straddle zero keep the four products.

**`atan2`.** Away from the origin and the branch cut,
$\partial \theta / \partial y = x / r^2$ and
$\partial \theta / \partial x = -y / r^2$. For $y \ge 0$ the angle is
nonincreasing in $x$, so the minimum has $x = \overline{x}$ and the maximum
$x = \underline{x}$; at that $x$ the angle is nondecreasing in $y$ if
$x > 0$, nonincreasing if $x < 0$, and constant ($\pi/2$) at $x = 0$. For
$y \le 0$ (with $\underline{y} < 0$) the angle is nondecreasing in $x$ and the
same rule applies to $y$. If $\boldsymbol{y}$ straddles zero the branch-cut
case has been excluded, so $\underline{x} \ge 0$ and both bounds sit at
$x = \underline{x}$ (the minimum at $\underline{y}$, the maximum at
$\overline{y}$). A zero endpoint of $\boldsymbol{y}$ belongs to the side of
the other endpoint: $\mathrm{atan2}(+0, x < 0) = \pi$ is the limit from
$y > 0$ and $\mathrm{atan2}(0, x > 0) = 0$ the limit from $y < 0$. Every
edge of the box is therefore monotone and the extrema over a box are at
corners, also when the origin is a corner or lies on an edge, since the
angles seen near the origin are those of the neighbouring corners. The axis
points that earlier versions added are between these two extremes. A box
whose extreme corner is the origin (a degenerate box) uses the general
corner hull.

**`sinpi`, `cospi`, `sin`, `cos`.** With the index range $K$ of the previous
section, an extremum of each kind inside gives $\pm 1$ without evaluation.
Without any extremum inside, $\boldsymbol{x}$ lies in one arc between two
consecutive extrema and the function is monotone there: sine increases
through an index $\equiv 0 \pmod 4$ and decreases through $\equiv 2$ (when
$K$ contains an index), and otherwise the arc is $k = \lceil q^- \rceil - 1$,
increasing for $k \equiv 0, 3$ and decreasing for $k \equiv 1, 2$. Cosine is
sine shifted by one index. The lower bound is then the endpoint value rounded
down at the lower end of the arc direction and the upper bound the other
endpoint rounded up; with one extremum inside, the opposite bound is the
better of the two endpoints.

**`sin`, `cos`, `tan` (`try_` forms).** Each endpoint value is the correctly
rounded value of the binary kernel in the directed mode, which is the value
the exact-rational series produced (it rounded an enclosure that rounded
uniquely). The enclosure of $\pi$ is needed only for the index range $K$ (the
critical points and the poles); it is taken once from `certified_pi_interval`
with $w + 48$ bits, where $w = p + m + 96$ is the working precision of the
first refinement round ($p$ the precision of the interval, $m$ the binade of
the larger endpoint). Its width, about $2^{-(w + 47)}$, is smaller than that of
the rational enclosure of the old refinement loop (about $2^{-(w + 19)}$), so
$K$ is contained in the first-round range of the old code. The old code
decided a pole at its first round too, so `try_tan` returns the whole
line only where the old code did. What is identical by construction: every
endpoint value, and the result whenever the old code needed no refinement
round. What is not: when the old code refined (an endpoint within about
$2^{-w}$ of a multiple of $\pi/2$) it used a narrower $K$ of a later round, and
the new $K$ can then hold a spurious index, only for
$|\xi - k\pi/2| < 2^{-(p + 140)}$ (an absolute bound that does not depend on
the number of bits of the endpoint). A spurious extremum does not change a
sine or cosine bound, since that close to an extremum the directed value
already rounds to $\pm 1$; a spurious pole makes the tangent the whole line,
which keeps the inclusion property. The tests compare old and new bit for bit
on the binary64 number closest to a multiple of $\pi/2$
($6381956970095103 \cdot 2^{797}$) and on the correctly rounded $\pi/2$ and
$3\pi/2$ with their neighbours at 24, 53 and 113 bits, and no input differs.
The non-`try` `sin`, `cos` and `tan` are these
`try_` forms with a fallback: they return $[-1, 1]$ (Entire for `tan`) for an
argument the kernel cannot certify, which the `try_` forms report as an
error.

### Certified evaluation of transcendental endpoints

$e^{\underline{x}}$ is not a dyadic number, so an endpoint needs a directed
rounding of the exact value: $\operatorname{RD}_p(f(a))$ is a valid lower
endpoint and $\operatorname{RU}_p(f(b))$ a valid upper endpoint by property
(i). This package does not implement the series itself. Each endpoint is
evaluated by the certified `try_*_ctx` function of
[`bin_float`](bin_float.md) in an unbounded context of the interval's
precision, rounded toward $-\infty$ for a lower bound and toward $+\infty$ for
an upper bound; those functions refine a working precision until the two
directed roundings agree (a Ziv-style acceptance test[^ziv]) and report a
certification failure when the work budget runs out.

What this package adds is the interval analysis around the point kernels:
the domain restriction (an argument outside the domain is dropped, and the
result is Empty when nothing is left, which is decided by comparisons before
any kernel runs), the monotonicity and critical-point analysis of the
previous section (which endpoint gives which bound, where an extremum of
`sin` or a pole of `tan` lies), the handling of infinite endpoints, and the
fallback range. An enclosure of $\pi$ is needed only to locate critical points
and poles of the trigonometric functions, and for the fallbacks of the inverse
trigonometric functions; it comes from the cached binary-splitting constant of
`bin_float` (`atan(+inf)` is $\pi/2$ correctly rounded in each direction,
and the scaling by 2 is exact).

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

#### Integer functions

`sign`, `ceil`, `floor`, `trunc`, `roundTiesToEven` and `roundTiesToAway`
(IEEE 1788-2015 Table 9.1) are nondecreasing with integer values, so the bare
result is $[f(\underline{x}), f(\overline{x})]$ and no rounding happens. Their
decoration needs one observation: a function with values in $\mathbb{Z}$ (or
$\{-1, 0, 1\}$) restricted to an interval is continuous exactly when it is
constant on it, by the intermediate value theorem. So the strongest
decoration $d_g$ of 11.2 is `def` when $f(\underline{x}) \ne f(\overline{x})$.
When $f$ is constant, `dac` holds, and `com` holds when in addition
$\boldsymbol{x}$ is bounded and contains no point where $f$ is discontinuous
on the real line. With $k = f(\underline{x}) = f(\overline{x})$ that last test
is an endpoint comparison, because a constant box lies in a single step of the
function:

| Function | Points of discontinuity | $\boldsymbol{x}$ contains one iff |
| --- | --- | --- |
| `ceil` | integers, $\operatorname{ceil}(n) = n$ | $\overline{x} = k$ |
| `floor` | integers, $\operatorname{floor}(n) = n$ | $\underline{x} = k$ |
| `trunc` | nonzero integers | $k > 0$: $\underline{x} = k$; $k < 0$: $\overline{x} = k$; $k = 0$: never |
| `sign` | $0$ | $k = 0$ |
| `roundTiesToEven`, `roundTiesToAway` | $n + 1/2$ | $\underline{x} = k - 1/2$ or $\overline{x} = k + 1/2$ |

This is why the ITF1788 corpus has `ceil([1.1, 2.0]_com) = [2, 2]_dac` (the
restriction is constant, but $2$ is a point of discontinuity) next to
`floor([-1.2, -1.1]_com) = [-2, -2]_com`. An unbounded box is never `com`, and
is `def` for `ceil`, `floor`, `trunc` and the roundings (the function is not
constant on it), `dac` for `sign` on a half line that excludes 0. The
corpus's 55 decorated integer-function cases and the tests of the package
(each function with the jump as the lower endpoint, the upper endpoint, a point
box and in the interior) agree with this rule.

#### Reverse multiplication and two-output division

$\boldsymbol{c} /_{\text{set}} \boldsymbol{b}$ (IEEE 1788-2015 10.5.5) is
computed by cases on whether $0 \in \boldsymbol{c}$ and $0 \in \boldsymbol{b}$.
Both intervals are nonempty (otherwise the set is empty).

| $0 \in \boldsymbol{c}$ | $0 \in \boldsymbol{b}$ | Set |
| --- | --- | --- |
| yes | yes | $\mathbb{R}$: $x \cdot 0 = 0 \in \boldsymbol{c}$ for every $x$ |
| any | no | the interval quotient $\boldsymbol{c} / \boldsymbol{b}$ (closed endpoints; the endpoint 0 of an unattained limit is open when $0 \notin \boldsymbol{c}$) |
| no | $\boldsymbol{b} = \{0\}$ | empty |
| no | $0 \in \boldsymbol{b}$, $\boldsymbol{b} \ne \{0\}$ | only $y \ne 0$ contributes: one or two components below |

In the last row let $n$ be the end of $\boldsymbol{c}$ nearest to zero. The
divisor values $y \in [\underline{b}, 0)$ give $x \le n / \underline{b}$ when
$\boldsymbol{c} > 0$ and $x \ge n / \underline{b}$ when $\boldsymbol{c} < 0$;
the values $y \in (0, \overline{b}]$ give $x \ge n / \overline{b}$ when
$\boldsymbol{c} > 0$ and $x \le n / \overline{b}$ when $\boldsymbol{c} < 0$.
A divisor side exists only when $\underline{b} < 0$, respectively
$\overline{b} > 0$. The quotient $n / \pm\infty$ is 0 and is the unattained
end of the component, so that component is open there. Each finite quotient is
rounded outward, which keeps the closure a valid enclosure and tight in the
type (the exact endpoint is attained, because $y = \underline{b}$ or
$\overline{b}$ is in $\boldsymbol{b}$).

`mul_rev_to_pair` closes the components. `mul_rev(b, c, x)` intersects each
component, with its open ends, with the closed interval $\boldsymbol{x}$ and
takes the hull of what is nonempty (a lower end $L$ and upper end $U$ meet
when $L < U$, or $L = U$ and both ends are closed). This is why the hull of
the set and the intersection of $\boldsymbol{x}$ with its hull differ: for
$\boldsymbol{b} = [-1, 1]$, $\boldsymbol{c} = [1, 1]$ the set avoids $(-1, 1)$,
so the prior $[0, 0.5]$ gives Empty. All 533 corpus cases of `mulRev`,
`mulRevTen` and `mulRevToPair` agree with the construction.

#### Reverse functions of even and monotone algebraic functions

`sqr_rev`, `abs_rev`, `cosh_rev` and `pown_rev` (IEEE 1788-2015 10.5.4) share
one scheme. The preimage of $\boldsymbol{c}$ under $\varphi$ is a union of at
most two intervals, found from the inverse of $\varphi$ at the ends of
$\boldsymbol{c}$ after cutting $\boldsymbol{c}$ to the range of $\varphi$:

- for an even $\varphi$ ($x^2$, $\lvert x\rvert$, $\cosh$, an even $x^p$) with
  inverse $r$ on the positive side, and $\boldsymbol{c}' = \boldsymbol{c} \cap
  \text{range}$: the two pieces $[-r(\overline{c'}), -r(\underline{c'})]$ and
  $[r(\underline{c'}), r(\overline{c'})]$;
- for an odd $x^p$ with $p > 0$, increasing: $[r(\underline{c}), r(\overline{c})]$;
- for a negative power, $x^p$ is decreasing on each side of the pole 0, so the
  roles of the two ends swap, $x = 0$ is excluded, and the end of a piece at 0 is
  open: the unbounded end of $\boldsymbol{c}$ gives $r = 0$, which is only a
  limit.

Each finite end is one directed rounding of the exact root of one exact
endpoint (`sqrt`, `rootn`, `acosh` of a point interval), so the closed pieces are
the tightest in the type. The hull with the prior $\boldsymbol{x}$ meets each
piece, with its open ends, with $\boldsymbol{x}$ and takes the hull of the
nonempty parts, the same routine as `mul_rev`. The trivial decoration (`trv`)
is attached by the decorated forms. All 360 corpus cases of these functions in
`libieeep1788_tests_rev.itl` and `abs_rev.itl` agree.

#### Reverse sine, cosine and tangent

`sin_rev`, `cos_rev` and `tan_rev` (IEEE 1788-2015 10.5.4) return the hull of the part
of a periodic union of intervals that lies in the prior $\boldsymbol{x}$. A piece end has
the form $t = \tfrac{m}{2}\pi + \sigma\,\alpha(s)$ with an integer $m$, $\sigma = \pm 1$
and $\alpha$ one of $\arcsin$, $\arccos$, $\arctan$ of an endpoint $s$ of $\boldsymbol{c}$ (a pole of
$\tan$ has no $\alpha$). The result takes the piece ends that matter, so the
comparison of a prior end with a piece end has to be exact; a wrong answer there moves
a result end by a whole period (for example `sin_rev([0, 0], x = [RU(pi), 6])`).

*Which piece ends can be floats.* If $t = d$ with $d$ a nonzero float, then $d$ is
algebraic, and so is $s$. For $\sin d = \pm s$ the Lindemann-Weierstrass theorem says
$e^{id}$ is transcendental, so $\sin d$ cannot be algebraic; the same holds for $\cos d$
and $\tan d$. Every end is therefore irrational (a pole $\pm\pi/2 + \pi k$ and the ends
from $s = \pm 1$ are nonzero rational multiples of $\pi$) except $t = 0$, which needs
$m = 0$ and $\alpha = 0$: $\arcsin 0$ and $\arctan 0$, and $\arccos 1$. Those
ends are compared with the prior by an exact test, and every other end has a strict
answer for every float $d$. A pole therefore never equals a float, and the trigonometric
reverse functions need no open flag.

*Comparison and rounding.* Each end is evaluated as an enclosure at a working precision
$w$, starting at $p + b + 96$ bits ($b$ the binary exponent of the larger prior end),
from the certified enclosure of $\pi$ and the certified `asin`, `acos`, `atan` of the
exact point $s$. A comparison with a prior end $d$ is decided as soon as the enclosure
excludes $d$, else $w$ is doubled. The value written for a result end is the outward
rounding of an enclosure that contains no float of the result precision, which is exactly
$\operatorname{RD}(t)$ or $\operatorname{RU}(t)$; here too $w$ is doubled until that holds. The first
step is enough for almost every input, and not for all: a float can lie within a small
fraction of an ulp of a multiple of $\pi/2$, which is why the loop is needed. The loop is
capped at 12 doublings (the same budget as the certified forward functions). At the cap an
undecided comparison counts as met in both conditions (a piece that might meet the prior is
never dropped) and the end written for such a piece is the prior's own end, a valid bound of
both possibilities; a rounding is that of the last enclosure. The result is then an enclosure
of the hull, possibly wider. A white-box test sets the cap to 0 and to 1 and checks, on cases
of the reference test, that the result contains the hull and stays inside the prior. The pinned ITF1788 corpus never leaves the first
step: its 136 cases need $w = p + b + 96$ at most.

*Pieces and indices.* A piece $[\mathrm{lo}(k), \mathrm{hi}(k)]$ belongs to a family
with $m = \text{offset} + \text{period} \cdot k$ (period 4 for $\sin$ and $\cos$, in units of
$\pi/2$ twice, and 2 for $\tan$). The first piece that reaches the lower prior end $x_l$ has
its upper end in a window of a dozen consecutive values of $m$ around $2 x_l/\pi$, which is
computed exactly in rational arithmetic from the lower and upper bound of the enclosure of
$\pi$, widened by a stated margin: an end lies in $[(m-2)\pi/2, (m+2)\pi/2]$ since
$\lvert\alpha\rvert \le \pi$, so a piece below the window cannot reach $x_l$ and the
predecessor of a piece above it already does. The same holds at $x_h$ with the lower ends.
Every piece of the window is tested for meeting the prior (`hi >= x_l` and `lo <= x_h`, both
exact), the lower end of the result is the minimum over the met pieces of $x_l$ or
$\operatorname{RD}(\mathrm{lo})$, and the upper end the maximum of $x_h$ or
$\operatorname{RU}(\mathrm{hi})$; no two transcendental ends are compared with each other, since
$\operatorname{RD}$ is monotone. The work is two searches of a few pieces each, whatever
the prior spans, and its cost follows the number of bits of the period index through the
working precision. The only limit is the one of the forward functions: an end of the prior at
or beyond $2^{\max(65536, 4p)+1}$ is kept (valid, not tight). It is decided before any work
(the working precision comes only from the ends inside it, and a prior whose finite ends are
all beyond it is returned at once), so such an end never costs $\pi$ at its precision.

*Tightness against the corpus.* The tests compare the result with an enumeration of every
piece (`trig_reverse_reference_wbtest.mbt`), with no index arithmetic in common with the
implementation, over 4,200 random cases at precisions 24 and 53 that include priors with an end next
to a piece end. Six distinct corpus cases (twelve with the decorated copies) have an
expected value that is one or two ulps wider than the hull; they are listed on the
[conformance page](../conformance/ball_float.md).

#### Reverse power with an interval exponent

`pow_rev1(b, c, x)` (IEEE 1788-2015 10.5.4) reduces to the set division of `mul_rev` in logarithm
coordinates (see the [API page](../api/ball_float.md#ballfloatpow_rev1)): the pieces of
$\exp(L /_{\text{set}} \boldsymbol{b})$ come from the same case split as $c /_{\text{set}} b$
(whether $0 \in L$, that is $1 \in \boldsymbol{c}$, and whether $0 \in \boldsymbol{b}$), with the
sign of an end of $L$ decided by comparing the end of $\boldsymbol{c}$ with 1. The end $x = 0$ of
a piece is open (it comes from $\ln x \to -\infty$); the zero part $\{0\}$ is a piece of its own;
$x = 1$ is open when it is the limit of a quotient by an unbounded $\boldsymbol{b}$ and attained when
$c_\text{end} = 1$; every other finite end is attained.

*Exactness of an end* $x = c^{1/\beta}$, $c > 0$, $\beta \ne 0$ finite. Write $\beta = s\,u\,2^j$
and $c = C\,2^\gamma$ with $u$ and $C$ odd, $p = 2^{\max(-j, 0)}$ and $q = u\,2^{\max(j, 0)}$. Then
$x = c^{s p / q}$ with $\gcd(p, q) = 1$, and $x$ is rational iff $c$ is a perfect $q$-th power in
$\mathbb{Q}$, that is $C = m^q$ and $q \mid \gamma$ (for $C > 1$ this needs $q \le \operatorname{bitlen}(C)$,
a comparison, and then one integer root; for $C = 1$ it needs $q \mid \gamma$, a divisibility test; no
power of $c$ is formed). The value is then $(m\,2^{\gamma/q})^{s p}$. There are three classes of end and
each has its own line in the procedure:

| Class | When | Comparison with a prior end | Rounding |
| --- | --- | --- | --- |
| dyadic | $s = +1$ or $m = 1$ | exact (it is $m^p 2^{\ldots}$) | exact `with_precision` |
| rational, not dyadic | $s = -1$ and $m > 1$, for example $9^{1/(-2)} = 1/3$ | exact cross-multiplication | integer division with directed rounding |
| irrational | otherwise | the loop below | the loop below |

A rational that is not dyadic is never a float, so its comparisons are strict without any refinement. An
irrational value is not rational, so it differs from every float, and the loop terminates: the
working precision starts at $p + 64 + e_t$, with $e_t$ the exponent of $t = \ln(c)/\beta$ (the result
needs the absolute error of $t$ below $2^{-p}$), and doubles up to the cap of 12 as in `sin_rev`; at the
cap an undecided comparison counts as met in both conditions and the end written for that piece is
the prior's own end. The sign of $t$ is exact, so $\exp(t) > 1$ iff $t > 0$: the enclosure is strict
at the float 1, and an exponent such as $\beta = 2^{10^9}$, where $x = 1 + 2^{-10^9}\ln c$, is decided at
once ($\operatorname{RD} = 1$, $\operatorname{RU} = 1 + \text{ulp}$). The stored range is decided with a certified upper bound of $\ln 2$, by a test that is sufficient and never wrong. Above: every finite float is below $2^{e_{\max}+1}$ ($e_{\max}$ is the exponent of the leading bit), so if the enclosure of $t$ lies wholly at or above $(e_{\max}+1)\ln 2$ the enclosure of the value is [largest finite float at $w$ bits, $+\infty$], built explicitly, and a lower end then rounds down to the largest finite float of the result precision; the top binade $[2^{e_{\max}}, 2^{e_{\max}+1})$ is finite and goes through $\exp$. Below: the stored values at $w$ bits go down to the leading bit $e_{\min}-w+1$, so if the enclosure of $t$ lies wholly at or below $(e_{\min}-w)\ln 2$ the enclosure is $[0, 2^{e_{\min}-w+1}]$, the smallest positive stored value at $w$ bits, and an upper end rounds up to the smallest positive stored value of the result precision. Between the limits $\exp$ is used, with gradual underflow (the enclosure is at most one quantum $2^{e_{\min}-w+1}$ wide). `BallFloat::exp` of an interval with an end past the range returns the range of the function $[0, +\infty]$ at some precisions (issue [#569](https://github.com/Luna-Flow/floating/issues/569)); the point `exp` of the lower end is a tight bound, so the two ends give the enclosure. If the enclosure of $t$ straddles the upper limit, $\exp$ returns an infinite upper end; the loops stop with it only if its lower end is checked to be at least $2^{e_{\max}+1}(1 - 2^{-(w-64)})$ (the largest finite float at $w - 64$ bits), which says exactly that the upper end is $+\infty$ and the lower end rounds down to the largest finite float of the result at every precision $p \le w - 64$, hence at every further precision; otherwise the loops go on to their cap. If it straddles the lower limit the loops go on and terminate, since the quantum shrinks with $w$ while the value is fixed. An exact dyadic end in the subnormal range is kept exact, at a datum precision of at least $e_{\min} - \text{low} + 1$ bits within `pow_value_budget`, where $\text{low}$ is the exponent of the coefficient's lowest bit (the stored values at $P$ bits are the multiples of $2^{e_{\min}-P+1}$; the leading-bit formula is too small for a coefficient of more than one bit), and the datum built is checked to carry the value asked (an exact class never carries a rounded value) (for example $2^{-2^{30}}$ is the stored value $2^{e_{\min}-2}$, and $3 \cdot 2^{e_{\min}-5}$ needs 6 bits; the result for a point set is $[v, v]$ for every prior that contains it, in about 0.2 s); an exact end above $2^{e_{\max}+1}$ (for example $2^{(2^{30})}$), a rational end in the subnormal range, and a dyadic end below the budget are decided by the loop, which clamps at the limits (a rational is never a float, so its separation terminates at the first precision).

*Budgets*, in bits and not in terms of 53: the exactness test runs only for $C$ and $q$ within
`pow_int_budget` = 65,536 bits (an exact 65,535-bit square takes about 80 ms, against about 20 ms for
the forward `sqrt` of the same operand) and an exact value is materialised only within
`pow_value_budget` = 262,144 bits (a value of millions of bits would be built only to be rounded to
$p$ bits). Above a budget the end goes to the loop with its documented fallback. The corpus needs none of
this: its 429 cases need the first working precision of the loop at most ($w = p + 64 = 117$ at
$p = 53$, measured), and the oracle reproduces all of them.

*Tests.* The definition tests cover the classes (including a 2000-bit perfect square and a $\beta$ with 500
fractional bits), the open ends at 0 and 1 against a prior that touches them from both sides, and exponents
and prior ends of magnitude $2^{\pm 10^9}$. The reference test
(`pow_reverse_reference_wbtest.mbt`) does not use the pieces: it evaluates the condition for a float $x$
with the forward `BallFloat::pow` at 200 bits, since $\beta \mapsto x^\beta$ is monotone and its range
over $\boldsymbol{b}$ is the interval `pow(x, b)`, and checks, at precisions 24, 53 and 113, that every float
certainly in the set is in the result, that a point a quarter of a float outside either end that comes from
a piece is not in the set, and that the float one step inside is not certainly outside while the next one
is certainly inside. A sample runs in every test run; the long run is an interval gate stage.

#### Reverse power with an interval base

`pow_rev2(a, c, x)` (IEEE 1788-2015 10.5.4) is the same set division with the roles exchanged
(see the [API page](../api/ball_float.md#ballfloatpow_rev2)): the unknown is the exponent, and the set is
$L /_{\text{set}} M$ with $L = \ln(\boldsymbol{c} \cap (0, +\infty))$ and
$M = \ln(\boldsymbol{a} \cap (0, +\infty))$, plus $(0, +\infty)$ when $0 \in \boldsymbol{a}$ and
$0 \in \boldsymbol{c}$. The pieces come from the same case split as `pow_rev1` (whether $1 \in \boldsymbol{c}$ and
whether $1 \in \boldsymbol{a}$, the signs of the logarithms being comparisons with 1), and a piece
end is the quotient $\ln(c_\text{end}) / \ln(a_\text{end})$, with the infinities and the open 0 as in
`pow_rev1` (here no value is mapped through $\exp$, so there is no end at 1).

*Exactness of an end* $r = \ln(C)/\ln(A)$ for floats $A \ne 1$ and $C > 0$. Write $A = \alpha\,2^i$ and
$C = \gamma\,2^j$ with $\alpha$ and $\gamma$ odd and positive (the exponents $i$ and $j$ carry the sign of the
logarithms). $r$ is rational iff $A$ and $C$ are multiplicatively dependent, and then:

| Case | End |
| --- | --- |
| $C = 1$ | $r = 0$ |
| $\alpha = \gamma = 1$ | $r = j / i$ |
| exactly one of $\alpha$, $\gamma$ is 1 | irrational ($C \ne 1$) |
| both exceed 1 | the multiplicative Euclidean algorithm gives $B$ with $\alpha = B^{i'}$, $\gamma = B^{j'}$ and $\gcd(i', j') = 1$; $r = j'/i'$ iff $i\,j' = j\,i'$, else irrational |

The algorithm divides the larger odd integer by a power of the smaller, $y^k$ with
$k = \lfloor (\operatorname{bitlen}(x) - 1) / \operatorname{bitlen}(y) \rfloor$ (so that $y^k \le x$; it divides $x$ whenever both are
powers of one base), and an inexact division proves independence; a high power of a small base ($3$ against $3^{40000}$)
takes a few steps, not one per factor. The exponents of $B$ are recovered by running the steps
backwards, and the exact check $\alpha = B^{i'}$, $\gamma = B^{j'}$ is made before the value is used. The value
$j'/i'$ is a float iff the reduced denominator is a power of two (class dyadic), and otherwise a rational that is
not a float (compared by exact cross-multiplication, rounded by integer division with directed
rounding, the sign taken into account). An odd part beyond `pow_int_budget` = 65,536 bits gives the class
Unknown, decided by the loop like an irrational end.

*Working precision.* The first working precision of the loop is $p + 64 + e_r$, with $e_r$ the exponent of the
quotient: $\ln$ has a relative error of about $2^{-w}$ also for an argument next to 1 (the enclosure of
$\ln(1 + 2^{-52})$ keeps its full width in bits), so only the integer part of the quotient costs
bits. A base one unit from 1 gives a quotient of about $2^{51}$, and the tests check that its enclosure is tight (adjacent floats) at precision 53.

*Budgets*, in bits: one call of the exactness test at the budget ($3^{41340}$ against $3$, 65,524 bits) takes
about 7 ms, against about 6 ms for the forward `pow` of the same operand at 200 bits, so the budget of
`pow_rev1` is kept. The corpus needs none of it: the oracle finds no irrational piece end among its 375 statements (every end is exact, a float or a rational), so the loop and its fallback are covered by the tests below and not by the corpus.

*Corpus.* Two statements of the corpus expect a value that is valid but wider than the hull
(`powRev2 [0.25, 0.5] [2, inf]` expects Entire and `powRev2 [0.25, 1] [2, inf]` expects $[-\infty, 0]$, where
$a_0^\beta \ge 2$ with $a_0 < 1$ needs $\beta \le -1/2$); they are refinements, with the oracle
(`tools/itl_pow2_reverse_oracle.py`, which derives the set from the corner quotients and shares no code with
`ball_float`) giving 373 equal and 2 refined of 375 statements.

*Tests.* The definition tests cover the classes (including the Euclid steps, $3$ against $3^{40000}$, and a
beyond-budget odd part), exact and rounded rational ends with their sign, the examples of the corpus, the open
ends at 0 against a prior that touches them, a base one unit from 1 on both sides, and bases, results and
prior ends of magnitude $2^{\pm 10^9}$. The reference test (`pow_reverse2_reference_wbtest.mbt`) evaluates the
condition for a float $\beta$ with the forward `BallFloat::pow` at 200 bits (the range of $a_0^\beta$ over
$\boldsymbol{a}$ is the interval `pow(a, beta)`) and checks, at precisions 24, 53 and 113, that every float
certainly in the set is in the result, that a point a quarter of a float outside an end that comes from a
piece is not in the set, and that the float one step inside is not certainly outside while the next one is
certainly inside. A sample runs in every test run; the long run is an interval gate stage.

#### Reverse arctangent of two arguments

`atan2_rev1(b, c, x)` and `atan2_rev2(a, c, x)` (IEEE 1788-2015 10.5.4, equations (6) and (7), Table 10.1; see
the [API page](../api/ball_float.md#ballfloatatan2_rev1-and-ballfloatatan2_rev2)). With
$\Theta = \boldsymbol{c} \cap (-\pi, \pi]$ the set is the projection of the sector
$\{\, r(\cos t, \sin t) : r > 0,\ t \in \Theta \,\}$ on the axis of the unknown (the ordinate for Rev1, the
abscissa for Rev2), cut by the strip of the given operand: a point of the ray at the angle $t$ has the
ordinate $r \sin t$ and the abscissa $r \cos t$. Away from the axis directions this is the product
$y = b_0 \tan t$ (Rev1) or $x_0 = a_0 \cot t$ (Rev2) of an operand point and the trigonometric value, so each
piece is an interval product, and the hull is taken over the pieces inside the prior as for `pow_rev1`. Write
$b^+ = \boldsymbol{b} \cap (0, \infty)$ and $b^- = \boldsymbol{b} \cap (-\infty, 0)$ (likewise $a^\pm$).

| Operation | Piece | Angles $t$ | Needs | Set |
| --- | --- | --- | --- | --- |
| Rev1 | right | $\Theta \cap (-\pi/2, \pi/2)$ | $b^+ \ne \emptyset$ | $b^+ \cdot \tan(\Theta_r)$ |
| Rev1 | upper-left | $\Theta \cap (\pi/2, \pi]$ | $b^- \ne \emptyset$ | $b^- \cdot \tan(\Theta_{ul})$, a subset of $[0, \infty)$; $\tan \pi = 0$ is attained |
| Rev1 | lower-left | $\Theta \cap (-\pi, -\pi/2)$ | $b^- \ne \emptyset$ | $b^- \cdot \tan(\Theta_{ll})$, a subset of $(-\infty, 0)$; the end at $-\pi$ is open |
| Rev1 | up, down | $t = \pi/2$ or $t = -\pi/2$ in $\Theta$ | $0 \in \boldsymbol{b}$ | $(0, +\infty)$ or $(-\infty, 0)$ |
| Rev2 | upper half-plane | $\Theta \cap (0, \pi)$ | $a^+ \ne \emptyset$ | $a^+ \cdot \cot(\Theta_u)$ ($\cot$ decreases from $+\infty$ to $-\infty$) |
| Rev2 | lower half-plane | $\Theta \cap (-\pi, 0)$ | $a^- \ne \emptyset$ | $a^- \cdot \cot(\Theta_l)$; the end at $-\pi$ is open |
| Rev2 | right, left | $t = 0$ or $t = \pi$ in $\Theta$ | $0 \in \boldsymbol{a}$ | $(0, +\infty)$ or $(-\infty, 0)$ |

The tangent (cotangent) interval of a piece has one end per end of $\Theta_r$: the tangent of an end of
$\boldsymbol{c}$ inside the region, or the limit at a boundary of the region: $\pm\infty$ at $\pm\pi/2$ for
the tangent (at $0$ and $\pi$ for the cotangent), 0 at $-\pi$, 0 and $\pi$ for the tangent. Whether an end of
$\boldsymbol{c}$ is below or above $-\pi$, $-\pi/2$, $0$, $\pi/2$ or $\pi$ is decided exactly, in seven zones
(`atan2_zone`): $\pi$ is irrational, so a float is never equal to a multiple of it, and only $0$ is an exact
angle; the enclosure of $\pi$ is refined until the float is separated. The product of the operand part with
the trigonometric interval is monotone in each variable, so each extreme is the product of two ends, chosen by the
signs of the ends of the trigonometric interval (no numerical comparison between corners is needed), and an end
is attained only if both factors are: the limit 0 of $b^+$ (when $0 \in \boldsymbol{b}$) and the infinities are
not attained, $\tan 0 = 0$ and $\tan \pi = 0$ are, and $\tan(-\pi) = 0$ is not.

*Branch cut and origin.* The angle $\pi$ is attained and $-\pi$ never, so $\pi \in \boldsymbol{c}$ puts $y = 0$
into the Rev1 set when $b^- \ne \emptyset$ (an end of the upper-left piece, attained) and $x_0 < 0$ into the Rev2 set
when $0 \in \boldsymbol{a}$, while a $\boldsymbol{c}$ with lower end $\le -\pi$ gives a lower-left piece whose end
at $-\pi$ (the limit of $\tan$ at $-\pi$) is open. The origin is excluded: for $\boldsymbol{b} = \{0\}$ there are
only the up and down pieces, so $y = 0$ is not reachable and $\operatorname{atan2Rev1}(\{0\}, \{0\})$ is Empty;
for $\boldsymbol{a} = \{0\}$ there are only the angles $0$ and $\pi$, so $x_0 = 0$ is not in the set.

*Exactness of an end.* The exact ends are $0$ and the infinities. Every other end is
$b_\text{end} \tan(c_\text{end})$ (Rev1) or $a_\text{end} / \tan(c_\text{end})$ (Rev2) with a nonzero float
operand end and a nonzero float angle, which is irrational: $\tan$ of a nonzero algebraic number is transcendental
(Lindemann-Weierstrass) and a nonzero rational times a transcendental number is transcendental, so the end differs from
every float, comparisons with a prior end are strict, and the loop of `pow_rev1` (the working precision doubles up
to the cap of 12; an undecided comparison counts as met and the prior's own end is written) terminates. No integer
test and no budget are involved. The first working precision is $p + 96$: the forward `tan` of a point has a relative
error of about $2^{-w}$ also next to $\pi/2$, $0$ and $\pi$ (the argument reduction runs at the working precision),
and the loop needs the value to a relative $2^{-(p+2)}$. An angle one float from $\pi$ gives a cotangent of order
$2^{p}$ (the tests check the result is two adjacent floats that contain the 200-bit reference).

*Evidence.* The ITF1788 corpus has no `atan2Rev` case, so the evidence is ours.
`tools/itl_atan2_reverse_oracle.py` (pure Python, 260 digits, no `ball_float` code) derives the exact hull by
polar rectangles (an angle interval times an operand part of one sign, with corner limits) and validates every
expected hull by the forward definition of the operation, which shares nothing with the case analysis. For a fixed
ordinate $y$, $\operatorname{atan2}(y, b_0)$ is monotone and continuous in $b_0$ on each side of 0
(decreasing for $y > 0$, increasing for $y < 0$; for $y = 0$ it is 0 for $b_0 > 0$ and $\pi$ for $b_0 < 0$), so
its image over $\boldsymbol{b}$ is an interval decided from the ends of $\boldsymbol{b}$, and $y$ is a member iff
the image meets $\boldsymbol{c}$ (Rev2 likewise, with the ordinate part split at 0). The validation tests an
attained end, three points a geometric step inside each piece end ($10^{-9}$, $10^{-15}$, $10^{-30}$ relative) and six
points beyond each end of the hull, inside the prior ($10^{-30}$, $10^{-15}$, $10^{-9}$, $10^{-3}$, 1 and 100 relative). The
generated file `testdata/interval/generated/atan2_rev.itl` (see its README) has 16,260 cases, run as the
`atan2-reverse` phase, counted apart from the ITF1788 total. The reference test
(`atan2_reverse_reference_wbtest.mbt`) evaluates membership of a float with the forward `BallFloat::atan2` of points at
200 bits (the same monotone image, with the cut treated explicitly) and checks, at precisions 24, 53 and 113, that
every float certainly in the set is in the result, that a point a quarter of a float outside an end that comes from a
piece is not in the set, and that the float one step inside is not certainly outside while the next one is certainly
inside. The maximum working precision on the generated corpus is 149 bits (the first working precision, $p + 96$ at $p = 53$; none of the 6,813 evaluations of the loop doubled it) bits.

### Interval literals and text input

`from_string` (IEEE 1788-2015 `textToInterval`, 9.7, 12.11, 12.12.7, 13.2; see the
[API page](../api/ball_float.md#ballfloatfrom_string-and-ballfloatdecoratedfrom_string)) is a hand-written parser of the portable
grammar (Tables 9.5 and 12.2) over the characters of the string. A number literal is read into one of four exact
descriptions: an infinity, a decimal $d \cdot 10^{e}$ (the digits without the point and the exponent minus the number of
digits after the point), a hexadecimal $h \cdot 2^{e}$ (the exponent minus four times the number of hexadecimal digits
after the point), or a rational $p/q$ with $q$ positive. An exponent field is saturated at $10^{15}$ in magnitude (beyond
every range). The uncertain form $m?rve$ is turned into two decimal descriptions by the definition of 9.7.3: $\operatorname{ulp}(m) = 10^{-k}$ with
$k$ the number of digits after the point of $m$, the bounds are $(M \mp r) 10^{e-k}$ with $M$ the integer of the digits
(one ulp being $10^{-k}$; for the empty radius, half an ulp, as $(10M \mp 5) 10^{e-k-1}$), the direction $u$ or $d$ keeps
one side, and the radius $?$ is unbounded; the arithmetic is on big integers, so no rounding precedes the final one.

*Rounding.* Each bound is rounded once, outward and exactly: a decimal and a hexadecimal description go through
the correctly rounded directed conversions of `BinFloat` (`from_string_ctx`, `from_hex_ctx`, which accept any exponent),
and a rational is divided by integer division to a quotient of at least $p + 3$ bits with the sticky remainder (the same
rule as the exact rational ends of `pow_rev1`). A literal whose exact value is beyond the stored range is therefore decided
by those conversions from the exponent without forming the value, and `1e400000000` has the lower end the largest finite
float and the upper end $+\infty$. `from_hex_ctx` rejects a binary exponent beyond $10^{12}$ in magnitude, although the value is then far beyond the stored range, so the exponent of a hexadecimal description is clamped to $\pm 2^{39}$ first (the significand has at most $4 \cdot 65{,}536$ bits, so the class, above the range or below the smallest stored value, is unchanged); `from_string_ctx` accepts every exponent. The invariants are checked: a failure of a converter or of the digit parser aborts instead of returning a bound.

*The order $l \le u$.* It is decided from the exact values, so rounding never makes a nonempty literal Empty and an empty one nonempty: two
decimal bounds are compared by the adjusted exponent and then the digit strings (trailing zeros removed, the shorter padded with
zeros), which needs no power of ten whatever the exponent; any other pair is first separated by roundings at 64 bits and
otherwise compared by cross-multiplication of the exact numerators and denominators, a power being formed only for an
exponent of magnitude at most 65,536. A pair that is neither separated nor within that limit (two bounds of different radices
that agree to 64 bits and have an exponent beyond 65,536) is undecided: 12.12.7 case (b) allows it and requires the result to contain
both bounds, so the result is the hull of the four roundings (a false positive, which the standard permits; a false negative
is not possible).

*Rejections.* Every failed call is an `Err` of the parse kind whose message names the rule of the grammar or of
12.11 that was broken (a missing digit, the exponent field of a hexadecimal literal, the denominator of a rational, the order of the bounds,
an infinite bound on the wrong side, the characters after the literal, the decoration literal, a decoration not permitted
for the value by 11.4, a decoration on a bare literal). The test table asserts the reason of every rejected string. A literal
longer than `interval_literal_max_length` is not parsed and gives Entire (12.11.5).

*Evidence.* The independent oracle `tools/interval_literal_oracle.py` (pure Python, no `ball_float` code) evaluates a literal from whole-string
patterns (a special form, the two bound strings of an inf-sup form cut at the comma, the groups of an uncertain pattern) to an exact `Fraction`, derives the uncertain form from the definition of the
ulp, and rounds each bound with integer arithmetic against the stored range (gradual underflow to the quantum $2^{e_{\min}-p+1}$, the largest finite float
$(2^p - 1) 2^{e_{\max}-p+1}$); it also checks every one of 20,000 rational literals against the rounded ends by cross-multiplication (the rounded lower end is not above the value
and the float below it is below, and likewise for the upper end). The generated table (9,242 literals: the vectors of Tables 9.4 and 12.1, the negative
examples, and random decimal, hexadecimal, rational, uncertain, decorated and special literals at precisions 24, 53 and 113, bare and decorated) is
compared with the parser in `interval_literal_wbtest.mbt`.

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
"certainly not less", so the two families are dual: `DefinitelyLt::definitely_lt(x, y)` is
false exactly when some pair satisfies $\xi \ge \eta$. With empty operands the
universal statements would be vacuously true, which would let a caller prove
anything from an empty enclosure; the `DefinitelyLt` and `DefinitelyLe` relations (and `Overlaps`, `MaybeEq`) therefore
return false for empty operands, whereas the IEEE 1788 relation `precedes`
($\forall\xi\,\forall\eta: \xi \le \eta$) is defined to be vacuously true.

The set relations (`subset`, `interior`, `disjoint`, `==`) and the
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
useless bits. The midpoint–radius *view* (`new`, `midpoint`, `radius`) is kept for users
who reason in $c \pm r$, with the conversions derived
[above](#from-midpointradius-to-endpoints).

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
nearest-rounded sums inside the center, where it is not exact; this is the
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
$\operatorname{RD}_p(a)$, and conversely. So `(x + y).apply_ctx(ctx)` equals a
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

*Chosen.* Both, with one kernel. The `try_` forms return an
`ArithmeticError` with a certification detail (operation, stage, reason,
precision). The total form is the `try_` form with a fallback: when the `try_`
form fails it returns the range of the function over its domain, which keeps
the inclusion property: $[0, +\infty)$ for `exp`, `exp2`, `exp10`, `pow` and
`hypot`, $[-1, +\infty)$ for `expm1`, Entire for the logarithms, `sinh`,
`asinh`, `atanh`, `tan`, `tanpi` and `log1p`, $[-1, 1]$ for `sin`, `cos`,
`sinpi`, `cospi` and `tanh`, $[1, +\infty)$ for `cosh`, $[0, +\infty)$ for
`acosh`, $[-\pi/2, \pi/2]$ for `atan` and `asin`, $[0, \pi]$ for `acos`,
$[-\pi, \pi]$ for `atan2`. The $\pi$ of a fallback is evaluated at no more
than 64 bits and rounded outward, so a fallback cannot fail at any precision.
The domain is decided before the kernel runs, so a failure is always a
certification failure and never a domain error: an argument outside the domain
gives Empty, a wide interval means the kernel gave up. Trigonometric reduction
is capped: when the larger endpoint magnitude is at least
$2^{\max(65536, 4p)+1}$, reduction would need more than that many bits, so the
`try_` forms report a resource limit and the total forms return the fallback.

*Why one kernel.* Until this was settled the total forms of fifteen functions
had a kernel of their own (exact-rational series), which aborted at a high
precision (about 32,000 bits for `ln`, issue 449) and lost all relative
accuracy for a tiny argument in the hyperbolic functions, while the `try_`
forms used the `bin_float` kernels and had neither limit. Keeping two kernels
for the same function meant two sets of bugs, and results that depended on
which form the caller chose.

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

**Tightness.** Basic arithmetic, `sqr`, `pown`, `fma`, `abs`, `min`,
`max`, `intersection`, `convex_hull` of non-empty operands and
`sqrt` return the outward rounding of the exact hull, so each
endpoint is within one ulp of optimal. Trigonometric and arctangent endpoints
are correctly directed roundings when certified; the other elementary
functions are usually within a few ulps. Not tight: fallbacks; `pown` with
$n < -4096$ and 0 inside (Entire);  `with_precision` and
`normalized` round the endpoints outward, which is the tightest enclosure and
the identity on an interval already representable at the target precision, so
`convex_hull` with an Empty operand and the checked capabilities do not widen
either.

**Decorations.** The decoration of a result is a true statement about the
function evaluated, by the induction argument above.

**Complexity.** Arithmetic performs at most four endpoint products or two
sums, $O(M(p))$ for $p$-bit endpoints with multiplication cost $M(p)$, plus
alignment of at most about $65536 + p$ bits for sums. Elementary functions cost one
or two directed evaluations of the `bin_float` kernels at precision $p$ (see
[`bin_float`](bin_float.md) for their cost), plus the index range for the
trigonometric functions.

**Evidence.** Package tests check directed endpoints, the far-addend and
exponent-range cases, decorations and relations; the pinned ITF1788 corpus
runs 6,632 cases in strict mode (see [conformance](../conformance/ball_float.md)).

### Known limitations

The following inputs currently lose part of the input set, round or flag a
result incorrectly, or return a set other than the specified one. Each is
tracked in an issue with a proposed fix that is not merged yet; they are
documented here so that callers can avoid them.

No limitation is open at present. Decorated `rootn` with a negative degree
lowers the decoration to `trv` when 0 is in the argument, as the decoration
rules of IEEE 1788-2015 §11 require; `library/src/ball_float/ball_float_decorated_wbtest.mbt`
checks degrees `-1`, `-2` and `-3`.

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

- provide reverse versions of division and reciprocal (Table 10.1 does not require them: change
  `z = x / y` to `x = y z` and use `mul_rev`);
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
