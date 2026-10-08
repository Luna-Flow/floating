#set document(title: "Rounding and exactness proofs for bin_float")
#set page(paper: "a4", margin: 2.2cm, numbering: "1")
#set text(size: 10.5pt)
#set par(justify: true)
#set heading(numbering: "1.")

#let lemma(name, body) = block(width: 100%, inset: (y: 4pt))[*#name.* #body]
#let proof(body) = block(width: 100%, inset: (left: 1em, y: 2pt))[_Proof._ #body #h(1fr) $square$]

#align(center)[
  #text(size: 16pt, weight: "bold")[Rounding and exactness proofs for `bin_float`]
  #v(4pt)
  Companion to the `bin_float` design page of Luna-Flow `floating`
]

#v(8pt)

This note proves the claims that the design page states with a sketch. The
notation follows that page. $F = F(p, e_min, e_max)$ is the set of finite
values of a context, $eta = 2^(e_min - p + 1)$ the subnormal quantum,
$op("top")(x) = floor(log_2 abs(x))$, $op("bits")(c) = floor(log_2 c) + 1$ for
an integer $c > 0$, and $nu_2(c)$ the number of trailing zero bits of $c$. A
rounding function $circle.small$ is one of RD, RU, RZ, RA, RNE, RNA, and every one of them
satisfies

$ (R 1) quad x in F => circle.small(x) = x, #h(3em) (R 2) quad x <= y => circle.small(x) <= circle.small(y). $

= Round and sticky bits

#lemma[Lemma 1][Let $m > 0$ be an integer, $sigma >= 1$, $q = floor(m 2^(-sigma))$,
$f = m 2^(-sigma) - q in [0, 1)$, $g$ = bit $sigma - 1$ of $m$ and
$t = [nu_2(m) < sigma - 1]$. Then $g = [f >= 1/2]$, $f = 1/2 <=> g and not t$,
$f > 1/2 <=> g and t$, and $f > 0 <=> g or t$.]

#proof[Write $m = q 2^sigma + g 2^(sigma - 1) + ell$ with $0 <= ell < 2^(sigma - 1)$.
Then $f = g/2 + ell 2^(-sigma)$ with $0 <= ell 2^(-sigma) < 1/2$, so
$f >= 1/2 <=> g = 1$. The low part $ell$ is nonzero exactly when some bit below
$sigma - 1$ is set, that is when $nu_2(m) < sigma - 1$, so $ell != 0 <=> t$. The
remaining equivalences follow by cases on $g$ and $t$.]

Consequently the increment rules of the design page (for example
$g and (t or q_0)$ for RNE) are exactly the definitions of the rounding
functions applied to $q + f$, and the result is inexact iff $g or t$.

= One rounding onto the subnormal grid

#lemma[Lemma 2][Let $r = m 2^e > 0$ and
$sigma = max(op("bits")(m) - p, (e_min - p + 1) - e, 0)$. Then the points of $F$
nearest to $r$ from below and above are $q 2^(e + sigma)$ and $(q + 1) 2^(e + sigma)$
(the latter possibly equal to $2^(op("top")(r) + 1)$), where
$q = floor(m 2^(-sigma))$.]

#proof[The exponent $e + sigma$ is the quantum of $F$ at $r$: in the normal range
the quantum is $2^(op("top")(r) - p + 1)$ and $op("top")(r) = e + op("bits")(m) - 1$,
so the precision shift gives it; below $2^(e_min)$ the quantum is $eta$, which the
range shift gives. Taking the maximum covers both and never makes the quantum
smaller than either constraint requires. $q 2^(e + sigma)$ is the largest
multiple of the quantum not above $r$ and has at most $p$ significant bits.]

