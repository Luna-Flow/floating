#set document(title: "Inclusion proofs for ball_float")
#set page(paper: "a4", margin: 2.2cm, numbering: "1")
#set text(size: 10.5pt)
#set par(justify: true)
#set heading(numbering: "1.")
#set math.equation(numbering: "(1)")

#let lemma(name, body) = block(width: 100%, inset: (y: 4pt))[*#name.* #body]
#let proof(body) = block(width: 100%, inset: (left: 1em, y: 2pt))[_Proof._ #body #h(1fr) $square$]

#align(center)[
  #text(size: 16pt, weight: "bold")[Inclusion proofs for `ball_float`]
  #v(2pt)
  Luna-Flow `floating`, design attachment
]

This note proves the facts the `ball_float` design page relies on. Notation:
$bold(x) = [underline(x), overline(x)]$ is a closed interval of the extended
reals with $underline(x) <= overline(x)$, $underline(x) != +oo$,
$overline(x) != -oo$, read as the set of _real_ numbers between the endpoints;
$emptyset$ is the empty interval. $"RD"_p$ and $"RU"_p$ round a real number to
the nearest $p$-bit binary number below and above. $F_p$ is the set of $p$-bit
binary numbers (with unbounded exponent).

= Directed rounding

#lemma("Lemma 1 (directed rounding)")[
For all reals $a <= b$: (i) $"RD"_p (a) <= a <= "RU"_p (a)$; (ii)
$"RD"_p (a) <= "RD"_p (b)$ and $"RU"_p (a) <= "RU"_p (b)$; (iii) for a finite
set $S$, $min_(s in S) "RD"_p (s) = "RD"_p (min S)$ and
$max_(s in S) "RU"_p (s) = "RU"_p (max S)$.
]
#proof[
$"RD"_p (a) = max{f in F_p : f <= a}$, which gives (i). If $a <= b$, every
$f in F_p$ with $f <= a$ also satisfies $f <= b$, so the maximum over the
larger set is not smaller: (ii). For (iii), let $m = min S$. By (ii)
$"RD"_p (m) <= "RD"_p (s)$ for every $s in S$, and the minimum is attained at
$s = m$. The $"RU"$ case is symmetric.
]

#lemma("Corollary 2 (outward rounding preserves containment)")[
If $L <= inf A$ and $U >= sup A$ for a set $A$ of reals, then
$A subset.eq ["RD"_p (L), "RU"_p (U)]$.
]
#proof[By Lemma 1(i), $"RD"_p (L) <= L <= inf A$ and $"RU"_p (U) >= U >= sup A$.]

#lemma("Lemma 3 (nested grids)")[
If $q <= p$ then $"RD"_q ("RD"_p (a)) = "RD"_q (a)$ and likewise for $"RU"$.
]
#proof[
$F_q subset.eq F_p$: a $q$-bit significand is a $p$-bit significand padded
with zeros. Let $r = "RD"_p (a)$. Every $f in F_q$ with $f <= a$ lies in $F_p$,
hence $f <= r$ by maximality of $r$; conversely $f <= r$ implies $f <= a$. So
${f in F_q : f <= r} = {f in F_q : f <= a}$ and the maxima agree.
]

= The fundamental theorem

For a real function $f$ with domain $D_f$, an _interval extension_ $F$ is a map
on intervals with $f(bold(x) inter D_f) subset.eq F(bold(x))$ for every
$bold(x)$. Interval extensions are _inclusion isotone_ if
$bold(x) subset.eq bold(y) => F(bold(x)) subset.eq F(bold(y))$.

#lemma("Theorem 4 (fundamental theorem of interval arithmetic)")[
Let $e$ be an arithmetic expression in variables $xi_1, dots, xi_n$ built from
operations each of which is evaluated by an interval extension. Write $f$ for
the real function of $e$ (defined where every subexpression is defined) and
$E$ for its interval evaluation. Then for all intervals
$bold(x)_1, dots, bold(x)_n$,
$ {f(xi) : xi in bold(x)_1 times dots times bold(x)_n, xi in D_f} subset.eq E(bold(x)_1, dots, bold(x)_n). $
]
#proof[
Induction on $e$. A variable $xi_i$ evaluates to $bold(x)_i$ and
$xi_i in bold(x)_i$. For $e = g(e_1, dots, e_k)$ with $g$ evaluated by the
extension $G$: take $xi in D_f$. Then each $e_j$ is defined at $xi$, and by the
induction hypothesis $y_j := f_(e_j)(xi) in E_j$. Since
$(y_1, dots, y_k) in D_g$ and $G$ is an extension,
$f(xi) = g(y_1, dots, y_k) in g((E_1 times dots times E_k) inter D_g) subset.eq G(E_1, dots, E_k) = E(bold(x))$.
]

Nothing in the proof requires the two occurrences of a variable to take the
same value, which is why $bold(x) - bold(x) != {0}$ (the _dependency
problem_): $E$ encloses the larger set where every occurrence varies
independently.

= Endpoint formulas

#lemma("Lemma 5 (corners of a bilinear map)")[
On a box $bold(x) times bold(y)$ of bounded intervals, $h(xi, eta) = xi eta$
attains its minimum and maximum at corners.
]
#proof[
For fixed $eta$, $h$ is affine in $xi$, so its extrema over $bold(x)$ are at
$underline(x)$ or $overline(x)$; therefore
$max_(bold(x) times bold(y)) h = max_(eta in bold(y)) max(underline(x) eta, overline(x) eta)$,
and each $eta |-> underline(x) eta$ is affine, attaining its maximum at
$underline(y)$ or $overline(y)$. The minimum is analogous.
]

