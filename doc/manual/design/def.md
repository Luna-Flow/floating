# def design

## Design goal

`def` gives the four representations of `floating` (binary `BinFloat`, IEEE
decimal `@decimal.Decimal`, GDA decimal `@decimal_gda.Decimal` and interval
`BallFloat`) one vocabulary for the things they have in common: what class a
value belongs to, what its sign is, at what precision it is stored, how to move
it to another precision, and which representative of its value it is. It also
names the result of an IEEE comparison and re-exports the context and error
types of [Luna-Flow/arithmetic](https://lunaflow.cn/en/arithmetic/). The
package is deliberately thin: it states contracts and contains no numerical
algorithm. The [API page](../api/def.md) lists the items; the
[tutorial](../tutorial/def.md) shows them in use.

## Mathematical background

### Values and their meaning

A finite scalar of radix $\beta$ ($\beta = 2$ for `BinFloat`, $\beta = 10$ for
both decimals) is a triple of a sign bit $s$, a coefficient $c \in \mathbb{N}$
and an exponent $e \in \mathbb{Z}$, and denotes the real number

$$
[\![x]\!] = (-1)^{s}\, c\, \beta^{e}.
$$

Several triples denote the same real: $(0, 15, -1)$ and $(0, 150, -2)$ both
denote $1.5$ in radix ten, and $(0, 0, e)$ and $(1, 0, e)$ both denote $0$.
Non-finite scalars denote $\pm\infty$ or are NaN, which denotes no number. A
non-empty `BallFloat` with endpoints $\ell \le u$ denotes the closed set
$X = \{\, t \in \mathbb{R} : \ell \le t \le u \,\}$ (with infinite endpoints
meaning an unbounded side), and the empty interval denotes $\varnothing$.

For a precision $p \ge 1$ let

$$
\mathbb{F}_{\beta,p} = \{\, (-1)^{s} c\, \beta^{e} : s \in \{0,1\},\ 0 \le c < \beta^{p},\ e \in \mathbb{Z} \,\}
$$

be the numbers with at most $p$ significant radix-$\beta$ digits and an
unbounded exponent. A rounding function $\circ_{m,p} : \mathbb{R} \to
\mathbb{F}_{\beta,p}$ for a direction $m$ (`RoundingMode`) maps a real to a
neighbouring element of $\mathbb{F}_{\beta,p}$: $\nabla$ (`TowardNegative`)
to the largest element $\le t$, $\Delta$ (`TowardPositive`) to the smallest
element $\ge t$, `TowardZero` to the one of these two with the smaller
magnitude, `AwayFromZero` to the larger, and `ToNearestEven` to the nearer one,
ties going to the even coefficient.[^ieee-rounding]

[^ieee-rounding]: IEEE 754-2019, clause 4.3 (rounding-direction attributes).
    `AwayFromZero` is not an IEEE binary attribute; it corresponds to the GDA
    rounding `Up` (Cowlishaw, *General Decimal Arithmetic Specification*).

### The IEEE comparison relation

IEEE 754 defines comparison so that for every pair of floating-point data
exactly one of four relations holds: *less than*, *equal*, *greater than* and
*unordered*.[^ieee-compare] On the extended reals the first three are the usual
trichotomy, with $-0 = +0$ and $-\infty < t < +\infty$ for every finite $t$;
*unordered* holds exactly when at least one operand is NaN, including when both
are the same NaN. `PartialOrder` is this four-valued relation as a datatype.

[^ieee-compare]: IEEE 754-2019, clause 5.11 (details of comparison predicates)
    and Table 5.1. The quiet and signaling predicates differ only in whether a
    quiet-NaN operand signals invalid operation, which is why `bin_float`
    returns the relation together with `BinaryFlags`.

## Design decisions

### A small open trait instead of a numeric tower

**Problem.** Generic code must be able to ask any representation a few
questions, but the representations do not share arithmetic laws: binary and
decimal operations round in different radices, GDA operations thread a sticky
context, and interval operations return enclosures rather than rounded points.

**Options.** (a) A broad "real number" trait with arithmetic, ordering and
parsing. (b) A trait with only representation-independent observations and
re-precision. (c) No shared trait.

**Choice: (b).** `Floating` has exactly `classify`, `sign`, `precision`,
`with_precision` and `normalized`. Arithmetic is taken from MoonBit's operator
traits and from the capability traits of Luna-Flow/arithmetic (`SqrtChecked`,
`AddContextual`, …), which each type implements only where it can honour the
law. A single broad trait would force one law on all four domains; for example
an interval cannot implement a scalar `compare` without lying about overlapping
operands. This follows the Luna-Flow principle that code depends on the
smallest trait composition stating its requirements.

### `Sign` merges the two zeros

`sign` answers "on which side of zero is the value", not "what is the sign
bit". Merging $-0$ and $+0$ into `Zero` makes `sign` a function of the denoted
value, so it agrees across representations and with the
[`semantic`](semantic.md) projection, which also forgets signed zeros. The sign
bit stays observable through the concrete packages. The scalar implementations
return `Zero` for NaN because NaN has no position on the line; callers that
care test `is_nan` first.

For an interval $X = [\ell, u]$ the same question has three honest answers,
and `BallFloat::sign` returns them as follows:

$$
\operatorname{sign}(X) =
\begin{cases}
\texttt{Positive} & \text{if } \ell > 0 \quad(\text{every member is positive}),\\
\texttt{Negative} & \text{if } u < 0 \quad(\text{every member is negative}),\\
\texttt{Zero} & \text{if } \ell \le 0 \le u \quad(0 \in X).
\end{cases}
$$

The three cases are exhaustive and disjoint for non-empty $X$ because
$\ell \le u$: if neither $\ell > 0$ nor $u < 0$, then $\ell \le 0 \le u$. So
`Zero` on an interval means "contains zero", and `is_zero`, which is defined
through `sign`, inherits that meaning.

### `PartialOrder` is the IEEE four-way relation

**Problem.** Comparison results must be expressible for NaN operands.

**Options.** (a) Return `Int` through MoonBit's `Compare`. (b) Return
`Option[Int]`. (c) Return a four-valued enum.

**Choice: (c).** Let $\preceq$ be "less or equal" on floating-point data. It
is not an order on the whole set:

$$
\begin{aligned}
&\text{reflexivity fails:} && \mathrm{NaN} \preceq \mathrm{NaN} \text{ is false, since the pair is unordered;}\\
&\text{totality fails:} && \text{neither } 1 \preceq \mathrm{NaN} \text{ nor } \mathrm{NaN} \preceq 1;\\
&\text{antisymmetry fails on data:} && -0 \preceq +0 \text{ and } +0 \preceq -0, \text{ but } -0 \ne +0 \text{ as data.}
\end{aligned}
$$

Restricted to non-NaN data, $\preceq$ is reflexive, transitive and total, hence
a total *preorder*, and its quotient by "equal" is the total order of the
extended reals. With NaN it is not even a preorder, so no `Int`-valued
`Compare` instance can represent it lawfully: whichever integer is chosen for
an unordered pair, a sort based on it would treat NaN as comparable. An enum
with an explicit `Unordered` keeps the information and forces callers to handle
it in a `match`. `Option[Int]` would carry the same information but give "no
answer" the generic meaning of absence, and would lose the name.

The concrete packages additionally provide relations that *are* total, for
tasks that need one: `BinFloat::total_order` implements the IEEE `totalOrder`
predicate (clause 5.10), and `BinFloat::compare` (the `Compare` instance) is a
total preorder that places every NaN above every number. These are different
relations from `PartialOrder`, chosen per call site.

### Re-exporting the arithmetic types

`ArithmeticContext`, `ArithmeticError`, `RoundingMode`, `FpClass` and the
certification types are owned by Luna-Flow/arithmetic, which defines the
contextual and checked traits that `floating` implements. `def` re-exports them
with `pub using` rather than defining look-alikes, so a value of
`@def.RoundingMode` *is* a value of `@lf_arith.RoundingMode` and no conversion
layer exists between the two repositories.

## Correctness / invariants

### The `Floating` laws

The laws below are the contract of the trait. They are stated for a value $x$,
a precision $p$ and a direction $m$; $q = \max(1, p)$. The three scalar
implementations satisfy (F1)–(F5) and (F7), with the exponent-range exception
of `BinFloat` stated below (F5). `BallFloat` satisfies (F1)–(F4), (F6) and only
the weaker (F7′). A downstream implementation is expected to satisfy the laws
of its kind.

$$
\begin{aligned}
&\textbf{(F1) partition} && \text{exactly one of } \texttt{is\_finite}(x),\ \texttt{is\_infinite}(x),\ \texttt{is\_nan}(x) \text{ holds;}\\
&\textbf{(F2) sign} && \texttt{classify}(x) \ne \texttt{NaN} \implies \texttt{sign}(x) \text{ is given by the side of } 0 \text{ on which } [\![x]\!] \text{ lies;}\\
&\textbf{(F3) precision} && \texttt{precision}(x) \ge 1;\\
&\textbf{(F4) re-precision} && \texttt{precision}(\texttt{with\_precision}(x, p, m)) = q;\\
&\textbf{(F5) rounding} && x \text{ a finite scalar} \implies [\![\texttt{with\_precision}(x,p,m)]\!] = \circ_{m,q}([\![x]\!]);\\
&\textbf{(F6) enclosure} && x \text{ an interval} \implies [\![x]\!] \subseteq [\![\texttt{with\_precision}(x,p,m)]\!];\\
&\textbf{(F7) normal form} && x \text{ a scalar} \implies [\![\texttt{normalized}(x)]\!] = [\![x]\!],\quad \texttt{normalized}(\texttt{normalized}(x)) = \texttt{normalized}(x);\\
&\textbf{(F7′) interval normal form} && x \text{ an interval} \implies [\![x]\!] \subseteq [\![\texttt{normalized}(x)]\!].
\end{aligned}
$$

**The exponent range of `BinFloat`.** (F5) is stated over
$\mathbb{F}_{\beta,q}$, whose exponent is unbounded. The decimal types store the
exponent as an `Int` and add no other limit, so for them (F5) holds as stated.
`BinFloat` keeps its implementation range even in `with_precision`: let
$E = 2^{30} - 1$ (`binary_implementation_e_max`, and $-E$ is
`binary_implementation_e_min`). A rounded result whose leading bit would lie
above $2^{E}$ overflows: to an infinity for `ToNearestEven`, `AwayFromZero`
and the directed mode that points away from zero on that side, otherwise to
the largest finite value with $q$ bits. A value whose leading bit lies below
$2^{-E-(q-1)}$, the smallest positive value stored at $q$ bits, is rounded to
$0$ or to that value. So for `BinFloat` (F5) holds whenever
$\circ_{m,q}([\![x]\!])$ lies in that range. For example
$3 \cdot 2^{E-1}$ re-expressed with one bit and `AwayFromZero` becomes
$+\infty$ instead of $2^{E+1}$.

For non-finite scalars, `with_precision` keeps the class and the sign and only
changes the stored precision, so (F4) still holds. (F2) for intervals is the
three-case rule derived above; for scalars "the side of $0$" is `Zero` for
$[\![x]\!] = 0$.

**Why (F6) holds for `BallFloat`.** A bounded `BallFloat` stores its endpoints
$\ell \le u$. Its centre $c = (\ell + u)/2$ is computed exactly, and its radius
$r$ is the half-width $(u - \ell)/2$ rounded upward, so every member $t$
satisfies $|t - c| \le (u - \ell)/2 \le r$. `with_precision` computes $\tilde c = \circ_{m,q}(c)$, rounds the
error $|c - \tilde c|$ and the radius upward to $\tilde e \ge |c-\tilde c|$
and $\tilde r \ge r$, adds them with upward rounding to $R \ge \tilde r +
\tilde e$, and stores $[\nabla(\tilde c - R), \Delta(\tilde c + R)]$. For any
member $t$ with $|t - c| \le r$,

$$
|t - \tilde c| \le |t - c| + |c - \tilde c| \le r + |c - \tilde c| \le \tilde r + \tilde e \le R,
$$

so $\nabla(\tilde c - R) \le \tilde c - R \le t \le \tilde c + R \le
\Delta(\tilde c + R)$. The direction $m$ only moves the centre; the enclosure
holds for every $m$. If $\tilde c \pm R$ leaves the `BinFloat` range, the
directed roundings go to $\mp\infty$, which still encloses. Unbounded
intervals round the lower endpoint down and the upper endpoint up, which
encloses trivially. The empty interval maps to the empty interval.

**Why `BallFloat` has only (F7′).** `normalized` on a bounded interval calls
the same centre–radius quantization at the stored precision $q$, so the
argument above gives (F7′). Equality fails in general: the exact centre of two
$q$-bit endpoints may need $q + 1$ bits, and then rounding it adds an error
term to the radius. With $q = 53$, $\ell = 1$ and $u = 1 + 2^{-52}$, the centre
$1 + 2^{-53}$ rounds to $1$, the radius $2^{-53}$ grows by the error $2^{-53}$
to $2^{-52}$, and the result is $[1 - 2^{-52}, 1 + 2^{-52}] \supsetneq [\ell, u]$.
For the same reason `with_precision(x, precision(x), m)` is not the identity
on intervals, and repeated normalization is not guaranteed to be stable
(each step can only widen, and it stops widening once the centre is
representable at $q$ bits and the endpoints are exact).

```moonbit
///|
test "interval normalization encloses but widens" {
  let x = @ball_float.BallFloat::from_bounds(
    @bin_float.BinFloat::from_int(1),
    @bin_float.BinFloat::from_hex("0x10000000000001p-52", 53).unwrap(),
  )
  let n = @def.Floating::normalized(x)
  inspect(n.lower_bound().to_hex(), content="0xfffffffffffffp-52")
  inspect(n.upper_bound().to_hex(), content="0x10000000000001p-52")
  let again = @def.Floating::normalized(n)
  inspect(again.lower_bound().to_hex(), content="0xfffffffffffffp-52")
}
```

### Consequences of (F5)

Rounding is the identity on its target set: if $t \in \mathbb{F}_{\beta,q}$
then $\circ_{m,q}(t) = t$ for every direction, because $t$ is its own
neighbour. Hence

$$
[\![x]\!] \in \mathbb{F}_{\beta,q} \implies [\![\texttt{with\_precision}(x, p, m)]\!] = [\![x]\!],
$$

and in particular raising the precision never changes a value, since
$\mathbb{F}_{\beta,p} \subseteq \mathbb{F}_{\beta,p'}$ for $p \le p'$.

Lowering the precision in two steps is *not* the same as lowering it once in
general. For the directed modes it is. Take $q \le p$ and $m =$
`TowardZero`, write $\circ_k$ for $\circ_{m,k}$, and let $a = \circ_q(t)$, the
element of $\mathbb{F}_{\beta,q}$ with the sign of $t$ and the largest
magnitude not exceeding $|t|$. Then

$$
\begin{aligned}
a \in \mathbb{F}_{\beta,q} \subseteq \mathbb{F}_{\beta,p},\ |a| \le |t|
  &\implies |a| \le |\circ_p(t)| \le |t| && \text{(definition of } \circ_p\text{)}\\
b \in \mathbb{F}_{\beta,q},\ |b| \le |\circ_p(t)|
  &\implies |b| \le |t| \implies |b| \le |a| && \text{(definition of } a\text{)}\\
  &\implies \circ_q(\circ_p(t)) = a = \circ_q(t).
\end{aligned}
$$

The same argument with "largest element $\le t$" works for $\nabla$, with
"smallest element $\ge t$" for $\Delta$, and with "smallest magnitude
$\ge |t|$" for `AwayFromZero`: every directed rounding to $\mathbb{F}_{\beta,q}$
factors through any finer set $\mathbb{F}_{\beta,p}$ that contains
$\mathbb{F}_{\beta,q}$. For
`ToNearestEven` the identity fails (double rounding).[^double-rounding] Take
$t = 1.0100001_2 = 161/128$ in binary. With $p = 3$ the neighbours are $1.25$
and $1.5$, and $t$ rounds to $1.25$, which is exactly halfway between the
$q = 2$ neighbours $1$ and $1.5$; the tie goes to the even coefficient, $1$.
Rounding $t$ directly to two bits gives $1.5$ because $t > 1.25$:

```moonbit
///|
test "double rounding to nearest differs from one rounding" {
  let t = @bin_float.BinFloat::from_double(1.2578125)
  let nearest = @lf_arith.RoundingMode::ToNearestEven
  let twice = @def.Floating::with_precision(
    @def.Floating::with_precision(t, 3, nearest),
    2,
    nearest,
  )
  let once = @def.Floating::with_precision(t, 2, nearest)
  inspect(twice.to_string(), content="1p0")
  inspect(once.to_string(), content="3p-1")
  let toward_zero = @lf_arith.RoundingMode::TowardZero
  let twice_rz = @def.Floating::with_precision(
    @def.Floating::with_precision(t, 3, toward_zero),
    2,
    toward_zero,
  )
  let once_rz = @def.Floating::with_precision(t, 2, toward_zero)
  inspect(twice_rz.to_string() == once_rz.to_string(), content="true")
}
```

[^double-rounding]: Muller et al., *Handbook of Floating-Point Arithmetic*,
    2nd ed., 2018, section 3.2 (double rounding); Goldberg, "What every
    computer scientist should know about floating-point arithmetic", 1991.

### The predicates

The four predicates are projections of `classify` and `sign`, so their
correctness reduces to (F1) and (F2). `is_zero` evaluates `classify` first and
uses short-circuit `&&`; it therefore never calls `sign` on a NaN-class value,
which keeps it total on empty intervals although `BallFloat::sign` aborts
there.

### Cost

Every item of `def` is constant time apart from the delegated
implementation. `with_precision` and `normalized` cost what the concrete
package's rounding or trailing-zero removal costs: linear in the coefficient
length for decimals, and linear in the coefficient bit length for binary.

## Alternatives rejected

- **A `Real` super-trait with arithmetic.** It would claim laws (associativity,
  total order) that rounded and interval arithmetic do not satisfy, and would
  hide the difference between exact, rounded and enclosing operations.
- **`Compare` for IEEE comparison.** An `Int` result cannot express
  *unordered*; see the derivation above.
- **Separate `NegativeZero` / `PositiveZero` signs.** They would make `sign`
  depend on the representation rather than the value, and the interval sign
  has no analogue.
- **Defining local copies of `RoundingMode` and `ArithmeticContext`.** They
  would need conversions at every boundary with Luna-Flow/arithmetic.

## Boundaries

- No arithmetic, parsing, formatting or comparison is implemented here; `def`
  only names results (`Sign`, `PartialOrder`) and states contracts.
- `Floating` does not imply a field, a total order, an IEEE format, exact
  arithmetic or any error behaviour. Generic code must request the additional
  capability traits it uses.
- `with_precision` neither honours context exponent bounds nor reports flags
  (only the `BinFloat` implementation range applies); contexts and flags belong
  to the `*_ctx` APIs of the concrete packages and to the contextual traits of
  Luna-Flow/arithmetic.
- `normalized` keeps the value only on scalars; on intervals it is an
  enclosure (F7′).
- `Sign` does not expose the sign bit of zeros or NaNs.
- The laws are documented and tested by the implementations; the trait does not
  enforce them for downstream implementations.
