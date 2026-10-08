# semantic design

## Design goal

`semantic` answers one question independently of representation: *which
number does this datum denote?* A binary float, an IEEE decimal and an
interval endpoint are mapped to exact rationals, signed infinities, NaN and
closed intervals, so that values computed by different packages, at different
precisions and in different radices, can be compared exactly. Checked errors
are mapped to a small common vocabulary for the same purpose. The package is a
boundary for tests, diagnostics and protocols; it performs no arithmetic. The
[API page](../api/semantic.md) lists the items and the
[tutorial](../tutorial/semantic.md) shows them in use.

## Mathematical background

### Floating-point numbers are rationals

A finite binary float with sign bit $s$, integer coefficient $c \ge 0$ and
exponent $e$ denotes $(-1)^{s} c\, 2^{e}$, and a finite decimal denotes
$(-1)^{s} c\, 10^{q}$. Writing $m = (-1)^{s} c$, both have the shape
$m\, r^{k}$ with an integer $m$, a radix $r \ge 2$ and an integer $k$, which is
a rational number:

$$
m\, r^{k} =
\begin{cases}
\dfrac{m\, r^{k}}{1}, & k \ge 0,\\[2ex]
\dfrac{m}{r^{-k}}, & k < 0.
\end{cases}
$$

The finite binary values are therefore exactly the *dyadic rationals*
$\mathbb{Z}[1/2] = \{\, a/2^{j} : a \in \mathbb{Z}, j \in \mathbb{N} \,\}$ and the
finite decimal values are exactly $\mathbb{Z}[1/10] = \{\, a/10^{j} \,\}$, both
subrings of $\mathbb{Q}$. This is the map `ExactRational::from_scaled_integer`
computes, with $r^{|k|}$ evaluated exactly in `BigInt`.

### The reduced form is canonical

Every rational $x$ has exactly one representation $n/d$ with

$$
d > 0, \qquad \gcd(|n|, d) = 1 \qquad (\text{and } 0 = 0/1).
$$

