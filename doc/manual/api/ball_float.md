# ball_float API

## Purpose

`ball_float` is interval arithmetic over `BinFloat` endpoints. A `BallFloat`
is a closed real interval $[\underline{x}, \overline{x}]$, possibly unbounded,
or the empty set; every operation returns an interval that contains all exact
results of the operation on points of its operands (the *inclusion property*).
`BallFloatDecorated` adds the decorations of IEEE 1788-2015, `BallContext`
rounds results into a target binary format and reports `BallFlags`.

Despite the name, the stored representation is the endpoint pair, not a
midpoint and a radius: `BallFloat::new(center, radius)` builds an interval from
the midpoint–radius view, and `midpoint()` and `radius()` read it back as
IEEE 1788-2015 12.12.8 defines them. The
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
- The *precision* of an interval is between 1 and `binary_precision_max`
  (268,435,456) bits, the limits of a `BinaryContext`. A constructor that
  returns a value aborts on a precision outside them and names the limits; the
  `try_` constructors and the checked tier return an error. A precision is
  never replaced silently (before 0.12 a precision below 1 became 1).
- *Empty* is the empty set, *Entire* is $(-\infty, +\infty)$. An unbounded
  interval stores $-\infty$ and/or $+\infty$ as endpoints; these mean that the
  set is unbounded on that side, never that it contains an infinite value.
