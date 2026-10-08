# bin_float tutorial

This tutorial teaches you to compute with `BinFloat`, the arbitrary-precision
binary floating-point type of `floating`: build exact values, run a
calculation in an IEEE 754 format such as binary32 with its status flags,
read and write interchange bits and decimal text, and call correctly rounded
elementary functions. Every example compiles and shows its output. The
mathematics behind the rounding rules is on the
[design page](../design/bin_float.md), and every function is listed in the
[API reference](../api/bin_float.md).

## Quick start

Add the module and import the package in your `moon.pkg`:

```text
moon add Luna-Flow/floating@0.8.0
```

```text
import {
  "Luna-Flow/floating/bin_float",
}
```

The smallest useful program divides one by three, once with 53 bits and once
in the binary32 format, and prints both results as the shortest decimal that
reads back exactly:

```moonbit
///|
test "one third, two precisions" {
  let one = @bin_float.BinFloat::one()
  let three = @bin_float.BinFloat::from_int(3)
  inspect((one / three).to_shortest_string(), content="0.3333333333333333")
  let binary32 = @bin_float.BinaryContext::binary32()
  let (third, flags) = one.div_ctx(three, binary32)
  inspect(third.to_shortest_string_ctx(binary32), content="0.33333334")
  inspect(flags.inexact(), content="true")
}
```

The operator `/` rounds to nearest-even at the precision of its operands (53
bits by default). `div_ctx` rounds under the binary32 context and also returns
the IEEE flags; here `inexact` says that one third is not a binary number.

## Everyday tasks

### Build exact values

A finite `BinFloat` is $c \cdot 2^{e}$ with an integer coefficient $c$ and
an exponent $e$. `make` takes both plus a precision; `to_string` prints the
stored form `c p e`, which is exact.

```moonbit
///|
test "exact dyadic values" {
  let x = @bin_float.BinFloat::make(
    @bin_float.BinCoeff::from_uint64(3UL),
    -1,
    32,
  )
  inspect(x, content="3p-1")
  inspect(x.to_shortest_string(), content="1.5")
  // Powers of two move into the exponent: 12 = 3 * 2^2.
  let twelve = @bin_float.BinFloat::from_int(12)
  inspect("\{twelve.coefficient()} \{twelve.exponent2()}", content="3 2")
}
```

Read decimal input with `from_string`, which rounds the decimal value itself.
Converting through a host `Double` rounds twice when you want a precision
other than 53 bits, and `from_double` faithfully keeps the host's binary
approximation:

```moonbit
///|
test "decimal input" {
  let tenth = @bin_float.BinFloat::from_string("0.1").unwrap()
  inspect(tenth, content="3602879701896397p-55")
  let tenth_200 = @bin_float.BinFloat::from_string("0.1", precision=200).unwrap()
  inspect(tenth_200.precision(), content="200")
  let host = @bin_float.BinFloat::from_double(0.1)
  // Same 53-bit value, but a 200-bit parse is much closer to one tenth.
  inspect(host.compare(tenth), content="0")
  inspect(host.compare(tenth_200), content="1")
}
```

### Compute in an IEEE format and keep the flags

A `BinaryContext` fixes the precision, exponent range, rounding direction and
tininess rule of an operation. The `*_ctx` methods return the value and the
flags of that one operation; combine flags yourself to accumulate them.

```moonbit
///|
test "a binary16 computation with accumulated flags" {
  let half = @bin_float.BinaryContext::binary16()
  let x = @bin_float.BinFloat::from_int(60000)
  let (sum, add_flags) = x.add_ctx(x, half)
  let (product, mul_flags) = @bin_float.BinFloat::from_string("0.001")
    .unwrap()
    .mul_ctx(@bin_float.BinFloat::from_string("0.0001").unwrap(), half)
  let all = add_flags.combine(mul_flags)
  inspect(sum, content="inf")
  inspect(product.to_shortest_string_ctx(half), content="1e-7")
  inspect(
    "\{all.overflow()} \{all.underflow()} \{all.inexact()}",
    content="true true true",
  )
}
```