*Existence.* From any $n'/d'$ with $d' \ne 0$, multiply numerator and
denominator by $\operatorname{sgn}(d')$ and divide both by
$g = \gcd(|n'|, |d'|)$. *Uniqueness.* Suppose $n/d = n'/d'$ with both pairs
reduced and $d, d' > 0$. Then

$$
\begin{aligned}
n d' &= n' d &&\text{(cross-multiplying)}\\
d \mid n d',\ \gcd(d, n) = 1 &\implies d \mid d' &&\text{(Euclid's lemma)}\\
d' \mid n' d,\ \gcd(d', n') = 1 &\implies d' \mid d\\
d, d' > 0 &\implies d = d' \implies n = n'.
\end{aligned}
$$

`ExactRational::new` establishes exactly this form (sign moved to the
numerator, Euclid's algorithm for the gcd, zero normalized to $0/1$), and the
fields are private, so every `ExactRational` is reduced. Consequently the
derived structural equality on the two `BigInt` fields *is* equality of
rational numbers: $n/d = n'/d' \iff (n, d) = (n', d')$.

### Comparing values of different radices

Equality of two projected values is decided by the canonical form. Ordering is
not provided by the package, but the representation makes it a two-multiplication
test: for reduced $a/b$ and $c/d$ with $b, d > 0$,

$$
\frac{a}{b} < \frac{c}{d}
\iff \frac{a}{b} - \frac{c}{d} < 0
\iff \frac{ad - cb}{bd} < 0
\iff ad - cb < 0
\quad (\text{since } bd > 0),
$$

which is what the [tutorial](../tutorial/semantic.md#order-two-values-exactly)
implements over `numerator()` and `denominator()`.

The canonical denominators also explain which decimals have a binary
representation. A reduced binary value has denominator $2^{j}$; a reduced
decimal value $a/10^{j}$ reduces to a denominator $2^{u} 5^{v}$. By uniqueness
of the reduced form, a decimal value equals some finite binary float (of
sufficient precision, and inside the `BinFloat` exponent range of about
$2^{\pm 2^{30}}$) if and only if its reduced denominator has no factor $5$. One tenth reduces to $1/(2 \cdot 5)$, so no binary float equals it, and the
projection of binary64 `0.1` is $3602879701896397/2^{55}$, a different
number.[^goldberg]

[^goldberg]: Goldberg, "What every computer scientist should know about
    floating-point arithmetic", *ACM Computing Surveys* 23(1), 1991, section
    on base conversion; Knuth, *TAOCP* vol. 2, section 4.4.

```moonbit
///|
test "a decimal has a binary equal iff its denominator has no factor 5" {
  let denominator = fn(s : @semantic.SemanticScalar) {
    match s {
      Rational(q) => q.denominator().to_string()
      _ => "none"
    }
  }
  let d = fn(text : String) {
    @semantic.SemanticScalar::from_decimal(@decimal.Decimal::from_string(text).unwrap())
  }
  let b = fn(x : Double) {
    @semantic.SemanticScalar::from_bin_float(@bin_float.BinFloat::from_double(x))
  }
  inspect(denominator(d("0.375")), content="8")
  inspect(d("0.375") == b(0.375), content="true")
  inspect(denominator(d("0.1")), content="10")
  inspect(denominator(b(0.1)), content="36028797018963968")
}
```

### Intervals as pairs of extended rationals

A non-empty `BallFloat` denotes $X = \{\, t \in \mathbb{R} : \ell \le t \le u
\,\}$ for endpoints $\ell \le u$ in $\mathbb{Z}[1/2] \cup \{-\infty,
+\infty\}$, with an infinite endpoint meaning an unbounded side, as in IEEE
1788-2015 set-based intervals.[^ieee1788] `SemanticInterval::from_ball_float`
projects $\ell$ and $u$ independently with `from_bin_float`, so the pair
determines $X$ exactly. The empty interval is stored by `ball_float` with
$\ell = +\infty$ and $u = -\infty$, and the projection keeps that reversed pair;
in the extended order, *lower > upper* holds exactly for the empty set. A
membership test $t \in X$ for a rational $t$ is then two comparisons of the
kind derived above.

[^ieee1788]: IEEE 1788-2015, *Standard for Interval Arithmetic*, clause 7
    (set-based flavor): intervals are closed connected subsets of
    $\mathbb{R}$, possibly unbounded or empty.

## Design decisions

### Exact rationals, not a common floating format

**Problem.** Comparing a binary and a decimal value needs a common domain.

**Options.** (a) Convert both to `Double` or to a wide binary float. (b) Convert
both to a decimal string. (c) Project both to $\mathbb{Q}$.

**Choice: (c).** Conversion to a float rounds, so two different values may
compare equal after conversion (binary64 `0.1` and decimal `0.1` both round to
the same `Double`). A string comparison depends on formatting and cohort.
$\mathbb{Z}[1/2]$ and $\mathbb{Z}[1/10]$ both embed into $\mathbb{Q}$ without
loss, and the reduced form makes equality a field comparison. The price is
size: $r^{|k|}$ has about $|k| \log_2 r$ bits.

### What the projection forgets

The projection keeps only the denoted value. It drops precision, decimal
quantum (cohort), the sign of zero, NaN payload, sign and signalling state,
and all flags and context state. Interval decorations never reach it:
`from_ball_float` accepts only an undecorated `BallFloat`. These are properties of
representations and of computations, and the concrete packages expose them.
Keeping any of them would make two equal numbers from different packages
compare unequal, which defeats the purpose of the package.

### NaN as a single value with structural equality

`SemanticScalar` derives `Eq`, so `NaN == NaN`. The type is a model in which
"this computation produced no number" is one outcome among others, and tests
need to assert that two packages both produce it. IEEE comparison, where NaN is
unordered with itself, stays in the concrete packages and in
[`PartialOrder`](def.md).

### A separate error vocabulary

`ArithmeticError` carries a message and, for certification failures, a detail
record with precisions and refinement counts that differ between packages for
the same mathematical failure. `SemanticError` keeps only the kind, so
`semantic_scalar_result` makes the outcome comparable across packages. The
mapping tests the kind predicates in a fixed order and falls back to
`UnsupportedOperation`; since every `ArithmeticErrorKind` constructor has its
own predicate, each kind maps to the `SemanticError` of the same name.

### Projections as plain functions

`semantic_scalar_result` takes the projection as an argument instead of
dispatching on a trait. With $\mathrm{Res}(T) = T + E$ and
$\mathrm{Sem}(S) = S + E'$, the function is

$$
\texttt{semantic\_scalar\_result}(\cdot, f) = f + \texttt{from\_arithmetic} : T + E \longrightarrow S + E',
$$

the coproduct of the two maps, applying $f$ on the left summand and the error
map on the right. It satisfies the functor law
$\texttt{semantic\_scalar\_result}(r.\texttt{map}(g), f) =
\texttt{semantic\_scalar\_result}(r, f \circ g)$, which lets callers reuse one
projection for every pipeline.

## Correctness and invariants

- **Reduced form.** Every `ExactRational` satisfies $d > 0$,
  $\gcd(|n|, d) = 1$ and $n = 0 \Rightarrow d = 1$; `new` aborts on $d = 0$.
- **Exactness.** For finite $x$,
  $\texttt{from\_bin\_float}(x) = \texttt{Rational}([\![x]\!])$ and
  $\texttt{from\_decimal}(x) = \texttt{Rational}([\![x]\!])$; nothing is
  rounded.
- **Soundness and completeness of equality.** For finite $x$, $y$ of any of
  the two supported scalar types, the projections are equal if and only if
  $[\![x]\!] = [\![y]\!]$; this is the uniqueness of the reduced form.
- **Class preservation.** Infinities project to `Infinity` with the same sign,
  every NaN projects to `NaN`, finite values to `Rational`.
- **Intervals.** `from_ball_float` is the pair of endpoint projections; the
  entire line gives $(-\infty, +\infty)$, the empty interval
  $(+\infty, -\infty)$.
- **Cost.** `from_scaled_integer` performs one exact power and, for negative
  exponents, one gcd; both are polynomial in the bit length
  $O(|k| \log r + \log |m|)$ of the operands.

## Alternatives rejected

- **Implementing arithmetic on `ExactRational`.** Exact rational arithmetic
  is a different library; here it would invite using the projection as a
  number type, which it is not.
- **An `Ord`-style instance on `SemanticScalar`.** NaN and the reversed empty
  interval have no place in a total order; callers order rationals explicitly.
- **Keeping the signed zero.** It would make `-0.0` and decimal `0` unequal,
  although they denote the same number.
- **A projection for `@decimal_gda.Decimal`.** Not provided on the current
  branch; GDA values reach this package through their string form or through
  `@decimal.Decimal`.

## Boundaries

- No arithmetic, rounding, parsing, formatting, interchange encoding or interval
  tightening.
- No ordering of semantic values; equality only.
- Representation details (precision, quantum, signed zero, NaN payload and
  signalling, flags, context) are deliberately not preserved, and decorated
  intervals are not accepted.
- Only `BinFloat`, `@decimal.Decimal` and `BallFloat` have projections.
- Projections of values with very large exponents are exact and therefore
  large; the package does not guard against that cost. A `BinFloat` exponent
  near its implementation limit $\pm(2^{30} - 1)$ gives a `BigInt` of about
  $2^{30}$ bits, and a decimal exponent near $10^{9}$ one of about
  $3.3 \cdot 10^{9}$ bits.
