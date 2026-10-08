#set document(title: "Rounding proofs for decimal")
#set page(paper: "a4", margin: 2.2cm, numbering: "1")
#set text(size: 10.5pt)
#set par(justify: true)
#set heading(numbering: "1.")
#set math.equation(numbering: "(1)")

#let lemma(name, body) = block(width: 100%, inset: (y: 4pt))[*#name.* #body]
#let proof(body) = block(width: 100%, inset: (left: 1em, y: 2pt))[_Proof._ #body #h(1fr) $square$]

#align(center)[
  #text(size: 16pt, weight: "bold")[Rounding proofs for `decimal`]
  #v(2pt)
  Luna-Flow `floating`, design attachment
]

This note proves the facts the `decimal` design page relies on. Notation: a
decimal format has precision $p$, adjusted-exponent range $[e_min, e_max]$,
$E_"tiny" = e_min - p + 1$ and $E_"top" = e_max - p + 1$. For a real $x > 0$
and an integer exponent $t$ write $x dot 10^(-t) = c + f$ with
$c in ZZ_(>= 0)$ and $0 <= f < 1$; a rounding direction $circle.small$ returns
$c dot 10^t$ or $(c + 1) dot 10^t$. Negative arguments are rounded through
$|x|$, with `Ceiling` and `Floor` exchanged.

= Rounding digit and sticky information

#lemma[Lemma 1 (midpoint test)][
Let $C = Q dot 10^s + R$ with $s >= 1$ and $0 <= R < 10^s$, and write
$R = r dot 10^(s-1) + R'$ with $r in {0, dots, 9}$, $0 <= R' < 10^(s-1)$.
Then $2R > 10^s$ iff $r > 5$ or ($r = 5$ and $R' > 0$); $2R = 10^s$ iff
$r = 5$ and $R' = 0$; and $2R < 10^s$ iff $r < 5$.
]
#proof[
$2R - 10^s = 2(r - 5) 10^(s-1) + 2R'$ and $0 <= 2R' < 2 dot 10^(s-1)$.
If $r >= 6$ the first term is at least $2 dot 10^(s-1)$, so the sum is
positive. If $r <= 4$ the first term is at most $-2 dot 10^(s-1)$ and the sum
is negative. If $r = 5$ the sum is $2R'$.
]

Hence the comparison of $2R$ with $10^s$ carries the rounding digit and the
sticky bit together, and the comparison of $2R$ with a divisor $D$ does the
same for an integer quotient $N = Q D + R$, because $f = R / D$.

#lemma[Lemma 2 (no square-root ties)][
For integers $M >= 0$ and $r = floor(sqrt(M))$, $sqrt(M) != r + 1/2$.
]
#proof[
$sqrt(M) = r + 1/2$ would give $4M = (2r + 1)^2$, an even number equal to an
odd one.
]

= Double rounding with `ZeroFiveUp`

Let $"zfu"_k (x)$ denote rounding $x > 0$ with `ZeroFiveUp` to the grid
$10^(t - k)$, $k >= 1$, and let $circle.small$ be any rounding direction to
the grid $10^t$.

#lemma[Lemma 3][
$circle.small("zfu"_k (x)) = circle.small(x)$ for every $x > 0$ and every
direction $circle.small$.
]
#proof[
Let $g = 10^(t-k)$ and $x = (n + phi) g$ with $n in ZZ$, $0 <= phi < 1$. If
$phi = 0$ then $"zfu"_k (x) = x$. Otherwise $y = "zfu"_k (x)$ is $n g$ or
$(n+1) g$, and the last digit of $y / g$ is in ${1,2,3,4,6,7,8,9}$: if $n$
ends in 0 or 5 the result is $n+1$, ending in 1 or 6; otherwise it is $n$.

The decision of $circle.small$ depends only on the position of its argument
relative to the points $m dot 10^t$ ("grid points") and $(m + 1/2) 10^t$
("midpoints"), $m in ZZ$, and on whether the argument is one of them. Grid
points are multiples of $g$ whose last digit is 0; midpoints are multiples of
$g$ whose last digit is 5 if $k = 1$ and 0 if $k >= 2$. So $y$ is neither a
grid point nor a midpoint, and neither is $x$, because $x$ is not a multiple
of $g$.

Let $z$ be any grid point or midpoint; it is a multiple of $g$. If $z <= n g$
then $z <= n g <= y$ and $z <= n g < x$, and $z != y$, so both $x$ and $y$ are
strictly above $z$. If $z >= (n+1) g$ then $x < z$ and $y <= z$, $y != z$, so
both are strictly below $z$. No multiple of $g$ lies strictly between $n g$
and $(n+1) g$. Therefore $x$ and $y$ are on the same side of every grid point
and midpoint, both are inexact at the grid $10^t$, and the last digit of the
truncation $m$ is the same for both; every rounding direction makes the same
decision.
]

The lemma fails for the half modes as the first rounding: rounding $x$ just
above a midpoint down onto the midpoint lets the tie rule of the second
rounding decide, which may pick the other neighbour.

= Overflow

