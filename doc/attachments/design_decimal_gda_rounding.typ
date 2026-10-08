#set document(title: "decimal_gda: rounding proofs")
#set page(paper: "a4", margin: 2.2cm, numbering: "1")
#set text(size: 10.5pt)
#set par(justify: true)
#set heading(numbering: "1.")
#set math.equation(numbering: "(1)")

#let thm(name, body) = block(
  width: 100%,
  inset: 8pt,
  stroke: 0.5pt + luma(150),
  radius: 3pt,
)[*#name.* #body]

#align(center)[
  #text(size: 16pt, weight: "bold")[Rounding proofs for `decimal_gda`]

  Supplement to the `decimal_gda` design page of Luna-Flow/floating
]

This note proves the four facts the design page relies on: the error bound of
rounding to precision, when two successive roundings equal one, why the
certified elementary functions return the correctly rounded result, and the
error bound of integer powers. Notation follows the design page: a finite
value is $(-1)^s c dot 10^e$ with $c in NN$, $d(c)$ is the number of decimal
digits of $c > 0$, and the context precision is $p >= 1$.

= Rounding to precision

Let $v = (-1)^s c dot 10^e$ be exact with $d(c) = p + k$, $k >= 1$. Write
$c = q dot 10^k + r$ with $0 <= r < 10^k$. Each mode returns
$(-1)^s (q + delta) dot 10^(e+k)$ with an increment $delta in {0, 1}$:

$
delta_"Down" = 0, quad
delta_"Up" = [r > 0], quad
delta_"Ceiling" = [r > 0 and s = 0], quad
delta_"Floor" = [r > 0 and s = 1],
$
$
delta_"HalfUp" = [2r >= 10^k], quad
delta_"HalfDown" = [2r > 10^k], quad
delta_"HalfEven" = [2r > 10^k or (2r = 10^k and q "odd")],
$
$
delta_"ZeroFiveUp" = [r > 0 and q equiv 0 med (mod 5)].
$

The last condition is "the last digit of $q$ is 0 or 5", because
$q mod 10 in {0, 5} <=> q equiv 0 med (mod 5)$.

#thm("Lemma 1 (error bound)")[
Let $u = 10^(e+k)$ be the unit in the last place of the result $hat(v)$. Then
$|hat(v) - v| <= u slash 2$ for the three half modes and $|hat(v) - v| < u$
for the other five. Relative to $v$,
$ |hat(v) - v| slash |v| <= 1/2 dot 10^(1-p) quad "(half modes)", quad
  |hat(v) - v| slash |v| < 10^(1-p) quad "(others)". $
]

_Proof._ $|hat(v) - v| = |delta dot 10^k - r| dot 10^e$. For the half modes
$delta = 1$ only if $r >= 10^k slash 2$, giving $10^k - r <= 10^k slash 2$,
and $delta = 0$ only if $r <= 10^k slash 2$. For the other modes
$|delta 10^k - r| < 10^k$ because $0 <= r < 10^k$. For the relative bound,
$c >= 10^(p+k-1)$, so $|v| >= 10^(p-1) dot u$; divide. If $q + delta = 10^p$
the result is renormalized to $10^(p-1) dot 10^(e+k+1)$, which is the same
number, so the bounds are unchanged. $square$

= Two roundings and one

Rounding to a finer unit $10^j$ and then to a coarser unit $10^(j+m)$
($m >= 1$) is called _double rounding_.

#thm("Lemma 2")[
For `Down`, `Up`, `Ceiling` and `Floor`, double rounding equals a single
rounding to $10^(j+m)$. For the half modes it does not in general.
]

_Proof._ Take `Down` on magnitudes: truncating to a multiple of $10^j$ and then
to a multiple of $10^(j+m)$ gives $10^(j+m) floor(x slash 10^(j+m))$ because
$floor(floor(x slash 10^j) slash 10^m) = floor(x slash 10^(j+m))$. `Up` is the
same identity with ceilings; `Ceiling` and `Floor` are `Up` or `Down`
depending on the sign, and the sign is unchanged by the first rounding.
For the half modes take $p = 1$ and $x = 1 slash 2222 = 0.000450045...$. To
the unit $10^(-7)$ (the first rounding used by `divide`), half-even gives
$4500 dot 10^(-7)$, an exact tie for the second rounding to $10^(-4)$, which
half-even resolves downwards to $4 dot 10^(-4)$. A single rounding of $x$
gives $5 dot 10^(-4)$ because $x > 4.5 dot 10^(-4)$. $square$

#thm("Corollary (division)")[
Let `divide` form $Q = c_1 10^t slash c_2$ with $t = p + d(c_2) + 2$, round
$Q$ to an integer $q$ with the context mode, and then round $q$ to $p$ digits.
The quotient is correctly rounded in the four directed modes. In a half mode
it is wrong exactly when the first rounding manufactures a tie: the digits of
$q$ discarded by the second rounding are $5 0 dots.c 0$ while $Q != q$ and the
exact discarded part is not one half.
]

_Proof._ The directed modes follow from Lemma 2. In a half mode the second
rounding compares the discarded part of $q$ with the integer threshold
$h = 5 dot 10^(m-1)$ ($m$ discarded digits) after removing the retained
multiple of $10^m$. Since $q$ is the nearest integer to $Q$ and $h$ is an
integer, $Q < h$ implies $q <= h$ and $Q > h$ implies $q >= h$. Hence the
comparison of $q$ with $h$ agrees with that of $Q$ unless $q = h != Q$, the
manufactured tie. $square$

