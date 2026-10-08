# ball_float API

## Purpose

`ball_float` is interval arithmetic over `BinFloat` endpoints. A `BallFloat`
is a closed real interval $[\underline{x}, \overline{x}]$, possibly unbounded,
or the empty set; every operation returns an interval that contains all exact
results of the operation on points of its operands (the *inclusion property*).
`BallFloatDecorated` adds the decorations of IEEE 1788-2015, `BallContext`
rounds results into a target binary format and reports `BallFlags`.

Despite the name, the stored representation is the endpoint pair, not a
midpoint and a radius: `BallFloat::new(center, radius)`, `center()` and
`radius()` convert to and from the midpoint–radius view. The
[tutorial](../tutorial/ball_float.md) shows typical use; the
[design page](../design/ball_float.md) derives the formulas and proves the
inclusion property. The fallible pipeline wrapper is
[`ball_float_checked`](ball_float_checked.md).

Conventions used on this page:

- $\operatorname{RD}_p$ and $\operatorname{RU}_p$ round toward $-\infty$ and
  $+\infty$ to $p$ significant bits. "Rounded outward" means the lower endpoint
  is rounded with $\operatorname{RD}_p$ and the upper with
  $\operatorname{RU}_p$.
- The *precision* of an interval is a tag in bits. Operations round their
  result outward to the larger precision of their operands; elementary
  functions use the precision of their argument.
- The exponent range of `BinFloat` endpoints is the implementation range of
  `bin_float`: leading-bit exponents up to $e_{\max} = 2^{30} - 1$, and
  nonzero magnitudes down to $2^{e_{\min} - p + 1}$ with
  $e_{\min} = -(2^{30} - 1)$. Use a `BallContext` to impose a narrower range.
- *Empty* is the empty set, *Entire* is $(-\infty, +\infty)$. An unbounded
  interval stores $-\infty$ and/or $+\infty$ as endpoints; these mean that the
  set is unbounded on that side, never that it contains an infinite value.