#lemma[Lemma 4 (overflow results)][
Let $N_max = (10^p - 1) 10^(E_"top")$ and let $x > 0$ overflow, i.e. $x$
rounded to $p$ digits with unbounded exponent has adjusted exponent above
$e_max$. Then the IEEE 754 result is $+infinity$ for `HalfEven`, `HalfUp`,
`HalfDown`, `Up` and `Ceiling`, and $N_max$ for `Down`, `Floor` and
`ZeroFiveUp`.
]
#proof[
The overflowing rounded value is at least $10^(e_max + 1)$, so
$x > N_max$. For `Down` and `Floor` the rounding never increases $|x|$
relative to the truncation, and the largest representable value not above
$x$ is $N_max$. For `ZeroFiveUp` the truncation is at least $N_max$, whose
last digit is 9, so no increment happens; saturation gives $N_max$. For
`Up` and `Ceiling` the rounding of any $x > N_max$ is above $N_max$, hence
infinite. For the half modes, $x$ rounds with unbounded exponent either to
$N_max$ (no overflow) or to a value of at least $10^(e_max + 1)$; the
latter happens only for $x >= N_max + 1/2 dot 10^(E_"top")$, i.e. when $x$
is at least as far from $N_max$ as the midpoint toward the next power of
ten. IEEE 754 §7.4 delivers $plus.minus infinity$ for every overflow under a
round-to-nearest attribute, which is the saturation of that upward rounding.
The negative case is symmetric with `Ceiling` and `Floor` exchanged.
]

= Clamping

#lemma[Lemma 5 (fold-down fits)][
If a finite non-zero $x = C dot 10^Q$ with $d$ digits has
$Q > E_"top"$ and adjusted exponent $a = Q + d - 1 <= e_max$, then
$C dot 10^(Q - E_"top")$ has at most $p$ digits.
]
#proof[
Its digit count is $d + Q - E_"top" = (a - Q + 1) + Q - (e_max - p + 1) =
a - e_max + p <= p$.
]

= Certified rounding of enclosures

#lemma[Lemma 6 (certification)][
Let $L <= v <= U$ and let $circle.small$ be a rounding to a decimal context.
If $circle.small(L)$ and $circle.small(U)$ are the same representation, then
$circle.small(v)$ is that representation. If moreover $v$ is not
representable and $circle.small(L)$, $circle.small(U)$ carry the same flags,
$circle.small(v)$ carries them too.
]
#proof[
Rounding is monotone, so $circle.small(L) <= circle.small(v) <=
circle.small(U)$; equal outer values force the middle one in value. $L$ and
$U$ cannot straddle zero, because then they would round to zeros of
different signs or to values of different signs; so all three have one
sign, and the member of the cohort is the one the finalizer chooses for
that value, which is the same. For the flags: let $r$ be the common result. Not both $L = r$ and $U = r$,
since then $v = r$ would be representable; so one endpoint differs from $r$
and is inexact, and because the flags agree both are. $v != r$, so $v$ is
inexact too, and `rounded` accompanies `inexact`. `overflow`, `subnormal`
and `underflow` are monotone predicates of $|v|$ on a one-signed interval
(adjusted exponent above $e_max$, below $e_min$, and inexactness), so if
they agree at both ends they hold at $v$. `clamped` depends only on the result.
]

If $v$ is itself representable, a directed rounding sends $L < v$ and
$U > v$ to different neighbours and the test never succeeds; the
implementation therefore decides exact cases before entering the loop.

= Kernel bounds

#lemma[Lemma 7 (Comba columns)][
For $n <= 18$ limbs of base $10^9$, a column sum of $n$ limb products plus
the incoming carry is below $2^64$.
]
#proof[
The carry into a column is the previous column sum divided by $10^9$, below
$18 dot 10^9 + 1 < 2 dot 10^(10)$ by induction. The sum is at most
$18 (10^9 - 1)^2 + 2 dot 10^(10) < 1.8 dot 10^(19) < 2^64 approx 1.8447 dot 10^(19)$.
With $n = 19$, $19 (10^9 - 1)^2 > 1.89 dot 10^(19) > 2^64$.
]

#lemma[Lemma 8 (two-prime NTT)][
Let $p_1 = 998244353 = 119 dot 2^(23) + 1$ and $p_2 = 754974721 = 45 dot
2^(24) + 1$. For digit sequences in base $10^4$ of lengths $n_a, n_b$ with
$n_a + n_b - 1 <= 2^(23)$, every coefficient $z$ of the integer convolution
is recovered from $r_i = z mod p_i$ by
$z = r_1 + p_1 ((r_2 - r_1) p_1^(-1) mod p_2)$.
]
#proof[
Both $p_i - 1$ are divisible by $2^(23)$, so $ZZ slash p_i ZZ$ contains a
primitive root of unity of every order $2^j <= 2^(23)$ and the cyclic
convolution of the zero-padded sequences equals the integer convolution
reduced modulo $p_i$. Each $z$ is a sum of at most $m = min(n_a, n_b)$
products below $10^8$, so $0 <= z < m dot 9999^2 < 2^(23) dot 10^8 < p_1 p_2
approx 7.54 dot 10^(17)$. The formula gives the unique integer in
$[0, p_1 p_2)$ congruent to $r_1$ modulo $p_1$ and to $r_2$ modulo $p_2$
(Chinese remainder theorem), which is $z$.
]