Rounding to $p$ bits first and then onto the subnormal grid can differ. In
binary16 ($p = 11$, $eta = 2^(-24)$) take $r = 2^(-25) (1 + 2^(-11))$. At 11 bits
$r$ is a tie between $2^(-25)$ and $2^(-25)(1 + 2^(-10))$ and RNE chooses
$2^(-25) = eta / 2$, which is again a tie and rounds to $0$. Directly, $r > eta/2$
rounds to $eta$. The finalizer uses Lemma 2 and returns $eta$.

= Addition with far-apart operands

#lemma[Lemma 3][Let $H, L$ be nonzero dyadic operands of arbitrary
length with $op("top")(H) - op("top")(L) > p + 3$, $H = c_H 2^(e_H)$ with $c_H$
odd. Let $T = e_H - p - 3$, let $L'$ be $L$ truncated toward zero to a multiple
of $2^T$, and $delta = [L != L']$. Then $H + L$ and the value
$ S = H + L' + "sign"(L) dot delta dot 2^(T - 1) $
have the same rounding $circle.small(H + L) = circle.small(S)$ and the same inexactness, for
every context of precision $p$.]

#proof[Since $abs(L) < 2^(op("top")(L) + 1) <= 2^(op("top")(H) - p - 3)$, we have
$abs(H + L) > 2^(op("top")(H)) - 2^(op("top")(H) - p - 3) >= 2^(op("top")(H) - 1)$, so
$op("top")(H + L) >= op("top")(H) - 1$. The rounding quantum at $H + L$ is
therefore at least $2^(op("top")(H) - p)$ and the round bit sits at
$2^(op("top")(H) - p - 1)$ or higher. Because $c_H$ is odd,
$e_H <= op("top")(H)$, so $T <= op("top")(H) - p - 3$: every bit of $L - L'$ and
the substitute bit $2^(T - 1)$ lie strictly below the round-bit position.
Both $H + L$ and $S$ agree on all positions from $2^T$ upward, hence on $q$
and $g$ of Lemma 1, and $L - L'$ and $"sign"(L) delta 2^(T-1)$ are both zero or
both nonzero with the same sign. When $L$ and $H$ have the same sign this
gives the same $t$. When they have opposite signs, write
$abs(L) = abs(L') + epsilon$ with $0 <= epsilon < 2^T$; then
$abs(H) - abs(L) = (abs(H) - abs(L') - 2^T) + (2^T - epsilon)$, and for
$epsilon > 0$ the last term lies strictly between $0$ and $2^T$, which is
exactly what $abs(H) - abs(L') - 2^T + 2^(T - 1)$ represents, the form the code
uses. If the exponents also force a subnormal shift, the rounding position
only moves up, and the argument is unchanged. The values agree in sign, and
by Lemma 1 the rounding and the inexact flag agree.]

= The IEEE remainder

#lemma[Lemma 4][If $x, y in F$, $y != 0$, $n$ is the integer nearest to $x/y$
(ties to even) and $r = x - n y$, then $r in F$.]

#proof[Write $x = M_x 2^(q_x)$, $y = M_y 2^(q_y)$ with $abs(M_x), abs(M_y) < 2^p$ and
$q_x, q_y >= e_min - p + 1$. By the choice of $n$, $abs(r) <= abs(y)/2$. If
$n = 0$ then $r = x in F$. Otherwise $abs(x / y) >= 1/2$, so $abs(r) <= abs(y)/2 <= abs(x)$.
In all cases $r$ is an integer multiple of $2^(min(q_x, q_y))$. If
$q_x >= q_y$, $r = k 2^(q_y)$ with $abs(k) <= abs(M_y) / 2 < 2^(p - 1)$. If $q_x < q_y$,
$r = k 2^(q_x)$ with $abs(k) <= abs(M_x) < 2^p$. In both cases $r$ has a
representation with fewer than $p$ bits on an admissible quantum, and
$abs(r) <= max(abs(x), abs(y)) <= Omega$, so $r in F$.]

#lemma[Lemma 5][For integers $X >= 0$ and $Y > 0$ let $R = X mod 2Y$. Then
$X mod Y = R - Y [R >= Y]$ and $floor(X / Y) equiv [R >= Y] (mod 2)$.]

