# def design

## Design goal

`def` gives the three scalar representations of `floating` (binary `Binary`,
IEEE decimal `@decimal.Decimal` and GDA decimal `@decimal_gda.Decimal`) one
vocabulary for the things they have in common: what class a
value belongs to, what its sign is, at what precision it is stored, how to move
it to another precision, and which representative of its value it is. It also
names the result of an IEEE comparison and re-exports the context and error
types of [Luna-Flow/arithmetic](https://lunaflow.cn/en/arithmetic/). The
package is deliberately thin: it states contracts and contains no numerical
algorithm. The [API page](../api/def.md) lists the items; the
[tutorial](../tutorial/def.md) shows them in use.

## Mathematical background

### Values and their meaning

A finite scalar of radix $\beta$ ($\beta = 2$ for `Binary`, $\beta = 10$ for
both decimals) is a triple of a sign bit $s$, a coefficient $c \in \mathbb{N}$
and an exponent $e \in \mathbb{Z}$, and denotes the real number

$$
[\![x]\!] = (-1)^{s}\, c\, \beta^{e}.
$$

Several triples denote the same real: $(0, 15, -1)$ and $(0, 150, -2)$ both
denote $1.5$ in radix ten, and $(0, 0, e)$ and $(1, 0, e)$ both denote $0$.
Non-finite scalars denote $\pm\infty$ or are NaN, which denotes no number.

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
    quiet-NaN operand signals invalid operation, which is why `binary`
    returns the relation together with `BinaryFlags`.

## Design decisions

### A small trait instead of a numeric tower

**Problem.** Generic code must be able to ask any representation a few
questions, but the representations do not share arithmetic laws: binary and
decimal operations round in different radices and GDA operations thread a sticky
context. Intervals are deliberately not among them (see [Intervals are not
`Floating`](#intervals-are-not-floating)).

**Options.** (a) A broad "real number" trait with arithmetic, ordering and
parsing. (b) A trait with only representation-independent observations and
re-precision. (c) No shared trait.

**Choice: (b).** `Floating` has exactly `classify`, `signum`, `precision`,
`with_precision` and `normalized`. Arithmetic is taken from MoonBit's operator
traits and from the capability traits of Luna-Flow/arithmetic (`SqrtChecked`,
`AddContextual`, …), which each type implements only where it can honour the
law. A single broad trait would force one law on all domains; for example
an interval cannot implement a scalar `compare` without lying about overlapping
operands. This follows the Luna-Flow principle that code depends on the
smallest trait composition stating its requirements.

### Why `Floating` is declared open

**Problem.** `Floating` is meant to be implemented by the types of this
library only, so that a method can be added to it in a minor release without
breaking a downstream type. MoonBit has a visibility that would enforce this,
`pub trait` (readonly), but it is per package.

**Evidence.** Declaring `pub trait Floating` in `def` makes every
implementation outside `def` fail to compile:

```text
Error: [4145]
 1047 │ pub impl @def.Floating for Binary with fn classify(self) {
      │          ──────┬──────
      │                ╰──────── Cannot implement trait '@Luna-Flow/floating/def.Floating' because it is readonly.
```

The four implementations are in `binary`, `decimal`, `decimal_gda` and
`interval`, which are other packages of the module, and `def` cannot import
them (they import `def`).

**Options.** (a) Keep `pub(open)` and state the contract in the documentation.
(b) Seal the trait with a token type that only this module can build. (c) Move
the implementations into `def`, which is a dependency cycle.

**Choice: (a).** (b) puts an internal type into a public trait signature for
a promise that documentation can state as well, and (c) is impossible. The
contract is: implementing `Floating` outside this module is not supported and
not covered by the compatibility promise; the tutorial therefore shows no
such implementation, and the generic predicates `is_finite`, `is_infinite`,
`is_nan` and `is_zero` are unchanged.

### `Sign` merges the two zeros

`signum` answers "on which side of zero is the value", not "what is the sign
bit". Merging $-0$ and $+0$ into `Zero` makes `signum` a function of the denoted
value, so it agrees across representations and with the
[`semantic`](semantic.md) projection, which also forgets signed zeros. The sign
bit stays observable through the concrete packages. The scalar implementations
return `Zero` for NaN because NaN has no position on the line; callers that
care test `is_nan` first.

### Intervals are not `Floating`

Up to 0.11 `Interval` implemented `Floating`, and every observation had to be
read with an interval meaning: `signum` returned `Zero` for "contains 0" and
aborted on the empty set, `is_zero` through it meant "contains 0", `is_nan`
meant "empty", and `with_precision` ignored its rounding mode. A generic
function written for scalars then gave answers that were true of no single
number: `is_zero` of $[-1, 1]$ is true, but $[-1, 1] \ne \{0\}$. The names of
those predicates are the scalar ones, so the interval meaning could not be
told from the call site. `Interval` therefore does not implement `Floating`;
its package spells the questions the way IEEE 1788-2015 does (`is_empty`,
`is_entire`, `is_common_interval`, `is_singleton`, the comparisons of Table
10.3, `contains` for a point) and re-rounds with `with_precision`, which always
rounds outward.

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
tasks that need one: `Binary::total_order` implements the IEEE `totalOrder`
predicate (clause 5.10), and `Binary::compare` (the `Compare` instance) is a
total preorder that places every NaN above every number. These are different
relations from `PartialOrder`, chosen per call site.

### Re-exporting the arithmetic types

`ArithmeticContext`, `ArithmeticError`, `RoundingMode`, `FpClass` and the
certification types are owned by Luna-Flow/arithmetic, which defines the
contextual and checked traits that `floating` implements. `def` re-exports them
with `pub using` rather than defining look-alikes, so a value of
`@def.RoundingMode` *is* a value of `@lf_arith.RoundingMode` and no conversion
layer exists between the two repositories.

## Correctness and invariants

### The `Floating` laws

The laws below are the contract of the trait. They are stated for a value $x$,
a precision $p$ and a direction $m$; $q = \max(1, p)$. The three scalar
implementations satisfy (F1)–(F5) and (F6), with the exponent-range exception
of `Binary` stated below (F5). The laws are the contract between the three implementations and the generic
code of this library; they are not an invitation to implement the trait
elsewhere (see [Why `Floating` is declared open](#why-floating-is-declared-open)).

$$
\begin{aligned}
&\textbf{(F1) partition} && \text{exactly one of } \texttt{is\_finite}(x),\ \texttt{is\_infinite}(x),\ \texttt{is\_nan}(x) \text{ holds;}\\
&\textbf{(F2) sign} && \texttt{classify}(x) \ne \texttt{NaN} \implies \texttt{sign}(x) \text{ is given by the side of } 0 \text{ on which } [\![x]\!] \text{ lies;}\\
&\textbf{(F3) precision} && \texttt{precision}(x) \ge 1;\\
&\textbf{(F4) re-precision} && \texttt{precision}(\texttt{with\_precision}(x, p, m)) = q;\\
&\textbf{(F5) rounding} && x \text{ a finite scalar} \implies [\![\texttt{with\_precision}(x,p,m)]\!] = \circ_{m,q}([\![x]\!]);\\
&\textbf{(F6) normal form} && [\![\texttt{normalized}(x)]\!] = [\![x]\!],\quad \texttt{normalized}(\texttt{normalized}(x)) = \texttt{normalized}(x).
\end{aligned}
$$

**The exponent range of `Binary`.** (F5) is stated over
$\mathbb{F}_{\beta,q}$, whose exponent is unbounded. The decimal types store the
exponent as an `Int` and add no other limit, so for them (F5) holds as stated.
`Binary` keeps its implementation range even in `with_precision`: let
$E = 2^{30} - 1$ (`binary_implementation_e_max`, and $-E$ is
`binary_implementation_e_min`). A rounded result whose leading bit would lie
above $2^{E}$ overflows: to an infinity for `ToNearestEven`, `AwayFromZero`
and the directed mode that points away from zero on that side, otherwise to
the largest finite value with $q$ bits. A value whose leading bit lies below
$2^{-E-(q-1)}$, the smallest positive value stored at $q$ bits, is rounded to
$0$ or to that value. So for `Binary` (F5) holds whenever
$\circ_{m,q}([\![x]\!])$ lies in that range. For example
$3 \cdot 2^{E-1}$ re-expressed with one bit and `AwayFromZero` becomes
$+\infty$ instead of $2^{E+1}$.

For non-finite scalars, `with_precision` keeps the class and the sign and only
changes the stored precision, so (F4) still holds. For scalars "the side of $0$" is `Zero` for $[\![x]\!] = 0$.

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
`ToNearestEven` the identity fails (double rounding).[^double-rounding] (The trait method `Floating::with_precision` has no mode and rounds to nearest even; the example calls the inherent `Binary::with_precision`, which takes one.) Take
$t = 1.0100001_2 = 161/128$ in binary. With $p = 3$ the neighbours are $1.25$
and $1.5$, and $t$ rounds to $1.25$, which is exactly halfway between the
$q = 2$ neighbours $1$ and $1.5$; the tie goes to the even coefficient, $1$.
Rounding $t$ directly to two bits gives $1.5$ because $t > 1.25$:

```moonbit
///|
test "double rounding to nearest differs from one rounding" {
  let t = @binary.Binary::from_double(1.2578125)
  let nearest = @binary.BinaryRoundingMode::RoundTiesToEven
  let twice = t.with_precision(3, nearest).with_precision(2, nearest)
  let once = t.with_precision(2, nearest)
  inspect(twice.to_string(), content="1p0")
  inspect(once.to_string(), content="3p-1")
  inspect(@def.Floating::with_precision(t, 2).to_string(), content="3p-1")
  let toward_zero = @binary.BinaryRoundingMode::RoundTowardZero
  let twice_rz = t.with_precision(3, toward_zero).with_precision(2, toward_zero)
  let once_rz = t.with_precision(2, toward_zero)
  inspect(twice_rz.to_string() == once_rz.to_string(), content="true")
}
```

[^double-rounding]: Muller et al., *Handbook of Floating-Point Arithmetic*,
    2nd ed., 2018, section 3.2 (double rounding); Goldberg, "What every
    computer scientist should know about floating-point arithmetic", 1991.

### The predicates

The four predicates are projections of `classify` and `signum`, so their
correctness reduces to (F1) and (F2). `is_zero` evaluates `classify` first and
uses short-circuit `&&`; it therefore never calls `signum` on a NaN-class value,
which keeps it total on NaN.

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
- **Separate `NegativeZero` / `PositiveZero` signs.** They would make `signum`
  depend on the representation rather than the value.
- **Defining local copies of `RoundingMode` and `ArithmeticContext`.** They
  would need conversions at every boundary with Luna-Flow/arithmetic.

## Boundaries

- No arithmetic, parsing, formatting or comparison is implemented here; `def`
  only names results (`Sign`, `PartialOrder`) and states contracts.
- `Floating` does not imply a field, a total order, an IEEE format, exact
  arithmetic or any error behaviour. Generic code must request the additional
  capability traits it uses.
- `with_precision` neither honours context exponent bounds nor reports flags
  (only the `Binary` implementation range applies); contexts and flags belong
  to the `*_ctx` APIs of the concrete packages and to the contextual traits of
  Luna-Flow/arithmetic.
- `normalized` keeps the representation-independent value (F6).
- `Sign` does not expose the sign bit of zeros or NaNs.
- The laws are documented and tested by the implementations; the trait does not
  enforce them for downstream implementations.
