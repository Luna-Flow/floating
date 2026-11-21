# interval tutorial

This tutorial teaches you to compute with guaranteed enclosures: you build an
interval that is known to contain an uncertain real number, push it through
arithmetic and elementary functions, and read back bounds that still contain
every possible exact result. Each section is a complete example with its
output. The mathematics behind the guarantees is in the
[design page](../design/interval.md); every item is listed in the
[API reference](../api/interval.md).

| I want to | Use |
| --- | --- |
| enclose a known point, known bounds or a measurement $c \pm r$ | `exact`, `from_bounds`, `new` ([Build intervals](#build-intervals)) |
| enclose a decimal constant such as 0.1 | directed `from_string_ctx` + `from_bounds` ([Enclose a decimal constant](#enclose-a-decimal-constant)) |
| compute with `+ - * /` and read the bounds | operators, `lower_bound`, `upper_bound`, `width` ([Compute and read the result](#compute-and-read-the-result)) |
| ask whether one uncertain value is certainly below another | `DefinitelyLt`, `MaybeEq`, `subset` ([Compare intervals](#compare-intervals)) |
| evaluate `sin`, `exp`, `ln`, … rigorously | `*_interval` and `try_*_interval` ([Evaluate elementary functions](#evaluate-elementary-functions)) |
| round a result into binary32 or binary64 | `IntervalContext`, `apply_ctx` ([Round to a target format](#round-to-a-target-format)) |
| know whether a function was defined and continuous on the input | `DecoratedInterval` ([Decorations](#decorations)) |
| write code for any enclosure type | `@lf_arith.DefinitelyLt` and friends ([Generic code](#generic-code-over-the-enclosure-traits)) |
| report the first failure of a multi-step computation | [`interval_checked`](interval_checked.md) |

## Quick start

Add the module:

```bash
moon add Luna-Flow/floating@0.11.0
```

Import the package, plus `bin_float`, which supplies the endpoint type (the
generic example below also uses `Luna-Flow/arithmetic` as `@lf_arith`):

```moonbit nocheck
import {
  "Luna-Flow/floating/bin_float",
  "Luna-Flow/floating/interval",
  "Luna-Flow/arithmetic" @lf_arith,
}
```

An `Interval` is a closed interval $[\underline{x}, \overline{x}]$ whose two
endpoints are `BinFloat` values. The examples on this page print an interval
with this helper: it writes the lower endpoint rounded down and the upper
endpoint rounded up, so the printed decimal interval still contains the stored
one.

```moonbit
///|
fn show(x : @interval.Interval, digits : Int) -> String {
  if x.is_empty() {
    return "[empty]"
  }
  let down = @bin_float.BinaryContext::new(
    precision=x.precision(),
    rounding=@bin_float.BinaryRoundingMode::RoundTowardNegative,
  )
  let up = @bin_float.BinaryContext::new(
    precision=x.precision(),
    rounding=@bin_float.BinaryRoundingMode::RoundTowardPositive,
  )
  let lo = x.lower_bound().to_decimal_string_ctx(digits, down).0
  let hi = x.upper_bound().to_decimal_string_ctx(digits, up).0
  "[" + lo + ", " + hi + "]"
}
```

The smallest useful program encloses $1/3$ at 53 bits:

```moonbit
///|
test "quick start: enclose one third" {
  let one = @interval.Interval::from_int(1, precision=53)
  let three = @interval.Interval::from_int(3, precision=53)
  let third = one / three
  inspect(show(third, 20), content="[3.3333333333333331482e-1, 3.3333333333333337035e-1]")
  // The endpoints are neighbouring 53-bit numbers: the width is one unit
  // in the last place, 2^-54.
  inspect(third.width().to_string(), content="1p-54")
}
```

No `BinFloat` with 53 bits equals $1/3$, so the result is the smallest
53-bit interval around it: the lower endpoint is $1/3$ rounded down, the upper
endpoint $1/3$ rounded up.

## Everyday tasks

### Build intervals

Choose the constructor by what you know about the value.

```moonbit
///|
test "constructors" {
  let two = @bin_float.BinFloat::from_int(2, precision=53)
  let five = @bin_float.BinFloat::from_int(5, precision=53)
  // A known point: the singleton {2}.
  let point = @interval.Interval::exact(two)
  inspect(point.is_singleton(), content="true")
  // Known bounds: [2, 5].
  let range = @interval.Interval::from_bounds(two, five)
  inspect(show(range, 3), content="[2.00e+0, 5.00e+0]")
  // A measurement: 5 +/- 2, stored as the endpoints [3, 7].
  let measured = @interval.Interval::new(five, two)
  inspect(show(measured, 3), content="[3.00e+0, 7.00e+0]")
  inspect(measured.midpoint().to_string(), content="5p0")
  inspect(measured.radius().to_string(), content="1p1")
  // Untrusted bounds: reversed endpoints are an error value, not an abort.
  let reversed = @interval.Interval::try_from_bounds(five, two)
  inspect(reversed is Err(_), content="true")
}
```

`from_bounds` and `exact` abort on invalid input (a NaN endpoint, reversed
bounds, a non-finite point); their `try_` forms return the same condition as an
`ArithmeticError`, and so does `try_new(center, radius)` for a non-finite center
or a negative or non-finite radius. `new(center, radius)` is a constructor view:
the stored value is always the endpoint pair, and `midpoint()` / `radius()` read
the midpoint–radius form back as IEEE 1788-2015 12.12.8 defines it. The whole real line and the empty set are
`Interval::entire()` and `Interval::empty()`.

### Enclose a decimal constant

`Interval::from_double(0.1)` encloses the binary64 number nearest to $0.1$,
which is not $0.1$. To enclose the decimal value itself, round the decimal
string once down and once up, and use the two results as bounds.

```moonbit
///|
test "enclose decimal 0.1" {
  let down = @bin_float.BinaryContext::new(
    precision=53,
    rounding=@bin_float.BinaryRoundingMode::RoundTowardNegative,
  )
  let up = @bin_float.BinaryContext::new(
    precision=53,
    rounding=@bin_float.BinaryRoundingMode::RoundTowardPositive,
  )
  let lo = @bin_float.BinFloat::from_string_ctx("0.1", down).unwrap().0
  let hi = @bin_float.BinFloat::from_string_ctx("0.1", up).unwrap().0
  let tenth = @interval.Interval::from_bounds(lo, hi)
  inspect(show(tenth, 20), content="[9.9999999999999991673e-2, 1.0000000000000000556e-1]")
  // The binary64 double 0.1 is one of the two endpoints, so the singleton
  // built from it misses the other half of the uncertainty.
  let double_tenth = @interval.Interval::from_double(0.1)
  inspect(double_tenth.is_singleton(), content="true")
  inspect(double_tenth.subset(tenth), content="true")
}
```

Do this at every boundary where data enters from decimal text or from a
rounded computation; inside the interval domain the guarantee is then kept
automatically.

### Compute and read the result

The arithmetic operators return an interval that contains every result of the
operation applied to points of the operands.

```moonbit
///|
test "arithmetic on intervals" {
  let x = @interval.Interval::from_bounds(
    @bin_float.BinFloat::from_int(1, precision=53),
    @bin_float.BinFloat::from_int(2, precision=53),
  )
  let y = @interval.Interval::from_bounds(
    @bin_float.BinFloat::from_int(-3, precision=53),
    @bin_float.BinFloat::from_int(5, precision=53),
  )
  inspect(show(x + y, 3), content="[-2.00e+0, 7.00e+0]")
  inspect(show(x - y, 3), content="[-4.00e+0, 5.00e+0]")
  inspect(show(x * y, 3), content="[-6.00e+0, 1.00e+1]")
  // y contains 0 in its interior, so x / y is the whole real line.
  inspect(show(x / y, 3), content="[-inf, inf]")
  // y / x is bounded because x stays away from 0.
  inspect(show(y / x, 3), content="[-3.00e+0, 5.00e+0]")
}
```

Read the result with `lower_bound()` / `upper_bound()` for the endpoints,
`width()` for $\overline{x} - \underline{x}$ rounded up, `midpoint()` for a
representative point, and `is_common_interval()` / `is_entire()` / `is_empty()` for
the shape.

### Compare intervals

An interval stands for an unknown point inside it, so "is $x < y$?" has three
answers: certainly, possibly, or certainly not. The relations say which.

```moonbit
///|
test "relations" {
  let a = @interval.Interval::from_bounds(
    @bin_float.BinFloat::from_int(9, precision=53),
    @bin_float.BinFloat::from_int(11, precision=53),
  )
  let b = @interval.Interval::from_bounds(
    @bin_float.BinFloat::from_int(10, precision=53),
    @bin_float.BinFloat::from_int(16, precision=53),
  )
  let c = @interval.Interval::from_bounds(
    @bin_float.BinFloat::from_int(12, precision=53),
    @bin_float.BinFloat::from_int(13, precision=53),
  )
  inspect(@lf_arith.DefinitelyLt::definitely_lt(a, c), content="true") // every point of a < every point of c
  inspect(@lf_arith.DefinitelyLt::definitely_lt(a, b), content="false") // not certain ...
  inspect(@lf_arith.MaybeEq::maybe_eq(a, b), content="true") // ... because they share points
  inspect(c.subset(b), content="true")
  inspect(a.is_member(@bin_float.BinFloat::from_int(10, precision=53)), content="true")
  debug_inspect(a.overlap(b), content="Overlaps")
}
```

`is_member` tests a point; `subset`, `interior` and `==` (the `equal` of IEEE 1788) compare sets;
`DefinitelyLt::definitely_lt` and `DefinitelyLe::definitely_le` of
Luna-Flow/arithmetic hold only when the order holds for every pair of points;
`MaybeEq::maybe_eq` (and `Overlaps::overlaps`) holds when some pair may be
equal; `disjoint`, `precedes` and `strict_precedes` are the relations of
IEEE 1788 and are true for an empty operand; `overlap` gives the full IEEE 1788 classification
of two intervals.

### Evaluate elementary functions

Functions are evaluated so that the result contains $f(\xi)$ for every $\xi$
in the argument where $f$ is defined. Extrema inside the interval and poles are
taken into account.

```moonbit
///|
test "elementary functions" {
  let zero_to_four = @interval.Interval::from_bounds(
    @bin_float.BinFloat::from_int(0, precision=53),
    @bin_float.BinFloat::from_int(4, precision=53),
  )
  // sin reaches its maximum 1 at pi/2, which lies inside [0, 4].
  inspect(show(zero_to_four.sin(), 6), content="[-7.56803e-1, 1.00000e+0]")
  inspect(show(zero_to_four.exp(), 6), content="[1.00000e+0, 5.45982e+1]")
  // ln is undefined at 0; the result encloses ln over (0, 4].
  inspect(show(zero_to_four.ln(), 6), content="[-inf, 1.38630e+0]")
  // [1, 2] contains the pole pi/2 of tan.
  let one_to_two = @interval.Interval::from_bounds(
    @bin_float.BinFloat::from_int(1, precision=53),
    @bin_float.BinFloat::from_int(2, precision=53),
  )
  inspect(one_to_two.tan().is_entire(), content="true")
  // Outside the domain the result is the empty set.
  let negative = zero_to_four.neg() - one_to_two
  inspect(negative.sqrt().is_empty(), content="true")
}
```

Every `*_interval` function has a total form, which always returns a valid
enclosure at any precision, and most also have a `try_*_interval` form. They
use the same kernel and give the same interval whenever the certified
evaluation succeeds. When it runs out of its work budget the total form widens
to the range of the function (for example $[-1, 1]$ for `sin`), and
the `try_` form returns an `ArithmeticError` describing the failure.

### Round to a target format

`IntervalContext` describes a binary format (precision and exponent range).
`apply_ctx` rounds an interval outward into it and reports what happened in
`IntervalFlags`; to round the result of an operation, apply the context to it.

```moonbit
///|
test "round into binary32" {
  let ctx = @interval.IntervalContext::binary32()
  let x = @interval.Interval::from_int(1, precision=64)
  let y = @interval.Interval::from_int(3, precision=64)
  let (q, flags) = (x / y).apply_ctx(ctx)
  inspect(q.precision(), content="24")
  inspect(show(q, 9), content="[3.33333313e-1, 3.33333344e-1]")
  inspect(flags.inexact(), content="true")
  inspect(flags.overflow(), content="false")
  // A bound beyond the binary32 range becomes infinite (or the largest
  // finite value, on the side where that is still an enclosure).
  let big = @interval.Interval::from_double(1.0e300)
  let (clamped, big_flags) = big.apply_ctx(ctx)
  inspect(show(clamped, 9), content="[3.40282346e+38, inf]")
  inspect(big_flags.overflow(), content="true")
}
```

## Going further

### Decorations

`DecoratedInterval` pairs an interval with an IEEE 1788 decoration that
records what is known about the function evaluation that produced it: `com`
(defined, continuous and bounded), `dac` (defined and continuous), `def`
(defined), `trv` (nothing known) and `ill` (the special value NaI, "not an
interval").

```moonbit
///|
test "decorated evaluation" {
  let x = @interval.DecoratedInterval::new(
    @interval.Interval::from_bounds(
      @bin_float.BinFloat::from_int(-1, precision=53),
      @bin_float.BinFloat::from_int(4, precision=53),
    ),
  )
  inspect(x.decoration(), content="com")
  // sqrt is only defined on part of [-1, 4]: the bare result [0, 2] is
  // correct, but the decoration drops to trv.
  let root = x.sqrt()
  inspect(show(root.interval(), 3), content="[-0.00e+0, 2.00e+0]")
  inspect(root.decoration(), content="trv")
  // Decorations only go down: later operations cannot restore com.
  inspect((root + x).decoration(), content="trv")
  // NaI absorbs everything and is different from the empty set.
  let nai = @interval.DecoratedInterval::nai()
  inspect((nai + x).is_nai(), content="true")
  inspect((nai + x).is_empty(), content="false")
}
```

Use decorations when a caller must learn whether a result is backed by a
function that was defined and continuous on the whole input — the condition
under which interval results prove existence theorems such as Brouwer's fixed
point theorem. When only the enclosure matters, bare `Interval` is simpler.

### Generic code over the enclosure traits

`Interval` implements the enclosure relations of
[`Luna-Flow/arithmetic`](https://lunaflow.cn/en/arithmetic/) (`Contains`,
`Overlaps`, `DefinitelyLt`, `DefinitelyLe`, `MaybeEq`), so code written
against those traits works for any enclosure type.

```moonbit
///|
fn[T : @lf_arith.DefinitelyLt] certainly_increasing(xs : Array[T]) -> Bool {
  for i in 1..<xs.length() {
    if !@lf_arith.DefinitelyLt::definitely_lt(xs[i - 1], xs[i]) {
      return false
    }
  }
  true
}

///|
test "generic enclosure code" {
  let xs = [1, 3, 5].map(fn(n) {
    @interval.Interval::from_int(n, precision=53) /
    @interval.Interval::from_int(3, precision=53)
  })
  inspect(certainly_increasing(xs), content="true")
  // The trait form of contains tests set inclusion, unlike the
  // point-taking method Interval::is_member.
  inspect(@lf_arith.Contains::contains(xs[2], xs[2]), content="true")
}
```

The checked capabilities `DivChecked`, `PowNatChecked` and `PowIntChecked`
take an `@lf_arith.ArithmeticContext`; its `precision` sets the result
precision. They never fail for `Interval`: division by an interval containing
zero returns an unbounded enclosure.

### Checked pipelines

When a computation has several steps that may fail (invalid construction,
uncertified elementary functions), the companion package
[`interval_checked`](interval_checked.md) threads the first error through a
chain of operations so that you test for failure once at the end.

### Precision and cost

Each interval carries a working `precision` in bits; results of binary
operations use the larger precision of the two operands. Arithmetic costs a
few endpoint operations at that precision. Elementary functions evaluate the certified `bin_float` kernels at the
interval's precision (with their own guard bits, up to 12 work precisions on
hard inputs), so they cost several times more than one multiplication.
Raising the precision narrows the rounding part of the width, but not the part
that comes from the width of the inputs.

## Common pitfalls

**`x - x` is not zero.** Interval arithmetic treats the two operands as
independent unknowns, so $[1, 2] - [1, 2] = [-1, 1]$. The same holds for
`x * x`, which is wider than `x.sqr()` when `x` contains zero:

```moonbit
///|
test "dependency" {
  let x = @interval.Interval::from_bounds(
    @bin_float.BinFloat::from_int(-1, precision=53),
    @bin_float.BinFloat::from_int(2, precision=53),
  )
  inspect(show(x - x, 3), content="[-3.00e+0, 3.00e+0]")
  inspect(show(x * x, 3), content="[-2.00e+0, 4.00e+0]")
  inspect(show(x.sqr(), 3), content="[-0.00e+0, 4.00e+0]")
  inspect(show(x.pown(2), 3), content="[-0.00e+0, 4.00e+0]")
}
```

Rewrite expressions so that each uncertain quantity appears once, and prefer
`sqr`, `pown` and the elementary functions over hand-written products.

**`==` compares sets, not representations.** `a == b` is true when the two
intervals are the same set, whatever their precision tags (IEEE 1788-2015
`equal`); use `a.identical(b)` when the precision tag matters too. On decorated
intervals `==` is false for NaI, even against itself.

**`is_member` takes a point.** The method `Interval::is_member` tests a
`BinFloat` point. Set inclusion is `subset` (or the trait method
`@lf_arith.Contains::contains`, which means "contains as a subset").

**Intervals are not ordered.** There is no total order on intervals; never sort
them with `less` (an IEEE 1788 set relation) as if it were a comparison of
numbers.

**Unbounded and empty intervals have no useful center.** `midpoint()`,
`radius()`, `width()`, `magnitude()` and `mignitude()` are total and follow
IEEE 1788-2015 12.12.8 instead of aborting: NaN for the empty set, `midpoint()`
0 for the whole line and the largest finite value (with the sign of the
unbounded side) for a half-bounded interval, `radius()` and `width()`
$+\infty$ for any unbounded interval. Test `is_empty()` and
`is_common_interval()` first when a NaN or an infinity would be a problem;
`midpoint_ctx` takes the result format as an `IntervalContext`.

**Integers wider than the precision.** `from_int(n, precision=p)` and
`from_coefficient` enclose `n` exactly, but when `n` needs more than $p$ bits
the result is the two-point interval of its $p$-bit neighbours, not a point.
At the default of 53 bits every `Int32` is a point, but a `BinCoeff` wider than
53 bits, or an explicit small precision, is not: pass a precision at least as
large as the bit length of the integer.

**Inputs from `Double`.** `from_double(x)` encloses the binary value of `x`
exactly; it cannot know which decimal number `x` approximated. Enclose decimal
data as in [Enclose a decimal constant](#enclose-a-decimal-constant).

## Next steps

- The [design page](../design/interval.md) proves why these results are
  enclosures, derives the endpoint formulas, and explains decorations and
  certified elementary functions.
- The [API reference](../api/interval.md) documents every item with its
  special cases.
- [`interval_checked`](interval_checked.md) composes fallible interval
  operations; [`bin_float`](bin_float.md) is the endpoint arithmetic.
- [Conformance](../conformance/interval.md) states what the IEEE 1788 test
  corpus covers.