- The few inputs for which the code currently loses part of the input set,
  widens without need, or rounds or flags a context result incorrectly are
  noted where they occur, with their tracking issue, and collected under
  [Known limitations](../design/ball_float.md#known-limitations) on the
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
  let down = @bin_float.BinaryContext::new(
    precision=53,
    rounding=@bin_float.BinaryRoundingMode::RoundTowardNegative,
  )
  let up = @bin_float.BinaryContext::new(
    precision=53,
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
[Construction](#construction). `==` is the `equal` of IEEE 1788-2015 Table 10.3: it compares the sets, not
the representation; see
[`BallFloat::equal`](#ballfloatsubset-ballfloatinterior-ballfloatequal-ballfloatdisjoint)
and [`BallFloat::identical`](#ballfloatidentical).

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
} derive(Compare, Eq, @debug.Debug)
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
totally ordered; `Decoration` derives `Compare` in that order, so `<`, `<=`,
`>` and `>=` are the comparisons of decorations of IEEE 1788-2015 11.5.3. `Show` prints the lower-case IEEE 1788 names `com`, `dac`,
`def`, `trv`, `ill`.

### `OverlapState`

`OverlapState` is the result of `overlap`: the IEEE 1788 classification
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

The constructors are the 16 states of IEEE 1788-2015 Table 10.7 (10.6.4),
with the standard's names: `bothEmpty`, `firstEmpty`, `secondEmpty`, `before`,
`meets`, `overlaps`, `starts`, `containedBy`, `finishes`, `equals`, `after`,
`metBy`, `overlappedBy`, `startedBy`, `contains` and `finishedBy`. There is no
17th state: the decorated `overlap` has no value for NaI (11.7.2) and returns
`None`.

### `BallContext`

`BallContext` describes a target binary format of IEEE 754-2019 3.3: a
precision in bits and the exponent range $[1 - e_{\max}, e_{\max}]$ (`e_min`
is derived, not a parameter).

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
  // private fields
} derive(Eq)
```

`inexact` is set when an endpoint (or, for `midpoint_ctx`, the midpoint)
changed; `overflow` when it was beyond $e_{\max}$; `underflow` when it is tiny
and inexact, as IEEE 754 defines it (see
[`BallFloat::apply_ctx`](#ballfloatapply_ctx)). The fields are private; each flag is read with the accessor method of the same name, listed under
[`BallFlags::new`](#ballflagsnew-ballflagscombine-ballflagsinexact-ballflagsoverflow-ballflagsunderflow).

## Construction

### `BallFloat::new`

`BallFloat::new` builds the interval $[c - r, c + r]$ from a center and a
radius, enlarged so that it is exact at the requested precision.
`BallFloat::try_new` returns the same interval, or an `ArithmeticError` where
`new` aborts.

```mbti
pub fn BallFloat::new(@bin_float.BinFloat, @bin_float.BinFloat, precision? : Int) -> Self
pub fn BallFloat::try_new(@bin_float.BinFloat, @bin_float.BinFloat, precision? : Int) -> Result[Self, @arithmetic.ArithmeticError]
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
$p$ bits. `new` aborts, and `try_new` returns a domain error, when `center` or
`radius` is not finite or when `radius` is negative, and when `precision` is
outside `1..=binary_precision_max`.

When $c$ already has at most $p$ bits and $r = 0$, the result is the
singleton $\{c\}$. When $c$ needs more than $p$ bits, the rounding error of
the center is added to the radius on *both* sides, so the interval is wider
than $[\operatorname{RD}_p(c - r), \operatorname{RU}_p(c + r)]$; use
`from_bounds` for the tightest enclosure of known bounds.

### `BallFloat::from_string` and `BallFloatDecorated::from_string`

IEEE 1788-2015 `textToInterval` (10.5.8, 12.12.7, 13.2): the interval literal `s`, as the hull of its
value at `precision` bits.

```mbti
pub let interval_literal_max_length : Int
pub fn BallFloat::from_string(String, precision? : Int) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloatDecorated::from_string(String, precision? : Int) -> Result[Self, @arithmetic.ArithmeticError]
```

The portable literals of 12.11 are accepted, with the case ignored and no whitespace except the spaces and tabs
the grammar allows inside the brackets:

| Form | Examples |
| --- | --- |
| number literals | `3.56`, `1.e-3`, `-0x1.3p-1`, `2/3`, `inf`, `-Infinity` |
| inf-sup | `[1.5, 2.5]`, `[-Inf, 2/3]`, `[0x1.3p-1,]` (the omitted bound is infinite), `[,]` (Entire) |
| point | `[3.56]` |
| uncertain `m?rve` | `3.56?1` ($[3.55, 3.57]$), `3.56?1e2` ($[355, 357]$), `3.560?2u`, `-10?` (half an ulp), `-10??u` ($[-10, +\infty]$), `-10??` (Entire) |
| special | `[]`, `[empty]`, `[entire]` |
| decorated | `[1,2]_com`, `3.56?1_def`, `[nai]` |

The bounds are parsed exactly (the decimal, hexadecimal and rational value, the ulp of the last place of an uncertain
form) and rounded outward: the lower bound down and the upper bound up. The comparison $l \le u$ is decided from
the exact values, so a literal is never rejected or emptied by rounding; a decimal exponent or a binary exponent beyond
the range is decided from the exponent and the digits without forming the value (a lower bound above the range is the
largest finite float and an upper bound is $+\infty$; below the smallest stored value they are 0 and the smallest
positive stored value). Only two finite bounds of different radices that are equal to the working size and have an
exponent beyond 65,536 cannot be ordered; then (12.12.7 case (b), `PossiblyUndefinedOperation`) the result contains
both bounds.

`Err` is the failed call of the standard (the result Empty for a bare literal, NaI for a decorated one, and the
exception `UndefinedOperation`). It is an `ArithmeticError` of the parse kind whose message names the rule that was
broken (for example "the lower bound is greater than the upper bound (l <= u is required)", "rational literal: the
denominator must be a positive natural number", "the decoration com needs a bounded interval (11.4)"). A decoration
or `[nai]` in a bare literal is such a failure for `BallFloat::from_string`. `BallFloatDecorated::from_string` accepts
a bare literal (decorated by `newDec`, so `com` for a bounded interval and `dac` otherwise), `bare_dec`, and `[nai]`,
which is `Ok(NaI)`; a decoration not permitted for the value (11.4: only `trv` for Empty, `com` only for a bounded
interval) is an `Err`, and `com` becomes `dac` if the rounding of a bounded literal overflowed. A string longer than
`interval_literal_max_length` (65,536 characters) is not parsed: 12.11.5 allows an implementation to "restrict support
of some input strings (too long strings or strings with a rational number literal)" and then requires that the
constructor "shall always return a Level 2 interval (possibly Entire in this case) that contains the Level 1 interval",
so the result is Entire (decorated: `dac`, or the `trv` or `def` the string ends with).

```moonbit
///|
test "from_string" {
  // 3.56?1 is [3.55, 3.57]: each bound is rounded outward
  let u = @ball_float.BallFloat::from_string("3.56?1").unwrap()
  assert_true(u.lower_bound().compare(@bin_float.BinFloat::from_double(3.55)) <= 0)
  // [0x1.3p-1,] is [19/32, +inf), exact
  let r = @ball_float.BallFloat::from_string("[0x1.3p-1,]").unwrap()
  assert_true(r.lower_bound().compare(@bin_float.BinFloat::from_double(19.0 / 32.0)) == 0)
  // the failed call is an Err that names the rule
  assert_true(@ball_float.BallFloat::from_string("[2,1]") is Err(_))
  // [nai] is NaI for the decorated form
  assert_true(@ball_float.BallFloatDecorated::from_string("[nai]").unwrap().is_nai())
}
```

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
pub fn BallFloat::from_int(Int, precision~ : Int) -> Self
pub fn BallFloat::from_coefficient(@bin_float.BinCoeff, precision? : Int, negative? : Bool) -> Self
```

The precision of `from_int` is required and counts bits (it was 53 by default). `from_coefficient` takes a non-negative
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

### `BallFloat::entire` and `BallFloat::empty`

`BallFloat::entire` returns Entire and `BallFloat::empty` returns Empty.

```mbti
pub fn BallFloat::entire(precision? : Int) -> Self
pub fn BallFloat::empty(precision? : Int) -> Self
```

The default precision is 53.

## Observers

### `BallFloat::lower_bound` and `BallFloat::upper_bound`

`lower_bound` and `upper_bound` are `inf` and `sup` of IEEE 1788-2015 12.12.8: they return
the endpoints.

```mbti
pub fn BallFloat::lower_bound(Self) -> @bin_float.BinFloat
pub fn BallFloat::upper_bound(Self) -> @bin_float.BinFloat
```

For an unbounded side the endpoint is an infinity. For Empty they return
$+\infty$ and $-\infty$ respectively, so test `is_empty` first.

The sign of a zero follows 12.12.8: in a format with a signed zero a Level 1 value of 0
is returned as $-0$ by `lower_bound` and as $+0$ by every other function of the subclause
(`upper_bound`, `midpoint`, `radius`, `width`, `magnitude`, `mignitude` and their contextual
forms). So the lower bound of `[0, 1]` is $-0$ and the upper bound of `[-1, 0]` is $+0$,
whatever sign of zero the interval was built from; `[0, 0]` has the representative
$(-0, +0)$. An interval is a set: the sign of a stored zero is not part of it. `BinFloat`'s `==`
agrees with `compare` (`-0 == +0`); `identical` tells the two zeros apart.

The label of an endpoint, `endpoint.precision()`, is the precision $p$ of the
interval exactly when the endpoint is a number of the format of $p$ bits (at most
$p$ significant bits and on the grid of $p$ bits, the band below the range floor
included); the infinities and the zeros carry $p$ too. The one exception is an
exact endpoint that is not such a number (an end of `new` or of `cancel_minus`
kept unrounded with more than $p$ bits, or finer than the grid of $p$ bits below
the range floor): it keeps the label of its own bit count. `BinFloat`'s `==`
agrees with `compare` and ignores the label (`BinFloat::identical` compares it), so
`x.lower_bound() == y` holds for a value `y` of the same number; `BallFloat`'s own
`==` and `identical` compare the endpoints by value and never read a label.
The sign of a stored zero is not part of the interval: the accessors decide it, as the paragraph above says.

### `BallFloat::midpoint` and `BallFloat::radius`

`midpoint` is `mid` and `radius` is `rad` of IEEE 1788-2015 12.12.8 (the names
`mid`, `rad`, `wid`, `inf`, `sup`, `mag` and `mig` are spelled out here; the
standard's short names would sit next to `BinFloat::inf`, so the long names are
a documented exception).

```mbti
pub fn BallFloat::midpoint(Self) -> @bin_float.BinFloat
pub fn BallFloat::radius(Self) -> @bin_float.BinFloat
```

Both are total; none aborts. `midpoint` returns NaN for Empty, 0 for Entire,
the largest finite number of the format (the interval's precision, the widest
exponent range of `BinFloat`) with the sign of the unbounded side for a
half-bounded interval, and otherwise the exact midpoint rounded to nearest
(ties to even) at the interval's precision. `midpoint_ctx` is the same
observer for a given `BallContext` as the result format. `radius` returns NaN
for Empty, $+\infty$ for every unbounded interval, and otherwise the smallest
number $r$ of the precision with $\boldsymbol{x} \subseteq [m - r, m + r]$, where
$m$ is the value `midpoint` returns: the larger of $m - \underline{x}$ and
$\overline{x} - m$, rounded up. This is measured from the rounded midpoint, not
from the exact center, so `[midpoint - radius, midpoint + radius]` always
contains the interval (before 0.12 the radius was the half-width and could miss
a bound by up to half an ulp). For $[1, 1 + 3 \cdot 2^{-52}]$ at 53 bits the
midpoint is $1 + 2^{-51}$ and the radius $2^{-51}$.

### `BallFloat::width`

`width` returns $\operatorname{RU}_p(\overline{x} - \underline{x})$, an upper bound
of the exact width. It is NaN for Empty and $+\infty$ for unbounded
intervals.

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
and it is monotone on each side of 0. Both are exact. Empty gives NaN for both
(12.12.8); `magnitude` of an unbounded interval is $+\infty$.

```moonbit
///|
test "observers" {
  let x = iv(-3, 5)
  inspect(x.midpoint().to_string(), content="1p0")
  inspect(x.radius().to_string(), content="1p2")
  inspect(x.width().to_string(), content="1p3")
  inspect(x.magnitude().to_string(), content="5p0")
  inspect(x.mignitude().to_string(), content="0")
  inspect(iv(2, 7).mignitude().to_string(), content="1p1")
}
```

### `BallFloat::precision`

`precision` returns the precision tag.

```mbti
pub fn BallFloat::precision(Self) -> Int
```

### `BallFloat::is_empty`, `BallFloat::is_entire`, `BallFloat::is_common_interval`, `BallFloat::is_singleton`

These predicates test the shape of the set.

```mbti
pub fn BallFloat::is_empty(Self) -> Bool
pub fn BallFloat::is_entire(Self) -> Bool
pub fn BallFloat::is_common_interval(Self) -> Bool
pub fn BallFloat::is_singleton(Self) -> Bool
```

`is_common_interval` holds when the interval is non-empty with two finite
endpoints (IEEE 1788-2015 10.6.3). `is_singleton` holds when
$\underline{x} = \overline{x}$. To ask whether an interval contains 0, use
`is_member` with a zero.

## Precision

### `BallFloat::with_precision`

`with_precision` re-rounds an interval to a new precision without shrinking
it.

```mbti
pub fn BallFloat::with_precision(Self, Int) -> Self
```

The endpoints are rounded outward: the lower bound toward $-\infty$ and the
upper bound toward $+\infty$, because outward rounding is the only direction
that keeps the result an enclosure; there is no rounding-mode argument. Empty
stays Empty with the new precision.

> [!NOTE]
> The result is the tightest representable enclosure of the input, so widening
> the precision is exact and re-rounding at an unchanged precision is an
> identity. The center–radius rebuild this function used to perform is not an
> identity: if the exact center $(\underline{x} + \overline{x})/2$ needs more
> than $p$ bits, both endpoints move outward by the rounding error of the
> center, so at 53 bits $[1, 1 + 2^{-52}]$ became $[1 - 2^{-52}, 1 + 2^{-52}]$.
> `normalized`, `convex_hull` with an Empty operand, the checked capabilities
> (`div_checked`, `pow_nat_checked`, `pow_int_checked`) and the
> `pow_nat`/`pown` methods of `ball_float_checked` round endpoints the same
> way and do not widen a representable interval either.

```moonbit
///|
test "with_precision keeps the endpoints" {
  let one = @bin_float.BinFloat::one(precision=53)
  let next = @bin_float.BinFloat::make(
    @bin_float.BinCoeff::from_uint64((1UL << 52) + 1UL),
    -52,
    53,
  )
  let x = @ball_float.BallFloat::from_bounds(one, next)
  let y = x.with_precision(53)
  inspect(y.lower_bound().to_string(), content="1p0")
  inspect(y.upper_bound().to_string(), content="4503599627370497p-52")
  inspect(y.equal(x), content="true")
  // `normalized` keeps the endpoints too.
  inspect(x.normalized().equal(x), content="true")
}
```

### `BallFloat::normalized`

`normalized` normalizes the two endpoints (`BinFloat::normalized` removes
trailing zero bits) and stores them at the interval's precision.

```mbti
pub fn BallFloat::normalized(Self) -> Self
```

The stored endpoints are already representable at that precision, so the
result is the same set as the input: `normalized` of $[1, 1 + 2^{-52}]$ at
53 bits is $[1, 1 + 2^{-52}]$. Empty stays Empty.

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
  inspect(fmt(iv(0, 1).convex_hull(iv(5, 6))), content="[-0.00000e+0, 6.00000e+0]")
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

### `BallFloat::is_member`

`is_member` tests whether a point belongs to the interval.

```mbti
pub fn BallFloat::is_member(Self, @bin_float.BinFloat) -> Bool
```

It returns false for Empty and for a non-finite point (an unbounded interval
contains all sufficiently large reals, but not $\pm\infty$ or NaN). The trait
method `@lf_arith.Contains::contains` instead takes two intervals and tests
inclusion; see
[Enclosure relations](#arithmeticcontains-arithmeticoverlaps-arithmeticdefinitelylt-arithmeticdefinitelyle-arithmeticmaybeeq).

### `BallFloat::subset`, `BallFloat::interior`, `BallFloat::equal`, `BallFloat::disjoint`

These test inclusion, inclusion in the interior, equality and disjointness of
sets.

```mbti
pub fn BallFloat::subset(Self, Self) -> Bool
pub fn BallFloat::interior(Self, Self) -> Bool
pub fn BallFloat::equal(Self, Self) -> Bool
pub fn BallFloat::disjoint(Self, Self) -> Bool
```

`x.subset(y)` is $\boldsymbol{x} \subseteq \boldsymbol{y}$, that is
$\underline{y} \le \underline{x}$ and $\overline{x} \le \overline{y}$.
`x.interior(y)` is $\boldsymbol{x} \subseteq \operatorname{int}
\boldsymbol{y}$: each endpoint comparison is strict, except that two equal
infinite endpoints count as interior (the interior of $[a, +\infty)$ is
$(a, +\infty)$, so Entire is interior to itself). Empty is a subset of,
interior to and disjoint from every interval. `equal` is the method of the
`Eq` implementation, so `x == y` is `x.equal(y)`: the two intervals are the
same set (two empty intervals are equal), whatever their precision tags and the
representation of their endpoints (IEEE 1788-2015 12.3 and 12.12.9).

### `BallFloat::identical`

`identical` compares the datum, not only the set (12.3): the same set and the
same precision tag.

```mbti
pub fn BallFloat::identical(Self, Self) -> Bool
```

The same interval at 24 and at 113 bits is `==` and not `identical`; use
`identical` where the precision matters, for example to check that a result
has the precision that was asked for. Two empty intervals are identical when
their precisions are equal.

The same holds for any other part of the format of an interval that a later release
adds (the optional exponent range of the 754-conforming types, issue 232): the format is not
part of `==` or of `compare`; only `identical` may look at it.

### `BallFloat::less`, `BallFloat::strict_less`, `BallFloat::precedes`, `BallFloat::strict_precedes`

These are the order relations of IEEE 1788.

```mbti
pub fn BallFloat::less(Self, Self) -> Bool
pub fn BallFloat::strict_less(Self, Self) -> Bool
pub fn BallFloat::precedes(Self, Self) -> Bool
pub fn BallFloat::strict_precedes(Self, Self) -> Bool
```

For non-empty operands:

| Relation | Set definition | Condition |
| --- | --- | --- |
| `less` | $\forall\xi\,\exists\eta: \xi \le \eta$ and $\forall\eta\,\exists\xi: \xi \le \eta$ | $\underline{x} \le \underline{y}$ and $\overline{x} \le \overline{y}$ |
| `strict_less` | the same with $<$ | $\underline{x} < \underline{y}$ (or both $-\infty$) and $\overline{x} < \overline{y}$ (or both $+\infty$) |
| `precedes` | $\forall\xi\,\forall\eta: \xi \le \eta$ | $\overline{x} \le \underline{y}$ |
| `strict_precedes` | $\forall\xi\,\forall\eta: \xi < \eta$ | $\overline{x} < \underline{y}$ |

With Empty: `less` and `strict_less` hold only when both are Empty;
`precedes` and `strict_precedes` hold when either is Empty.

### `BallFloat::overlap`

`overlap` classifies the relative position of two intervals.

```mbti
pub fn BallFloat::overlap(Self, Self) -> OverlapState
```

The result is one of the sixteen states of [`OverlapState`](#overlapstate); it
is computed from the comparisons of the four
endpoints, testing equal endpoints first, so a singleton that coincides with
an endpoint of the other interval gives `Starts`, `Finishes`, `StartedBy` or
`FinishedBy` rather than `Meets` or `MetBy`, as IEEE 1788 requires.

```moonbit
///|
test "relations" {
  let a = iv(1, 3)
  let b = iv(3, 6)
  inspect(a.precedes(b), content="true")
  inspect(a.strict_precedes(b), content="false")
  inspect(@lf_arith.DefinitelyLe::definitely_le(a, b), content="true")
  inspect(@lf_arith.MaybeEq::maybe_eq(a, b), content="true")
  inspect(iv(2, 3).interior(iv(1, 6)), content="true")
  inspect(iv(1, 3).interior(iv(1, 6)), content="false")
  debug_inspect(a.overlap(b), content="Meets")
  debug_inspect(iv(1, 6).overlap(iv(2, 3)), content="Contains")
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

### `BallFloat::recip`

`recip` returns $1/\boldsymbol{x}$ with the division rules above.

```mbti
pub fn BallFloat::recip(Self) -> Self
```

### `BallFloat::sqr` and `BallFloat::pown`

`sqr` returns $\{\xi^2\}$ and `pown` returns $\{\xi^n\}$ for an integer
exponent $n$.

```mbti
pub fn BallFloat::sqr(Self) -> Self
pub fn BallFloat::pown(Self, Int) -> Self
```

Unlike `x * x`, these use the same point twice, so `[-1, 2].sqr()` is
$[0, 4]$ (while `x * x` is $[-2, 4]$): `sqr` is
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
  inspect(fmt(x.sqr()), content="[-0.00000e+0, 4.00000e+0]")
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

### `BallFloat::min` and `BallFloat::max`

`min` and `max` return $\{\min(\xi, \eta)\}$ and
$\{\max(\xi, \eta)\}$.

```mbti
pub fn BallFloat::min(Self, Self) -> Self
pub fn BallFloat::max(Self, Self) -> Self
```

`min` is $[\min(\underline{x}, \underline{y}), \min(\overline{x},
\overline{y})]$ and `max` is the analogue with `max`: $\min$ is
increasing in each argument. An Empty operand gives Empty.

### `BallFloat::sign`, `BallFloat::ceil`, `BallFloat::floor`, `BallFloat::trunc`, `BallFloat::round_ties_to_even`, `BallFloat::round_ties_to_away`

The integer functions of IEEE 1788-2015 Table 9.1. `sign` is $-1$, $0$ or $1$
by the sign of the point; `ceil` and `floor` give the smallest integer not
less and the largest integer not greater than the point; `trunc` the nearest
integer toward zero; `round_ties_to_even` and `round_ties_to_away` the nearest
integer, a tie going to the even integer or away from zero (the names are the
754 `roundTiesToEven` and `roundTiesToAway`).

```mbti
pub fn BallFloat::sign(Self) -> Self
pub fn BallFloat::ceil(Self) -> Self
pub fn BallFloat::floor(Self) -> Self
pub fn BallFloat::trunc(Self) -> Self
pub fn BallFloat::round_ties_to_even(Self) -> Self
pub fn BallFloat::round_ties_to_away(Self) -> Self
```

Each function $f$ is nondecreasing, so the result is
$[f(\underline{x}), f(\overline{x})]$. The values are integers (or $-1$, $0$,
$1$), so the result is exact: nothing is rounded, the precision tag is kept,
and a zero bound is stored as $+0$. The function of $\pm\infty$ is
$\pm\infty$ (for `sign`, $\pm 1$). An Empty operand gives Empty. There is no
`try_` form: no input fails.

```moonbit
///|
test "integer functions" {
  let x = @ball_float.BallFloat::from_bounds(
    @bin_float.BinFloat::from_double(1.1),
    @bin_float.BinFloat::from_double(2.0),
  )
  assert_true(x.ceil() == iv(2, 2))
  assert_true(x.floor() == iv(1, 2))
  let d = @ball_float.BallFloatDecorated::new(x)
  assert_eq(d.ceil().decoration(), @ball_float.Decoration::Dac)
  assert_eq(d.floor().decoration(), @ball_float.Decoration::Def)
}
```

### `BallFloat::sqr_rev`, `BallFloat::abs_rev`, `BallFloat::pown_rev` and `BallFloat::cosh_rev`

IEEE 1788-2015 10.5.4 and Table 10.1. Each is the natural reverse extension:
the hull of $\{\, x \in \boldsymbol{x} \mid \varphi(x) \in \boldsymbol{c} \,\}$,
where $\boldsymbol{c}$ is the receiver and the prior $\boldsymbol{x}$ is the
optional last argument (default Entire). The hull is taken after meeting the
preimage with $\boldsymbol{x}$, not before: for $\boldsymbol{c} = [1, 4]$,
`sqr_rev` is $[-2, 2]$ and with the prior $[0, 1.2]$ it is $[1, 1.2]$, while
$[-2, 2] \cap [0, 1.2] = [0, 1.2]$.

```mbti
pub fn BallFloat::sqr_rev(Self, x? : Self) -> Self
pub fn BallFloat::abs_rev(Self, x? : Self) -> Self
pub fn BallFloat::pown_rev(Self, Int, x? : Self) -> Self
pub fn BallFloat::cosh_rev(Self, x? : Self) -> Self
```

`pown_rev(c, p, x?)` is the standard's `pownRev(c, x, p)`: the power comes
before the optional prior. The functions:

| Function | Preimage of $\boldsymbol{c}$ |
| --- | --- |
| `sqr_rev` | $\pm\sqrt{\boldsymbol{c} \cap [0, +\infty)}$, the endpoints of the roots rounded outward |
| `abs_rev` | $\pm(\boldsymbol{c} \cap [0, +\infty))$, exact |
| `cosh_rev` | $\pm\operatorname{acosh}(\boldsymbol{c} \cap [1, +\infty))$ |
| `pown_rev`, $p = 0$ | $\mathbb{R}$ if $1 \in \boldsymbol{c}$, else empty ($x^0 = 1$ for every $x$) |
| `pown_rev`, $p$ even and positive | $\pm\sqrt[p]{\boldsymbol{c} \cap [0, +\infty)}$ |
| `pown_rev`, $p$ odd and positive | $\sqrt[p]{\boldsymbol{c}}$, one interval ($p = 1$: $\boldsymbol{c}$) |
| `pown_rev`, $p$ even and negative | $x \ne 0$ with $x^p \in \boldsymbol{c} \cap (0, +\infty)$: $\pm$ the $\lvert p\rvert$-th root of $1/\boldsymbol{c}$, the upper end of $\boldsymbol{c}$ bounding $\lvert x\rvert$ from below and the lower end from above |
| `pown_rev`, $p$ odd and negative | the positive part of $\boldsymbol{c}$ gives positive $x$ and the negative part gives negative $x$, each by $\sqrt[p]{\cdot}$ with the pole 0 excluded |

An Empty $\boldsymbol{c}$, or a $\boldsymbol{c}$ outside the range of the function
(negative for `sqr_rev`, below 1 for `cosh_rev`), gives Empty. The root
endpoints are directed roundings of exact points, so the results are the
tightest in the type. For a negative power the value $x = 0$ is not in the
domain, so the component that ends at 0 (when $\boldsymbol{c}$ is unbounded above
for an even $p$, or reaches the pole) is open there: with $\boldsymbol{c} =
[1, +\infty)$ and $p = -2$ the set is $[-1, 0) \cup (0, 1]$ and the prior
$[0, 0]$ gives Empty. The result precision is the largest of the operands'.

```moonbit
///|
test "sqr_rev and pown_rev" {
  let c = iv(1, 4)
  inspect(c.sqr_rev().lower_bound().to_string() + " " + c.sqr_rev().upper_bound().to_string(), content="-1p1 1p1")
  assert_true(c.sqr_rev(x=iv(0, 1)) == iv(1, 1))
  assert_true(iv(16, 81).pown_rev(4, x=iv(0, 5)) == iv(2, 3))
  assert_true(iv(1, 4).pown_rev(0) == @ball_float.BallFloat::entire())
}
```

### `BallFloat::sin_rev`, `BallFloat::cos_rev` and `BallFloat::tan_rev`

IEEE 1788-2015 10.5.4 and Table 10.1. Each is the hull of
$\{\, x \in \boldsymbol{x} \mid \varphi(x) \in \boldsymbol{c} \,\}$ for the receiver
$\boldsymbol{c}$ and the optional prior $\boldsymbol{x}$ (default Entire).

```mbti
pub fn BallFloat::sin_rev(Self, x? : Self) -> Self
pub fn BallFloat::cos_rev(Self, x? : Self) -> Self
pub fn BallFloat::tan_rev(Self, x? : Self) -> Self
```

The preimage is a periodic union of intervals. With $\boldsymbol{c}' =
\boldsymbol{c} \cap [-1, 1]$, $A = \arcsin \underline{c'}$ and $B = \arcsin
\overline{c'}$, the preimage of `sin_rev` is $\bigcup_k [A + 2\pi k, B + 2\pi k]
\cup [\pi - B + 2\pi k, \pi - A + 2\pi k]$; `cos_rev` and `tan_rev` are analogous
(`tan_rev`: $\bigcup_k (\arctan \underline{c} + \pi k, \arctan \overline{c} + \pi k)$, a
bound at $\pm\infty$ giving the pole $\pm\pi/2 + \pi k$, which is not in the domain).
With the default prior the result is Entire for every $\boldsymbol{c}$ that meets the
range of the function; $\boldsymbol{c}$ outside $[-1, 1]$ gives Empty for `sin_rev` and
`cos_rev`, and $\boldsymbol{c} \supseteq [-1, 1]$ (`tan_rev`: $\boldsymbol{c} = $ Entire)
returns the prior itself. With a bounded prior only the first and the last piece that
meet it matter, so the cost does not depend on how many periods the prior spans.

The result is the hull of the true set in the type: every comparison of a prior
end with a piece end is decided exactly, and an end of the result that comes from a
piece is the exact directed rounding of that end (`RD` for a lower end, `RU` for an upper
end). This is the tightest result, and it can be narrower than a reference value that
leaves an ulp of slack. For example `sin_rev([0, 0], x = [RU(pi), 7])` is
$[RD(2\pi), RU(2\pi)]$ and `sin_rev([0, 0], x = [RU(pi), 6])` is Empty. How the ends are
decided is on the [design page](../design/ball_float.md#reverse-sine-cosine-and-tangent).
The one limit is the forward trigonometric one: an end of the prior at or beyond
$2^{\max(65536, 4p) + 1}$ in magnitude is kept as it is (valid, not tight), decided before
any work is done, and a prior whose finite ends are all beyond it is returned at once. For
a prior end of magnitude $2^e$ inside the limit the cost grows with $e$ like the cost of the
forward functions of the
[trigonometric functions section](#ballfloatsin-ballfloatcos-ballfloattan-ballfloattry_sin-ballfloattry_cos-ballfloattry_tan),
the working precision following $e$.

```moonbit
///|
test "sin_rev with a prior" {
  let rd_pi = @bin_float.BinFloat::from_double(3.141592653589793)
  let ru_pi = @bin_float.BinFloat::from_double(3.1415926535897936)
  let c = iv(0, 0)
  // the multiples of pi in [3, 4]: only pi, which is not a float
  let r = c.sin_rev(x=iv(3, 4))
  assert_true(r.lower_bound().compare(rd_pi) == 0)
  assert_true(r.upper_bound().compare(ru_pi) == 0)
  // the prior starts above pi and ends before 2 pi: nothing
  let six = @bin_float.BinFloat::from_int(6)
  let beyond = @ball_float.BallFloat::from_bounds(ru_pi, six)
  assert_true(c.sin_rev(x=beyond).is_empty())
  // the default prior
  assert_true(c.sin_rev().is_entire())
}
```

### `BallFloat::pow_rev1`

IEEE 1788-2015 Table 10.1. `b.pow_rev1(c, x?)` is the hull of
$\{\, x \in \boldsymbol{x} \mid \exists\, \beta \in \boldsymbol{b} : x^\beta \text{ is defined and in } \boldsymbol{c} \,\}$
for the optional prior $\boldsymbol{x}$ (default Entire); the receiver is the exponent interval
$\boldsymbol{b}$. $x^\beta$ is defined for $x > 0$ and for $x = 0$ with $\beta > 0$ (value 0).

```mbti
pub fn BallFloat::pow_rev1(Self, Self, x? : Self) -> Self
```

For $x > 0$, $x^\beta \in \boldsymbol{c}$ means $\beta \ln x \in \ln(\boldsymbol{c} \cap (0, +\infty))$, so
the set is $\exp(L /_{\text{set}} \boldsymbol{b})$ with $L = \ln(\boldsymbol{c} \cap (0, +\infty))$,
the set division of [`mul_rev`](#ballfloatmul_rev_to_pair-and-ballfloatmul_rev) in logarithm
coordinates, plus the point 0 when $0 \in \boldsymbol{c}$ and $\boldsymbol{b}$ has a positive point.
Every end of a piece is $c_\text{end}^{1/\beta_\text{end}}$, 0, 1 or infinite. The ends that are not
attained are open: 0 (from $\ln x \to -\infty$, unless the zero part closes it) and 1 (the limit of a
quotient by an unbounded $\boldsymbol{b}$); a prior that only touches such an end does not meet the
set. For example `pow_rev1([1, +inf), [2, +inf))` is $(1, +\infty)$, so with the prior $[0, 1]$ the
result is Empty, and `pow_rev1([-1, 1], [0.5, 2])` is $(0, +\infty)$, so with the prior $[0, 0]$
it is Empty.

The result is the hull in the type: every comparison of a prior end with a piece end is exact and an
end written to the result is the exact directed rounding of the piece end. The exact value of
$c^{1/\beta}$ is classified from the structure of $c$ and $\beta$ (no squaring): it is a float
candidate (dyadic), a rational that is not a float (for example $9^{1/(-2)} = 1/3$), or irrational,
and the last is decided by a loop that raises the working precision as `sin_rev` does. The
[design page](../design/ball_float.md#reverse-power-with-an-interval-exponent) has the classes,
the budgets and their cost. An end of the set above the largest finite float is written as $+\infty$ when it is an upper end
and as the largest finite float of the result precision when it is a lower end; an end below the
smallest positive stored value is written as 0 when it is a lower end and as the smallest positive stored value
when it is an upper end; in between, including the subnormal range, the end is the usual directed rounding.
An exponent of magnitude $2^{10^9}$ is decided at once because the sign of $\ln(c)/\beta$ is exact.

```moonbit
///|
test "pow_rev1" {
  // x^2 in [4, 4] with x > 0: x = 2
  assert_true(iv(2, 2).pow_rev1(iv(4, 4)) == iv(2, 2))
  // x^beta in [0.25, 0.5] for beta in [-4, -2]: the upper end 0.25^(1/-2) = 2 is exact
  let r = iv(-4, -2).pow_rev1(iv(1, 1), x=iv(1, 1))
  assert_true(r == iv(1, 1))
  // 0^beta = 0 for beta > 0
  assert_true(iv(1, 2).pow_rev1(iv(0, 0)) == iv(0, 0))
}
```

### `BallFloat::pow_rev2`

IEEE 1788-2015 Table 10.1. `a.pow_rev2(c, x?)` is the hull of
$\{\, \beta \in \boldsymbol{x} \mid \exists\, a_0 \in \boldsymbol{a} : a_0^\beta \text{ is defined and in } \boldsymbol{c} \,\}$
for the optional prior $\boldsymbol{x}$ (default Entire); the receiver is the base interval
$\boldsymbol{a}$ and the unknown is the exponent. $a_0^\beta$ is defined for $a_0 > 0$ and for
$a_0 = 0$ with $\beta > 0$ (value 0).

```mbti
pub fn BallFloat::pow_rev2(Self, Self, x? : Self) -> Self
```

For $a_0 > 0$, $a_0^\beta \in \boldsymbol{c}$ means $\beta \ln a_0 \in \ln(\boldsymbol{c} \cap (0, +\infty))$, so the
set is $L /_{\text{set}} M$ with $L = \ln(\boldsymbol{c} \cap (0, +\infty))$ and
$M = \ln(\boldsymbol{a} \cap (0, +\infty))$, the set division of
[`mul_rev`](#ballfloatmul_rev_to_pair-and-ballfloatmul_rev) in logarithm coordinates, plus
$(0, +\infty)$ when $0 \in \boldsymbol{a}$ and $0 \in \boldsymbol{c}$ (the base 0). The base 1 is the
branch "$0$ in the divisor": if $1 \in \boldsymbol{a}$ and $1 \in \boldsymbol{c}$ every exponent qualifies,
and if $\boldsymbol{a} = [1, 1]$ and $1 \notin \boldsymbol{c}$ there is none. Every end of a piece is
$\ln(c_\text{end}) / \ln(a_\text{end})$, 0 or infinite. The ends that are not attained are open: the
infinities, and 0 when it is the limit of a quotient by an unbounded $M$ (and $0 \notin L$); a prior that
only touches such an end does not meet the set. For example `pow_rev2([2, +inf), [2, 4])` is
$(0, 2]$, so with the prior $[-3, 0]$ the result is Empty, while with $\boldsymbol{c} = [1, 4]$ the
end 0 is attained and the result is $[0, 0]$.

The result is the hull in the type: every comparison of a prior end with a piece end is exact and an
end written to the result is the exact directed rounding of the piece end. The value
$r = \ln(C)/\ln(A)$ of an end is classified from the structure of $A$ and $C$: it is rational iff $A$
and $C$ are multiplicatively dependent, decided by the multiplicative Euclidean algorithm on the odd
parts (an inexact division proves independence). A rational is a float iff its reduced denominator is
a power of two, and otherwise it is a rational that is not a float (for example
$\ln 3 / \ln 27 = 1/3$); every other end is irrational and is decided by a loop that raises the
working precision as `sin_rev` does. The
[design page](../design/ball_float.md#reverse-power-with-an-interval-base) has the classes, the
budgets and their cost. A base one unit from 1 gives a huge quotient, and the first working precision
follows its magnitude.

```moonbit
///|
test "pow_rev2" {
  // 2^beta in [8, 8] gives beta = 3
  assert_true(iv(2, 2).pow_rev2(iv(8, 8)) == iv(3, 3))
  // 2^beta in [1, 1] gives beta = 0
  assert_true(iv(2, 2).pow_rev2(iv(1, 1)) == iv(0, 0))
  // a prior restricts the result: 2^beta = 4 has the only solution beta = 2
  assert_true(iv(2, 2).pow_rev2(iv(4, 4), x=iv(0, 5)) == iv(2, 2))
}
```

### `BallFloat::atan2_rev1` and `BallFloat::atan2_rev2`

IEEE 1788-2015 Table 10.1, equations (6) and (7) of 10.5.4. `b.atan2_rev1(c, x?)` is the hull of
$\{\, y \in \boldsymbol{x} \mid \exists\, b_0 \in \boldsymbol{b} : \operatorname{atan2}(y, b_0) \text{ is defined and in } \boldsymbol{c} \,\}$:
the receiver is the abscissa interval $\boldsymbol{b}$ and the unknown is the ordinate $y$.
`a.atan2_rev2(c, x?)` is the hull of
$\{\, x_0 \in \boldsymbol{x} \mid \exists\, a_0 \in \boldsymbol{a} : \operatorname{atan2}(a_0, x_0) \text{ is defined and in } \boldsymbol{c} \,\}$:
the receiver is the ordinate interval $\boldsymbol{a}$ and the unknown is the abscissa $x_0$. The optional prior
$\boldsymbol{x}$ defaults to Entire.

```mbti
pub fn BallFloat::atan2_rev1(Self, Self, x? : Self) -> Self
pub fn BallFloat::atan2_rev2(Self, Self, x? : Self) -> Self
```

$\operatorname{atan2}(y, x)$ is defined on the plane minus the origin, with the range $(-\pi, \pi]$ (Table 9.1,
footnote f): the angle $\pi$ is attained on the half-line $y = 0$, $x < 0$, and $-\pi$ is never attained. With
$\Theta = \boldsymbol{c} \cap (-\pi, \pi]$ the set is the projection of the sector
$\{\, r(\cos t, \sin t) : r > 0,\ t \in \Theta \,\}$ on the axis of the unknown, cut by the strip of the
given operand. The [design page](../design/ball_float.md#reverse-arctangent-of-two-arguments) has the case
table by angle region and by the sign of the operand, the open ends, the branch cut and the origin. The set is
empty when $\boldsymbol{c}$ has no point in $(-\pi, \pi]$ (for example $[4, 5]$), when an operand or the prior is
Empty, and for the abscissa $\{0\}$ (Rev1) or the ordinate $\{0\}$ (Rev2) when $\boldsymbol{c}$ misses the
angles $\pm\pi/2$ (Rev1) or $0$ and $\pi$ (Rev2); the origin is never part of the set.

The result is the hull in the type: every comparison of a prior end with a piece end is exact, and an end written to
the result is the exact directed rounding of the piece end. The exact ends are 0 and the infinities; every other end
is $b_\text{end} \tan(c_\text{end})$ (Rev1) or $a_\text{end} / \tan(c_\text{end})$ (Rev2) of nonzero floats,
which is irrational (the tangent of a nonzero algebraic number is transcendental), so it differs from every float
and a loop that raises the working precision decides it, as in `sin_rev`. Whether an end of $\boldsymbol{c}$ is
below or above a multiple of $\pi/2$ is decided exactly ($\pi$ is irrational, so a float is never equal to such a
multiple).

```moonbit
///|
test "atan2_rev1 and atan2_rev2" {
  // the angle 0 with a positive abscissa: the ordinate is 0
  assert_true(iv(1, 1).atan2_rev1(iv(0, 0)) == iv(0, 0))
  // c = [4, 5] has no point in (-pi, pi]: Empty; so has the origin
  assert_true(iv(1, 1).atan2_rev1(iv(4, 5)).is_empty())
  assert_true(iv(0, 0).atan2_rev1(iv(0, 0)).is_empty())
  // the angle 0 with the ordinate {0} and a prior x0 in [1, 2]: the abscissa interval of the prior
  assert_true(iv(0, 0).atan2_rev2(iv(0, 0), x=iv(1, 2)) == iv(1, 2))
}
```

### `BallFloat::mul_rev_to_pair` and `BallFloat::mul_rev`

IEEE 1788-2015 10.5.5 and Table 10.1. For intervals $\boldsymbol{b}$ and
$\boldsymbol{c}$ the set

$$
\boldsymbol{c} \mathbin{/_{\text{set}}} \boldsymbol{b} = \{\, x \in \mathbb{R} \mid \exists\, y \in \boldsymbol{b} : x y \in \boldsymbol{c} \,\}
$$

has zero, one or two connected components, and is not always closed
($[1, 1] /_{\text{set}} [1, +\infty) = (0, 1]$). `mul_rev_to_pair` returns the
closures of the components, ordered, as a pair; `mul_rev` returns the hull of
the part of the set that lies in the prior interval `x`.

```mbti
pub fn BallFloat::mul_rev_to_pair(Self, Self) -> (Self, Self)
pub fn BallFloat::mul_rev(Self, Self, x? : Self) -> Self
```

`mul_rev_to_pair(b, c)` is `(Empty, Empty)` when there is no component,
`(u, Empty)` for one, and `(u, v)` with $u < v$ for two. The two closures can
share an endpoint: $[1, 1] /_{\text{set}} \text{Entire} = (-\infty, 0) \cup
(0, +\infty)$ gives `([-inf, 0], [0, +inf])`. An Empty operand gives
`(Empty, Empty)`. The receiver is $\boldsymbol{b}$ and the argument is
$\boldsymbol{c}$, as in the standard's `mulRevToPair(b, c)`.

`mul_rev(b, c, x?)` is $\operatorname{hull}\{x \in \boldsymbol{x} \mid
\exists y \in \boldsymbol{b} : x y \in \boldsymbol{c}\}$ with the default
$\boldsymbol{x} = $ Entire. The hull is of the set and not of its closure,
and not the intersection of `x` with the hull of the set: with
$\boldsymbol{b} = [-1, 1]$, $\boldsymbol{c} = [1, 1]$ and $\boldsymbol{x} =
[0, 0.5]$ the result is Empty, whereas the hull of the set is Entire. An
endpoint 0 that is the unattained limit of a quotient by an unbounded
$\boldsymbol{b}$ counts as open, so `mul_rev([1, +inf), [1, 1], x=[-1, 0])` is
Empty (the set is $(0, 1]$) and with $\boldsymbol{x} = [0, 0.5]$ it is
$[0, 0.5]$. The endpoints of the components are quotients rounded outward, so
the results are the tightest in the type. The result precision is the largest
of the operands'.

```moonbit
///|
test "mul_rev_to_pair and mul_rev" {
  let b = @ball_float.BallFloat::from_bounds(
    @bin_float.BinFloat::from_int(-1),
    @bin_float.BinFloat::from_int(1),
  )
  let (u, v) = b.mul_rev_to_pair(iv(1, 1))
  // (-inf, -1] and [1, +inf)
  inspect(u.upper_bound().to_string() + " " + v.lower_bound().to_string(), content="-1p0 1p0")
  assert_true(b.mul_rev(iv(1, 1), x=iv(0, 0)).is_empty())
}
```

## Elementary functions

Each function $f$ returns an interval containing
$f(\boldsymbol{x} \cap D_f)$, where $D_f$ is the domain of $f$; points of
$\boldsymbol{x}$ outside $D_f$ are ignored and the result is Empty when
$\boldsymbol{x} \cap D_f$ is empty. The result precision is the argument's
precision.

Functions come in two forms, and there is one kernel. The `try_` form
(`try_exp`, …) evaluates each endpoint with the corresponding
`bin_float` `try_*_ctx` function rounded toward $-\infty$ or $+\infty$, and
returns `Err(ArithmeticError)` with a certification-failure detail naming the
operation, stage and reason when that evaluation runs out of its work budget.
The total form (`exp`, `sin`, …) is the `try_` form with a
fallback: it returns the same interval whenever the `try_` form succeeds, and
otherwise the range of the function over its domain (the fallbacks are listed
below), which is a valid but wide enclosure. A total form never aborts, at any
precision the type accepts; a domain error is not a failure (the result is
Empty), so an argument outside the domain and a certification failure give
different results. Nothing is computed twice: the total form calls the `try_`
form once.

### `BallFloat::sqrt`

`sqrt` returns $\sqrt{\boldsymbol{x} \cap [0, +\infty)}$.

```mbti
pub fn BallFloat::sqrt(Self) -> Self
```

The endpoints are the downward and upward square roots at the interval's
precision. Empty when $\overline{x} < 0$. There is no `try_` form: square
root never fails.

### `BallFloat::exp`, `BallFloat::exp2`, `BallFloat::exp10`, `BallFloat::expm1`, `BallFloat::try_exp`, `BallFloat::try_exp2`, `BallFloat::try_exp10`, `BallFloat::try_expm1`

These return enclosures of $e^{\xi}$, $2^{\xi}$, $10^{\xi}$ and
$e^{\xi} - 1$.

```mbti
pub fn BallFloat::exp(Self) -> Self
pub fn BallFloat::exp2(Self) -> Self
pub fn BallFloat::exp10(Self) -> Self
pub fn BallFloat::expm1(Self) -> Self
pub fn BallFloat::try_exp(Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::try_exp2(Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::try_exp10(Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::try_expm1(Self) -> Result[Self, @arithmetic.ArithmeticError]
```

All four are increasing, so the result is
$[\operatorname{RD} f(\underline{x}), \operatorname{RU} f(\overline{x})]$.
For $|\xi| \ge 2^{30}$ the enclosure is $[\text{largest finite}, +\infty)$ or
$[0, \text{smallest positive}]$, which is valid because $e^{2^{30}}$ exceeds
$2^{e_{\max}+1}$ and $e^{-2^{30}}$ is below the smallest positive `BinFloat`
at every precision. `exp2` and `exp10` return exact powers
for integer endpoints whose power is representable at the interval's precision
(`exp2` of $\{10\}$ is $\{1024\}$, `exp10` of $\{3\}$ is
$\{1000\}$); an integer endpoint outside the exponent range keeps the
outward-rounded enclosure, so `exp2` of $\{-1073742000\}$ is
$[0, \text{smallest positive}]$ and of $\{2^{30}\}$ is
$[\text{largest finite}, +\infty)$. The fallback of the total forms is
$[0, +\infty)$ for `exp`, `exp2` and `exp10` and $[-1, +\infty)$ for
`expm1`.

### `BallFloat::ln`, `BallFloat::log2`, `BallFloat::log10`, `BallFloat::log1p`, `BallFloat::try_ln`, `BallFloat::try_log2`, `BallFloat::try_log10`, `BallFloat::try_log1p`

These return enclosures of $\ln \xi$, $\log_2 \xi$, $\log_{10} \xi$ and
$\ln(1 + \xi)$ over their domains $(0, \infty)$ and $(-1, \infty)$.

```mbti
pub fn BallFloat::ln(Self) -> Self
pub fn BallFloat::log2(Self) -> Self
pub fn BallFloat::log10(Self) -> Self
pub fn BallFloat::log1p(Self) -> Self
pub fn BallFloat::try_ln(Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::try_log2(Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::try_log10(Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::try_log1p(Self) -> Result[Self, @arithmetic.ArithmeticError]
```

When the interval reaches the domain boundary ($\underline{x} \le 0$, or
$\underline{x} \le -1$ for `log1p`) the lower endpoint is $-\infty$; when it
lies entirely outside the domain ($\overline{x} \le 0$, or
$\overline{x} < -1$ for `log1p`) the result is Empty. `log10`
returns exact integers at endpoints $10^k$, $0 \le k \le 9$. The fallback of
the total forms is Entire (an endpoint at or below the domain boundary is
decided before the kernel runs and is not a failure).

```moonbit
///|
test "exponentials and logarithms" {
  inspect(fmt(iv(0, 1).exp()), content="[1.00000e+0, 2.71829e+0]")
  inspect(fmt(iv(-1, 10).exp2()), content="[5.00000e-1, 1.02400e+3]")
  inspect(fmt(iv(0, 4).ln()), content="[-inf, 1.38630e+0]")
  inspect(fmt(iv(1, 1000).log10()), content="[-0.00000e+0, 3.00000e+0]")
  inspect(iv(-2, -1).ln().is_empty(), content="true")
  // Integer endpoints outside the exponent range keep the outward-rounded enclosure.
  let below = @ball_float.BallFloat::from_int(-1073742000, precision=53).exp2()
  inspect(below.lower_bound().to_string(), content="-0")
  inspect(below.upper_bound().to_string(), content="1p-1073741874")
  let above = @ball_float.BallFloat::from_int(1 << 30, precision=53).exp2()
  inspect(above.lower_bound().to_string(), content="9007199254740991p1073741771")
  inspect(above.upper_bound().to_string(), content="inf")
}
```

### `BallFloat::pow` and `BallFloat::try_pow`

`pow(x, y)` returns an enclosure of
$\{\xi^{\eta} : \xi \in \boldsymbol{x}, \eta \in \boldsymbol{y}\}$ over the
IEEE 1788 domain of `pow`: $\xi > 0$, or $\xi = 0$ and $\eta > 0$.

```mbti
pub fn BallFloat::pow(Self, Self) -> Self
pub fn BallFloat::try_pow(Self, Self) -> Result[Self, @arithmetic.ArithmeticError]
```

Negative parts of the base are ignored (use `pown` or `rootn` for negative
bases). Since $\xi^\eta = e^{\eta \ln \xi}$ and $\eta \ln \xi$ is bilinear in
$(\ln \xi, \eta)$, the extrema over a box with $\underline{x} > 0$ are at the
four corners. When the base reaches 0, $\xi^\eta \to 0$ for $\eta > 0$ and
$\to +\infty$ for $\eta < 0$, so the result is extended by 0 or $+\infty$
accordingly. The code also adds the value 1 when the base interval contains
1 or the exponent interval contains 0; it already lies between the corner
values, so this changes nothing but is harmless. $0^{\eta}$ for $\eta \le 0$
is excluded, so `pow([0, 0], y)` is Empty when $\overline{y} \le 0$.
The result precision is the larger operand precision. A corner whose power is
representable at the result precision, such as $16^{3/4} = 8$, gives that
power exactly. The total
form falls back to $[0, +\infty)$.

### `BallFloat::rootn` and `BallFloat::try_rootn`

`rootn(x, n)` returns an enclosure of the real $n$-th roots
$\{\xi^{1/n}\}$: for even $n$ over $\xi \ge 0$, for odd $n$ over all reals,
and for negative $n$ the reciprocal of the root.

```mbti
pub fn BallFloat::rootn(Self, Int) -> Self
pub fn BallFloat::try_rootn(Self, Int) -> Result[Self, @arithmetic.ArithmeticError]
```

`rootn(x, 0)` and `rootn(x, Int min)` are Empty; `try_rootn(x, 0)` is a domain
error. `rootn(x, 1)` is `x` and `rootn(x, 2)` is `sqrt`. The total
form is `try_rootn` with a fallback ($[0, +\infty)$ for an even degree, Entire
for an odd one). For negative $n$, `try_rootn` returns Entire when an odd
root's argument contains 0. Exact roots are returned exactly for every degree, so
`try_rootn({8}, -3)` is $\{1/2\}$.

```moonbit
///|
test "exact powers and roots" {
  let three_quarters = @ball_float.BallFloat::exact(
    @bin_float.BinFloat::make(@bin_float.BinCoeff::from_uint64(3UL), -2, 53),
  )
  let p = iv(16, 16).pow(three_quarters)
  inspect(p.lower_bound().to_string() + " " + p.upper_bound().to_string(), content="1p3 1p3")
  let r = iv(8, 8).try_rootn(-3).unwrap()
  inspect(r.lower_bound().to_string() + " " + r.upper_bound().to_string(), content="1p-1 1p-1")
}
```

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
to `sqrt(sqr(x) + sqr(y))`.

### `BallFloat::sin`, `BallFloat::cos`, `BallFloat::tan`, `BallFloat::try_sin`, `BallFloat::try_cos`, `BallFloat::try_tan`

These return enclosures of $\sin$, $\cos$ and $\tan$ over the interval (in
radians).

```mbti
pub fn BallFloat::sin(Self) -> Self
pub fn BallFloat::cos(Self) -> Self
pub fn BallFloat::tan(Self) -> Self
pub fn BallFloat::try_sin(Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::try_cos(Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::try_tan(Self) -> Result[Self, @arithmetic.ArithmeticError]
```

Both forms evaluate the `bin_float` functions at the endpoints (a point
interval) or at the endpoints and the critical points. A critical point $k\pi/2$ inside the
interval contributes the extremum $\pm 1$ of `sin`/`cos` (`sin` reaches $+1$
at $k \equiv 1$ and $-1$ at $k \equiv 3 \pmod 4$, `cos` reaches $+1$ at
$k \equiv 0$ and $-1$ at $k \equiv 2$); for `tan` an odd multiple of $\pi/2$
inside the interval (a pole) makes the result Entire. The set of candidate
indices $k$ is computed from the enclosure of $\pi$ and can only be too large,
which widens but never invalidates the result. Unbounded arguments give
$[-1, 1]$ (Entire for `tan`). When the larger endpoint magnitude is at least
$2^{\max(65536,\, 4p) + 1}$ the `try_` forms return a resource-limit error
without evaluating; the total forms return $[-1, 1]$ (Entire for `tan`), the
same fallback they use when the certification budget (12 work precisions) is
exhausted.

### `BallFloat::sinpi`, `BallFloat::cospi`, `BallFloat::tanpi`, `BallFloat::try_sinpi`, `BallFloat::try_cospi`, `BallFloat::try_tanpi`

These return enclosures of $\sin \pi\xi$, $\cos \pi\xi$ and $\tan \pi\xi$.

```mbti
pub fn BallFloat::sinpi(Self) -> Self
pub fn BallFloat::cospi(Self) -> Self
pub fn BallFloat::tanpi(Self) -> Self
pub fn BallFloat::try_sinpi(Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::try_cospi(Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::try_tanpi(Self) -> Result[Self, @arithmetic.ArithmeticError]
```

Here the critical points are the exact half-integers $k/2$, located from the
dyadic endpoints without approximating $\pi$. `tanpi` returns a
half-unbounded interval when a pole is exactly an endpoint and no other pole
lies in the interval (for example $[1/2, 1]$ gives $(-\infty, 0]$, whose upper
endpoint is $\tan \pi = -0$), Empty for
the singleton of a pole, and Entire when a pole lies inside. Unbounded
arguments and fallbacks give $[-1, 1]$ (Entire for `tanpi`).

```moonbit
///|
test "trigonometric functions" {
  inspect(fmt(iv(0, 4).sin()), content="[-7.56803e-1, 1.00000e+0]")
  inspect(fmt(iv(0, 4).cos()), content="[-1.00000e+0, 1.00000e+0]")
  inspect(iv(1, 2).tan().is_entire(), content="true")
  let half = @bin_float.BinFloat::make(@bin_float.BinCoeff::one(), -1, 53)
  let x = @ball_float.BallFloat::from_bounds(half, @bin_float.BinFloat::one(precision=53))
  inspect(fmt(x.sinpi()), content="[-0.00000e+0, 1.00000e+0]")
  inspect(fmt(x.tanpi()), content="[-inf, 0.00000e+0]")
}
```

### `BallFloat::asin`, `BallFloat::acos`, `BallFloat::atan`, `BallFloat::try_asin`, `BallFloat::try_acos`, `BallFloat::try_atan`

These return enclosures of $\arcsin$, $\arccos$ (over $[-1, 1]$) and
$\arctan$.

```mbti
pub fn BallFloat::asin(Self) -> Self
pub fn BallFloat::acos(Self) -> Self
pub fn BallFloat::atan(Self) -> Self
pub fn BallFloat::try_asin(Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::try_acos(Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::try_atan(Self) -> Result[Self, @arithmetic.ArithmeticError]
```

`asin` and `atan` are increasing and `acos` is decreasing, so only endpoints
are evaluated. `atan` of an infinite endpoint is $\pm\pi/2$. The fallback of
the total forms is $[-\pi/2, \pi/2]$ for `atan` and `asin` and $[0, \pi]$ for
`acos`, with $\pi$ taken from a constant of at most 64 bits and rounded
outward to the interval's precision, so the fallback itself cannot fail.

### `BallFloat::atan2` and `BallFloat::try_atan2`

`y.atan2(x)` returns an enclosure of the angles
$\operatorname{atan2}(\eta, \xi) \in (-\pi, \pi]$ of the points
$(\xi, \eta) \ne (0, 0)$ of the box $\boldsymbol{x} \times \boldsymbol{y}$.

```mbti
pub fn BallFloat::atan2(Self, Self) -> Self
pub fn BallFloat::try_atan2(Self, Self) -> Result[Self, @arithmetic.ArithmeticError]
```

The receiver is the ordinate. The result is the hull of the angles at the
four corners and at the points where the box meets the axes. When the box
crosses the branch cut ($\underline{x} < 0$ and
$\underline{y} < 0 \le \overline{y}$) the result is $[-\pi, \pi]$. The box
$\{(0, 0)\}$ gives Empty. The total form falls back to $[-\pi, \pi]$.

### `BallFloat::sinh`, `BallFloat::cosh`, `BallFloat::tanh`, `BallFloat::asinh`, `BallFloat::acosh`, `BallFloat::atanh`, `BallFloat::try_sinh`, `BallFloat::try_cosh`, `BallFloat::try_tanh`, `BallFloat::try_asinh`, `BallFloat::try_acosh`, `BallFloat::try_atanh`

These return enclosures of the hyperbolic functions and their inverses over
their domains ($[1, \infty)$ for `acosh`, $(-1, 1)$ for `atanh`).

```mbti
pub fn BallFloat::sinh(Self) -> Self
pub fn BallFloat::cosh(Self) -> Self
pub fn BallFloat::tanh(Self) -> Self
pub fn BallFloat::asinh(Self) -> Self
pub fn BallFloat::acosh(Self) -> Self
pub fn BallFloat::atanh(Self) -> Self
pub fn BallFloat::try_sinh(Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::try_cosh(Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::try_tanh(Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::try_asinh(Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::try_acosh(Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::try_atanh(Self) -> Result[Self, @arithmetic.ArithmeticError]
```

`cosh` has its minimum 1 at 0; the others are monotone. `atanh` of an
interval reaching $\pm 1$ is unbounded on that side, and an interval whose
only point in the domain's closure is $1$ or $-1$ gives Empty. The fallback of
the total forms is Entire for `sinh`, `asinh` and `atanh`, $[-1, 1]$ for
`tanh`, $[1, +\infty)$ for `cosh` and $[0, +\infty)$ for `acosh`.

The total forms keep their relative accuracy for a tiny argument, since they
are the `bin_float` kernels: at 53 bits `sinh` of $\{2^{-300}\}$ is
the two-ulp interval $[2^{-300}, (1 + 2^{-52})\,2^{-300}]$.

```moonbit
///|
test "inverse and hyperbolic functions" {
  let unit = iv(-1, 1)
  inspect(fmt(unit.asin()), content="[-1.57080e+0, 1.57080e+0]")
  inspect(fmt(iv(-2, 2).acos()), content="[-0.00000e+0, 3.14160e+0]")
  inspect(fmt(iv(1, 1).atan2(iv(1, 1))), content="[7.85398e-1, 7.85399e-1]")
  inspect(fmt(unit.cosh()), content="[1.00000e+0, 1.54309e+0]")
  inspect(fmt(unit.atanh()), content="[-inf, inf]")
}
```

## Contexts and flags

### `BallContext::new` and `BallContext::try_new`

`BallContext::new` builds a context from a precision and the largest exponent
`e_max`; `e_min` is `1 - e_max` (IEEE 754-2019 3.3).

```mbti
pub fn BallContext::new(precision? : Int, e_max? : Int) -> Self
pub fn BallContext::try_new(precision? : Int, e_max? : Int) -> Result[Self, @arithmetic.ArithmeticError]
```

The defaults are precision 53 and, for `e_max`, the implementation limit
`binary_implementation_e_max` of `bin_float`, the same as
`BinaryContext::new` given a precision alone (so `BallContext::new()` is not
binary64: use `binary64()` for that). The legality of the pair is decided by
`BinaryContext::try_new`, so `bin_float` and `ball_float` have one definition
of a format: the precision is between 1 and `binary_precision_max` and
`e_max` is at least 1. An illegal pair aborts `new`, naming the parameter, and
is a domain error for `try_new`. Before 0.12 `e_min` was a parameter, any pair
with `e_min <= e_max` was accepted, and the precision had no upper limit.

### `BallContext::with_precision` and `BallContext::with_e_max`

These return the same format with another precision, or another largest
exponent (and `e_min = 1 - e_max`); they abort when the result is not legal.

```mbti
pub fn BallContext::with_precision(Self, Int) -> Self
pub fn BallContext::with_e_max(Self, Int) -> Self
```

### `BallContext::binary16`, `BallContext::binary32`, `BallContext::binary64`, `BallContext::binary128`

These return the contexts of the IEEE 754 interchange formats: binary16
($p = 11$, $[-14, 15]$), binary32 ($p = 24$, $[-126, 127]$), binary64
($p = 53$, $[-1022, 1023]$) and binary128 ($p = 113$, $[-16382, 16383]$).

```mbti
pub fn BallContext::binary16() -> Self
pub fn BallContext::binary32() -> Self
pub fn BallContext::binary64() -> Self
pub fn BallContext::binary128() -> Self
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

`underflow` follows IEEE 754 with tininess detected after rounding: it is
raised when an endpoint is inexact and its rounding to $p$ bits with an
unbounded exponent range lies below $2^{e_{\min}}$, whichever of the two steps
lost the bits. With $p = 4$ and $e_{\min} = -2$, the lower endpoint
$2^{-3}(1 + 2^{-10})$ becomes $2^{-3}$, which is already on the subnormal grid,
and raises both `inexact` and `underflow`. An exact tiny endpoint raises
nothing.

There is no `add_ctx` or `exp_ctx`: the operation and the context are composed,
`(x + y).apply_ctx(ctx)`. When the operands' precision is at least the context
precision, the double rounding gives the same endpoints as a single outward
rounding into the context (see the
[design page](../design/ball_float.md#contexts-and-double-rounding)).

### `BallFloat::midpoint_ctx`

`midpoint_ctx` is the IEEE 1788 `mid` operation with the context as the result
format.

```mbti
pub fn BallFloat::midpoint_ctx(Self, BallContext) -> (@bin_float.BinFloat, BallFlags)
```

Following IEEE 1788-2015 §12.12.8, Empty gives NaN, Entire gives $+0$, an
interval unbounded only above gives the largest finite value of the context,
$(2 - 2^{1-p})\,2^{e_{\max}}$, and one unbounded only below gives its
negative; none of these raises a flag. A bounded interval gives its exact
center rounded once to nearest (ties to even) onto the context's grid,
including the subnormal grid $2^{e_{\min} - p + 1}\mathbb{Z}$, so with
$p = 4$, $e_{\min} = -2$ the center $2^{-6} + 2^{-20}$ gives $2^{-5}$. A zero
center gives $+0$. `inexact` is set when the result differs from the center
and `underflow` when it is also tiny, as for `apply_ctx`. A center that rounds
beyond $e_{\max}$ overflows to an infinity of its sign with `overflow` and
`inexact`: rounding to nearest maps it to $\pm\infty$ in IEEE 754, and
IEEE 1788 uses that rounding for the bounded case. Only an interval whose
endpoints are themselves outside the context's range can do this.

```moonbit
///|
test "contexts" {
  let ctx = @ball_float.BallContext::new(precision=8, e_max=10)
  let (third, flags) = (iv(1, 1) / iv(3, 3)).apply_ctx(ctx)
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

The default decoration is `Com`. `new` is `setDec` of IEEE 1788-2015 11.5.2:
the decoration `Ill` gives NaI for any interval, empty or not (at the
precision of the interval, so the result equals `BallFloatDecorated::nai`);
otherwise the decoration is made canonical, so `new(entire())` is decorated
`Dac` and `new(empty())` is decorated `Trv`, as in IEEE 1788 `newDec`.

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

### `BallFloatDecorated::is_empty`, `BallFloatDecorated::is_entire`, `BallFloatDecorated::is_common_interval`, `BallFloatDecorated::is_singleton`, `BallFloatDecorated::is_member`

These predicates apply the bare predicate to the interval and return false for
NaI.

```mbti
pub fn BallFloatDecorated::is_empty(Self) -> Bool
pub fn BallFloatDecorated::is_entire(Self) -> Bool
pub fn BallFloatDecorated::is_common_interval(Self) -> Bool
pub fn BallFloatDecorated::is_singleton(Self) -> Bool
pub fn BallFloatDecorated::is_member(Self, @bin_float.BinFloat) -> Bool
```

### `BallFloatDecorated::equal`, `BallFloatDecorated::identical`, `BallFloatDecorated::subset`, `BallFloatDecorated::interior`, `BallFloatDecorated::disjoint`, `BallFloatDecorated::less`, `BallFloatDecorated::strict_less`, `BallFloatDecorated::precedes`, `BallFloatDecorated::strict_precedes`, `BallFloatDecorated::overlap`

These relations apply the bare relation to the intervals and return false
when an operand is NaI.

```mbti
pub fn BallFloatDecorated::equal(Self, Self) -> Bool
pub fn BallFloatDecorated::identical(Self, Self) -> Bool
pub fn BallFloatDecorated::subset(Self, Self) -> Bool
pub fn BallFloatDecorated::interior(Self, Self) -> Bool
pub fn BallFloatDecorated::disjoint(Self, Self) -> Bool
pub fn BallFloatDecorated::less(Self, Self) -> Bool
pub fn BallFloatDecorated::strict_less(Self, Self) -> Bool
pub fn BallFloatDecorated::precedes(Self, Self) -> Bool
pub fn BallFloatDecorated::strict_precedes(Self, Self) -> Bool
pub fn BallFloatDecorated::overlap(Self, Self) -> OverlapState?
```

`overlap` returns `None` when an operand is NaI, which has no value for a
non-interval-valued operation (IEEE 1788-2015 11.7.2), and `Some(state)`
otherwise.

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

### `BallFloatDecorated::add`, `BallFloatDecorated::sub`, `BallFloatDecorated::mul`, `BallFloatDecorated::div`, `BallFloatDecorated::pos`, `BallFloatDecorated::neg`, `BallFloatDecorated::abs`, `BallFloatDecorated::recip`, `BallFloatDecorated::sqr`, `BallFloatDecorated::pown`, `BallFloatDecorated::fma`, `BallFloatDecorated::min`, `BallFloatDecorated::max`

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
pub fn BallFloatDecorated::recip(Self) -> Self
pub fn BallFloatDecorated::sqr(Self) -> Self
pub fn BallFloatDecorated::pown(Self, Int) -> Self
pub fn BallFloatDecorated::fma(Self, Self, Self) -> Self
pub fn BallFloatDecorated::min(Self, Self) -> Self
pub fn BallFloatDecorated::max(Self, Self) -> Self
```

| Operation | Operation decoration |
| --- | --- |
| `div`, `recip` | `Trv` when the divisor contains 0 |
| `pown(x, n)` | `Trv` when $n < 0$ and $0 \in \boldsymbol{x}$ |
| `pos` | identity (IEEE 1788 `pos`) |
| others | `Com` |

### `BallFloatDecorated::sqrt`, `BallFloatDecorated::exp`, `BallFloatDecorated::exp2`, `BallFloatDecorated::exp10`, `BallFloatDecorated::expm1`, `BallFloatDecorated::ln`, `BallFloatDecorated::log2`, `BallFloatDecorated::log10`, `BallFloatDecorated::log1p`, `BallFloatDecorated::pow`, `BallFloatDecorated::rootn`, `BallFloatDecorated::hypot`

The decorated elementary functions apply the bare total form (there are no
decorated `try_` forms) and lower the decoration when the input leaves the
domain of the function, as listed in the table at the end of this group.

These are the decorated square root, exponentials, logarithms, powers and
`hypot`.

```mbti
pub fn BallFloatDecorated::sqrt(Self) -> Self
pub fn BallFloatDecorated::exp(Self) -> Self
pub fn BallFloatDecorated::exp2(Self) -> Self
pub fn BallFloatDecorated::exp10(Self) -> Self
pub fn BallFloatDecorated::expm1(Self) -> Self
pub fn BallFloatDecorated::ln(Self) -> Self
pub fn BallFloatDecorated::log2(Self) -> Self
pub fn BallFloatDecorated::log10(Self) -> Self
pub fn BallFloatDecorated::log1p(Self) -> Self
pub fn BallFloatDecorated::pow(Self, Self) -> Self
pub fn BallFloatDecorated::rootn(Self, Int) -> Self
pub fn BallFloatDecorated::hypot(Self, Self) -> Self
```

### `BallFloatDecorated::sign`, `BallFloatDecorated::ceil`, `BallFloatDecorated::floor`, `BallFloatDecorated::trunc`, `BallFloatDecorated::round_ties_to_even`, `BallFloatDecorated::round_ties_to_away`

The interval part is the bare result. The operation decoration is the
strongest decoration of 11.2 for the function over the input box, and the
result is the minimum of it and the input decoration (11.6, equation 18):

| Input box $\boldsymbol{x}$ | Operation decoration |
| --- | --- |
| Empty | `Trv` |
| the function is not constant on $\boldsymbol{x}$ | `Def` |
| constant, and $\boldsymbol{x}$ unbounded | `Dac` |
| constant, bounded, and $\boldsymbol{x}$ contains a point of discontinuity of the function on the real line | `Dac` |
| constant, bounded, and no such point in $\boldsymbol{x}$ | `Com` |

The functions take integer values, so their restriction to $\boldsymbol{x}$ is
continuous exactly when it is constant (`dac` asks for continuity of the
restriction, `com` for continuity at each point of $\boldsymbol{x}$). The points
of discontinuity are the integers for `ceil` and `floor`, the nonzero integers
for `trunc`, $0$ for `sign`, and the half-integers for the two roundings. For
example `ceil` of the box $[1.1, 2.0]$ is $[2, 2]$ with `Dac`: the restriction
is constant, but $2$ is a point of discontinuity of `ceil`. `floor` of the same
box is $[1, 2]$ with `Def`. NaI gives NaI.

```mbti
pub fn BallFloatDecorated::sign(Self) -> Self
pub fn BallFloatDecorated::ceil(Self) -> Self
pub fn BallFloatDecorated::floor(Self) -> Self
pub fn BallFloatDecorated::trunc(Self) -> Self
pub fn BallFloatDecorated::round_ties_to_even(Self) -> Self
pub fn BallFloatDecorated::round_ties_to_away(Self) -> Self
```

### `BallFloatDecorated::sqr_rev`, `BallFloatDecorated::abs_rev`, `BallFloatDecorated::pown_rev` and `BallFloatDecorated::cosh_rev`

Reverse-mode operations have the trivial decorated version of 11.7.1: NaI if any
input (the interval or the prior) is NaI, else the bare result decorated `Trv`.

```mbti
pub fn BallFloatDecorated::sqr_rev(Self, x? : Self) -> Self
pub fn BallFloatDecorated::abs_rev(Self, x? : Self) -> Self
pub fn BallFloatDecorated::pown_rev(Self, Int, x? : Self) -> Self
pub fn BallFloatDecorated::cosh_rev(Self, x? : Self) -> Self
```

### `BallFloatDecorated::sin_rev`, `BallFloatDecorated::cos_rev` and `BallFloatDecorated::tan_rev`

The trivial decorated version of 11.7.1: NaI if any input (the interval or the prior) is
NaI, else the bare result decorated `Trv`.

```mbti
pub fn BallFloatDecorated::sin_rev(Self, x? : Self) -> Self
pub fn BallFloatDecorated::cos_rev(Self, x? : Self) -> Self
pub fn BallFloatDecorated::tan_rev(Self, x? : Self) -> Self
```

### `BallFloatDecorated::pow_rev1`

The trivial decorated version of 11.7.1: NaI if any input is NaI, else the bare result decorated `Trv`.

```mbti
pub fn BallFloatDecorated::pow_rev1(Self, Self, x? : Self) -> Self
```

### `BallFloatDecorated::mul_rev_to_pair` and `BallFloatDecorated::mul_rev`

`mul_rev_to_pair` follows 12.12.3. If either input is NaI both outputs are NaI.
Otherwise, when both are nonempty and $0 \notin \boldsymbol{b}$, the first
output is the decorated quotient $\boldsymbol{c} / \boldsymbol{b}$ (the same
decoration as `/`) and the second is Empty with `Trv`. Every other output,
empty or not, is decorated `Trv`. `mul_rev` is a reverse-mode operation and has
the trivial decorated version of 11.7.1: NaI if any input is NaI, else the bare
result decorated `Trv`.

```mbti
pub fn BallFloatDecorated::mul_rev_to_pair(Self, Self) -> (Self, Self)
pub fn BallFloatDecorated::mul_rev(Self, Self, x? : Self) -> Self
```

### `BallFloatDecorated::sin`, `BallFloatDecorated::cos`, `BallFloatDecorated::tan`, `BallFloatDecorated::sinpi`, `BallFloatDecorated::cospi`, `BallFloatDecorated::tanpi`, `BallFloatDecorated::asin`, `BallFloatDecorated::acos`, `BallFloatDecorated::atan`, `BallFloatDecorated::atan2`

These are the decorated trigonometric functions and their inverses.

```mbti
pub fn BallFloatDecorated::sin(Self) -> Self
pub fn BallFloatDecorated::cos(Self) -> Self
pub fn BallFloatDecorated::tan(Self) -> Self
pub fn BallFloatDecorated::sinpi(Self) -> Self
pub fn BallFloatDecorated::cospi(Self) -> Self
pub fn BallFloatDecorated::tanpi(Self) -> Self
pub fn BallFloatDecorated::asin(Self) -> Self
pub fn BallFloatDecorated::acos(Self) -> Self
pub fn BallFloatDecorated::atan(Self) -> Self
pub fn BallFloatDecorated::atan2(Self, Self) -> Self
```

### `BallFloatDecorated::sinh`, `BallFloatDecorated::cosh`, `BallFloatDecorated::tanh`, `BallFloatDecorated::asinh`, `BallFloatDecorated::acosh`, `BallFloatDecorated::atanh`

These are the decorated hyperbolic functions and their inverses.

```mbti
pub fn BallFloatDecorated::sinh(Self) -> Self
pub fn BallFloatDecorated::cosh(Self) -> Self
pub fn BallFloatDecorated::tanh(Self) -> Self
pub fn BallFloatDecorated::asinh(Self) -> Self
pub fn BallFloatDecorated::acosh(Self) -> Self
pub fn BallFloatDecorated::atanh(Self) -> Self
```

| Function | Operation decoration `Trv` when |
| --- | --- |
| `sqrt` | $\underline{x} < 0$ (or the input is Empty) |
| `ln`, `log2`, `log10` | $\underline{x} \le 0$ |
| `log1p` | $\underline{x} \le -1$ |
| `asin`, `acos` | $\boldsymbol{x} \not\subseteq [-1, 1]$ |
| `acosh` | $\underline{x} < 1$ |
| `atanh` | $\underline{x} \le -1$ or $\overline{x} \ge 1$ |
| `rootn(x, n)` | $n = 0$, or $n$ even and $\underline{x} < 0$, or $n < 0$ and $0 \in \boldsymbol{x}$ |
| `pow(x, y)` | $\underline{x} < 0$, or $0 \in \boldsymbol{x}$ and $\underline{y} \le 0$, or the result is Empty |
| `tan` | the result is Entire (a pole may lie inside) |
| `tanpi` | the result is unbounded (a pole lies in the argument, possibly at an endpoint) |
| `atan2` | both operands contain 0 |

All other functions have operation decoration `Com`. For `y.atan2(x)`
the decoration is `Def` when the box crosses the branch cut
($\underline{x} < 0$, $\underline{y} < 0 \le \overline{y}$: the restriction
jumps from $-\pi$ to $\pi$) and `Dac` when it touches the cut from above
($\overline{x} < 0$, $\underline{y} = 0$: the restriction is continuous, but
`atan2` itself is not continuous at those points).

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
  inspect(x.sqrt().decoration(), content="trv")
  inspect(x.exp().decoration(), content="com")
  inspect((x / x).decoration(), content="trv")
  inspect(@ball_float.BallFloatDecorated::new(iv(0, 4)).rootn(-2).decoration(), content="trv")
  let half = @bin_float.BinFloat::make(@bin_float.BinCoeff::one(), -1, 53)
  let pole = @ball_float.BallFloatDecorated::new(
    @ball_float.BallFloat::from_bounds(half, @bin_float.BinFloat::one(precision=53)),
  )
  inspect(pole.tanpi().decoration(), content="trv")
  let unbounded = @ball_float.BallFloatDecorated::new(@ball_float.BallFloat::entire())
  inspect(unbounded.decoration(), content="dac")
  let nai = @ball_float.BallFloatDecorated::nai()
  inspect((x + nai).to_string(), content="[nai]")
  debug_inspect(nai.overlap(x), content="None")
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

`Show` writes an interval as the portable inf-sup literal of IEEE 1788-2015
13.3 (`intervalToText`): the text `from_string` reads.

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

A nonempty bounded or half-bounded interval prints as `[l, u]`, Empty as
`[empty]`, Entire as `[entire]`; a decorated interval appends `_` and the
decoration, and NaI prints as `[nai]`. Each bound is a decimal number rounded
outward (the lower bound down, the upper bound up), so the text is a literal of
an interval that contains the value (13.3). The digits are the fewest that keep
the bound within one unit in the last place of the stored bound at the
precision of the interval, so `from_string(text, precision=x.precision())`
contains `x` and is wider by at most one unit in the last place at each end. A
bound with a binary exponent beyond 4096 in magnitude is written in
hexadecimal (`0x3p1073741000`) because its decimal expansion needs a power of
ten of that size; a hexadecimal bound is exact and is a valid literal. A zero bound is written `0`, without a sign, whatever sign it has: the literal of $[0, 0]$ does not carry the signs that `lower_bound` and `upper_bound` return ($-0$ and $+0$, 12.12.8), and 13.3 does not ask for them.

```moonbit
///|
test "show" {
  inspect(iv(1, 2).to_string(), content="[1, 2]")
  inspect(@ball_float.BallFloat::entire().to_string(), content="[entire]")
  inspect(@ball_float.BallFloatDecorated::new(iv(1, 2)).to_string(), content="[1, 2]_com")
}
```

### `BallFloat::to_exact_string`, `BallFloat::from_exact_string`, `BallFloatDecorated::to_exact_string`, `BallFloatDecorated::from_exact_string`

IEEE 1788-2015 13.4 `intervalToExact` and `exactToInterval`: a text that names
the interval itself.

```mbti
pub fn BallFloat::to_exact_string(Self) -> String
pub fn BallFloat::from_exact_string(String, precision~ : Int32 = ..) -> Result[BallFloat, @def.ArithmeticError]
pub fn BallFloatDecorated::to_exact_string(Self) -> String
pub fn BallFloatDecorated::from_exact_string(String, precision~ : Int32 = ..) -> Result[BallFloatDecorated, @def.ArithmeticError]
```

The text is `[empty]`, `[entire]` or `[l, u]` with the bounds written as
hexadecimal numbers (`0x1fffffp-3`; `inf` and `-inf` for an infinite bound), and
for a decorated interval `_` and the decoration (`[nai]` for NaI). The bounds
are the stored bounds, so `from_exact_string(x.to_exact_string(),
precision=x.precision())` is `identical` to `x` (no signed zero is written, 13.4).
`from_exact_string` reads the text exactly, at whatever bit count its bounds have, and never
widens it: `precision` is the precision of the interval, not a limit on the bounds. A bound with
more bits than `precision` is kept as it is, with the label of its own bit count (`lower_bound().precision()`
is 57 for `0x1.00000000000001p0`, whatever zero digits the text has), as the type keeps such ends (an end of `new` or of
`cancel_minus` that is not rounded), so the round trip above holds for every interval of the type, and
`[0x1.00000000000001p0, 0x2p0]` at precision 53 is the interval with that exact lower end and precision
53, neither `[1, 2]` nor an error. The call is refused (a parse error naming the reason) only for
what cannot be an interval of the library: a decimal or malformed bound, a bound beyond the exponent
range of the library (or finer than the grid of the larger of its own bit count and `precision` below the
range floor), a lower bound above the upper bound. Which bounds are representable at all is decided by the
converter of IEEE 754-2019 5.12.3 (`BinFloat::from_hex_ctx` reports `inexact`), not by counting digits
of the text, so a fractional mantissa (`0x1.8p0`, `0x.8p1`), leading and trailing zero digits and
upper case are read.

```moonbit
///|
test "exact text" {
  let x = iv(1, 2)
  inspect(x.to_exact_string(), content="[0x1p0, 0x1p1]")
  let back = @ball_float.BallFloat::from_exact_string(x.to_exact_string()).unwrap()
  assert_true(x.identical(back))
}
```

### `BallFloat::to_ball_string`, `BallFloatDecorated::to_ball_string`

The midpoint-radius view, `center +/- half-width`, with both numbers in the
`BinFloat` notation (`3p-1` is $3 \cdot 2^{-1}$). It was the output of `Show`
before 0.12; it is for reading, not a literal (`from_string` does not read it),
and its cost does not depend on the exponent range: an interval whose bounds
have exponents a billion apart is written in a few characters. An interval with
an infinite bound prints as `[l, u]` of binary numbers, Empty as `[empty]`;
a decorated interval appends `_` and the decoration.

```mbti
pub fn BallFloat::to_ball_string(Self) -> String
pub fn BallFloatDecorated::to_ball_string(Self) -> String
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

The `Eq` implementations of `BallFloat` and `BallFloatDecorated` are the
`equal` relation of IEEE 1788-2015 (12.12.9), not equality of representation:
`==` compares sets, ignoring precision tags, and on decorated intervals it is
false whenever one operand is NaI, so NaI is not equal to itself (as NaN is
not), and decorations are ignored. `identical` is the equality of the datum.
`to_repr` gives the structural `Debug` form. The `Eq` of `Decoration` and
`OverlapState` is the equality of the variants.

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
point-taking method). `Overlaps::overlaps(x, y)` is
$\underline{x} \le \overline{y} \wedge \underline{y} \le \overline{x}$, that is
$\boldsymbol{x} \cap \boldsymbol{y} \ne \emptyset$, and `MaybeEq::maybe_eq` is
the same relation read as "the two unknown points may be equal".
`DefinitelyLt::definitely_lt(x, y)` is $\overline{x} < \underline{y}$ and
`DefinitelyLe::definitely_le(x, y)` is $\overline{x} \le \underline{y}$: they hold
when the order holds for every pair of points. All four are false when an
operand is Empty. This differs from `disjoint`, `precedes` and
`strict_precedes`, which are true for an Empty operand (IEEE 1788-2015
Table 10.4): `overlaps` is false where `disjoint` is true, and
`definitely_lt` is false where `strict_precedes` is true, so a `true` answer
of the traits is always backed by at least one pair of points. These are the
generic interface of `Luna-Flow/arithmetic`; the interval package spells the
standard relations `disjoint`, `precedes` and `strict_precedes`.

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
`with_precision`, the operation is applied, and the result is re-rounded
outward (see [`BallFloat::with_precision`](#ballfloatwith_precision)). At the
operands' own precision the result is that of the plain operation; at a lower
precision it can be wider. They
always return `Ok`. `div_checked` follows the division rules above (a divisor
containing 0 gives an unbounded result, not an error). `pow_int_checked` uses
`pown`. `pow_nat_checked` uses binary powering by repeated interval
multiplication, which treats the factors as independent: for an argument
containing 0 its result is wider than `pown`. An Empty base gives Empty for
every exponent, including 0, as `pown` does.

```moonbit
///|
test "checked capabilities" {
  let ctx = @lf_arith.ArithmeticContext::new(53)
  let x = iv(-1, 2)
  inspect(fmt(x.pow_int_checked(2, ctx).unwrap()), content="[-0.00000e+0, 4.00000e+0]")
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
  "moonbitlang/core/debug",
}

// Values
pub let interval_literal_max_length : Int32

// Errors

// Types and methods
pub struct BallContext {
  // private fields
}
pub fn BallContext::binary128() -> Self
pub fn BallContext::binary16() -> Self
pub fn BallContext::binary32() -> Self
pub fn BallContext::binary64() -> Self
pub fn BallContext::e_max(Self) -> Int32
pub fn BallContext::e_min(Self) -> Int32
pub fn BallContext::new(precision? : Int32, e_max? : Int32) -> Self
pub fn BallContext::precision(Self) -> Int32
pub fn BallContext::try_new(precision? : Int32, e_max? : Int32) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallContext::with_e_max(Self, Int32) -> Self
pub fn BallContext::with_precision(Self, Int32) -> Self

#derive(Eq)
pub struct BallFlags {
  // private fields
}
pub fn BallFlags::combine(Self, Self) -> Self
pub fn BallFlags::equal(Self, Self) -> Bool
pub fn BallFlags::inexact(Self) -> Bool
pub fn BallFlags::new() -> Self
pub fn BallFlags::not_equal(Self, Self) -> Bool
pub fn BallFlags::overflow(Self) -> Bool
pub fn BallFlags::underflow(Self) -> Bool

#derive(@debug.Debug)
pub struct BallFloat {
  // private fields
}
pub fn BallFloat::abs(Self) -> Self
pub fn BallFloat::abs_rev(Self, x? : Self) -> Self
pub fn BallFloat::acos(Self) -> Self
pub fn BallFloat::acosh(Self) -> Self
pub fn BallFloat::add(Self, Self) -> Self
pub fn BallFloat::apply_ctx(Self, BallContext) -> (Self, BallFlags)
pub fn BallFloat::asin(Self) -> Self
pub fn BallFloat::asinh(Self) -> Self
pub fn BallFloat::atan(Self) -> Self
pub fn BallFloat::atan2(Self, Self) -> Self
pub fn BallFloat::atan2_rev1(Self, Self, x? : Self) -> Self
pub fn BallFloat::atan2_rev2(Self, Self, x? : Self) -> Self
pub fn BallFloat::atanh(Self) -> Self
pub fn BallFloat::cancel_minus(Self, Self) -> Self
pub fn BallFloat::cancel_plus(Self, Self) -> Self
pub fn BallFloat::ceil(Self) -> Self
pub fn BallFloat::convex_hull(Self, Self) -> Self
pub fn BallFloat::cos(Self) -> Self
pub fn BallFloat::cos_rev(Self, x? : Self) -> Self
pub fn BallFloat::cosh(Self) -> Self
pub fn BallFloat::cosh_rev(Self, x? : Self) -> Self
pub fn BallFloat::cospi(Self) -> Self
pub fn BallFloat::disjoint(Self, Self) -> Bool
pub fn BallFloat::div(Self, Self) -> Self
pub fn BallFloat::div_checked(Self, Self, @arithmetic.ArithmeticContext) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::empty(precision? : Int32) -> Self
pub fn BallFloat::entire(precision? : Int32) -> Self
pub fn BallFloat::equal(Self, Self) -> Bool
pub fn BallFloat::exact(@bin_float.BinFloat, precision? : Int32) -> Self
pub fn BallFloat::exp(Self) -> Self
pub fn BallFloat::exp10(Self) -> Self
pub fn BallFloat::exp2(Self) -> Self
pub fn BallFloat::expm1(Self) -> Self
pub fn BallFloat::floor(Self) -> Self
pub fn BallFloat::fma(Self, Self, Self) -> Self
pub fn BallFloat::from_bounds(@bin_float.BinFloat, @bin_float.BinFloat, precision? : Int32) -> Self
pub fn BallFloat::from_coefficient(@bin_float.BinCoeff, precision? : Int32, negative? : Bool) -> Self
pub fn BallFloat::from_double(Double, precision? : Int32) -> Self
pub fn BallFloat::from_exact_string(String, precision? : Int32) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::from_float(Float, precision? : Int32) -> Self
pub fn BallFloat::from_int(Int32, precision~ : Int32) -> Self
pub fn BallFloat::from_string(String, precision? : Int32) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::hypot(Self, Self) -> Self
pub fn BallFloat::identical(Self, Self) -> Bool
pub fn BallFloat::interior(Self, Self) -> Bool
pub fn BallFloat::intersection(Self, Self) -> Self
pub fn BallFloat::is_common_interval(Self) -> Bool
pub fn BallFloat::is_empty(Self) -> Bool
pub fn BallFloat::is_entire(Self) -> Bool
pub fn BallFloat::is_member(Self, @bin_float.BinFloat) -> Bool
pub fn BallFloat::is_singleton(Self) -> Bool
pub fn BallFloat::less(Self, Self) -> Bool
pub fn BallFloat::ln(Self) -> Self
pub fn BallFloat::log10(Self) -> Self
pub fn BallFloat::log1p(Self) -> Self
pub fn BallFloat::log2(Self) -> Self
pub fn BallFloat::lower_bound(Self) -> @bin_float.BinFloat
pub fn BallFloat::magnitude(Self) -> @bin_float.BinFloat
pub fn BallFloat::max(Self, Self) -> Self
pub fn BallFloat::midpoint(Self) -> @bin_float.BinFloat
pub fn BallFloat::midpoint_ctx(Self, BallContext) -> (@bin_float.BinFloat, BallFlags)
pub fn BallFloat::mignitude(Self) -> @bin_float.BinFloat
pub fn BallFloat::min(Self, Self) -> Self
pub fn BallFloat::mul(Self, Self) -> Self
pub fn BallFloat::mul_rev(Self, Self, x? : Self) -> Self
pub fn BallFloat::mul_rev_to_pair(Self, Self) -> (Self, Self)
pub fn BallFloat::neg(Self) -> Self
pub fn BallFloat::new(@bin_float.BinFloat, @bin_float.BinFloat, precision? : Int32) -> Self
pub fn BallFloat::normalized(Self) -> Self
pub fn BallFloat::not_equal(Self, Self) -> Bool
pub fn BallFloat::output(Self, &Logger) -> Unit
pub fn BallFloat::overlap(Self, Self) -> OverlapState
pub fn BallFloat::pow(Self, Self) -> Self
pub fn BallFloat::pow_int_checked(Self, Int32, @arithmetic.ArithmeticContext) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::pow_nat_checked(Self, UInt32, @arithmetic.ArithmeticContext) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::pow_rev1(Self, Self, x? : Self) -> Self
pub fn BallFloat::pow_rev2(Self, Self, x? : Self) -> Self
pub fn BallFloat::pown(Self, Int32) -> Self
pub fn BallFloat::pown_rev(Self, Int32, x? : Self) -> Self
pub fn BallFloat::precedes(Self, Self) -> Bool
pub fn BallFloat::precision(Self) -> Int32
pub fn BallFloat::radius(Self) -> @bin_float.BinFloat
pub fn BallFloat::recip(Self) -> Self
pub fn BallFloat::rootn(Self, Int32) -> Self
pub fn BallFloat::round_ties_to_away(Self) -> Self
pub fn BallFloat::round_ties_to_even(Self) -> Self
pub fn BallFloat::sign(Self) -> Self
pub fn BallFloat::sin(Self) -> Self
pub fn BallFloat::sin_rev(Self, x? : Self) -> Self
pub fn BallFloat::sinh(Self) -> Self
pub fn BallFloat::sinpi(Self) -> Self
pub fn BallFloat::sqr(Self) -> Self
pub fn BallFloat::sqr_rev(Self, x? : Self) -> Self
pub fn BallFloat::sqrt(Self) -> Self
pub fn BallFloat::strict_less(Self, Self) -> Bool
pub fn BallFloat::strict_precedes(Self, Self) -> Bool
pub fn BallFloat::sub(Self, Self) -> Self
pub fn BallFloat::subset(Self, Self) -> Bool
pub fn BallFloat::tan(Self) -> Self
pub fn BallFloat::tan_rev(Self, x? : Self) -> Self
pub fn BallFloat::tanh(Self) -> Self
pub fn BallFloat::tanpi(Self) -> Self
pub fn BallFloat::to_ball_string(Self) -> String
pub fn BallFloat::to_exact_string(Self) -> String
pub fn BallFloat::to_repr(Self) -> @debug.Repr
pub fn BallFloat::to_string(Self) -> String
pub fn BallFloat::trunc(Self) -> Self
pub fn BallFloat::try_acos(Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::try_acosh(Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::try_asin(Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::try_asinh(Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::try_atan(Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::try_atan2(Self, Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::try_atanh(Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::try_cos(Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::try_cosh(Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::try_cospi(Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::try_exact(@bin_float.BinFloat, precision? : Int32) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::try_exp(Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::try_exp10(Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::try_exp2(Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::try_expm1(Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::try_from_bounds(@bin_float.BinFloat, @bin_float.BinFloat, precision? : Int32) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::try_from_double(Double, precision? : Int32) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::try_from_float(Float, precision? : Int32) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::try_hypot(Self, Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::try_ln(Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::try_log10(Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::try_log1p(Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::try_log2(Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::try_new(@bin_float.BinFloat, @bin_float.BinFloat, precision? : Int32) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::try_pow(Self, Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::try_rootn(Self, Int32) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::try_sin(Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::try_sinh(Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::try_sinpi(Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::try_tan(Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::try_tanh(Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::try_tanpi(Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::upper_bound(Self) -> @bin_float.BinFloat
pub fn BallFloat::width(Self) -> @bin_float.BinFloat
pub fn BallFloat::with_precision(Self, Int32) -> Self
pub impl @arithmetic.Contains for BallFloat
pub impl @arithmetic.DefinitelyLe for BallFloat
pub impl @arithmetic.DefinitelyLt for BallFloat
pub impl @arithmetic.DivChecked for BallFloat
pub impl @arithmetic.MaybeEq for BallFloat
pub impl @arithmetic.Overlaps for BallFloat
pub impl @arithmetic.PowIntChecked for BallFloat
pub impl @arithmetic.PowNatChecked for BallFloat
pub impl Add for BallFloat
pub impl Div for BallFloat
pub impl Eq for BallFloat
pub impl Mul for BallFloat
pub impl Neg for BallFloat
pub impl Show for BallFloat
pub impl Sub for BallFloat

pub struct BallFloatDecorated {
  // private fields
}
pub fn BallFloatDecorated::abs(Self) -> Self
pub fn BallFloatDecorated::abs_rev(Self, x? : Self) -> Self
pub fn BallFloatDecorated::acos(Self) -> Self
pub fn BallFloatDecorated::acosh(Self) -> Self
pub fn BallFloatDecorated::add(Self, Self) -> Self
pub fn BallFloatDecorated::apply_ctx(Self, BallContext) -> (Self, BallFlags)
pub fn BallFloatDecorated::asin(Self) -> Self
pub fn BallFloatDecorated::asinh(Self) -> Self
pub fn BallFloatDecorated::atan(Self) -> Self
pub fn BallFloatDecorated::atan2(Self, Self) -> Self
pub fn BallFloatDecorated::atan2_rev1(Self, Self, x? : Self) -> Self
pub fn BallFloatDecorated::atan2_rev2(Self, Self, x? : Self) -> Self
pub fn BallFloatDecorated::atanh(Self) -> Self
pub fn BallFloatDecorated::cancel_minus(Self, Self) -> Self
pub fn BallFloatDecorated::cancel_plus(Self, Self) -> Self
pub fn BallFloatDecorated::ceil(Self) -> Self
pub fn BallFloatDecorated::convex_hull(Self, Self) -> Self
pub fn BallFloatDecorated::cos(Self) -> Self
pub fn BallFloatDecorated::cos_rev(Self, x? : Self) -> Self
pub fn BallFloatDecorated::cosh(Self) -> Self
pub fn BallFloatDecorated::cosh_rev(Self, x? : Self) -> Self
pub fn BallFloatDecorated::cospi(Self) -> Self
pub fn BallFloatDecorated::decoration(Self) -> Decoration
pub fn BallFloatDecorated::disjoint(Self, Self) -> Bool
pub fn BallFloatDecorated::div(Self, Self) -> Self
pub fn BallFloatDecorated::equal(Self, Self) -> Bool
pub fn BallFloatDecorated::exp(Self) -> Self
pub fn BallFloatDecorated::exp10(Self) -> Self
pub fn BallFloatDecorated::exp2(Self) -> Self
pub fn BallFloatDecorated::expm1(Self) -> Self
pub fn BallFloatDecorated::floor(Self) -> Self
pub fn BallFloatDecorated::fma(Self, Self, Self) -> Self
pub fn BallFloatDecorated::from_exact_string(String, precision? : Int32) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloatDecorated::from_string(String, precision? : Int32) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloatDecorated::hypot(Self, Self) -> Self
pub fn BallFloatDecorated::identical(Self, Self) -> Bool
pub fn BallFloatDecorated::interior(Self, Self) -> Bool
pub fn BallFloatDecorated::intersection(Self, Self) -> Self
pub fn BallFloatDecorated::interval(Self) -> BallFloat
pub fn BallFloatDecorated::is_common_interval(Self) -> Bool
pub fn BallFloatDecorated::is_empty(Self) -> Bool
pub fn BallFloatDecorated::is_entire(Self) -> Bool
pub fn BallFloatDecorated::is_member(Self, @bin_float.BinFloat) -> Bool
pub fn BallFloatDecorated::is_nai(Self) -> Bool
pub fn BallFloatDecorated::is_singleton(Self) -> Bool
pub fn BallFloatDecorated::less(Self, Self) -> Bool
pub fn BallFloatDecorated::ln(Self) -> Self
pub fn BallFloatDecorated::log10(Self) -> Self
pub fn BallFloatDecorated::log1p(Self) -> Self
pub fn BallFloatDecorated::log2(Self) -> Self
pub fn BallFloatDecorated::max(Self, Self) -> Self
pub fn BallFloatDecorated::min(Self, Self) -> Self
pub fn BallFloatDecorated::mul(Self, Self) -> Self
pub fn BallFloatDecorated::mul_rev(Self, Self, x? : Self) -> Self
pub fn BallFloatDecorated::mul_rev_to_pair(Self, Self) -> (Self, Self)
pub fn BallFloatDecorated::nai(precision? : Int32) -> Self
pub fn BallFloatDecorated::neg(Self) -> Self
pub fn BallFloatDecorated::new(BallFloat, decoration? : Decoration) -> Self
pub fn BallFloatDecorated::not_equal(Self, Self) -> Bool
pub fn BallFloatDecorated::output(Self, &Logger) -> Unit
pub fn BallFloatDecorated::overlap(Self, Self) -> OverlapState?
pub fn BallFloatDecorated::pos(Self) -> Self
pub fn BallFloatDecorated::pow(Self, Self) -> Self
pub fn BallFloatDecorated::pow_rev1(Self, Self, x? : Self) -> Self
pub fn BallFloatDecorated::pow_rev2(Self, Self, x? : Self) -> Self
pub fn BallFloatDecorated::pown(Self, Int32) -> Self
pub fn BallFloatDecorated::pown_rev(Self, Int32, x? : Self) -> Self
pub fn BallFloatDecorated::precedes(Self, Self) -> Bool
pub fn BallFloatDecorated::recip(Self) -> Self
pub fn BallFloatDecorated::rootn(Self, Int32) -> Self
pub fn BallFloatDecorated::round_ties_to_away(Self) -> Self
pub fn BallFloatDecorated::round_ties_to_even(Self) -> Self
pub fn BallFloatDecorated::sign(Self) -> Self
pub fn BallFloatDecorated::sin(Self) -> Self
pub fn BallFloatDecorated::sin_rev(Self, x? : Self) -> Self
pub fn BallFloatDecorated::sinh(Self) -> Self
pub fn BallFloatDecorated::sinpi(Self) -> Self
pub fn BallFloatDecorated::sqr(Self) -> Self
pub fn BallFloatDecorated::sqr_rev(Self, x? : Self) -> Self
pub fn BallFloatDecorated::sqrt(Self) -> Self
pub fn BallFloatDecorated::strict_less(Self, Self) -> Bool
pub fn BallFloatDecorated::strict_precedes(Self, Self) -> Bool
pub fn BallFloatDecorated::sub(Self, Self) -> Self
pub fn BallFloatDecorated::subset(Self, Self) -> Bool
pub fn BallFloatDecorated::tan(Self) -> Self
pub fn BallFloatDecorated::tan_rev(Self, x? : Self) -> Self
pub fn BallFloatDecorated::tanh(Self) -> Self
pub fn BallFloatDecorated::tanpi(Self) -> Self
pub fn BallFloatDecorated::to_ball_string(Self) -> String
pub fn BallFloatDecorated::to_exact_string(Self) -> String
pub fn BallFloatDecorated::to_string(Self) -> String
pub fn BallFloatDecorated::trunc(Self) -> Self
pub impl Add for BallFloatDecorated
pub impl Div for BallFloatDecorated
pub impl Eq for BallFloatDecorated
pub impl Mul for BallFloatDecorated
pub impl Show for BallFloatDecorated
pub impl Sub for BallFloatDecorated

#derive(Compare, Eq, @debug.Debug)
pub(all) enum Decoration {
  Ill
  Trv
  Def
  Dac
  Com
}
pub fn Decoration::equal(Self, Self) -> Bool
pub fn Decoration::not_equal(Self, Self) -> Bool
pub fn Decoration::output(Self, &Logger) -> Unit
pub fn Decoration::to_repr(Self) -> @debug.Repr
pub fn Decoration::to_string(Self) -> String
pub impl Show for Decoration

#derive(Eq, @debug.Debug)
pub(all) enum OverlapState {
  BothEmpty
  FirstEmpty
  SecondEmpty
  Before
  Meets
  Overlaps
  Starts
  ContainedBy
  Finishes
  Equals
  After
  MetBy
  OverlappedBy
  StartedBy
  Contains
  FinishedBy
}
pub fn OverlapState::equal(Self, Self) -> Bool
pub fn OverlapState::not_equal(Self, Self) -> Bool
pub fn OverlapState::to_repr(Self) -> @debug.Repr

// Type aliases

// Traits
```
<!-- generated-api-end -->