#proof[$X = Q (2 Y) + R$ with $0 <= R < 2Y$. If $R < Y$ then $X = (2Q) Y + R$; if
$R >= Y$ then $X = (2Q + 1) Y + (R - Y)$ with $0 <= R - Y < Y$.]

The implementation computes $R$ without forming $X$ when $X = c_x 2^(q_x - q_y)$
is huge, as $((c_x mod 2Y) dot (2^(q_x - q_y) mod 2Y)) mod 2Y$ with the power
obtained by square-and-multiply. With $rho = X mod Y$, the nearest integer to
$X / Y$ is $floor(X/Y)$ if $2 rho < Y$, $floor(X/Y) + 1$ if $2 rho > Y$, and on a
tie the even one of the two; Lemma 5 supplies the parity, so the remainder is
$rho$ or $rho - Y$ with the sign of $x$ adjusted accordingly.

= nextUp

#lemma[Lemma 6][Let $x$ be finite (any number of bits),
$pi = min(e_min - p, e(x), op("top")(x) - p)$ for $x != 0$ and $pi = e_min - p$ for
$x = 0$, where $e(x)$ is the stored exponent. Then $op("RU")(x + 2^(pi - 2))$ is
the least element of $F$ greater than $x$ (or $+infinity$ beyond $Omega$).]

#proof[Let $x^+$ be the least element of $F union {+infinity}$ greater than $x$, and
assume first $x^+$ finite. Every point of $F$ is a multiple of
$eta = 2^(e_min - p + 1)$, every point of $F$ of magnitude at least
$2^(op("top")(x) - 1)$ is a multiple of $2^(op("top")(x) - p)$ (this covers the
binade of $x$ and, for negative $x$, the binade just below it in magnitude),
and $x$ is a multiple of $2^(e(x))$. Both $x$ and $x^+$ are therefore
multiples of $2^pi$, so $x^+ - x >= 2^pi$ and
$x < x + 2^(pi - 2) < x^+$. Since $op("RU")$ maps every point of $(x, x^+]$
to $x^+$, the claim follows; if $x = Omega$ the same step rounds upward to
$+infinity$. For $x = 0$, $x^+ = eta > 2^(e_min - p - 2)$.]

= Certification by enclosures

#lemma[Lemma 7][If $L <= y <= U$ and $circle.small(L) = circle.small(U)$, then $circle.small(y) = circle.small(L)$.]

#proof[By (R2), $circle.small(L) <= circle.small(y) <= circle.small(U) = circle.small(L)$.]

The enclosures are produced by evaluating every operation with RD for the
lower and RU for the upper end. Each such operation is monotone in its
arguments on the region where it is used (sums; products and quotients of
positive quantities; squaring of positive quantities), so the computed
interval contains the exact value; series tails are added as explicit upper
bounds. For the exponential series on $[0, 1/8]$ the tail after the term
$t_n$ is bounded by $t_n sum_(i >= 1) 8^(-i) = t_n / 7$, and the code adds
$2 t_n$. For $ln v = 2 sum_(k >= 0) z^(2k+1) / (2k+1)$ with $z in [0, 1/3]$ the
tail from index $m$ is at most $z^(2m+1) / ((2m+1)(1 - z^2))$.

#lemma[Lemma 8 (termination)][If $y$ is not a breakpoint of $circle.small$ (a point
of $F$ for directed rounding, a midpoint of adjacent points of $F$ for nearest
rounding) and the enclosure width tends to $0$ as the working precision
grows, then for some working precision $circle.small(L) = circle.small(U)$.]

#proof[$circle.small$ is constant on each open interval between consecutive breakpoints.
$y$ lies in the interior of such an interval, at a positive distance $d$ from
its ends; once the width is below $d$, both $L$ and $U$ lie in the same
interval.]