$120000$ exceeds the largest binary16 value $65504$, so the sum overflows to
infinity. The product $10^{-7}$ lies below the smallest normal binary16
number $2^{-14} \approx 6.1 \cdot 10^{-5}$, so it is rounded on the subnormal
grid and raises underflow. The rounding direction changes the overflow
result: toward zero it stays at the largest finite value.

```moonbit
///|
test "overflow depends on the rounding direction" {
  let toward_zero = @bin_float.BinaryContext::binary16(
    rounding=@bin_float.BinaryRoundingMode::RoundTowardZero,
  )
  let x = @bin_float.BinFloat::from_int(60000)
  let (sum, flags) = x.add_ctx(x, toward_zero)
  // 2047 * 2^5 = 65504, the largest finite binary16 value.
  inspect(sum, content="2047p5")
  inspect(flags.overflow(), content="true")
}
```

### Read and write interchange bits

Use `BinaryInterchange` when a file or protocol carries binary16, binary32,
binary64 or binary128 bit patterns. It never goes through a host `Double`,
so signaling NaNs, payloads and binary128 survive.

```moonbit
///|
test "binary32 bits in and out" {
  let format = @bin_float.BinaryInterchangeFormat::Binary32
  let value = @bin_float.BinaryInterchange::from_hex("3FC00000", format)
    .unwrap()
    .to_bin_float()
  inspect(value, content="3p-1")
  let (doubled, flags) = value.add_ctx(value, format.context())
  let (bits, encode_flags) = doubled.to_interchange(format)
  inspect(bits.to_hex(), content="40400000")
  inspect(flags.combine(encode_flags).to_testfloat_bits(), content="0")
}
```

Encoding rounds into the format, so it returns flags as well. Decoding is
always exact.

### Print decimal text

`to_shortest_string_ctx` gives the shortest decimal that reads back as the
same value in a format; for binary64 it matches the host formatter.
`to_decimal_string_ctx` gives a fixed number of significant digits, rounded
in the context's direction, and reports whether digits were dropped.

```moonbit
///|
test "decimal output" {
  let ctx = @bin_float.BinaryContext::binary64()
  let tenth = @bin_float.BinFloat::from_string("0.1").unwrap()
  inspect(tenth.to_shortest_string_ctx(ctx), content="0.1")
  let (exact, exact_flags) = tenth.to_decimal_string_ctx(55, ctx)
  inspect(exact, content="1.000000000000000055511151231257827021181583404541015625e-1")
  inspect(exact_flags.inexact(), content="false")
  let up = @bin_float.BinaryContext::binary64(
    rounding=@bin_float.BinaryRoundingMode::RoundTowardPositive,
  )
  let (short, _) = tenth.to_decimal_string_ctx(3, up)
  inspect(short, content="1.01e-1")
}
```

Every binary number has a finite decimal expansion, so 55 digits print the
binary64 value of `0.1` exactly.

### Call elementary functions

Each elementary function has a plain form, a `*_ctx` form and a `try_*_ctx`
form. All three return the correctly rounded result. They differ only in how
a domain error or an exhausted refinement budget is reported: the plain and
`*_ctx` forms return a quiet NaN with `invalid_operation`, while `try_*_ctx`
returns an `@lf_arith.ArithmeticError` that says what went wrong.

```moonbit
///|
test "certified elementary functions" {
  let ctx = @bin_float.BinaryContext::binary64()
  let two = @bin_float.BinFloat::from_int(2)
  inspect(two.ln().to_shortest_string(), content="0.6931471805599453")
  let (ln2, _) = two.ln_ctx(@bin_float.BinaryContext::binary128())
  inspect(ln2.to_shortest_string(), content="0.6931471805599453094172321214581766")
  match @bin_float.BinFloat::from_int(-2).try_ln_ctx(ctx) {
    Ok(_) => fail("ln(-2) is not real")
    Err(error) => inspect(error.message, content="ln requires a positive value")
  }
  let (sine, flags) = @bin_float.BinFloat::from_string("0.5")
    .unwrap()
    .sinpi_ctx(ctx)
  inspect("\{sine} \{flags.inexact()}", content="1p0 false")
}
```