- The few inputs for which the code currently breaks the inclusion property,
  aborts, or misreports a decoration are marked with a WARNING and collected
  under [Known limitations](../design/ball_float.md#known-limitations) on the
  design page.

## Importing

Add the package and the endpoint package to your `moon.pkg`:

```moonbit nocheck
import {
  "Luna-Flow/floating/bin_float",
  "Luna-Flow/floating/ball_float",
  "Luna-Flow/arithmetic" @lf_arith,
}
```

The examples refer to the packages as `@ball_float.`, `@bin_float.` and
`@lf_arith.` (for `Luna-Flow/arithmetic`, which defines `ArithmeticError`,
`RoundingMode` and the enclosure traits). They use two helpers: `iv(lo, hi)`
builds the 53-bit interval with integer endpoints, and `fmt(x)` prints the
endpoints as six-digit decimals, the lower one rounded down and the upper one
rounded up, so the text still encloses the stored set.

```moonbit
///|
fn iv(lo : Int, hi : Int) -> @ball_float.BallFloat {
  @ball_float.BallFloat::from_bounds(
    @bin_float.BinFloat::from_int(lo, precision=53),
    @bin_float.BinFloat::from_int(hi, precision=53),
  )
}

///|
fn fmt(x : @ball_float.BallFloat) -> String {
  if x.is_empty() {
    return "[empty]"
  }
  let down = @bin_float.BinaryContext::unbounded(
    53,
    rounding=@bin_float.BinaryRoundingMode::RoundTowardNegative,
  )
  let up = @bin_float.BinaryContext::unbounded(
    53,
    rounding=@bin_float.BinaryRoundingMode::RoundTowardPositive,
  )
  "[" +
  x.lower_bound().to_decimal_string_ctx(6, down).0 +
  ", " +
  x.upper_bound().to_decimal_string_ctx(6, up).0 +
  "]"
}
```

## Types

### `BallFloat`

`BallFloat` is a closed interval with `BinFloat` endpoints and a precision tag.

```mbti
pub struct BallFloat {
  // private fields
} derive(Eq, @debug.Debug)
```

A non-empty value satisfies $\underline{x} \le \overline{x}$, has no NaN
endpoint, never has $\underline{x} = +\infty$ or $\overline{x} = -\infty$, and
has precision $\ge 1$. The empty set is a separate state. The fields are
private; construct values with the functions in
[Construction](#construction). The derived `Eq` compares the stored
representation (endpoints and precision), not the sets; see
[`BallFloat::set_equal`](#ballfloatsubset-ballfloatinterior-ballfloatset_equal-ballfloatdisjoint).

### `BallFloatDecorated`

`BallFloatDecorated` is a `BallFloat` paired with an IEEE 1788
[`Decoration`](#decoration), or the special value NaI (not an interval).

```mbti
pub struct BallFloatDecorated {
  // private fields
} derive(Eq)
```

The decoration is kept canonical: an empty interval always carries `Trv`, an
unbounded interval never carries `Com`, and only `BallFloatDecorated::nai`
carries `Ill`.

### `Decoration`

`Decoration` is the IEEE 1788 decoration of a decorated interval, ordered
`Ill < Trv < Def < Dac < Com`.

```mbti
pub(all) enum Decoration {
  Ill
  Trv
  Def
  Dac
  Com
} derive(Eq, @debug.Debug)
```

For a decorated result $(\boldsymbol{y}, d)$ of a function $f$ evaluated on
a box $\boldsymbol{x}$:

| Constructor | Meaning |
| --- | --- |
| `Com` | $\boldsymbol{x}$ is non-empty and bounded, $f$ is defined and continuous on $\boldsymbol{x}$, and $\boldsymbol{y}$ is bounded |
| `Dac` | $\boldsymbol{x}$ is non-empty, $f$ is defined on $\boldsymbol{x}$ and its restriction to $\boldsymbol{x}$ is continuous |
| `Def` | $\boldsymbol{x}$ is non-empty and $f$ is defined on $\boldsymbol{x}$ |
| `Trv` | nothing is known |
| `Ill` | the value is NaI |

Each property implies the ones below it, which is why the decorations are
totally ordered. `Show` prints the lower-case IEEE 1788 names `com`, `dac`,
`def`, `trv`, `ill`.

### `OverlapState`

`OverlapState` is the result of `overlap_state`: the IEEE 1788 classification
of the relative position of two intervals.

```mbti
pub(all) enum OverlapState {
  Undefined
  BothEmpty
  FirstEmpty
  SecondEmpty
  Before
  Meets
  OverlapsState
  Starts
  ContainedBy
  Finishes
  EqualIntervals
  After
  MetBy
  OverlappedBy
  StartedBy
  ContainsInterval
  FinishedBy
} derive(Eq, @debug.Debug)
```

The constructors correspond to the IEEE 1788 states `bothEmpty`,
`firstEmpty`, `secondEmpty`, `before`, `meets`, `overlaps`, `starts`,
`containedBy`, `finishes`, `equal`, `after`, `metBy`, `overlappedBy`,
`startedBy`, `contains` and `finishedBy`; `OverlapsState`, `EqualIntervals`
and `ContainsInterval` carry a suffix only to avoid clashing with method names.
`Undefined` is returned only by the decorated version when an operand is NaI.

### `BallContext`

`BallContext` describes a target binary format: a precision in bits and an
exponent range $[e_{\min}, e_{\max}]$.

```mbti
pub struct BallContext {
  // private fields
}
```

$e_{\min}$ and $e_{\max}$ follow IEEE 754: a finite nonzero value $v$ with
$2^{e} \le |v| < 2^{e+1}$ is in range when $e \le e_{\max}$, and it is normal
when $e \ge e_{\min}$. See [Contexts and flags](#contexts-and-flags).

### `BallFlags`

`BallFlags` records the conditions raised while rounding an interval into a
`BallContext`.

```mbti
pub struct BallFlags {
  inexact : Bool
  overflow : Bool
  underflow : Bool
} derive(Eq)
```

`inexact` is set when an endpoint changed; `overflow` when an endpoint was
beyond $e_{\max}$; `underflow` when an endpoint had to be rounded on the
subnormal grid and that last step was inexact (see
[`BallFloat::apply_ctx`](#ballfloatapply_ctx) for how this differs from
IEEE 754). The fields are readable; the accessor methods are listed under
[`BallFlags::new`](#ballflagsnew-ballflagscombine-ballflagsinexact-ballflagsoverflow-ballflagsunderflow).

## Construction

### `BallFloat::new`

`BallFloat::new` builds the interval $[c - r, c + r]$ from a center and a
radius, enlarged so that it is exact at the requested precision.

```mbti
pub fn BallFloat::new(@bin_float.BinFloat, @bin_float.BinFloat, precision? : Int) -> Self
```

The default precision is the larger of the precisions of `center` and
`radius`. With $p$ that precision, the stored interval is

$$
[\tilde c - R,\; \tilde c + R], \qquad
\tilde c = \operatorname{RN}_p(c),\quad
R = \operatorname{RU}_p\bigl(\operatorname{RU}_p(r) + \operatorname{RU}_p(|c - \tilde c|)\bigr),
$$

which contains $[c - r, c + r]$ (proof in the
[design page](../design/ball_float.md#from-midpointradius-to-endpoints)). The
endpoints $\tilde c \pm R$ are formed exactly, so they may carry more than
$p$ bits. Aborts when `center` or `radius` is not finite or when `radius` is
negative. A precision below 1 is treated as 1.

When $c$ already has at most $p$ bits and $r = 0$, the result is the
singleton $\{c\}$. When $c$ needs more than $p$ bits, the rounding error of
the center is added to the radius on *both* sides, so the interval is wider
than $[\operatorname{RD}_p(c - r), \operatorname{RU}_p(c + r)]$; use
`from_bounds` for the tightest enclosure of known bounds.

### `BallFloat::from_bounds` and `BallFloat::try_from_bounds`

`BallFloat::from_bounds` builds the interval $[\underline{x}, \overline{x}]$
from its endpoints, rounded outward to the requested precision.

```mbti
pub fn BallFloat::from_bounds(@bin_float.BinFloat, @bin_float.BinFloat, precision? : Int) -> Self
pub fn BallFloat::try_from_bounds(@bin_float.BinFloat, @bin_float.BinFloat, precision? : Int) -> Result[Self, @arithmetic.ArithmeticError]
```

The default precision is the larger of the endpoint precisions. Infinite
endpoints build unbounded intervals: `from_bounds(-inf, +inf)` is Entire. The
inputs are invalid when an endpoint is NaN, the lower endpoint is $+\infty$,
the upper endpoint is $-\infty$, or $\underline{x} > \overline{x}$;
`from_bounds` aborts and `try_from_bounds` returns a domain error. There is no
way to build Empty from bounds; use `BallFloat::empty`.

```moonbit
///|
test "from_bounds" {
  let two = @bin_float.BinFloat::from_int(2, precision=53)
  let three = @bin_float.BinFloat::from_int(3, precision=53)
  inspect(fmt(@ball_float.BallFloat::from_bounds(two, three)), content="[2.00000e+0, 3.00000e+0]")
  inspect(@ball_float.BallFloat::try_from_bounds(three, two) is Err(_), content="true")
}
```

### `BallFloat::exact` and `BallFloat::try_exact`

`BallFloat::exact` builds the singleton $\{x\}$ of a finite `BinFloat`.

```mbti
pub fn BallFloat::exact(@bin_float.BinFloat, precision? : Int) -> Self
pub fn BallFloat::try_exact(@bin_float.BinFloat, precision? : Int) -> Result[Self, @arithmetic.ArithmeticError]
```

The default precision is that of `x`. When `x` has more significant bits than
the requested precision, the singleton is rounded outward to the two-point
interval $[\operatorname{RD}_p(x), \operatorname{RU}_p(x)]$. A non-finite `x`
aborts `exact` and makes `try_exact` return a domain error.

### `BallFloat::from_int` and `BallFloat::from_coefficient`

`BallFloat::from_int` and `BallFloat::from_coefficient` build an enclosure of
an integer.

```mbti
pub fn BallFloat::from_int(Int, precision? : Int) -> Self
pub fn BallFloat::from_coefficient(@bin_float.BinCoeff, precision? : Int, negative? : Bool) -> Self
```

The default precision is 16. `from_coefficient` takes a non-negative
`BinCoeff` magnitude and a separate sign. The integer is converted to a
`BinFloat` exactly and then passed to `exact`, so the result is the singleton
$\{n\}$ when $n$ fits in $p$ bits and the two-point interval
$[\operatorname{RD}_p(n), \operatorname{RU}_p(n)]$ otherwise. Either way it
contains $n$. Pass a precision at least as large as the bit length of the
integer to get a singleton.

### `BallFloat::from_double`, `BallFloat::try_from_double`, `BallFloat::from_float` and `BallFloat::try_from_float`

These functions build the singleton of the exact binary value of a `Double`
or `Float`.

```mbti
pub fn BallFloat::from_double(Double, precision? : Int) -> Self
pub fn BallFloat::try_from_double(Double, precision? : Int) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::from_float(Float, precision? : Int) -> Self
pub fn BallFloat::try_from_float(Float, precision? : Int) -> Result[Self, @arithmetic.ArithmeticError]
```

Default precisions are 53 and 24. The conversion to `BinFloat` is exact; a
smaller requested precision rounds the singleton outward. NaN and infinities
abort the plain forms and are domain errors for the `try_` forms. The result
encloses the binary value, not the decimal literal it was written as:
`from_double(0.1)` does not contain $1/10$.

### `BallFloat::whole` and `BallFloat::empty`

`BallFloat::whole` returns Entire and `BallFloat::empty` returns Empty.

```mbti
pub fn BallFloat::whole(precision? : Int) -> Self
pub fn BallFloat::empty(precision? : Int) -> Self
```

The default precision is 53.

## Observers

### `BallFloat::lower_bound` and `BallFloat::upper_bound`

`lower_bound` and `upper_bound` return the stored endpoints.

```mbti
pub fn BallFloat::lower_bound(Self) -> @bin_float.BinFloat
pub fn BallFloat::upper_bound(Self) -> @bin_float.BinFloat
```

For an unbounded side the endpoint is an infinity. For Empty they return
$+\infty$ and $-\infty$ respectively, so test `is_empty` first.

### `BallFloat::center` and `BallFloat::radius`

`center` and `radius` return the midpoint–radius view of a bounded interval.

```mbti
pub fn BallFloat::center(Self) -> @bin_float.BinFloat
pub fn BallFloat::radius(Self) -> @bin_float.BinFloat
```

`center` is $(\underline{x} + \overline{x})/2$ and `radius` is
$(\overline{x} - \underline{x})/2$. Both are dyadic, so they are computed
exactly (the radius is rounded up only if it underflows the exponent range),
and $[\text{center} - \text{radius}, \text{center} + \text{radius}]$ is the
stored interval. Both abort on Empty and on unbounded intervals.

> [!NOTE]
> For bounded intervals whose endpoints are more than about $2^{16}$ binary
> orders of magnitude apart, neither value is exact: the smaller endpoint is
> replaced by a sticky surrogate below the last bit of the larger one (see the
> [design page](../design/ball_float.md#far-addends-bound-endpoint-sums-by-precision)),
> rounded to nearest for `center` and upward for `radius`. The pair then
> describes the stored set only approximately.

### `BallFloat::midpoint`

`midpoint` returns the center rounded to nearest at the interval's precision.

```mbti
pub fn BallFloat::midpoint(Self) -> @bin_float.BinFloat
```

Entire has midpoint 0. Empty and half-bounded intervals abort.

### `BallFloat::width` and `BallFloat::radius_extended`

`width` returns $\operatorname{RU}_p(\overline{x} - \underline{x})$ and
`radius_extended` returns the radius rounded up to the interval's precision.

```mbti
pub fn BallFloat::width(Self) -> @bin_float.BinFloat
pub fn BallFloat::radius_extended(Self) -> @bin_float.BinFloat
```

Both return 0 for Empty and $+\infty$ for unbounded intervals instead of
aborting. Both are upper bounds of the exact value.

### `BallFloat::magnitude` and `BallFloat::mignitude`

`magnitude` returns $\sup\{|\xi| : \xi \in \boldsymbol{x}\}$ and `mignitude`
returns $\inf\{|\xi| : \xi \in \boldsymbol{x}\}$.

```mbti
pub fn BallFloat::magnitude(Self) -> @bin_float.BinFloat
pub fn BallFloat::mignitude(Self) -> @bin_float.BinFloat
```

For a non-empty interval,

$$
\operatorname{mag}\boldsymbol{x} = \max(|\underline{x}|, |\overline{x}|),
\qquad
\operatorname{mig}\boldsymbol{x} =
\begin{cases}
0 & 0 \in \boldsymbol{x}, \\
\min(|\underline{x}|, |\overline{x}|) & \text{otherwise,}
\end{cases}
$$

because $|\xi|$ is convex, so its maximum over an interval is at an endpoint,
and it is monotone on each side of 0. Both are exact. Empty gives 0 for both
(IEEE 1788 leaves them undefined there); `magnitude` of an unbounded interval
is $+\infty$.

```moonbit
///|
test "observers" {
  let x = iv(-3, 5)
  inspect(x.center().to_string(), content="1p0")
  inspect(x.radius().to_string(), content="1p2")
  inspect(x.width().to_string(), content="1p3")
  inspect(x.magnitude().to_string(), content="5p0")
  inspect(x.mignitude().to_string(), content="0")
  inspect(iv(2, 7).mignitude().to_string(), content="1p1")
}
```

### `BallFloat::precision`, `BallFloat::classify` and `BallFloat::sign`

`precision` returns the precision tag; `classify` and `sign` describe the
interval in the vocabulary of scalar floating-point types.

```mbti
pub fn BallFloat::precision(Self) -> Int
pub fn BallFloat::classify(Self) -> @arithmetic.FpClass
pub fn BallFloat::sign(Self) -> @def.Sign
```

`classify` returns `NaN` for Empty, `Finite` for a bounded interval and
`Infinity` for an unbounded one. `sign` returns `Positive` when
$\underline{x} > 0$, `Negative` when $\overline{x} < 0$, and `Zero` otherwise:
`Zero` means "the interval contains 0", not "the interval is $\{0\}$".
`sign` aborts on Empty.

### `BallFloat::is_empty`, `BallFloat::is_entire`, `BallFloat::is_bounded`, `BallFloat::is_common_interval`, `BallFloat::is_singleton`, `BallFloat::contains_zero`

These predicates test the shape of the set.

```mbti
pub fn BallFloat::is_empty(Self) -> Bool
pub fn BallFloat::is_entire(Self) -> Bool
pub fn BallFloat::is_bounded(Self) -> Bool
pub fn BallFloat::is_common_interval(Self) -> Bool
pub fn BallFloat::is_singleton(Self) -> Bool
pub fn BallFloat::contains_zero(Self) -> Bool
```

`is_bounded` and `is_common_interval` (the IEEE 1788 name) are the same: the
interval is non-empty with two finite endpoints. `is_singleton` holds when
$\underline{x} = \overline{x}$. `contains_zero` is false for Empty.

## Precision

### `BallFloat::with_precision`

`with_precision` re-rounds an interval to a new precision without shrinking
it.

```mbti
pub fn BallFloat::with_precision(Self, Int, @arithmetic.RoundingMode) -> Self
```

For a bounded interval the center is rounded with `mode`, the displacement
is added to the radius, and the result is rebuilt as in `BallFloat::new`. For
an unbounded interval the finite endpoint is rounded outward and `mode` is
ignored. Empty stays Empty with the new precision.

> [!WARNING]
> The center–radius rebuild is not an identity, even when the precision does
> not change: if the exact center $(\underline{x} + \overline{x})/2$ needs
> more than $p$ bits, both endpoints move outward by the rounding error of the
> center. At 53 bits, $[1, 1 + 2^{-52}]$ has center $1 + 2^{-53}$, and
> `with_precision(53, ToNearestEven)` returns $[1 - 2^{-52}, 1 + 2^{-52}]$.
> The result still contains the input (except in the far-endpoint case noted
> under `center`, when the new precision exceeds about $2^{16}$ bits), but it
> can be wider by up to one ulp per side at every call. `normalized`,
> `convex_hull` with an Empty operand, the checked capabilities
> (`div_checked`, `pow_nat_checked`, `pow_int_checked`) and the
> `pow_nat`/`pow_int` methods of `ball_float_checked` all go through this
> rebuild. To re-round without widening, use
> `from_bounds(x.lower_bound(), x.upper_bound(), precision=q)`.

```moonbit
///|
test "with_precision widens" {
  let one = @bin_float.BinFloat::one(precision=53)
  let next = @bin_float.BinFloat::make(
    @bin_float.BinCoeff::from_uint64((1UL << 52) + 1UL),
    -52,
    53,
  )
  let x = @ball_float.BallFloat::from_bounds(one, next)
  let y = x.with_precision(53, @lf_arith.RoundingMode::ToNearestEven)
  inspect(y.lower_bound().to_string(), content="4503599627370495p-52")
  inspect(y.upper_bound().to_string(), content="4503599627370497p-52")
  inspect(x.subset(y) && !y.subset(x), content="true")
  // Re-rounding through the bounds keeps the interval.
  let z = @ball_float.BallFloat::from_bounds(x.lower_bound(), x.upper_bound(), precision=53)
  inspect(z.set_equal(x), content="true")
}
```

### `BallFloat::normalized`

`normalized` rebuilds a bounded interval from its normalized center and radius
(`BinFloat::normalized` removes trailing zero bits), and re-rounds the finite
endpoints of an unbounded interval outward.

```mbti
pub fn BallFloat::normalized(Self) -> Self
```

The result contains the input but, for the reason given under
`with_precision`, can be strictly wider: `normalized` of
$[1, 1 + 2^{-52}]$ at 53 bits is $[1 - 2^{-52}, 1 + 2^{-52}]$. It therefore
satisfies only the enclosure form of the `@def.Floating` law "normalizing
keeps the value".

## Set operations

### `BallFloat::intersection` and `BallFloat::convex_hull`

`intersection` returns $\boldsymbol{x} \cap \boldsymbol{y}$ and `convex_hull`
returns the smallest interval containing $\boldsymbol{x} \cup \boldsymbol{y}$.

```mbti
pub fn BallFloat::intersection(Self, Self) -> Self
pub fn BallFloat::convex_hull(Self, Self) -> Self
```

For non-empty operands both are computed by endpoint `max`/`min`
($[\max(\underline{x}, \underline{y}), \min(\overline{x}, \overline{y})]$ and
$[\min(\underline{x}, \underline{y}), \max(\overline{x}, \overline{y})]$),
exact apart from the final outward rounding to the larger precision. Disjoint
intervals intersect to Empty, and an Empty operand makes the intersection
Empty. When one operand of `convex_hull` is Empty, the result is the other
operand passed through `with_precision`, so it can be one ulp wider per side
than that operand (see the warning under
[`BallFloat::with_precision`](#ballfloatwith_precision)).

### `BallFloat::cancel_plus` and `BallFloat::cancel_minus`

`cancel_minus(x, y)` is the IEEE 1788 cancellative subtraction: in exact
arithmetic it returns the interval $\boldsymbol{z}$ with
$\boldsymbol{y} + \boldsymbol{z} = \boldsymbol{x}$, which undoes a previous
sum; `cancel_plus(x, y)` is `cancel_minus(x, -y)`.

```mbti
pub fn BallFloat::cancel_plus(Self, Self) -> Self
pub fn BallFloat::cancel_minus(Self, Self) -> Self
```

For bounded operands `cancel_minus` is
$[\operatorname{RD}(\underline{x} - \underline{y}), \operatorname{RU}(\overline{x} - \overline{y})]$.
Indeed $\boldsymbol{y} + \boldsymbol{z} = [\underline{y} + \underline{z},
\overline{y} + \overline{z}]$, so $\boldsymbol{y} + \boldsymbol{z} = \boldsymbol{x}$
forces $\underline{z} = \underline{x} - \underline{y}$ and
$\overline{z} = \overline{x} - \overline{y}$, and this is an interval exactly
when $w(\boldsymbol{x}) \ge w(\boldsymbol{y})$. Because of the outward
rounding, the computed $\boldsymbol{z}$ satisfies
$\boldsymbol{y} + \boldsymbol{z} \supseteq \boldsymbol{x}$. When
$w(\boldsymbol{y}) > w(\boldsymbol{x})$, when an operand is unbounded, or when
only $\boldsymbol{y}$ is empty, the result is Entire. Empty $\boldsymbol{x}$
with bounded or empty $\boldsymbol{y}$ gives Empty.

```moonbit
///|
test "set operations" {
  inspect(fmt(iv(0, 4).intersection(iv(2, 9))), content="[2.00000e+0, 4.00000e+0]")
  inspect(iv(0, 1).intersection(iv(2, 3)).is_empty(), content="true")
  inspect(fmt(iv(0, 1).convex_hull(iv(5, 6))), content="[0.00000e+0, 6.00000e+0]")
  // (x + y) - y widens, cancel_minus recovers x.
  let x = iv(1, 2)
  let y = iv(10, 20)
  inspect(fmt(x + y - y), content="[-9.00000e+0, 1.20000e+1]")
  inspect(fmt((x + y).cancel_minus(y)), content="[1.00000e+0, 2.00000e+0]")
}
```

## Relations

All relations are set relations of IEEE 1788; none of them is a total order.
They never abort.

### `BallFloat::contains`

`contains` tests whether a point belongs to the interval.

```mbti
pub fn BallFloat::contains(Self, @bin_float.BinFloat) -> Bool
```

It returns false for Empty and for a non-finite point (an unbounded interval
contains all sufficiently large reals, but not $\pm\infty$ or NaN). The trait
method `@lf_arith.Contains::contains` instead takes two intervals and tests
inclusion; see
[Enclosure relations](#arithmeticcontains-arithmeticoverlaps-arithmeticdefinitelylt-arithmeticdefinitelyle-arithmeticmaybeeq).

### `BallFloat::subset`, `BallFloat::interior`, `BallFloat::set_equal`, `BallFloat::disjoint`

These test inclusion, inclusion in the interior, equality and disjointness of
sets.

```mbti
pub fn BallFloat::subset(Self, Self) -> Bool
pub fn BallFloat::interior(Self, Self) -> Bool
pub fn BallFloat::set_equal(Self, Self) -> Bool
pub fn BallFloat::disjoint(Self, Self) -> Bool
```

`x.subset(y)` is $\boldsymbol{x} \subseteq \boldsymbol{y}$, that is
$\underline{y} \le \underline{x}$ and $\overline{x} \le \overline{y}$.
`x.interior(y)` is $\boldsymbol{x} \subseteq \operatorname{int}
\boldsymbol{y}$: each endpoint comparison is strict, except that two equal
infinite endpoints count as interior (the interior of $[a, +\infty)$ is
$(a, +\infty)$, so Entire is interior to itself). Empty is a subset of,
interior to and disjoint from every interval. `set_equal` ignores the
precision tag and the representation of the endpoints.

### `BallFloat::overlaps`, `BallFloat::maybe_eq`, `BallFloat::separated_from`

`overlaps` tests whether two intervals share a point; `maybe_eq` is the same
relation read as "the two unknown points may be equal"; `separated_from` is its
negation.

```mbti
pub fn BallFloat::overlaps(Self, Self) -> Bool
pub fn BallFloat::maybe_eq(Self, Self) -> Bool
pub fn BallFloat::separated_from(Self, Self) -> Bool
```

For non-empty operands `overlaps` is
$\underline{x} \le \overline{y} \wedge \underline{y} \le \overline{x}$, which
is $\boldsymbol{x} \cap \boldsymbol{y} \ne \emptyset$. `overlaps` is false and
`separated_from` is true when an operand is Empty.

### `BallFloat::definitely_lt`, `BallFloat::definitely_le`, `BallFloat::definitely_gt`

These hold when the order holds for every pair of points.

```mbti
pub fn BallFloat::definitely_lt(Self, Self) -> Bool
pub fn BallFloat::definitely_le(Self, Self) -> Bool
pub fn BallFloat::definitely_gt(Self, Self) -> Bool
```

`x.definitely_lt(y)` is $\overline{x} < \underline{y}$,
`definitely_le` is $\overline{x} \le \underline{y}$ and `definitely_gt` is
$\underline{x} > \overline{y}$. All three are false when an operand is Empty
(unlike `precedes`, which is vacuously true), so a `true` answer is always
backed by at least one pair of points.

### `BallFloat::less`, `BallFloat::strictly_less`, `BallFloat::precedes`, `BallFloat::strictly_precedes`

These are the order relations of IEEE 1788.

```mbti
pub fn BallFloat::less(Self, Self) -> Bool
pub fn BallFloat::strictly_less(Self, Self) -> Bool
pub fn BallFloat::precedes(Self, Self) -> Bool
pub fn BallFloat::strictly_precedes(Self, Self) -> Bool
```

For non-empty operands:

| Relation | Set definition | Condition |
| --- | --- | --- |
| `less` | $\forall\xi\,\exists\eta: \xi \le \eta$ and $\forall\eta\,\exists\xi: \xi \le \eta$ | $\underline{x} \le \underline{y}$ and $\overline{x} \le \overline{y}$ |
| `strictly_less` | the same with $<$ | $\underline{x} < \underline{y}$ (or both $-\infty$) and $\overline{x} < \overline{y}$ (or both $+\infty$) |
| `precedes` | $\forall\xi\,\forall\eta: \xi \le \eta$ | $\overline{x} \le \underline{y}$ |
| `strictly_precedes` | $\forall\xi\,\forall\eta: \xi < \eta$ | $\overline{x} < \underline{y}$ |

With Empty: `less` and `strictly_less` hold only when both are Empty;
`precedes` and `strictly_precedes` hold when either is Empty.

### `BallFloat::overlap_state`

`overlap_state` classifies the relative position of two intervals.

```mbti
pub fn BallFloat::overlap_state(Self, Self) -> OverlapState
```

The result is one of the sixteen states of [`OverlapState`](#overlapstate)
other than `Undefined`; it is computed from the comparisons of the four
endpoints, testing equal endpoints first, so a singleton that coincides with
an endpoint of the other interval gives `Starts`, `Finishes`, `StartedBy` or
`FinishedBy` rather than `Meets` or `MetBy`, as IEEE 1788 requires.

```moonbit
///|
test "relations" {
  let a = iv(1, 3)
  let b = iv(3, 6)
  inspect(a.precedes(b), content="true")
  inspect(a.strictly_precedes(b), content="false")
  inspect(a.definitely_le(b), content="true")
  inspect(a.maybe_eq(b), content="true")
  inspect(iv(2, 3).interior(iv(1, 6)), content="true")
  inspect(iv(1, 3).interior(iv(1, 6)), content="false")
  debug_inspect(a.overlap_state(b), content="Meets")
  debug_inspect(iv(1, 6).overlap_state(iv(2, 3)), content="ContainsInterval")
}
```

## Arithmetic

### `BallFloat::add`, `BallFloat::sub`, `BallFloat::mul`, `BallFloat::div`

The four basic operations return the outward-rounded hull of
$\{\xi \circ \eta : \xi \in \boldsymbol{x}, \eta \in \boldsymbol{y}\}$; they
are also available as the operators `+`, `-`, `*`, `/`.

```mbti
pub fn BallFloat::add(Self, Self) -> Self
pub fn BallFloat::sub(Self, Self) -> Self
pub fn BallFloat::mul(Self, Self) -> Self
pub fn BallFloat::div(Self, Self) -> Self
```

The result precision is the larger operand precision; an Empty operand gives
Empty. Endpoint formulas:

$$
\begin{aligned}
\boldsymbol{x} + \boldsymbol{y} &= [\operatorname{RD}(\underline{x} + \underline{y}),\ \operatorname{RU}(\overline{x} + \overline{y})] \\
\boldsymbol{x} - \boldsymbol{y} &= [\operatorname{RD}(\underline{x} - \overline{y}),\ \operatorname{RU}(\overline{x} - \underline{y})] \\
\boldsymbol{x} \cdot \boldsymbol{y} &= [\operatorname{RD}\min S,\ \operatorname{RU}\max S],\quad S = \{\underline{x}\underline{y}, \underline{x}\overline{y}, \overline{x}\underline{y}, \overline{x}\overline{y}\}
\end{aligned}
$$

with $0 \cdot \infty$ taken as 0 in $S$ (a zero endpoint times an unbounded
side contributes 0). The sums and products are formed exactly and rounded
once. For bounded operands the signs select the products that can be
extremal: two when both operands have constant sign, four (the minimum of
$\underline{x}\,\overline{y}$ and $\overline{x}\,\underline{y}$, the maximum
of $\underline{x}\,\underline{y}$ and $\overline{x}\,\overline{y}$) when either
operand has 0 in its interior. The design page proves the
[sign-case table](../design/ball_float.md#endpoint-formulas).

Division follows IEEE 1788: $\boldsymbol{x} / \boldsymbol{y}$ is the hull of
$\{\xi/\eta : \xi \in \boldsymbol{x}, \eta \in \boldsymbol{y}, \eta \ne 0\}$.

| Divisor $\boldsymbol{y}$ | Result |
| --- | --- |
| $0 \notin \boldsymbol{y}$ | $[\operatorname{RD}\min Q, \operatorname{RU}\max Q]$ over the endpoint quotients $Q$ |
| $\{0\}$ | Empty |
| $\underline{y} < 0 < \overline{y}$ | Entire, unless $\boldsymbol{x} = \{0\}$ |
| $[0, \overline{y}]$ or $[\underline{y}, 0]$ | half-unbounded (see below), or Entire when $\underline{x} < 0 < \overline{x}$ |

When the divisor touches 0 at one end, the quotient is unbounded on one side:
for example $[1, 2]/[0, 4] = [1/4, +\infty)$ and $[-2, -1]/[0, 4] =
(-\infty, -1/4]$. A dividend equal to $\{0\}$ gives $\{0\}$ for any divisor
other than $\{0\}$. Each selected quotient is computed by one directed
division at the result precision.

```moonbit
///|
test "basic arithmetic" {
  let x = iv(1, 2)
  let y = iv(-3, 5)
  inspect(fmt(x + y), content="[-2.00000e+0, 7.00000e+0]")
  inspect(fmt(x - y), content="[-4.00000e+0, 5.00000e+0]")
  inspect(fmt(x * y), content="[-6.00000e+0, 1.00000e+1]")
  inspect((x / y).is_entire(), content="true")
  inspect(fmt(x / iv(0, 4)), content="[2.50000e-1, inf]")
  inspect((x / iv(0, 0)).is_empty(), content="true")
}
```

### `BallFloat::neg` and `BallFloat::abs`

`neg` returns $[-\overline{x}, -\underline{x}]$ and `abs` returns
$\{|\xi| : \xi \in \boldsymbol{x}\}$.

```mbti
pub fn BallFloat::neg(Self) -> Self
pub fn BallFloat::abs(Self) -> Self
```

`abs` is $\boldsymbol{x}$ when $\underline{x} \ge 0$, $-\boldsymbol{x}$ when
$\overline{x} \le 0$, and $[0, \operatorname{mag}\boldsymbol{x}]$ otherwise.
Both are exact. `neg` is also the unary operator `-`.

### `BallFloat::reciprocal`

`reciprocal` returns $1/\boldsymbol{x}$ with the division rules above.

```mbti
pub fn BallFloat::reciprocal(Self) -> Self
```

### `BallFloat::square` and `BallFloat::pown`

`square` returns $\{\xi^2\}$ and `pown` returns $\{\xi^n\}$ for an integer
exponent $n$.

```mbti
pub fn BallFloat::square(Self) -> Self
pub fn BallFloat::pown(Self, Int) -> Self
```

Unlike `x * x`, these use the same point twice, so `[-1, 2].square()` is
$[0, 4]$ (while `x * x` is $[-2, 4]$): `square` is
$[\operatorname{mig}(\boldsymbol{x})^2, \operatorname{mag}(\boldsymbol{x})^2]$.
`pown` evaluates the monotone pieces of $\xi^n$ at the endpoints with directed
rounding: odd positive powers are increasing; even positive powers decrease
then increase, with minimum 0 when $0 \in \boldsymbol{x}$; negative powers
have a pole at 0. `pown(x, 0)` is $\{1\}$ for every non-empty `x`; Empty stays
Empty. `pown(x, n)` with $n < 0$ returns Empty for $\boldsymbol{x} = \{0\}$, a
half-unbounded interval when 0 is an endpoint, and for 0 in the interior
Entire (odd $n$) or $[\min(\underline{x}^n, \overline{x}^n), +\infty)$ (even
$n$). As a shortcut, $n < -4096$ with 0 in the interior returns Entire even
for even $n$; this is a valid but not tight enclosure.

```moonbit
///|
test "powers" {
  let x = iv(-1, 2)
  inspect(fmt(x.square()), content="[0.00000e+0, 4.00000e+0]")
  inspect(fmt(x.pown(3)), content="[-1.00000e+0, 8.00000e+0]")
  inspect(fmt(x.pown(-2)), content="[2.50000e-1, inf]")
  inspect(x.pown(-1).is_entire(), content="true")
  inspect(fmt(iv(0, 2).pown(-1)), content="[5.00000e-1, inf]")
}
```

### `BallFloat::fma`

`fma(x, y, z)` returns an enclosure of $\{\xi\eta + \zeta\}$ with a single
outward rounding.

```mbti
pub fn BallFloat::fma(Self, Self, Self) -> Self
```

The exact product bounds are computed as for `mul` and added to the endpoints
of $\boldsymbol{z}$ before the final rounding, so the result is never wider
than `x * y + z`.

### `BallFloat::minimum` and `BallFloat::maximum`

`minimum` and `maximum` return $\{\min(\xi, \eta)\}$ and
$\{\max(\xi, \eta)\}$.

```mbti
pub fn BallFloat::minimum(Self, Self) -> Self
pub fn BallFloat::maximum(Self, Self) -> Self
```

`minimum` is $[\min(\underline{x}, \underline{y}), \min(\overline{x},
\overline{y})]$ and `maximum` is the analogue with `max`: $\min$ is
increasing in each argument. An Empty operand gives Empty.

## Elementary functions

Each function $f$ returns an interval containing
$f(\boldsymbol{x} \cap D_f)$, where $D_f$ is the domain of $f$; points of
$\boldsymbol{x}$ outside $D_f$ are ignored and the result is Empty when
$\boldsymbol{x} \cap D_f$ is empty. The result precision is the argument's
precision.

Functions come in two forms. The total form (`exp_interval`, `sin_interval`,
…) always returns a valid enclosure; when the certified evaluation exhausts
its refinement budget it returns a wider, still valid, interval. The `try_`
form (`try_exp_interval`, …) returns `Err(ArithmeticError)` in that case, with
a certification-failure detail naming the operation, stage and reason.
Except where noted, the `try_` forms evaluate each endpoint with the
corresponding `bin_float` `try_*_ctx` function rounded toward $-\infty$ or
$+\infty$; the total forms either call them or use the certified series of
this package. Both forms return the same set on ordinary inputs; their bounds
may differ by an ulp.

### `BallFloat::sqrt_interval`

`sqrt_interval` returns $\sqrt{\boldsymbol{x} \cap [0, +\infty)}$.

```mbti
pub fn BallFloat::sqrt_interval(Self) -> Self
```

The endpoints are the downward and upward square roots at the interval's
precision. Empty when $\overline{x} < 0$. There is no `try_` form: square
root never fails.

### `BallFloat::exp_interval`, `BallFloat::exp2_interval`, `BallFloat::exp10_interval`, `BallFloat::expm1_interval`, `BallFloat::try_exp_interval`, `BallFloat::try_exp2_interval`, `BallFloat::try_exp10_interval`, `BallFloat::try_expm1_interval`

These return enclosures of $e^{\xi}$, $2^{\xi}$, $10^{\xi}$ and
$e^{\xi} - 1$.

```mbti
pub fn BallFloat::exp_interval(Self) -> Self
pub fn BallFloat::exp2_interval(Self) -> Self
pub fn BallFloat::exp10_interval(Self) -> Self
pub fn BallFloat::expm1_interval(Self) -> Self
pub fn BallFloat::try_exp_interval(Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::try_exp2_interval(Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::try_exp10_interval(Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::try_expm1_interval(Self) -> Result[Self, @arithmetic.ArithmeticError]
```

All four are increasing, so the result is
$[\operatorname{RD} f(\underline{x}), \operatorname{RU} f(\overline{x})]$.
`exp_interval` uses a certified Taylor series with argument halving and never
needs a fallback; for $|\xi| \ge 2^{30}$ it returns
$[\text{largest finite}, +\infty)$ or $[0, \text{smallest positive}]$, which
is valid because $e^{2^{30}}$ exceeds $2^{e_{\max}+1}$ and $e^{-2^{30}}$ is
below the smallest positive `BinFloat` at every precision.
`exp2_interval` and `exp10_interval` evaluate $e^{\xi \ln b}$ at 96 extra bits
and return exact powers for integer endpoints (for `exp10_interval`,
exponents $0 \le n \le 100000$). The total `expm1_interval` falls back to
$[-1, +\infty)$.

> [!WARNING]
> The exact-power shortcut of `exp2_interval` does not respect the exponent
> range. An integer lower endpoint $n \ge 2^{30}$ makes $2^n$ overflow to
> $+\infty$ and the call aborts ("ball lower bound must not be positive
> infinity"). An integer upper endpoint $n < -2^{30} - p - 94$ (with $p$ the
> interval precision) makes $2^n$ underflow to 0, so the result misses the
> positive value $2^n$: at 53 bits, `exp2_interval` of
> $\{-1073742000\}$ is $\{0\}$. `try_exp2_interval` does not use the
> shortcut.

### `BallFloat::ln_interval`, `BallFloat::log2_interval`, `BallFloat::log10_interval`, `BallFloat::log1p_interval`, `BallFloat::try_ln_interval`, `BallFloat::try_log2_interval`, `BallFloat::try_log10_interval`, `BallFloat::try_log1p_interval`

These return enclosures of $\ln \xi$, $\log_2 \xi$, $\log_{10} \xi$ and
$\ln(1 + \xi)$ over their domains $(0, \infty)$ and $(-1, \infty)$.

```mbti
pub fn BallFloat::ln_interval(Self) -> Self
pub fn BallFloat::log2_interval(Self) -> Self
pub fn BallFloat::log10_interval(Self) -> Self
pub fn BallFloat::log1p_interval(Self) -> Self
pub fn BallFloat::try_ln_interval(Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::try_log2_interval(Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::try_log10_interval(Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::try_log1p_interval(Self) -> Result[Self, @arithmetic.ArithmeticError]
```

When the interval reaches the domain boundary ($\underline{x} \le 0$, or
$\underline{x} \le -1$ for `log1p`) the lower endpoint is $-\infty$; when it
lies entirely outside the domain ($\overline{x} \le 0$, or
$\overline{x} < -1$ for `log1p`) the result is Empty. `log10_interval`
returns exact integers at endpoints $10^k$, $0 \le k \le 9$. The total
`log1p_interval` falls back to Entire.

```moonbit
///|
test "exponentials and logarithms" {
  inspect(fmt(iv(0, 1).exp_interval()), content="[1.00000e+0, 2.71829e+0]")
  inspect(fmt(iv(-1, 10).exp2_interval()), content="[5.00000e-1, 1.02400e+3]")
  inspect(fmt(iv(0, 4).ln_interval()), content="[-inf, 1.38630e+0]")
  inspect(fmt(iv(1, 1000).log10_interval()), content="[0.00000e+0, 3.00000e+0]")
  inspect(iv(-2, -1).ln_interval().is_empty(), content="true")
}
```

### `BallFloat::pow_interval` and `BallFloat::try_pow_interval`

`pow_interval(x, y)` returns an enclosure of
$\{\xi^{\eta} : \xi \in \boldsymbol{x}, \eta \in \boldsymbol{y}\}$ over the
IEEE 1788 domain of `pow`: $\xi > 0$, or $\xi = 0$ and $\eta > 0$.

```mbti
pub fn BallFloat::pow_interval(Self, Self) -> Self
pub fn BallFloat::try_pow_interval(Self, Self) -> Result[Self, @arithmetic.ArithmeticError]
```

Negative parts of the base are ignored (use `pown` or `rootn` for negative
bases). Since $\xi^\eta = e^{\eta \ln \xi}$ and $\eta \ln \xi$ is bilinear in
$(\ln \xi, \eta)$, the extrema over a box with $\underline{x} > 0$ are at the
four corners. When the base reaches 0, $\xi^\eta \to 0$ for $\eta > 0$ and
$\to +\infty$ for $\eta < 0$, so the result is extended by 0 or $+\infty$
accordingly. The code also adds the value 1 when the base interval contains
1 or the exponent interval contains 0; it already lies between the corner
values, so this changes nothing but is harmless. $0^{\eta}$ for $\eta \le 0$
is excluded, so `pow_interval([0, 0], y)` is Empty when $\overline{y} \le 0$.
The result precision is the larger operand precision. The total form falls
back to an evaluation of $e^{\eta \ln \xi}$ at 192 extra bits.

### `BallFloat::rootn` and `BallFloat::try_rootn`

`rootn(x, n)` returns an enclosure of the real $n$-th roots
$\{\xi^{1/n}\}$: for even $n$ over $\xi \ge 0$, for odd $n$ over all reals,
and for negative $n$ the reciprocal of the root.

```mbti
pub fn BallFloat::rootn(Self, Int) -> Self
pub fn BallFloat::try_rootn(Self, Int) -> Result[Self, @arithmetic.ArithmeticError]
```

`rootn(x, 0)` and `rootn(x, Int min)` are Empty; `try_rootn(x, 0)` is a domain
error. `rootn(x, 1)` is `x` and `rootn(x, 2)` is `sqrt_interval`. The total
form evaluates other degrees through `pow_interval` with an enclosure of
$1/n$, so it may be slightly wider than `try_rootn`; negative degrees are
`rootn(x, -n).reciprocal()`. For negative $n$, `try_rootn` returns Entire
when an odd root's argument contains 0 (wider than the total form when 0 is an
endpoint).

### `BallFloat::hypot` and `BallFloat::try_hypot`

`hypot` returns an enclosure of $\{\sqrt{\xi^2 + \eta^2}\}$.

```mbti
pub fn BallFloat::hypot(Self, Self) -> Self
pub fn BallFloat::try_hypot(Self, Self) -> Result[Self, @arithmetic.ArithmeticError]
```

The function is increasing in $|\xi|$ and $|\eta|$, so the result is
$[\operatorname{RD}\operatorname{hypot}(\operatorname{mig}\boldsymbol{x}, \operatorname{mig}\boldsymbol{y}),
\operatorname{RU}\operatorname{hypot}(\operatorname{mag}\boldsymbol{x}, \operatorname{mag}\boldsymbol{y})]$,
evaluated on the endpoints of `abs(x)` and `abs(y)`. The total form falls back
to `sqrt_interval(square(x) + square(y))`.

### `BallFloat::sin_interval`, `BallFloat::cos_interval`, `BallFloat::tan_interval`, `BallFloat::try_sin_interval`, `BallFloat::try_cos_interval`, `BallFloat::try_tan_interval`

These return enclosures of $\sin$, $\cos$ and $\tan$ over the interval (in
radians).

```mbti
pub fn BallFloat::sin_interval(Self) -> Self
pub fn BallFloat::cos_interval(Self) -> Self
pub fn BallFloat::tan_interval(Self) -> Self
pub fn BallFloat::try_sin_interval(Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::try_cos_interval(Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::try_tan_interval(Self) -> Result[Self, @arithmetic.ArithmeticError]
```

Both forms reduce each endpoint by a certified enclosure of $\pi/2$ and
evaluate certified Taylor series. A critical point $k\pi/2$ inside the
interval contributes the extremum $\pm 1$ of `sin`/`cos` (`sin` reaches $+1$
at $k \equiv 1$ and $-1$ at $k \equiv 3 \pmod 4$, `cos` reaches $+1$ at
$k \equiv 0$ and $-1$ at $k \equiv 2$); for `tan` an odd multiple of $\pi/2$
inside the interval (a pole) makes the result Entire. The set of candidate
indices $k$ is computed from the enclosure of $\pi$ and can only be too large,
which widens but never invalidates the result. Unbounded arguments give
$[-1, 1]$ (Entire for `tan`). When the larger endpoint magnitude is at least
$2^{\max(65536,\, 4p) + 1}$, the total forms return $[-1, 1]$ (Entire)
without evaluating and the `try_` forms return a resource-limit error; the
total forms use the same fallback when the certification budget (12 work
precisions) is exhausted.

### `BallFloat::sinpi_interval`, `BallFloat::cospi_interval`, `BallFloat::tanpi_interval`, `BallFloat::try_sinpi_interval`, `BallFloat::try_cospi_interval`, `BallFloat::try_tanpi_interval`

These return enclosures of $\sin \pi\xi$, $\cos \pi\xi$ and $\tan \pi\xi$.

```mbti
pub fn BallFloat::sinpi_interval(Self) -> Self
pub fn BallFloat::cospi_interval(Self) -> Self
pub fn BallFloat::tanpi_interval(Self) -> Self
pub fn BallFloat::try_sinpi_interval(Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::try_cospi_interval(Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::try_tanpi_interval(Self) -> Result[Self, @arithmetic.ArithmeticError]
```

Here the critical points are the exact half-integers $k/2$, located from the
dyadic endpoints without approximating $\pi$. `tanpi_interval` returns a
half-unbounded interval when a pole is exactly an endpoint and no other pole
lies in the interval (for example $[1/2, 1]$ gives $(-\infty, 0]$), Empty for
the singleton of a pole, and Entire when a pole lies inside. Unbounded
arguments and fallbacks give $[-1, 1]$ (Entire for `tanpi`).

```moonbit
///|
test "trigonometric functions" {
  inspect(fmt(iv(0, 4).sin_interval()), content="[-7.56803e-1, 1.00000e+0]")
  inspect(fmt(iv(0, 4).cos_interval()), content="[-1.00000e+0, 1.00000e+0]")
  inspect(iv(1, 2).tan_interval().is_entire(), content="true")
  let half = @bin_float.BinFloat::make(@bin_float.BinCoeff::one(), -1, 53)
  let x = @ball_float.BallFloat::from_bounds(half, @bin_float.BinFloat::one(precision=53))
  inspect(fmt(x.sinpi_interval()), content="[0.00000e+0, 1.00000e+0]")
  inspect(fmt(x.tanpi_interval()), content="[-inf, -0.00000e+0]")
}
```

### `BallFloat::asin_interval`, `BallFloat::acos_interval`, `BallFloat::atan_interval`, `BallFloat::try_asin_interval`, `BallFloat::try_acos_interval`, `BallFloat::try_atan_interval`

These return enclosures of $\arcsin$, $\arccos$ (over $[-1, 1]$) and
$\arctan$.

```mbti
pub fn BallFloat::asin_interval(Self) -> Self
pub fn BallFloat::acos_interval(Self) -> Self
pub fn BallFloat::atan_interval(Self) -> Self
pub fn BallFloat::try_asin_interval(Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::try_acos_interval(Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::try_atan_interval(Self) -> Result[Self, @arithmetic.ArithmeticError]
```

`asin` and `atan` are increasing and `acos` is decreasing, so only endpoints
are evaluated. The total `atan_interval` uses a certified series with a
Machin-formula enclosure of $\pi$ and falls back to $[0, \pi/2]$ or
$[-\pi/2, 0]$ for an endpoint whose budget runs out; `asin` is computed as
$\arctan(\xi/\sqrt{1 - \xi^2})$ and `acos` as $\pi/2 - \arcsin \xi$, at 64
extra bits. `atan` of an infinite endpoint is $\pm\pi/2$.

### `BallFloat::atan2_interval` and `BallFloat::try_atan2_interval`

`y.atan2_interval(x)` returns an enclosure of the angles
$\operatorname{atan2}(\eta, \xi) \in (-\pi, \pi]$ of the points
$(\xi, \eta) \ne (0, 0)$ of the box $\boldsymbol{x} \times \boldsymbol{y}$.

```mbti
pub fn BallFloat::atan2_interval(Self, Self) -> Self
pub fn BallFloat::try_atan2_interval(Self, Self) -> Result[Self, @arithmetic.ArithmeticError]
```

The receiver is the ordinate. The result is the hull of the angles at the
four corners and at the points where the box meets the axes. When the box
crosses the branch cut ($\underline{x} < 0$ and
$\underline{y} < 0 \le \overline{y}$) the result is $[-\pi, \pi]$. The box
$\{(0, 0)\}$ gives Empty. The total form falls back to $[-\pi, \pi]$.

### `BallFloat::sinh_interval`, `BallFloat::cosh_interval`, `BallFloat::tanh_interval`, `BallFloat::asinh_interval`, `BallFloat::acosh_interval`, `BallFloat::atanh_interval`, `BallFloat::try_sinh_interval`, `BallFloat::try_cosh_interval`, `BallFloat::try_tanh_interval`, `BallFloat::try_asinh_interval`, `BallFloat::try_acosh_interval`, `BallFloat::try_atanh_interval`

These return enclosures of the hyperbolic functions and their inverses over
their domains ($[1, \infty)$ for `acosh`, $(-1, 1)$ for `atanh`).

```mbti
pub fn BallFloat::sinh_interval(Self) -> Self
pub fn BallFloat::cosh_interval(Self) -> Self
pub fn BallFloat::tanh_interval(Self) -> Self
pub fn BallFloat::asinh_interval(Self) -> Self
pub fn BallFloat::acosh_interval(Self) -> Self
pub fn BallFloat::atanh_interval(Self) -> Self
pub fn BallFloat::try_sinh_interval(Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::try_cosh_interval(Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::try_tanh_interval(Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::try_asinh_interval(Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::try_acosh_interval(Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::try_atanh_interval(Self) -> Result[Self, @arithmetic.ArithmeticError]
```

`cosh` has its minimum 1 at 0; the others are monotone. The total forms
evaluate the defining formulas ($(e^\xi - e^{-\xi})/2$,
$\ln(\xi + \sqrt{\xi^2 + 1})$, $\tfrac12 \ln\frac{1+\xi}{1-\xi}$, …) in
interval arithmetic at $w = p + 192$ bits at each endpoint, so they never
fail; `tanh_interval` is clipped to $[-1, 1]$. `atanh` of an interval reaching
$\pm 1$ is unbounded on that side. The `try_` forms use the certified
`bin_float` kernels instead.

The defining formulas of `sinh`, `tanh`, `asinh` and `atanh` cancel near 0:
their absolute error is about $2^{-w}$, so for $|\xi|$ below roughly
$2^{-190}$ the total forms are valid but far from tight. At 53 bits,
`sinh_interval` of $\{2^{-300}\}$ is $[0, 3 \cdot 2^{-246}]$ while
`try_sinh_interval` returns the two-ulp interval
$[2^{-300}, (1 + 2^{-52})\,2^{-300}]$. Use the `try_` forms for tiny
arguments.

```moonbit
///|
test "inverse and hyperbolic functions" {
  let unit = iv(-1, 1)
  inspect(fmt(unit.asin_interval()), content="[-1.57080e+0, 1.57080e+0]")
  inspect(fmt(iv(-2, 2).acos_interval()), content="[0.00000e+0, 3.14160e+0]")
  inspect(fmt(iv(1, 1).atan2_interval(iv(1, 1))), content="[7.85398e-1, 7.85399e-1]")
  inspect(fmt(unit.cosh_interval()), content="[1.00000e+0, 1.54309e+0]")
  inspect(fmt(unit.atanh_interval()), content="[-inf, inf]")
}
```

## Contexts and flags

### `BallContext::new` and `BallContext::try_new`

`BallContext::new` builds a context from a precision and an exponent range.

```mbti
pub fn BallContext::new(precision? : Int, e_min? : Int, e_max? : Int) -> Self
pub fn BallContext::try_new(precision? : Int, e_min? : Int, e_max? : Int) -> Result[Self, @arithmetic.ArithmeticError]
```

The defaults are those of binary64: precision 53, $e_{\min} = -1022$,
$e_{\max} = 1023$. A precision below 1 or $e_{\min} > e_{\max}$ aborts `new`
and is a domain error for `try_new`.

### `BallContext::binary32` and `BallContext::binary64`

These return the contexts of the IEEE 754 binary32 ($p = 24$,
$[-126, 127]$) and binary64 ($p = 53$, $[-1022, 1023]$) formats.

```mbti
pub fn BallContext::binary32() -> Self
pub fn BallContext::binary64() -> Self
```

### `BallContext::precision`, `BallContext::e_min`, `BallContext::e_max`

These return the parameters of a context.

```mbti
pub fn BallContext::precision(Self) -> Int
pub fn BallContext::e_min(Self) -> Int
pub fn BallContext::e_max(Self) -> Int
```

### `BallFlags::new`, `BallFlags::combine`, `BallFlags::inexact`, `BallFlags::overflow`, `BallFlags::underflow`

`BallFlags::new` returns the flags with nothing raised; `combine` is their
union; the accessors read the fields.

```mbti
pub fn BallFlags::new() -> Self
pub fn BallFlags::combine(Self, Self) -> Self
pub fn BallFlags::inexact(Self) -> Bool
pub fn BallFlags::overflow(Self) -> Bool
pub fn BallFlags::underflow(Self) -> Bool
```

### `BallFloat::apply_ctx`

`apply_ctx` rounds an interval outward into a context and reports the flags.

```mbti
pub fn BallFloat::apply_ctx(Self, BallContext) -> (Self, BallFlags)
```

Each finite nonzero endpoint is rounded outward to the context precision.
An endpoint whose rounded exponent exceeds $e_{\max}$ overflows: it becomes
$\mp\infty$ if it is a negative lower or a positive upper endpoint, and the
largest finite value of the right sign otherwise (a positive lower endpoint
becomes the largest finite value, which is still below it). An endpoint below
the normal range is then rounded outward on the subnormal grid
$2^{e_{\min} - p + 1}\mathbb{Z}$, so a tiny positive upper endpoint becomes the
smallest subnormal rather than 0. Rounding twice in the same direction equals
rounding once onto the coarser grid, so the endpoints are the directed
roundings of the stored ones. Zeros and infinities are kept. Empty gives
Empty with no flags. The result has the context precision.

`underflow` is raised only when the second, subnormal-grid step is inexact.
IEEE 754 raises it for every tiny inexact result, so a tiny endpoint whose
precision rounding is inexact but lands on the subnormal grid raises
`inexact` without `underflow`: with $p = 4$ and $e_{\min} = -2$, the lower
endpoint $2^{-3}(1 + 2^{-10})$ becomes $2^{-3}$ and only `inexact` is set.

### `BallFloat::add_ctx`, `BallFloat::sub_ctx`, `BallFloat::mul_ctx`, `BallFloat::div_ctx`

These compute the operation and then apply the context.

```mbti
pub fn BallFloat::add_ctx(Self, Self, BallContext) -> (Self, BallFlags)
pub fn BallFloat::sub_ctx(Self, Self, BallContext) -> (Self, BallFlags)
pub fn BallFloat::mul_ctx(Self, Self, BallContext) -> (Self, BallFlags)
pub fn BallFloat::div_ctx(Self, Self, BallContext) -> (Self, BallFlags)
```

`x.add_ctx(y, ctx)` is `(x + y).apply_ctx(ctx)`. When the operands' precision
is at least the context precision, the double rounding gives the same
endpoints as a single outward rounding into the context (see the
[design page](../design/ball_float.md#contexts-and-double-rounding)).

### `BallFloat::exp_ctx` and `BallFloat::ln_ctx`

`exp_ctx` and `ln_ctx` evaluate `exp_interval` and `ln_interval` at 32 bits
more than the context precision and then apply the context.

```mbti
pub fn BallFloat::exp_ctx(Self, BallContext) -> (Self, BallFlags)
pub fn BallFloat::ln_ctx(Self, BallContext) -> (Self, BallFlags)
```

### `BallFloat::midpoint_ctx`

`midpoint_ctx` returns the center rounded to nearest at the context precision.

```mbti
pub fn BallFloat::midpoint_ctx(Self, BallContext) -> (@bin_float.BinFloat, BallFlags)
```

Subnormal results are rounded on the subnormal grid and raise `underflow`
when inexact; `inexact` is set when the center changed. The exponent upper
limit is not applied, so `overflow` is never raised. Entire gives 0; Empty and
half-bounded intervals abort.

The center is rounded to nearest twice, first to $p$ bits and then onto the
subnormal grid, and double rounding to nearest is not single rounding: with
$p = 4$, $e_{\min} = -2$ (grid $2^{-5}$) the center $2^{-6} + 2^{-20}$ is
first rounded to the tie $2^{-6}$ and then to the even neighbour 0, whereas
the nearest grid point is $2^{-5}$. Normal results are correctly rounded.

```moonbit
///|
test "contexts" {
  let ctx = @ball_float.BallContext::new(precision=8, e_min=-10, e_max=10)
  let (third, flags) = iv(1, 1).div_ctx(iv(3, 3), ctx)
  inspect(third.lower_bound().to_string(), content="85p-8")
  inspect(third.upper_bound().to_string(), content="171p-9")
  inspect(flags.inexact(), content="true")
  let (big, big_flags) = iv(5000, 5000).apply_ctx(ctx)
  inspect(fmt(big), content="[2.04000e+3, inf]")
  inspect(big_flags.overflow(), content="true")
  let merged = flags.combine(big_flags)
  inspect(merged.overflow() && merged.inexact(), content="true")
}
```

## Decorated intervals

A decorated operation computes the bare result and the decoration
$d = \min(d_1, \dots, d_k, d_f)$, where $d_i$ are the operand decorations and
$d_f$ is the decoration of the operation on these operands (`Com` when the
function is defined and continuous on the whole input box, `Trv` when the
input leaves the domain, as listed below). The minimum is then made canonical
(Empty → `Trv`, unbounded with `Com` → `Dac`). Any NaI operand gives NaI.

### `BallFloatDecorated::new`

`BallFloatDecorated::new` decorates a bare interval.

```mbti
pub fn BallFloatDecorated::new(BallFloat, decoration? : Decoration) -> Self
```

The default decoration is `Com`. The decoration is made canonical, and `Ill`
is replaced by `Trv`: `new` never builds NaI. `new(whole())` is therefore
decorated `Dac` and `new(empty())` is decorated `Trv`, as in IEEE 1788
`newDec`.

### `BallFloatDecorated::nai` and `BallFloatDecorated::is_nai`

`nai` returns NaI, the result of an invalid decorated construction; `is_nai`
tests for it.

```mbti
pub fn BallFloatDecorated::nai(precision? : Int) -> Self
pub fn BallFloatDecorated::is_nai(Self) -> Bool
```

NaI has decoration `Ill` and an Empty interval (default precision 53), but it
is not Empty: `is_empty` is false for NaI.

### `BallFloatDecorated::interval` and `BallFloatDecorated::decoration`

These return the bare interval and the decoration.

```mbti
pub fn BallFloatDecorated::interval(Self) -> BallFloat
pub fn BallFloatDecorated::decoration(Self) -> Decoration
```

### `BallFloatDecorated::is_empty`, `BallFloatDecorated::is_entire`, `BallFloatDecorated::is_common_interval`, `BallFloatDecorated::is_singleton`, `BallFloatDecorated::contains`

These predicates apply the bare predicate to the interval and return false for
NaI.

```mbti
pub fn BallFloatDecorated::is_empty(Self) -> Bool
pub fn BallFloatDecorated::is_entire(Self) -> Bool
pub fn BallFloatDecorated::is_common_interval(Self) -> Bool
pub fn BallFloatDecorated::is_singleton(Self) -> Bool
pub fn BallFloatDecorated::contains(Self, @bin_float.BinFloat) -> Bool
```

### `BallFloatDecorated::set_equal`, `BallFloatDecorated::subset`, `BallFloatDecorated::interior`, `BallFloatDecorated::disjoint`, `BallFloatDecorated::less`, `BallFloatDecorated::strictly_less`, `BallFloatDecorated::precedes`, `BallFloatDecorated::strictly_precedes`, `BallFloatDecorated::overlap_state`

These relations apply the bare relation to the intervals and return false
when an operand is NaI.

```mbti
pub fn BallFloatDecorated::set_equal(Self, Self) -> Bool
pub fn BallFloatDecorated::subset(Self, Self) -> Bool
pub fn BallFloatDecorated::interior(Self, Self) -> Bool
pub fn BallFloatDecorated::disjoint(Self, Self) -> Bool
pub fn BallFloatDecorated::less(Self, Self) -> Bool
pub fn BallFloatDecorated::strictly_less(Self, Self) -> Bool
pub fn BallFloatDecorated::precedes(Self, Self) -> Bool
pub fn BallFloatDecorated::strictly_precedes(Self, Self) -> Bool
pub fn BallFloatDecorated::overlap_state(Self, Self) -> OverlapState
```

`overlap_state` returns `Undefined` when an operand is NaI.

### `BallFloatDecorated::intersection`, `BallFloatDecorated::convex_hull`, `BallFloatDecorated::cancel_plus`, `BallFloatDecorated::cancel_minus`

These apply the bare operation and always lower the decoration to `Trv`
(set operations are not point functions, so no property of a function can be
claimed for their results).

```mbti
pub fn BallFloatDecorated::intersection(Self, Self) -> Self
pub fn BallFloatDecorated::convex_hull(Self, Self) -> Self
pub fn BallFloatDecorated::cancel_plus(Self, Self) -> Self
pub fn BallFloatDecorated::cancel_minus(Self, Self) -> Self
```

### `BallFloatDecorated::add`, `BallFloatDecorated::sub`, `BallFloatDecorated::mul`, `BallFloatDecorated::div`, `BallFloatDecorated::pos`, `BallFloatDecorated::neg`, `BallFloatDecorated::abs`, `BallFloatDecorated::reciprocal`, `BallFloatDecorated::square`, `BallFloatDecorated::pown`, `BallFloatDecorated::fma`, `BallFloatDecorated::minimum`, `BallFloatDecorated::maximum`

The arithmetic operations apply the bare operation; their operation
decoration is `Com` except where the table says otherwise.

```mbti
pub fn BallFloatDecorated::add(Self, Self) -> Self
pub fn BallFloatDecorated::sub(Self, Self) -> Self
pub fn BallFloatDecorated::mul(Self, Self) -> Self
pub fn BallFloatDecorated::div(Self, Self) -> Self
pub fn BallFloatDecorated::pos(Self) -> Self
pub fn BallFloatDecorated::neg(Self) -> Self
pub fn BallFloatDecorated::abs(Self) -> Self
pub fn BallFloatDecorated::reciprocal(Self) -> Self
pub fn BallFloatDecorated::square(Self) -> Self
pub fn BallFloatDecorated::pown(Self, Int) -> Self
pub fn BallFloatDecorated::fma(Self, Self, Self) -> Self
pub fn BallFloatDecorated::minimum(Self, Self) -> Self
pub fn BallFloatDecorated::maximum(Self, Self) -> Self
```

| Operation | Operation decoration |
| --- | --- |
| `div`, `reciprocal` | `Trv` when the divisor contains 0 |
| `pown(x, n)` | `Trv` when $n < 0$ and $0 \in \boldsymbol{x}$ |
| `pos` | identity (IEEE 1788 `pos`) |
| others | `Com` |

### `BallFloatDecorated::sqrt_interval`, `BallFloatDecorated::exp_interval`, `BallFloatDecorated::exp2_interval`, `BallFloatDecorated::exp10_interval`, `BallFloatDecorated::expm1_interval`, `BallFloatDecorated::ln_interval`, `BallFloatDecorated::log2_interval`, `BallFloatDecorated::log10_interval`, `BallFloatDecorated::log1p_interval`, `BallFloatDecorated::pow_interval`, `BallFloatDecorated::rootn`, `BallFloatDecorated::hypot`

The decorated elementary functions apply the bare total form (there are no
decorated `try_` forms) and lower the decoration when the input leaves the
domain of the function, as listed in the table at the end of this group.

These are the decorated square root, exponentials, logarithms, powers and
`hypot`.

```mbti
pub fn BallFloatDecorated::sqrt_interval(Self) -> Self
pub fn BallFloatDecorated::exp_interval(Self) -> Self
pub fn BallFloatDecorated::exp2_interval(Self) -> Self
pub fn BallFloatDecorated::exp10_interval(Self) -> Self
pub fn BallFloatDecorated::expm1_interval(Self) -> Self
pub fn BallFloatDecorated::ln_interval(Self) -> Self
pub fn BallFloatDecorated::log2_interval(Self) -> Self
pub fn BallFloatDecorated::log10_interval(Self) -> Self
pub fn BallFloatDecorated::log1p_interval(Self) -> Self
pub fn BallFloatDecorated::pow_interval(Self, Self) -> Self
pub fn BallFloatDecorated::rootn(Self, Int) -> Self
pub fn BallFloatDecorated::hypot(Self, Self) -> Self
```

### `BallFloatDecorated::sin_interval`, `BallFloatDecorated::cos_interval`, `BallFloatDecorated::tan_interval`, `BallFloatDecorated::sinpi_interval`, `BallFloatDecorated::cospi_interval`, `BallFloatDecorated::tanpi_interval`, `BallFloatDecorated::asin_interval`, `BallFloatDecorated::acos_interval`, `BallFloatDecorated::atan_interval`, `BallFloatDecorated::atan2_interval`

These are the decorated trigonometric functions and their inverses.

```mbti
pub fn BallFloatDecorated::sin_interval(Self) -> Self
pub fn BallFloatDecorated::cos_interval(Self) -> Self
pub fn BallFloatDecorated::tan_interval(Self) -> Self
pub fn BallFloatDecorated::sinpi_interval(Self) -> Self
pub fn BallFloatDecorated::cospi_interval(Self) -> Self
pub fn BallFloatDecorated::tanpi_interval(Self) -> Self
pub fn BallFloatDecorated::asin_interval(Self) -> Self
pub fn BallFloatDecorated::acos_interval(Self) -> Self
pub fn BallFloatDecorated::atan_interval(Self) -> Self
pub fn BallFloatDecorated::atan2_interval(Self, Self) -> Self
```

### `BallFloatDecorated::sinh_interval`, `BallFloatDecorated::cosh_interval`, `BallFloatDecorated::tanh_interval`, `BallFloatDecorated::asinh_interval`, `BallFloatDecorated::acosh_interval`, `BallFloatDecorated::atanh_interval`

These are the decorated hyperbolic functions and their inverses.

```mbti
pub fn BallFloatDecorated::sinh_interval(Self) -> Self
pub fn BallFloatDecorated::cosh_interval(Self) -> Self
pub fn BallFloatDecorated::tanh_interval(Self) -> Self
pub fn BallFloatDecorated::asinh_interval(Self) -> Self
pub fn BallFloatDecorated::acosh_interval(Self) -> Self
pub fn BallFloatDecorated::atanh_interval(Self) -> Self
```

| Function | Operation decoration `Trv` when |
| --- | --- |
| `sqrt_interval` | $\underline{x} < 0$ (or the input is Empty) |
| `ln_interval`, `log2_interval`, `log10_interval` | $\underline{x} \le 0$ |
| `log1p_interval` | $\underline{x} \le -1$ |
| `asin_interval`, `acos_interval` | $\boldsymbol{x} \not\subseteq [-1, 1]$ |
| `acosh_interval` | $\underline{x} < 1$ |
| `atanh_interval` | $\underline{x} \le -1$ or $\overline{x} \ge 1$ |
| `rootn(x, n)` | $n = 0$, or $n$ even and $\underline{x} < 0$ |
| `pow_interval(x, y)` | $\underline{x} < 0$, or $0 \in \boldsymbol{x}$ and $\underline{y} \le 0$, or the result is Empty |
| `tan_interval`, `tanpi_interval` | the result is Entire (a pole may lie inside) |
| `atan2_interval` | both operands contain 0 |

All other functions have operation decoration `Com`. For `y.atan2_interval(x)`
the decoration is `Def` when the box crosses the branch cut
($\underline{x} < 0$, $\underline{y} < 0 \le \overline{y}$: the restriction
jumps from $-\pi$ to $\pi$) and `Dac` when it touches the cut from above
($\overline{x} < 0$, $\underline{y} = 0$: the restriction is continuous, but
`atan2` itself is not continuous at those points).

> [!WARNING]
> Two domain tests are incomplete, so the decoration can claim more than is
> true:
>
> - `rootn` with a negative degree does not lower the decoration when 0 is in
>   the argument, although $\xi^{1/n}$ is undefined at 0 for $n < 0$:
>   `rootn([0, 4], -2)` is decorated `dac` instead of `trv`.
> - `tanpi_interval` tests only for an Entire result. When a pole is an
>   endpoint, the bare result is half-unbounded and the decoration becomes
>   `dac`, although $\tan \pi\xi$ is undefined at the pole: `tanpi([1/2, 1])`
>   is `[-inf, 0]_dac` instead of `trv`.

### `BallFloatDecorated::apply_ctx`

`apply_ctx` applies `BallFloat::apply_ctx` to the interval and keeps the
decoration (made canonical again, so an overflowed `Com` becomes `Dac`).

```mbti
pub fn BallFloatDecorated::apply_ctx(Self, BallContext) -> (Self, BallFlags)
```

NaI stays NaI, with the context precision.

```moonbit
///|
test "decorated intervals" {
  let x = @ball_float.BallFloatDecorated::new(iv(-1, 4))
  inspect(x.sqrt_interval().decoration(), content="trv")
  inspect(x.exp_interval().decoration(), content="com")
  inspect((x / x).decoration(), content="trv")
  let unbounded = @ball_float.BallFloatDecorated::new(@ball_float.BallFloat::whole())
  inspect(unbounded.decoration(), content="dac")
  let nai = @ball_float.BallFloatDecorated::nai()
  inspect((x + nai).to_string(), content="[nai]")
  debug_inspect(nai.overlap_state(x), content="Undefined")
}
```

## Trait implementations

### `Add`, `Sub`, `Mul`, `Div` and `Neg` for `BallFloat` and `BallFloatDecorated`

`BallFloat` implements `Add`, `Sub`, `Mul`, `Div` and `Neg`;
`BallFloatDecorated` implements `Add`, `Sub`, `Mul` and `Div`. The operators
call the methods of the same name.

```mbti
pub impl Add for BallFloat
pub impl Sub for BallFloat
pub impl Mul for BallFloat
pub impl Div for BallFloat
pub impl Neg for BallFloat
pub impl Add for BallFloatDecorated
pub impl Sub for BallFloatDecorated
pub impl Mul for BallFloatDecorated
pub impl Div for BallFloatDecorated
```

### `BallFloat::to_string`, `BallFloat::output`, `BallFloatDecorated::to_string`, `BallFloatDecorated::output`, `Decoration::to_string`, `Decoration::output`

`Show` writes an interval in an exact text form.

```mbti
pub impl Show for BallFloat
pub fn BallFloat::to_string(Self) -> String
pub fn BallFloat::output(Self, &Logger) -> Unit
pub impl Show for BallFloatDecorated
pub fn BallFloatDecorated::to_string(Self) -> String
pub fn BallFloatDecorated::output(Self, &Logger) -> Unit
pub impl Show for Decoration
pub fn Decoration::to_string(Self) -> String
pub fn Decoration::output(Self, &Logger) -> Unit
```

A bounded `BallFloat` prints as `center +/- radius` with both numbers in the
exact `BinFloat` notation (`3p-1` is $3 \cdot 2^{-1}$), so the text denotes
exactly the stored set (up to the far-endpoint case noted under
[`BallFloat::center`](#ballfloatcenter-and-ballfloatradius)); an unbounded one
prints as `[lo, hi]`, Empty as `[empty]`. A decorated interval appends `_` and
the decoration; NaI prints as `[nai]`.

```moonbit
///|
test "show" {
  inspect(iv(1, 2).to_string(), content="3p-1 +/- 1p-1")
  inspect(@ball_float.BallFloat::whole().to_string(), content="[-inf, inf]")
  inspect(@ball_float.BallFloatDecorated::new(iv(1, 2)).to_string(), content="3p-1 +/- 1p-1_com")
}
```

### `BallFloat::equal`, `BallFloat::not_equal`, `BallFloat::to_repr`, `BallFloatDecorated::equal`, `BallFloatDecorated::not_equal`, `BallFlags::equal`, `BallFlags::not_equal`

These are the derived `Eq` and `Debug` methods of the structures.

```mbti
pub fn BallFloat::equal(Self, Self) -> Bool
pub fn BallFloat::not_equal(Self, Self) -> Bool
pub fn BallFloat::to_repr(Self) -> @debug.Repr
pub fn BallFloatDecorated::equal(Self, Self) -> Bool
pub fn BallFloatDecorated::not_equal(Self, Self) -> Bool
pub fn BallFlags::equal(Self, Self) -> Bool
pub fn BallFlags::not_equal(Self, Self) -> Bool
```

### `Decoration::equal`, `Decoration::not_equal`, `Decoration::to_repr`, `OverlapState::equal`, `OverlapState::not_equal`, `OverlapState::to_repr`

These are the derived `Eq` and `Debug` methods of the enums.

```mbti
pub fn Decoration::equal(Self, Self) -> Bool
pub fn Decoration::not_equal(Self, Self) -> Bool
pub fn Decoration::to_repr(Self) -> @debug.Repr
pub fn OverlapState::equal(Self, Self) -> Bool
pub fn OverlapState::not_equal(Self, Self) -> Bool
pub fn OverlapState::to_repr(Self) -> @debug.Repr
```

The `Eq` implementations compare representations. For `BallFloat` and
`BallFloatDecorated` this distinguishes equal sets stored with different
precision tags or endpoint precisions; use `set_equal` for sets. `to_repr`
gives the structural `Debug` form.

### `@def.Floating` for `BallFloat`

`BallFloat` implements the `Floating` trait of [`def`](def.md) with
`classify`, `sign`, `precision`, `with_precision` and `normalized` as
described above, so the generic predicates `@def.is_finite` (bounded),
`@def.is_infinite` (unbounded), `@def.is_nan` (Empty) and `@def.is_zero`
(sign `Zero`, that is, contains 0) apply to intervals.

```mbti
pub impl @def.Floating for BallFloat
```

The laws of `Floating` that speak of keeping a value hold only as
enclosures: `with_precision` and `normalized` return supersets of the input
(see the warning under
[`BallFloat::with_precision`](#ballfloatwith_precision)).

### `@arithmetic.Contains`, `@arithmetic.Overlaps`, `@arithmetic.DefinitelyLt`, `@arithmetic.DefinitelyLe`, `@arithmetic.MaybeEq`

`BallFloat` implements the enclosure relation traits of `Luna-Flow/arithmetic`.

```mbti
pub impl @arithmetic.Contains for BallFloat
pub impl @arithmetic.Overlaps for BallFloat
pub impl @arithmetic.DefinitelyLt for BallFloat
pub impl @arithmetic.DefinitelyLe for BallFloat
pub impl @arithmetic.MaybeEq for BallFloat
```

`Contains::contains(x, y)` is `y.subset(x)` (set inclusion, not the
point-taking method); the others call the methods of the same name.

### `BallFloat::div_checked`, `BallFloat::pow_nat_checked`, `BallFloat::pow_int_checked`

`BallFloat` implements `DivChecked`, `PowNatChecked` and `PowIntChecked`; their
methods are promoted.

```mbti
pub impl @arithmetic.DivChecked for BallFloat
pub impl @arithmetic.PowNatChecked for BallFloat
pub impl @arithmetic.PowIntChecked for BallFloat
pub fn BallFloat::div_checked(Self, Self, @arithmetic.ArithmeticContext) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::pow_nat_checked(Self, UInt, @arithmetic.ArithmeticContext) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::pow_int_checked(Self, Int, @arithmetic.ArithmeticContext) -> Result[Self, @arithmetic.ArithmeticError]
```

Only `ctx.precision` is used: the operands are re-rounded to it with
`with_precision`, the operation is applied, and the result is re-rounded, so
the result can be wider than the plain operation even when the precision is
unchanged (see [`BallFloat::with_precision`](#ballfloatwith_precision)). They
always return `Ok`. `div_checked` follows the division rules above (a divisor
containing 0 gives an unbounded result, not an error). `pow_int_checked` uses
`pown`. `pow_nat_checked` uses binary powering by repeated interval
multiplication, which treats the factors as independent: for an argument
containing 0 its result is wider than `pown`. Its loop starts from $\{1\}$,
so `pow_nat_checked(Empty, 0)` returns $\{1\}$ where `pown(Empty, 0)` returns
Empty.

```moonbit
///|
test "checked capabilities" {
  let ctx = @lf_arith.ArithmeticContext::new(53)
  let x = iv(-1, 2)
  inspect(fmt(x.pow_int_checked(2, ctx).unwrap()), content="[0.00000e+0, 4.00000e+0]")
  inspect(fmt(x.pow_nat_checked(2U, ctx).unwrap()), content="[-2.00000e+0, 4.00000e+0]")
  inspect(x.div_checked(iv(-1, 1), ctx).unwrap().is_entire(), content="true")
  inspect(@lf_arith.Contains::contains(iv(0, 9), iv(1, 2)), content="true")
}
```

## Complete public interface

This snapshot is the generated `pkg.generated.mbti` of the package. It is the
authority when prose and interface disagree.

<!-- generated-api-start -->
```mbti
// Generated using `moon info`, DON'T EDIT IT
package "Luna-Flow/floating/ball_float"

import {
  "Luna-Flow/arithmetic",
  "Luna-Flow/floating/bin_float",
  "Luna-Flow/floating/def",
  "moonbitlang/core/debug",
}

// Values

// Errors

// Types and methods
pub struct BallContext {
  // private fields
}
pub fn BallContext::binary32() -> Self
pub fn BallContext::binary64() -> Self
pub fn BallContext::e_max(Self) -> Int
pub fn BallContext::e_min(Self) -> Int
pub fn BallContext::new(precision? : Int, e_min? : Int, e_max? : Int) -> Self
pub fn BallContext::precision(Self) -> Int
pub fn BallContext::try_new(precision? : Int, e_min? : Int, e_max? : Int) -> Result[Self, @arithmetic.ArithmeticError]

pub struct BallFlags {
  inexact : Bool
  overflow : Bool
  underflow : Bool
} derive(Eq)
pub fn BallFlags::combine(Self, Self) -> Self
pub fn BallFlags::equal(Self, Self) -> Bool
pub fn BallFlags::inexact(Self) -> Bool
pub fn BallFlags::new() -> Self
pub fn BallFlags::not_equal(Self, Self) -> Bool
pub fn BallFlags::overflow(Self) -> Bool
pub fn BallFlags::underflow(Self) -> Bool

pub struct BallFloat {
  // private fields
} derive(Eq, @debug.Debug)
pub fn BallFloat::abs(Self) -> Self
pub fn BallFloat::acos_interval(Self) -> Self
pub fn BallFloat::acosh_interval(Self) -> Self
pub fn BallFloat::add(Self, Self) -> Self
pub fn BallFloat::add_ctx(Self, Self, BallContext) -> (Self, BallFlags)
pub fn BallFloat::apply_ctx(Self, BallContext) -> (Self, BallFlags)
pub fn BallFloat::asin_interval(Self) -> Self
pub fn BallFloat::asinh_interval(Self) -> Self
pub fn BallFloat::atan2_interval(Self, Self) -> Self
pub fn BallFloat::atan_interval(Self) -> Self
pub fn BallFloat::atanh_interval(Self) -> Self
pub fn BallFloat::cancel_minus(Self, Self) -> Self
pub fn BallFloat::cancel_plus(Self, Self) -> Self
pub fn BallFloat::center(Self) -> @bin_float.BinFloat
pub fn BallFloat::classify(Self) -> @arithmetic.FpClass
pub fn BallFloat::contains(Self, @bin_float.BinFloat) -> Bool
pub fn BallFloat::contains_zero(Self) -> Bool
pub fn BallFloat::convex_hull(Self, Self) -> Self
pub fn BallFloat::cos_interval(Self) -> Self
pub fn BallFloat::cosh_interval(Self) -> Self
pub fn BallFloat::cospi_interval(Self) -> Self
pub fn BallFloat::definitely_gt(Self, Self) -> Bool
pub fn BallFloat::definitely_le(Self, Self) -> Bool
pub fn BallFloat::definitely_lt(Self, Self) -> Bool
pub fn BallFloat::disjoint(Self, Self) -> Bool
pub fn BallFloat::div(Self, Self) -> Self
pub fn BallFloat::div_checked(Self, Self, @arithmetic.ArithmeticContext) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::div_ctx(Self, Self, BallContext) -> (Self, BallFlags)
pub fn BallFloat::empty(precision? : Int) -> Self
pub fn BallFloat::equal(Self, Self) -> Bool
pub fn BallFloat::exact(@bin_float.BinFloat, precision? : Int) -> Self
pub fn BallFloat::exp10_interval(Self) -> Self
pub fn BallFloat::exp2_interval(Self) -> Self
pub fn BallFloat::exp_ctx(Self, BallContext) -> (Self, BallFlags)
pub fn BallFloat::exp_interval(Self) -> Self
pub fn BallFloat::expm1_interval(Self) -> Self
pub fn BallFloat::fma(Self, Self, Self) -> Self
pub fn BallFloat::from_bounds(@bin_float.BinFloat, @bin_float.BinFloat, precision? : Int) -> Self
pub fn BallFloat::from_coefficient(@bin_float.BinCoeff, precision? : Int, negative? : Bool) -> Self
pub fn BallFloat::from_double(Double, precision? : Int) -> Self
pub fn BallFloat::from_float(Float, precision? : Int) -> Self
pub fn BallFloat::from_int(Int, precision? : Int) -> Self
pub fn BallFloat::hypot(Self, Self) -> Self
pub fn BallFloat::interior(Self, Self) -> Bool
pub fn BallFloat::intersection(Self, Self) -> Self
pub fn BallFloat::is_bounded(Self) -> Bool
pub fn BallFloat::is_common_interval(Self) -> Bool
pub fn BallFloat::is_empty(Self) -> Bool
pub fn BallFloat::is_entire(Self) -> Bool
pub fn BallFloat::is_singleton(Self) -> Bool
pub fn BallFloat::less(Self, Self) -> Bool
pub fn BallFloat::ln_ctx(Self, BallContext) -> (Self, BallFlags)
pub fn BallFloat::ln_interval(Self) -> Self
pub fn BallFloat::log10_interval(Self) -> Self
pub fn BallFloat::log1p_interval(Self) -> Self
pub fn BallFloat::log2_interval(Self) -> Self
pub fn BallFloat::lower_bound(Self) -> @bin_float.BinFloat
pub fn BallFloat::magnitude(Self) -> @bin_float.BinFloat
pub fn BallFloat::maximum(Self, Self) -> Self
pub fn BallFloat::maybe_eq(Self, Self) -> Bool
pub fn BallFloat::midpoint(Self) -> @bin_float.BinFloat
pub fn BallFloat::midpoint_ctx(Self, BallContext) -> (@bin_float.BinFloat, BallFlags)
pub fn BallFloat::mignitude(Self) -> @bin_float.BinFloat
pub fn BallFloat::minimum(Self, Self) -> Self
pub fn BallFloat::mul(Self, Self) -> Self
pub fn BallFloat::mul_ctx(Self, Self, BallContext) -> (Self, BallFlags)
pub fn BallFloat::neg(Self) -> Self
pub fn BallFloat::new(@bin_float.BinFloat, @bin_float.BinFloat, precision? : Int) -> Self
pub fn BallFloat::normalized(Self) -> Self
pub fn BallFloat::not_equal(Self, Self) -> Bool
pub fn BallFloat::output(Self, &Logger) -> Unit
pub fn BallFloat::overlap_state(Self, Self) -> OverlapState
pub fn BallFloat::overlaps(Self, Self) -> Bool
pub fn BallFloat::pow_int_checked(Self, Int, @arithmetic.ArithmeticContext) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::pow_interval(Self, Self) -> Self
pub fn BallFloat::pow_nat_checked(Self, UInt, @arithmetic.ArithmeticContext) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::pown(Self, Int) -> Self
pub fn BallFloat::precedes(Self, Self) -> Bool
pub fn BallFloat::precision(Self) -> Int
pub fn BallFloat::radius(Self) -> @bin_float.BinFloat
pub fn BallFloat::radius_extended(Self) -> @bin_float.BinFloat
pub fn BallFloat::reciprocal(Self) -> Self
pub fn BallFloat::rootn(Self, Int) -> Self
pub fn BallFloat::separated_from(Self, Self) -> Bool
pub fn BallFloat::set_equal(Self, Self) -> Bool
pub fn BallFloat::sign(Self) -> @def.Sign
pub fn BallFloat::sin_interval(Self) -> Self
pub fn BallFloat::sinh_interval(Self) -> Self
pub fn BallFloat::sinpi_interval(Self) -> Self
pub fn BallFloat::sqrt_interval(Self) -> Self
pub fn BallFloat::square(Self) -> Self
pub fn BallFloat::strictly_less(Self, Self) -> Bool
pub fn BallFloat::strictly_precedes(Self, Self) -> Bool
pub fn BallFloat::sub(Self, Self) -> Self
pub fn BallFloat::sub_ctx(Self, Self, BallContext) -> (Self, BallFlags)
pub fn BallFloat::subset(Self, Self) -> Bool
pub fn BallFloat::tan_interval(Self) -> Self
pub fn BallFloat::tanh_interval(Self) -> Self
pub fn BallFloat::tanpi_interval(Self) -> Self
pub fn BallFloat::to_repr(Self) -> @debug.Repr
pub fn BallFloat::to_string(Self) -> String
pub fn BallFloat::try_acos_interval(Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::try_acosh_interval(Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::try_asin_interval(Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::try_asinh_interval(Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::try_atan2_interval(Self, Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::try_atan_interval(Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::try_atanh_interval(Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::try_cos_interval(Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::try_cosh_interval(Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::try_cospi_interval(Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::try_exact(@bin_float.BinFloat, precision? : Int) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::try_exp10_interval(Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::try_exp2_interval(Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::try_exp_interval(Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::try_expm1_interval(Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::try_from_bounds(@bin_float.BinFloat, @bin_float.BinFloat, precision? : Int) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::try_from_double(Double, precision? : Int) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::try_from_float(Float, precision? : Int) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::try_hypot(Self, Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::try_ln_interval(Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::try_log10_interval(Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::try_log1p_interval(Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::try_log2_interval(Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::try_pow_interval(Self, Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::try_rootn(Self, Int) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::try_sin_interval(Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::try_sinh_interval(Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::try_sinpi_interval(Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::try_tan_interval(Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::try_tanh_interval(Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::try_tanpi_interval(Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::upper_bound(Self) -> @bin_float.BinFloat
pub fn BallFloat::whole(precision? : Int) -> Self
pub fn BallFloat::width(Self) -> @bin_float.BinFloat
pub fn BallFloat::with_precision(Self, Int, @arithmetic.RoundingMode) -> Self
pub impl @arithmetic.Contains for BallFloat
pub impl @arithmetic.DefinitelyLe for BallFloat
pub impl @arithmetic.DefinitelyLt for BallFloat
pub impl @arithmetic.DivChecked for BallFloat
pub impl @arithmetic.MaybeEq for BallFloat
pub impl @arithmetic.Overlaps for BallFloat
pub impl @arithmetic.PowIntChecked for BallFloat
pub impl @arithmetic.PowNatChecked for BallFloat
pub impl @def.Floating for BallFloat
pub impl Add for BallFloat
pub impl Div for BallFloat
pub impl Mul for BallFloat
pub impl Neg for BallFloat
pub impl Show for BallFloat
pub impl Sub for BallFloat

pub struct BallFloatDecorated {
  // private fields
} derive(Eq)
pub fn BallFloatDecorated::abs(Self) -> Self
pub fn BallFloatDecorated::acos_interval(Self) -> Self
pub fn BallFloatDecorated::acosh_interval(Self) -> Self
pub fn BallFloatDecorated::add(Self, Self) -> Self
pub fn BallFloatDecorated::apply_ctx(Self, BallContext) -> (Self, BallFlags)
pub fn BallFloatDecorated::asin_interval(Self) -> Self
pub fn BallFloatDecorated::asinh_interval(Self) -> Self
pub fn BallFloatDecorated::atan2_interval(Self, Self) -> Self
pub fn BallFloatDecorated::atan_interval(Self) -> Self
pub fn BallFloatDecorated::atanh_interval(Self) -> Self
pub fn BallFloatDecorated::cancel_minus(Self, Self) -> Self
pub fn BallFloatDecorated::cancel_plus(Self, Self) -> Self
pub fn BallFloatDecorated::contains(Self, @bin_float.BinFloat) -> Bool
pub fn BallFloatDecorated::convex_hull(Self, Self) -> Self
pub fn BallFloatDecorated::cos_interval(Self) -> Self
pub fn BallFloatDecorated::cosh_interval(Self) -> Self
pub fn BallFloatDecorated::cospi_interval(Self) -> Self
pub fn BallFloatDecorated::decoration(Self) -> Decoration
pub fn BallFloatDecorated::disjoint(Self, Self) -> Bool
pub fn BallFloatDecorated::div(Self, Self) -> Self
pub fn BallFloatDecorated::equal(Self, Self) -> Bool
pub fn BallFloatDecorated::exp10_interval(Self) -> Self
pub fn BallFloatDecorated::exp2_interval(Self) -> Self
pub fn BallFloatDecorated::exp_interval(Self) -> Self
pub fn BallFloatDecorated::expm1_interval(Self) -> Self
pub fn BallFloatDecorated::fma(Self, Self, Self) -> Self
pub fn BallFloatDecorated::hypot(Self, Self) -> Self
pub fn BallFloatDecorated::interior(Self, Self) -> Bool
pub fn BallFloatDecorated::intersection(Self, Self) -> Self
pub fn BallFloatDecorated::interval(Self) -> BallFloat
pub fn BallFloatDecorated::is_common_interval(Self) -> Bool
pub fn BallFloatDecorated::is_empty(Self) -> Bool
pub fn BallFloatDecorated::is_entire(Self) -> Bool
pub fn BallFloatDecorated::is_nai(Self) -> Bool
pub fn BallFloatDecorated::is_singleton(Self) -> Bool
pub fn BallFloatDecorated::less(Self, Self) -> Bool
pub fn BallFloatDecorated::ln_interval(Self) -> Self
pub fn BallFloatDecorated::log10_interval(Self) -> Self
pub fn BallFloatDecorated::log1p_interval(Self) -> Self
pub fn BallFloatDecorated::log2_interval(Self) -> Self
pub fn BallFloatDecorated::maximum(Self, Self) -> Self
pub fn BallFloatDecorated::minimum(Self, Self) -> Self
pub fn BallFloatDecorated::mul(Self, Self) -> Self
pub fn BallFloatDecorated::nai(precision? : Int) -> Self
pub fn BallFloatDecorated::neg(Self) -> Self
pub fn BallFloatDecorated::new(BallFloat, decoration? : Decoration) -> Self
pub fn BallFloatDecorated::not_equal(Self, Self) -> Bool
pub fn BallFloatDecorated::output(Self, &Logger) -> Unit
pub fn BallFloatDecorated::overlap_state(Self, Self) -> OverlapState
pub fn BallFloatDecorated::pos(Self) -> Self
pub fn BallFloatDecorated::pow_interval(Self, Self) -> Self
pub fn BallFloatDecorated::pown(Self, Int) -> Self
pub fn BallFloatDecorated::precedes(Self, Self) -> Bool
pub fn BallFloatDecorated::reciprocal(Self) -> Self
pub fn BallFloatDecorated::rootn(Self, Int) -> Self
pub fn BallFloatDecorated::set_equal(Self, Self) -> Bool
pub fn BallFloatDecorated::sin_interval(Self) -> Self
pub fn BallFloatDecorated::sinh_interval(Self) -> Self
pub fn BallFloatDecorated::sinpi_interval(Self) -> Self
pub fn BallFloatDecorated::sqrt_interval(Self) -> Self
pub fn BallFloatDecorated::square(Self) -> Self
pub fn BallFloatDecorated::strictly_less(Self, Self) -> Bool
pub fn BallFloatDecorated::strictly_precedes(Self, Self) -> Bool
pub fn BallFloatDecorated::sub(Self, Self) -> Self
pub fn BallFloatDecorated::subset(Self, Self) -> Bool
pub fn BallFloatDecorated::tan_interval(Self) -> Self
pub fn BallFloatDecorated::tanh_interval(Self) -> Self
pub fn BallFloatDecorated::tanpi_interval(Self) -> Self
pub fn BallFloatDecorated::to_string(Self) -> String
pub impl Add for BallFloatDecorated
pub impl Div for BallFloatDecorated
pub impl Mul for BallFloatDecorated
pub impl Show for BallFloatDecorated
pub impl Sub for BallFloatDecorated

pub(all) enum Decoration {
  Ill
  Trv
  Def
  Dac
  Com
} derive(Eq, @debug.Debug)
pub fn Decoration::equal(Self, Self) -> Bool
pub fn Decoration::not_equal(Self, Self) -> Bool
pub fn Decoration::output(Self, &Logger) -> Unit
pub fn Decoration::to_repr(Self) -> @debug.Repr
pub fn Decoration::to_string(Self) -> String
pub impl Show for Decoration

pub(all) enum OverlapState {
  Undefined
  BothEmpty
  FirstEmpty
  SecondEmpty
  Before
  Meets
  OverlapsState
  Starts
  ContainedBy
  Finishes
  EqualIntervals
  After
  MetBy
  OverlappedBy
  StartedBy
  ContainsInterval
  FinishedBy
} derive(Eq, @debug.Debug)
pub fn OverlapState::equal(Self, Self) -> Bool
pub fn OverlapState::not_equal(Self, Self) -> Bool
pub fn OverlapState::to_repr(Self) -> @debug.Repr

// Type aliases

// Traits
```
<!-- generated-api-end -->