Breakpoints are dyadic. By Lindemann–Weierstrass, $e^a$ is transcendental for
algebraic $a != 0$, hence so are $ln a$ ($a != 1$), $sin a$, $cos a$, $tan a$ and
the inverse functions at nonzero algebraic $a$ other than their trivial
points; by Niven's theorem $sin(pi r)$, $cos(pi r)$ and $tan(pi r)$ are dyadic for
dyadic $r$ only at multiples of $1/2$ and, for $tan$, at odd multiples of
$1/4$. The implementation special-cases these points, so Lemma 8 applies to
every other input; the refinement budget limits how long it may take.

= Integer powers

#lemma[Lemma 9][Let an addition chain $1 = a_0, a_1, dots, a_k = n$ be evaluated
with one rounding per step, $hat(x)_(a_j) = hat(x)_(a_i) hat(x)_(a_l) (1 + delta_j)$
with $abs(delta_j) <= u$. Then $hat(x)_n = x^n product_j (1 + delta_j)^(m_j)$ with
$sum_j m_j <= n - 1$.]

#proof[Let $E(a)$ be the total exponent of the error factors in $hat(x)_a$. Then
$E(1) = 0$ and $E(a_j) = E(a_i) + E(a_l) + 1$ for $a_j = a_i + a_l$. By induction,
$E(a_j) <= (a_i - 1) + (a_l - 1) + 1 = a_j - 1$.]

Therefore $hat(x)_n = x^n (1 + theta)$ with $abs(theta) <= gamma_(n-1) = (n-1)u / (1 - (n-1)u)$.
With $u = 2^(-w)$ and $w >= p + op("bits")(n) + 4$, $(n - 1) u < 2^(op("bits")(n) - w)$
is tiny, and since $abs(hat(x)_n) < 2^(op("top") + 1)$ the error is below
$2^(op("bits")(n)) (1 + gamma)$ units of $2^(op("top") - w + 1)$, which is covered
by the radius $2^(op("bits")(n) + 2)$ units used by the code. For negative
exponents the reciprocal of the base adds the factor $(1 + delta_0)^n$, so
$E <= 2n - 1$, covered by the radius $2^(op("bits")(n) + 3)$.

= The number-theoretic transform

#lemma[Lemma 10][Split $A$ and $B$ into $n_a$ and $n_b$ base-$2^16$ digits and let
$c_k = sum_(i + j = k) a_i b_j$. If the transform length is at most $2^23$, then
$0 <= c_k < p_1 p_2$ for $p_1 = 998244353$, $p_2 = 754974721$, so $c_k$ is
determined by $c_k mod p_1$ and $c_k mod p_2$.]

#proof[Each $c_k$ has at most $min(n_a, n_b) <= 2^23$ terms, each below $2^32$, so
$c_k < 2^55$. And $p_1 p_2 = 753649251896000513 > 2^59 > 2^55$. The Chinese
remainder theorem gives a unique residue in $[0, p_1 p_2)$. Both primes admit
transforms of length $2^23$ because $2^23 | p_1 - 1 = 119 dot 2^23$ and
$2^23 | p_2 - 1 = 45 dot 2^24$.]

= Shortest decimal output

#lemma[Lemma 11][Let $I$ be an interval containing $x > 0$, and let $d_n$ be $x$
truncated to $n$ significant decimal digits. If $d_n in I$ then $d_(n+1) in I$;
the same holds for the $n$-digit decimals rounded away from zero.]

#proof[Truncation to more digits only removes less, so $d_n <= d_(n+1) <= x$. An
interval containing $d_n$ and $x$ contains every point between them. The
upward case is symmetric.]

With $I$ the set of reals that round to $x$, a candidate is accepted iff it
lies in $I$, so acceptance is monotone in $n$ and the least accepted digit
count can be found by bisection.