With Corollary 2 this gives
$bold(x) bold(y) subset.eq ["RD" min S, "RU" max S]$ for
$S = {underline(x) underline(y), underline(x) overline(y), overline(x) underline(y), overline(x) overline(y)}$.
The sign cases used by the code select from $S$: if $underline(x), underline(y) >= 0$
then $xi eta$ is increasing in both arguments on the box, so the minimum is
$underline(x) underline(y)$ and the maximum $overline(x) overline(y)$; the other
three single-sign cases follow by $xi eta = (-xi)(-eta) = -((-xi) eta)$; when
both intervals contain $0$ in their interior, the products
$underline(x) underline(y)$ and $overline(x) overline(y)$ are $>= 0$ and the
other two $<= 0$, so the minimum is among the latter and the maximum among
the former. For unbounded intervals the corner lemma holds in the limit, with
$0 dot (plus.minus oo)$ contributing $0$: a zero endpoint multiplies an
unbounded side to $0$ because the real points near that endpoint give
products near $0$.

Sum and difference are monotone in each argument (increasing, resp.
increasing in $xi$ and decreasing in $eta$), so
$bold(x) + bold(y) = [underline(x) + underline(y), overline(x) + overline(y)]$ and
$bold(x) - bold(y) = [underline(x) - overline(y), overline(x) - underline(y)]$
exactly; Corollary 2 makes the rounded versions enclosures.

= Far addends

The endpoint sum $A + s$ with $|s| << |A|$ is not formed exactly. Let
$t(v)$ be the exponent of the leading bit of $v != 0$ (so
$2^(t(v)) <= |v| < 2^(t(v)+1)$), $e(A)$ the exponent of the last stored bit of
$A$, $M = max(65536, "prec"(A), "prec"(s))$ and
$c = min(e(A), t(A) - M)$. If $t(s) < c - 2$, the code replaces $s$ by
$s' = "sign"(s) 2^(c-2)$ when $s$ pushes the sum in the requested rounding
direction, and by $s' = 0$ otherwise.

#lemma("Lemma 6 (soundness)")[
For upward sums $A + s' >= A + s$; for downward sums $A + s' <= A + s$.
]
#proof[
$|s| < 2^(t(s)+1) <= 2^(c-2)$. Upward, $s > 0$: $s' = 2^(c-2) > s$. Upward,
$s < 0$: $s' = 0 > s$. The downward cases are mirror images.
]

#lemma("Lemma 7 (no change after rounding)")[
If $p <= M$ and $s != 0$, then $"RD"_p (A + s) = "RD"_p (A + s')$ and
$"RU"_p (A + s) = "RU"_p (A + s')$.
]
#proof[
Near $|A|$ (in the binade of $A$ and the one below it) the $p$-bit numbers are
multiples of $2^(t(A) - p)$, and $t(A) - p >= t(A) - M >= c$; $A$ itself is a
multiple of $2^(e(A))$, hence of $2^c$. So the open interval
$I = (A - 2^c, A + 2^c)$ contains no $p$-bit number other than possibly $A$.
Consequently $"RU"_p$ is constant on $(A - 2^c, A]$ (its value is
$"RU"_p (A)$) and on $(A, A + 2^c)$, and $"RD"_p$ is constant on
$[A, A + 2^c)$ and on $(A - 2^c, A)$. Since $|s|, |s'| <= 2^(c-2)$, both sums
lie in $I$. Upward with $s > 0$: both lie in $(A, A + 2^c)$. Upward with
$s < 0$: $s' = 0$, so the sums are $A$ and a point of $(A - 2^c, A)$, both in
$(A - 2^c, A]$. The downward cases are symmetric.
]

Lemma 6 is what the inclusion property needs and holds for every precision;
Lemma 7 says the surrogate costs no tightness when the result precision is at
most $M$. Alignment of $A$ and $s'$ shifts by at most $t(A) - c + 2 <= M + 2$
bits plus the width of $A$, instead of the full exponent gap.

= Certified elementary endpoints

#lemma("Lemma 8 (acceptance test)")[
Let $L <= y <= U$ with rational $L, U$. If $"RD"_p (L) = "RD"_p (U)$ then
$"RD"_p (L) = "RD"_p (y)$; if $"RU"_p (L) = "RU"_p (U)$ then
$"RU"_p (U) = "RU"_p (y)$.
]
#proof[
By Lemma 1(ii), $"RD"_p (L) <= "RD"_p (y) <= "RD"_p (U) = "RD"_p (L)$.
]

The trigonometric and arctangent kernels accept a work precision only when
both tests pass, so their endpoints are the correctly directed roundings of the
exact values; otherwise the work precision $w$ grows to $w + max(32, w/2)$, at
most 12 times. The exponential and logarithm kernels skip the test and return
$"RD"_p (L)$ and $"RU"_p (U)$, which are enclosures by Corollary 2 and, with
$64$ guard bits, almost always the correct directed roundings.

*Series tails.* For $0 <= x <= 1/8$ the terms $t_k = x^k / k!$ satisfy
$t_(k+1) / t_k = x/(k+1) <= 1/16$, so the tail after $t_n$ is at most
$t_(n+1) sum_(j >= 0) 16^(-j) = 16/15 dot t_(n+1) <= 2 t_(n+1)$, the bound
the code adds. For $ln y = 2 sum_(k>=0) z^(2k+1)/(2k+1)$ with
$z = (y-1)/(y+1) in [0, 1/3]$ ($1 <= y <= 2$), let $t'$ be the first omitted
term. Consecutive terms have ratio at most $z^2 <= 1/9$, so the omitted tail
is at most $t' sum_(j>=0) 9^(-j) = 9/8 t'$; after doubling it is at most
$9/4 t' <= 3 t'$, the bound the code adds.