`sinpi(0.5)` is exactly one, and the function knows it: exact results raise no
`inexact` flag.

## Going further

### Enclose a real number with directed rounding

Rounding toward negative and toward positive infinity brackets the exact
result. This is how you build a guaranteed enclosure without an interval
library:

```moonbit
///|
test "an enclosure of the square root of two" {
  let two = @bin_float.BinFloat::from_int(2)
  let (low, high) = @bin_float.sqrt_bounds_for_precision(two, 20).unwrap()
  inspect("\{low} \{high}", content="741455p-19 46341p-15")
  let down = @bin_float.BinaryContext::unbounded(
    20,
    rounding=@bin_float.BinaryRoundingMode::RoundTowardNegative,
  )
  let (low_exp, _) = two.exp_ctx(down)
  let up = @bin_float.BinaryContext::unbounded(
    20,
    rounding=@bin_float.BinaryRoundingMode::RoundTowardPositive,
  )
  let (high_exp, _) = two.exp_ctx(up)
  inspect(low_exp.compare(high_exp), content="-1")
}
```

`ball_float` packages this idea as midpoint–radius arithmetic; see the
[ball_float tutorial](ball_float.md).

### Use fused and exact IEEE operations

`fma` rounds $x y + z$ once, so it recovers the rounding error of a product.
`remainder` is always exact for operands of one precision.

```moonbit
///|
test "fma recovers the rounding error of a product" {
  let ctx = @bin_float.BinaryContext::binary64()
  let a = @bin_float.BinFloat::from_string("0.1").unwrap()
  let (p, _) = a.mul_ctx(a, ctx)
  let (error, flags) = a.fma_ctx(a, p.neg(), ctx)
  inspect(error.to_shortest_string(), content="-8.326672684688674e-19")
  // The error of a rounded product is exactly representable (Dekker).
  inspect(flags.inexact(), content="false")
  let r = @bin_float.BinFloat::one().remainder(a)
  inspect(r.to_hex(), content="-0x1p-54")
}
```

The two-product error term is the basis of compensated algorithms (Kahan
summation, double-double arithmetic); the design page shows why it is exact.

### Watch underflow and tininess

IEEE 754 lets an implementation detect tininess before or after rounding,
and the choice changes the underflow flag for values just below the smallest
normal number. `BinaryContext` lets you choose:

```moonbit
///|
test "tininess before and after rounding" {
  // 2^-14 - 2^-27 lies below the smallest binary16 normal 2^-14 but
  // rounds up to it.
  let x = @bin_float.BinFloat::make(
    @bin_float.BinCoeff::from_uint64(8191UL),
    -27,
    13,
  )
  let after = @bin_float.BinaryContext::binary16()
  let before = @bin_float.BinaryContext::binary16(
    tininess=@bin_float.TininessDetection::BeforeRounding,
  )
  let (a, a_flags) = x.round_ctx(after)
  let (b, b_flags) = x.round_ctx(before)
  inspect("\{a} \{a_flags.underflow()}", content="1p-14 false")
  inspect("\{b} \{b_flags.underflow()}", content="1p-14 true")
}
```

The value is the same; only the flag differs. Hardware differs too: x86
detects tininess after rounding and ARM before rounding, and TestFloat checks
both rules.

### Write generic code

`BinFloat` implements the `@def.Floating` trait shared by all scalar cores of
`floating`, and the checked and contextual traits of `@lf_arith`. Code
written against those traits runs on `BinFloat`, `Decimal` and the other
cores:

```moonbit
///|
fn[F : @lf_arith.DivContextual] reciprocal(
  x : F,
  ctx : @lf_arith.ArithmeticContext,
  one : F,
) -> Result[F, @lf_arith.ArithmeticError] {
  one.div_contextual(x, ctx).map(fn(outcome) { outcome.value })
}

///|
test "generic reciprocal on BinFloat" {
  let ctx = @lf_arith.ArithmeticContext::new(24, e_min=-126, e_max=127)
  let r = reciprocal(
    @bin_float.BinFloat::from_int(3),
    ctx,
    @bin_float.BinFloat::one(),
  ).unwrap()
  inspect(r.to_shortest_string(), content="0.33333334")
  inspect(
    reciprocal(@bin_float.BinFloat::zero(), ctx, @bin_float.BinFloat::one()) is Err(_),
    content="true",
  )
}
```

The contextual traits turn the IEEE `division_by_zero` and
`invalid_operation` flags into errors and report the other flags as
diagnostics. For a whole pipeline that stops at the first error, use
[`bin_float_checked`](bin_float_checked.md).

### Performance

Precision costs time roughly like integer multiplication of that many bits.
The coefficient kernel switches automatically from schoolbook to Karatsuba,
Toom-3 and number-theoretic transforms, so thousands of bits are practical.
Elementary functions refine their working precision until the result is
certain, and the first attempt succeeds for almost every input. Pick one
precision for an algorithm instead of widening and narrowing repeatedly. The
[performance page](../performance/bin_float.md) records measurements.

## Common pitfalls

- **`==` compares representations.** `BinFloat` derives `Eq`, so `1` at 53
  bits is not `==` to `1` at 24 bits, $-0 \ne +0$, and a NaN equals an
  identical NaN. Use `compare(x, y) == 0` for numerical equality, or
  `equal_quiet` for the IEEE predicate.
- **`compare` puts NaN last.** It never aborts: every NaN compares equal to
  every NaN and greater than every number, so `nan > x` is true. Use
  `compare_checked`, `compare_quiet` or `less_quiet` when NaN must be
  unordered.
- **Plain operators ignore your format.** `x + y` works at the larger operand
  precision with an exponent range of about $2^{\pm 2^{30}}$; it never
  overflows at binary32 limits. Use `add_ctx` with a format context.
- **`from_double(0.1)` is not one tenth.** It is the binary64 value the host
  already rounded. Parse decimal text with `from_string`.
- **`to_string` is not decimal.** It prints `3602879701896397p-55`. Use
  `to_shortest_string` or `to_decimal_string_ctx` for people.
- **`from_hex` has no hexadecimal point.** `0x3p-1` means $3 \cdot 2^{-1}$;
  `0x1.8p0` is rejected.
- **`with_precision` hides flags.** Use `round_ctx` when you need to know that
  narrowing was inexact or overflowed.
- **Known defects.** On the current branch `acos` recurses without end on a
  NaN, an infinity or $|x| > 1$, `atan2` mishandles signed zeros in two IEEE
  special cases, and `pow` rejects a negative base with an integral exponent
  of magnitude at least $2^{31}$ and a base of $-0$ with most non-integral
  exponents, and flags exact results such as $16^{3/4} = 8$ as inexact. The [API reference](../api/bin_float.md#binfloatasin-binfloatacos-binfloatatan-binfloatatan2)
  lists the details.

## Next steps

- [bin_float design](../design/bin_float.md): the error model, how correct
  rounding is decided, overflow and tininess, certified elementary functions.
- [bin_float API](../api/bin_float.md): every item with its special values.
- [bin_float conformance](../conformance/bin_float.md): the TestFloat and MPFR
  evidence.
- [bin_float_checked tutorial](bin_float_checked.md) and
  [ball_float tutorial](ball_float.md): pipelines and enclosures built on
  `BinFloat`.
- [Luna-Flow arithmetic](https://lunaflow.cn/en/arithmetic/): the checked and
  contextual traits.