The defect is avoided by keeping a sticky bit ($Q in.not ZZ$) with $q$ and
letting the second rounding treat "$5 0 dots.c 0$ plus sticky" as above half,
as `normalize` already does for the other operations.

= Certified rounding of elementary functions

Fix a mode $m$ and a representable result $r$ of the context. Its _rounding
cell_ is $C_m (r) = {y in RR : "round"_m (y) = r}$. Let $r^-$ and $r^+$ be the
representable neighbours of $r$ and let $mu(a, b) = (a + b) slash 2$. The cell
is an interval. The package does not need all of it: it uses an open
interval $I_m (r) subset.eq C_m (r)$, namely

$
I_m (r) = cases(
  (mu(r^-, r), mu(r, r^+)) & "half modes",
  (r, r^+) & "Floor",
  (r^-, r) & "Ceiling",
)
$

For `Down` the interval lies on the side of $r$ away from zero, for `Up` on
the side towards zero, and for `ZeroFiveUp` on the side of $r$ that contains
the approximation being tested; each of these open intervals rounds to $r$
under its mode. All endpoints are computed exactly as decimals
(`decimal_power_rounding_cell`).

#thm("Lemma 3 (cell certificate)")[
Let $[L, U]$ be a certified enclosure of $f(x)$, let $(a, b) = I_m (r)$,
and let $[a^-, a^+] in.rev a$ and $[b^-, b^+] in.rev b$ be binary enclosures of
the endpoints. If $L > a^+$ and $U < b^-$ then $"round"_m (f(x)) = r$.
]

_Proof._ $a <= a^+ < L <= f(x) <= U < b^- <= b$, so $f(x) in (a, b) = I_m (r) subset.eq C_m (r)$. $square$

#thm("Lemma 4 (endpoint certificate)")[
If $"round"_m (L) = "round"_m (U) = r$ then $"round"_m (f(x)) = r$.
]

_Proof._ Every rounding mode is a monotone (non-decreasing) map from $RR$ to
the representable set. From $L <= f(x) <= U$ follows
$r = "round"_m (L) <= "round"_m (f(x)) <= "round"_m (U) = r$. $square$

#thm("Lemma 5 (termination)")[
If $f(x)$ is neither representable nor a midpoint of two adjacent
representable numbers, and the enclosure width tends to 0 as the working
precision grows, then the refinement loop certifies after finitely many
steps.
]

_Proof._ Under the hypothesis $f(x)$ lies in the open interval
$I_m (r)$ for $r = "round"_m (f(x))$ (for `ZeroFiveUp` once the approximation is
on the same side of $r$ as $f(x)$). Let $eta > 0$ be its distance to the
endpoints. Once both the enclosure width and the endpoint enclosure widths are
below $eta slash 2$, the hypotheses of Lemma 3 hold. $square$

For `exp`, `ln` and `log10` the hypothesis holds for every input that is not
special-cased: by the Lindemann--Weierstrass theorem $e^x$ is transcendental
for rational $x != 0$, so $ln x$ is irrational for rational $x > 0$, $x != 1$;
and $log_10 x = a slash b$ with $x$ rational forces $x^b = 10^a$, so $x$ is an
integral power of ten. Representable numbers and midpoints are rational, so none of the
remaining values can be one. The budget of twelve refinements, each raising the working
precision $w$ to $w + max(32, floor(w slash 2))$, is a resource bound, not
part of the argument.

= Integer powers

`power` with an integer exponent $n$, $|n| < 10^D$, multiplies with
$w = p + D + 2$ working digits in half-even (one fewer digit in subset
contexts) and rounds the final product once more with the context mode.

#thm("Lemma 6")[
In an extended context, the result of an inexact integer power differs from
$x^n$ by at most $0.55$ units in the last place in the half modes and by less
than $1.05$ units in the other modes.
]

_Proof._ Any multiplication chain that forms $x^(|n|)$ from $x$ is a product
of $|n|$ copies of $x$ in which every copy passes through at most $|n| - 1$
roundings, so the computed value is $x^(|n|) (1 + theta)$ with
$|theta| <= (1 + epsilon)^(|n|-1) - 1 <= (|n| - 1) epsilon slash (1 - (|n| - 1) epsilon)$,
where $epsilon = 1/2 dot 10^(1-w)$ is the bound of Lemma 1 (Higham, _Accuracy
and Stability of Numerical Algorithms_, Lemma 3.1). For $n < 0$ the initial
reciprocal adds one rounding, covered by replacing $|n| - 1$ by $|n|$.
Since $|n| < 10^D$,
$ |theta| lt.approx 10^D dot 1/2 dot 10^(1-p-D-2) = 1/2 dot 10^(-1-p). $
The final result $hat(v)$ has unit $u$ with $|x^n| < 10^p u$, so the working
error is below $1/2 dot 10^(-1-p) dot 10^p u = 0.05 u$. The final rounding adds
at most $u slash 2$ (half modes) or less than $u$ (others). $square$

The bound is below one unit but above one half, which is why GDA (and this
package) does not promise correct rounding for integer powers.
