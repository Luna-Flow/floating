# bin_float API

## Purpose

`bin_float` is the binary floating-point core of `floating`. A `BinFloat` is
a signed dyadic number $(-1)^s \cdot c \cdot 2^{e}$ with an arbitrary-precision
coefficient, an attached working precision, and the IEEE 754 special values
(signed zero, infinities, quiet and signaling NaNs with payloads). Every
arithmetic operation rounds the exact result once. A `BinaryContext` gives the
precision, exponent range, rounding direction and tininess rule of one
operation, and the `*_ctx` methods return the IEEE status flags with the value.
The [tutorial](../tutorial/bin_float.md) shows the common workflows and the
[design page](../design/bin_float.md) derives the rounding, range and
certification rules used below. The verified IEEE 754 scope is listed in
[conformance](../conformance/bin_float.md).

Throughout this page, $p$ is a precision in bits, $\circ(x)$ is the rounding of
the real number $x$ under the active context, and "the flags" are the five IEEE
exception flags of a `BinaryFlags` value.

## Importing

Add the package to your `moon.pkg`, together with the two packages whose types
appear in its signatures:

```moonbit nocheck
import {
  "Luna-Flow/floating/bin_float",
  "Luna-Flow/floating/def",
  "Luna-Flow/arithmetic" @lf_arith,
}
```

The examples call the package as `@bin_float.`. `@lf_arith` is
`Luna-Flow/arithmetic`: its `RoundingMode`, `ArithmeticContext` and
`ArithmeticError` types appear in several signatures, where the interface file
prints the package as `@arithmetic`. `@def` is `Luna-Flow/floating/def`, which
provides `Sign`, `PartialOrder` and the `Floating` trait. No helper functions
are shared between examples.

## Three ways to call an operation

Most operations come in up to three forms with one numerical algorithm behind
them.

| Form | Example | Context | Result |
| --- | --- | --- | --- |
| plain | `x + y`, `x.exp()` | unbounded exponent range, nearest-even, precision of the operands | the value only |
| contextual | `x.add_ctx(y, ctx)`, `x.exp_ctx(ctx)` | the given `BinaryContext` | `(value, flags)` |
| checked | `x.try_exp_ctx(ctx)`, `x.div_checked(y)` | the given context, or the plain one | `Result` with an `@lf_arith.ArithmeticError` |

The plain form of a binary operation works at the larger precision of the two
operands (the largest of three for `fma`). Its exponent range is the
implementation range below, so it overflows to an infinity and underflows to a
signed zero or a tiny value only at about $2^{\pm 2^{30}}$.

## Values and limits

### `binary_implementation_e_max`, `binary_implementation_e_min`

The largest and smallest exponent of the leading bit that a finite `BinFloat`
may carry.

```mbti
pub let binary_implementation_e_max : Int
pub let binary_implementation_e_min : Int
```

They are $2^{30}-1 = 1073741823$ and $-(2^{30}-1)$. An unbounded context, and
every plain operation, uses them as $e_{\max}$ and $e_{\min}$: a result whose
leading bit would lie above $e_{\max}$ overflows, and below $e_{\min}$ the
value is subnormal with quantum $2^{e_{\min}-p+1}$. A context with explicit
bounds is intersected with this range.

### `binary_precision_max`

The largest precision a `BinaryContext` accepts.

```mbti
pub let binary_precision_max : Int
```

It is $2^{28} = 268435456$ bits. Together with the exponent range it keeps
every coefficient exponent inside the 32-bit `Int` range.

## Exact coefficients

### `BinCoeff`

A non-negative arbitrary-precision integer, used as the coefficient of a
`BinFloat` and as the bit pattern of an interchange encoding.

```mbti
pub struct BinCoeff {
  // private fields
} derive(@debug.Debug)
```

All arithmetic on `BinCoeff` is exact. On the native, LLVM and Wasm targets
the value is an inline 64- or 128-bit word or an array of 32-bit limbs; on
JavaScript it is a host `bigint`. The representation is not observable, and
the algorithm selection (schoolbook, Karatsuba, Toom-3, number-theoretic
transform, staged division) is described in the
[design page](../design/bin_float.md#the-coefficient-kernel). Operations whose
mathematical result could be negative or undefined are checked and return
`Err` with a message instead.

### `BinCoeff::zero`, `BinCoeff::one`, `BinCoeff::from_uint64`

Build a coefficient from a machine value.

```mbti
pub fn BinCoeff::zero() -> Self
pub fn BinCoeff::one() -> Self
pub fn BinCoeff::from_uint64(UInt64) -> Self
```

### `BinCoeff::parse`, `BinCoeff::to_string`, `BinCoeff::to_radix_string`

Convert between a coefficient and digits.

```mbti
pub fn BinCoeff::parse(String, radix? : Int) -> Result[Self, String]
pub fn BinCoeff::to_string(Self) -> String
pub fn BinCoeff::to_radix_string(Self, Int) -> String
```

`parse` reads a digit string in base `radix` (default 10, letters for digits
above 9, an optional leading `+`); an empty string, a `-` sign, a digit
outside the radix or a radix outside $[2, 36]$ is an `Err`. `to_string` prints
base 10 and `to_radix_string` any radix in $[2, 36]$, in lower case without a
prefix; it aborts for another radix.

### `BinCoeff::from_bytes_be`, `BinCoeff::to_bytes_be`

Convert between a coefficient and big-endian bytes.

```mbti
pub fn BinCoeff::from_bytes_be(BytesView) -> Self
pub fn BinCoeff::to_bytes_be(Self) -> Bytes
```

`to_bytes_be` uses the minimal number of bytes; leading zero bytes are ignored
by `from_bytes_be`.

### `BinCoeff::to_uint64`

Returns the value as a `UInt64`, or `None` when it needs more than 64 bits.

```mbti
pub fn BinCoeff::to_uint64(Self) -> UInt64?
```

### `BinCoeff::is_zero`, `BinCoeff::bit_length`, `BinCoeff::ctz`, `BinCoeff::test_bit`

Bit-level queries.

```mbti
pub fn BinCoeff::is_zero(Self) -> Bool
pub fn BinCoeff::bit_length(Self) -> Int
pub fn BinCoeff::ctz(Self) -> Int
pub fn BinCoeff::test_bit(Self, Int) -> Bool
```

`bit_length` is $\lfloor \log_2 c \rfloor + 1$ for $c > 0$ and $0$ for zero.
`ctz` counts trailing zero bits (the 2-adic valuation $\nu_2(c)$).
`test_bit(i)` is bit $i$, counting from the least significant bit $0$.

### `BinCoeff::compare`, `BinCoeff::equal`

Exact comparison.

```mbti
pub fn BinCoeff::compare(Self, Self) -> Int
pub fn BinCoeff::equal(Self, Self) -> Bool
```

`compare` returns $-1$, $0$ or $1$; `equal` is numerical equality, which for
natural numbers is the same as equality of representations. The operators
`<`, `<=`, `>`, `>=`, `==` and `!=` use them (see
[Trait implementations](#trait-implementations)).

### `BinCoeff::add`, `BinCoeff::mul`, `BinCoeff::square`, `BinCoeff::pow_nat`

Exact addition, multiplication, squaring and powers.

```mbti
pub fn BinCoeff::add(Self, Self) -> Self
pub fn BinCoeff::mul(Self, Self) -> Self
pub fn BinCoeff::square(Self) -> Self
pub fn BinCoeff::pow_nat(Self, UInt) -> Self
```

`square` uses a dedicated kernel that exploits the symmetry of the cross
products. `pow_nat(0)` is one, including $0^0$.

### `BinCoeff::sub_checked`, `BinCoeff::div_rem_checked`

Subtraction and Euclidean division, which can fail on a natural number.

```mbti
pub fn BinCoeff::sub_checked(Self, Self) -> Result[Self, String]
pub fn BinCoeff::div_rem_checked(Self, Self) -> Result[(Self, Self), String]
```

`a.sub_checked(b)` is `Err` when $b > a$. `n.div_rem_checked(d)` returns
$(q, r)$ with $n = qd + r$ and $0 \le r < d$, and is `Err` when $d = 0$.

### `BinCoeff::gcd`

Returns the greatest common divisor.

```mbti
pub fn BinCoeff::gcd(Self, Self) -> Self
```

$\gcd(a, 0) = a$ and $\gcd(0, 0) = 0$.

### `BinCoeff::shift_left`, `BinCoeff::shift_right`, `BinCoeff::shl`, `BinCoeff::shr`

Multiply by $2^k$ or divide by $2^k$ rounding toward zero.

```mbti
pub fn BinCoeff::shift_left(Self, Int) -> Self
pub fn BinCoeff::shift_right(Self, Int) -> Self
pub fn BinCoeff::shl(Self, Int) -> Self
pub fn BinCoeff::shr(Self, Int) -> Self
```

`shl` and `shr` are the `Shl`/`Shr` trait methods behind `<<` and `>>`. A
negative shift count aborts.

### `BinCoeff::bit_and`, `BinCoeff::bit_or`, `BinCoeff::bit_xor`

Bitwise operations on the binary expansions.

```mbti
pub fn BinCoeff::bit_and(Self, Self) -> Self
pub fn BinCoeff::bit_or(Self, Self) -> Self
pub fn BinCoeff::bit_xor(Self, Self) -> Self
```

`BinCoeff` also implements `Add`, `Mul`, `Shl`, `Shr`, `Eq`, `Compare`,
`Show` and `Debug`; the promoted trait methods are listed under
[Trait implementations](#trait-implementations).

```moonbit
///|
test "BinCoeff is exact natural-number arithmetic" {
  let c = @bin_float.BinCoeff::parse("ff", radix=16).unwrap()
  let ten = @bin_float.BinCoeff::from_uint64(10UL)
  let (q, r) = c.div_rem_checked(ten).unwrap()
  inspect("\{q} \{r} \{c.gcd(ten)} \{c.bit_length()}", content="25 5 5 8")
  inspect(ten.pow_nat(20), content="100000000000000000000")
  inspect(ten.sub_checked(c) is Err(_), content="true")
}
```

## The value type

### `BinFloat`

A binary floating-point value: a finite dyadic number, a signed infinity or a
NaN, with a working precision.

```mbti
pub struct BinFloat {
  // private fields
} derive(Eq, @debug.Debug)
```

A finite value is $(-1)^s \cdot c \cdot 2^{e}$ with $s$ the sign bit, $c$ a
`BinCoeff` and $e$ = `exponent2()`. Every value built through this API is
normalized: a nonzero $c$ is odd (factors of two are moved into $e$), a zero
has $c = 0$ and $e = 0$ and keeps its sign, and $c$ has at most `precision()`
bits. The precision is an attribute of the value: plain operations work at the
larger precision of their operands, and contextual operations stamp the
context precision on their result.

The derived `Eq` is structural, not numerical. Two values are `==` when sign,
class, coefficient, exponent, precision and NaN state all agree, so
`one(precision=53) != one(precision=24)`, `-0 != +0`, and a NaN is `==` to an
identical NaN. Use `compare`, `compare_quiet` or `total_order` for numerical
questions.

### `BinFloat::make`

Builds a finite value $(-1)^{\text{negative}} \cdot c \cdot 2^{e}$ rounded to
`precision` bits.

```mbti
pub fn BinFloat::make(BinCoeff, Int, Int, negative? : Bool, mode? : @arithmetic.RoundingMode) -> Self
```

The arguments are the coefficient, the exponent $e$ and the precision. When
the coefficient has more significant bits than the precision it is rounded
with `mode` (default `ToNearestEven`). The result is normalized. A precision
below 1 is treated as 1. A value outside the implementation exponent range is
replaced as an overflow or underflow would be: above it by $\pm\infty$ or, for
a mode that rounds toward zero, the largest finite magnitude
$(2^p - 1)\,2^{e_{\max} - p + 1}$; below the smallest implementation subnormal
$2^{e_{\min} - p + 1}$ by $\pm 0$ or, for a mode that rounds away from zero
(and for nearest when the value exceeds half of it), by that subnormal.
`make` rounds only to $p$ bits: a value between the smallest subnormal and
$2^{e_{\min}}$ is not moved onto the subnormal grid (use `round_ctx` for
that), which matters only at magnitudes near $2^{-2^{30}}$.

### `BinFloat::from_coefficient`, `BinFloat::from_int`

Build a value from an integer.

```mbti
pub fn BinFloat::from_coefficient(BinCoeff, precision? : Int, negative? : Bool) -> Self
pub fn BinFloat::from_int(Int, precision? : Int) -> Self
```

The default precision is 53. The integer is rounded to nearest-even when it
has more significant bits than the precision; `from_int(n)` is exact for every
`Int` at the default precision.

### `BinFloat::from_double`, `BinFloat::from_float`

Decode a host binary64 or binary32 value exactly.

```mbti
pub fn BinFloat::from_double(Double, precision? : Int) -> Self
pub fn BinFloat::from_float(Float, precision? : Int) -> Self
```

The defaults are 53 and 24 bits, so the conversion is exact. `from_double`
preserves signed zeros, infinities, the NaN sign, the quiet/signaling
distinction and the NaN payload (the fraction field without the quiet bit).
`from_float` first widens the `Float` to a `Double` on the host and then
decodes that: numbers, zeros and infinities are unaffected, but a NaN keeps
the payload of the widened binary64 encoding (the binary32 payload times
$2^{29}$), and on the native target a signaling `Float` NaN arrives as a quiet
NaN. Use `BinaryInterchange::from_hex` with `Binary32` to decode binary32 NaNs
bit-exactly. The value is the one the host already rounded: `from_double(0.1)` is
$3602879701896397 \cdot 2^{-55}$, not one tenth. Use `from_string` to round a
decimal literal directly.

### `BinFloat::zero`, `BinFloat::negative_zero`, `BinFloat::one`, `BinFloat::inf`

Build the constants $+0$, $-0$, $1$ and $\pm\infty$.

```mbti
pub fn BinFloat::zero(precision? : Int) -> Self
pub fn BinFloat::negative_zero(precision? : Int) -> Self
pub fn BinFloat::one(precision? : Int) -> Self
pub fn BinFloat::inf(@def.Sign, precision? : Int) -> Self
```

The default precision is 53. `inf(Sign::Negative)` is $-\infty$; any other
sign gives $+\infty$.

### `BinFloat::nan`, `BinFloat::quiet_nan`, `BinFloat::signaling_nan`

Build NaNs.

```mbti
pub fn BinFloat::nan(precision? : Int) -> Self
pub fn BinFloat::quiet_nan(payload? : BinCoeff, negative? : Bool, precision? : Int) -> Self
pub fn BinFloat::signaling_nan(payload? : BinCoeff, negative? : Bool, precision? : Int) -> Self
```

`nan()` is a positive quiet NaN with payload 0. A signaling NaN always has a
nonzero payload (the default and a requested 0 both become 1). Payloads are
carried through operations and are truncated to the payload field only when a
value is encoded in an interchange format.

## Observing a value

### `BinFloat::classify`, `BinFloat::sign`, `BinFloat::is_negative`

Report the class and sign of a value.

```mbti
pub fn BinFloat::classify(Self) -> @arithmetic.FpClass
pub fn BinFloat::sign(Self) -> @def.Sign
pub fn BinFloat::is_negative(Self) -> Bool
```

`classify` returns `Finite`, `Infinity` or `NaN` (zeros are `Finite`). `sign`
is `Zero` for every zero and every NaN, and `Positive` or `Negative` otherwise.
`is_negative` returns the sign bit itself, which is set for $-0$, $-\infty$
and negative NaNs. `@def.is_finite`, `@def.is_nan`, `@def.is_infinite` and
`@def.is_zero` work on `BinFloat` through the `Floating` trait.

### `BinFloat::is_zero`, `BinFloat::is_negative_zero`, `BinFloat::is_quiet_nan`, `BinFloat::is_signaling_nan`, `BinFloat::nan_payload`

Special-value predicates.

```mbti
pub fn BinFloat::is_zero(Self) -> Bool
pub fn BinFloat::is_negative_zero(Self) -> Bool
pub fn BinFloat::is_quiet_nan(Self) -> Bool
pub fn BinFloat::is_signaling_nan(Self) -> Bool
pub fn BinFloat::nan_payload(Self) -> BinCoeff
```

`nan_payload` is zero for a value that is not a NaN.

### `BinFloat::coefficient`, `BinFloat::exponent2`, `BinFloat::precision`

Return the stored representation.

```mbti
pub fn BinFloat::coefficient(Self) -> BinCoeff
pub fn BinFloat::exponent2(Self) -> Int
pub fn BinFloat::precision(Self) -> Int
```

For a finite value the number is `coefficient()` $\times 2^{\texttt{exponent2()}}$
with the sign applied. The coefficient and exponent of an infinity or NaN
carry no meaning.

### `BinFloat::normalized`

Returns the canonical representation of a finite value at its own precision.

```mbti
pub fn BinFloat::normalized(Self) -> Self
```

Values built through the public API are already canonical, so this is the
identity on them; infinities and NaNs are returned unchanged.

### `BinFloat::with_precision`

Rounds a value to a new working precision.

```mbti
pub fn BinFloat::with_precision(Self, Int, @arithmetic.RoundingMode) -> Self
```

A finite value with more significant bits than the new precision is rounded
in the given direction (`@lf_arith.RoundingMode` has no ties-to-away mode;
use `round_ctx` for it). Zeros, infinities and NaNs only change their
precision attribute. No flags are reported; use `round_ctx` when they matter.

### `BinFloat::ulp`

Returns the unit in the last place of a finite value at its own precision.

```mbti
pub fn BinFloat::ulp(Self) -> Self
```

For $x \ne 0$ with leading-bit exponent $t = \lfloor \log_2 |x| \rfloor$ the
result is $2^{t-p+1}$. For zero it is $2^{1-p}$, and for an infinity or NaN it
is a quiet NaN. The spacing ignores any context exponent range, so it is not
the subnormal spacing of an IEEE format.

```moonbit
///|
test "make normalizes and rounds to the precision" {
  let twelve = @bin_float.BinFloat::make(
    @bin_float.BinCoeff::from_uint64(12UL),
    0,
    2,
  )
  inspect(
    "\{twelve} \{twelve.coefficient()} \{twelve.exponent2()}",
    content="3p2 3 2",
  )
  // 13 needs four bits; at two bits it rounds to nearest-even 12.
  let thirteen = @bin_float.BinFloat::make(
    @bin_float.BinCoeff::from_uint64(13UL),
    0,
    2,
  )
  inspect(thirteen, content="3p2")
  inspect(@bin_float.BinFloat::one().ulp(), content="1p-52")
}
```

## Plain arithmetic

### `BinFloat::add`, `BinFloat::sub`, `BinFloat::mul`, `BinFloat::div`, `BinFloat::neg`

The four operations and negation, also available as `+`, `-`, `*`, `/` and
unary `-`.

```mbti
pub fn BinFloat::add(Self, Self) -> Self
pub fn BinFloat::sub(Self, Self) -> Self
pub fn BinFloat::mul(Self, Self) -> Self
pub fn BinFloat::div(Self, Self) -> Self
pub fn BinFloat::neg(Self) -> Self
pub impl Add for BinFloat
pub impl Sub for BinFloat
pub impl Mul for BinFloat
pub impl Div for BinFloat
pub impl Neg for BinFloat
```

The result is the exact sum, difference, product or quotient rounded once to
nearest-even at the larger operand precision, with the implementation exponent
range. Special values follow IEEE 754: NaNs propagate (the first NaN operand,
quieted), $\infty - \infty$, $0 \cdot \infty$, $0/0$ and $\infty/\infty$ are
NaN, and a nonzero number divided by zero is a signed infinity. Flags are
discarded; use the [contextual forms](#contextual-arithmetic) to observe them.
`neg` flips the sign bit of every value, including zeros and NaNs, and never
rounds.

### `BinFloat::abs`, `BinFloat::copy_sign`

Clear or copy the sign bit.

```mbti
pub fn BinFloat::abs(Self) -> Self
pub fn BinFloat::copy_sign(Self, Self) -> Self
```

Both are quiet IEEE sign-bit operations: they never round, never raise a flag
and keep NaN payloads. `x.copy_sign(y)` has the magnitude of `x` and the sign
bit of `y`.

### `BinFloat::div_checked`

Divides, returning an error for a zero divisor.

```mbti
pub fn BinFloat::div_checked(Self, Self) -> Result[Self, @arithmetic.ArithmeticError]
```

A finite zero divisor (including $0/0$) gives a `division_by_zero` error.
Otherwise the result is that of `div`.

### `BinFloat::sqrt`, `sqrt_for_precision`, `sqrt_bounds_for_precision`

Correctly rounded square roots.

```mbti
pub fn BinFloat::sqrt(Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn sqrt_for_precision(BinFloat, Int) -> Result[BinFloat, @arithmetic.ArithmeticError]
pub fn sqrt_bounds_for_precision(BinFloat, Int) -> Result[(BinFloat, BinFloat), @arithmetic.ArithmeticError]
```

`x.sqrt()` rounds $\sqrt{x}$ to nearest-even at the precision of `x`;
`sqrt_for_precision(x, p)` does the same at precision `p`. Both return a
`domain_error` for a negative nonzero argument (including $-\infty$ and a
NaN with its sign bit set); $\sqrt{-0} = -0$, and a positive NaN gives `Ok`
of a quiet NaN.
`sqrt_bounds_for_precision(x, p)` returns $(\operatorname{RD}_p(\sqrt x),
\operatorname{RU}_p(\sqrt x))$, an enclosure of width at most one unit in the
last place that collapses to a point when the root is exact. It needs a finite
non-negative argument: a NaN or infinity is `unsupported`, a negative value a
`domain_error`.

### `BinFloat::pow_int`, `BinFloat::pown`

Raise a value to an integer power.

```mbti
pub fn BinFloat::pow_int(Self, Int) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BinFloat::pown(Self, Int) -> Result[Self, @arithmetic.ArithmeticError]
```

The two names are the same function. The result is $x^n$ correctly rounded to
nearest-even at the precision of `x`, computed as in `pow_int_ctx`. A zero
base with a negative exponent is a `division_by_zero` error; $x^0 = 1$ for
every $x$, NaN included (a signaling NaN too, without an error).

### `BinFloat::fma`

Fused multiply-add: $x \cdot y + z$ with a single rounding.

```mbti
pub fn BinFloat::fma(Self, Self, Self) -> Self
```

The precision is the largest of the three operand precisions. See
[`fma_ctx`](#binfloatfma_ctx) for the special cases.

### `BinFloat::remainder`

IEEE 754 remainder $x - n y$, where $n$ is the integer nearest $x/y$ with ties
to even.

```mbti
pub fn BinFloat::remainder(Self, Self) -> Self
```

The result is exact whenever it fits the larger operand precision, which is
always the case for operands of that precision (the proof is on the
[design page](../design/bin_float.md#ieee-remainder-is-exact)). See
[`remainder_ctx`](#binfloatremainder_ctx).

```moonbit
///|
test "plain arithmetic rounds once at the operand precision" {
  let one = @bin_float.BinFloat::one()
  let three = @bin_float.BinFloat::from_int(3)
  let third = one / three
  inspect(third, content="6004799503160661p-54")
  inspect(third.to_shortest_string(), content="0.3333333333333333")
  inspect(one / @bin_float.BinFloat::zero(), content="inf")
  inspect(@bin_float.BinFloat::from_int(7).remainder(@bin_float.BinFloat::from_int(2)), content="-1p0")
  inspect(@bin_float.BinFloat::from_int(3).pow_int(-2).unwrap().to_shortest_string(), content="0.1111111111111111")
}
```

## Contexts, rounding and flags

### `BinaryRoundingMode`

The rounding-direction attribute of a context.

```mbti
pub(all) enum BinaryRoundingMode {
  RoundTiesToEven
  RoundTiesToAway
  RoundTowardZero
  RoundTowardPositive
  RoundTowardNegative
  RoundAwayFromZero
} derive(Eq, @debug.Debug)
```

The first five are the IEEE 754-2019 rounding directions (clause 4.3).
`RoundAwayFromZero` is an extra directed mode (round the magnitude up), used by
the GDA-style `@lf_arith.RoundingMode::AwayFromZero`. Each mode is a monotone
map $\mathbb{R} \to F \cup \{\pm\infty\}$; the
[design page](../design/bin_float.md#rounding-functions) defines them.

### `BinaryRoundingMode::from_arithmetic`, `BinaryRoundingMode::to_arithmetic`

Convert to and from `@lf_arith.RoundingMode`.

```mbti
pub fn BinaryRoundingMode::from_arithmetic(@arithmetic.RoundingMode) -> Self
pub fn BinaryRoundingMode::to_arithmetic(Self) -> @arithmetic.RoundingMode?
```

`to_arithmetic(RoundTiesToAway)` is `None`, because `@lf_arith.RoundingMode`
has no ties-to-away mode; the other modes map one to one.

### `TininessDetection`

When a nonzero result counts as tiny for the underflow flag.

```mbti
pub(all) enum TininessDetection {
  BeforeRounding
  AfterRounding
} derive(Eq, @debug.Debug)
```

`BeforeRounding` calls a result tiny when the exact value has
$|x| < 2^{e_{\min}}$. `AfterRounding` calls it tiny when $x$ rounded to $p$
bits with an unbounded exponent range has magnitude below $2^{e_{\min}}$
(IEEE 754-2019 clause 7.5). The default is `AfterRounding`. Underflow is
signaled only for a tiny result that is also inexact.

### `BinaryContext`

The precision, rounding direction, exponent range and tininess rule of one
operation.

```mbti
pub struct BinaryContext {
  // private fields
} derive(Eq, @debug.Debug)
```

A context is an immutable value; there is no global or thread state.
$e_{\min}$ and $e_{\max}$ are exponents of the leading bit, as in IEEE 754: a
normal number satisfies $2^{e_{\min}} \le |x| < 2^{e_{\max}+1}$, the largest
finite value is $(2 - 2^{1-p})\,2^{e_{\max}}$ and the smallest positive
subnormal is $2^{e_{\min}-p+1}$. A missing bound means the implementation
bound.

### `BinaryContext::new`, `BinaryContext::try_new`, `BinaryContext::unbounded`

Build a context.

```mbti
pub fn BinaryContext::new(Int, rounding? : BinaryRoundingMode, e_min? : Int, e_max? : Int, tininess? : TininessDetection) -> Self
pub fn BinaryContext::try_new(Int, rounding? : BinaryRoundingMode, e_min? : Int, e_max? : Int, tininess? : TininessDetection) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BinaryContext::unbounded(Int, rounding? : BinaryRoundingMode) -> Self
```

The first argument is the precision $p$. Defaults: `RoundTiesToEven`, no
explicit exponent bounds, `AfterRounding`. `new` aborts when
$p \le 0$, $p >$ `binary_precision_max`, or both bounds are given with
$e_{\min} > e_{\max}$; `try_new` returns a `domain_error` in those cases.
`unbounded(p)` has no explicit bounds, so only the implementation range
applies.

### `BinaryContext::binary16`, `BinaryContext::binary32`, `BinaryContext::binary64`, `BinaryContext::binary128`

Contexts of the IEEE 754 interchange formats.

```mbti
pub fn BinaryContext::binary16(rounding? : BinaryRoundingMode, tininess? : TininessDetection) -> Self
pub fn BinaryContext::binary32(rounding? : BinaryRoundingMode, tininess? : TininessDetection) -> Self
pub fn BinaryContext::binary64(rounding? : BinaryRoundingMode, tininess? : TininessDetection) -> Self
pub fn BinaryContext::binary128(rounding? : BinaryRoundingMode, tininess? : TininessDetection) -> Self
```

Each is `BinaryInterchangeFormat::context` of the format:

| Context | $p$ | $e_{\min}$ | $e_{\max}$ |
| --- | ---: | ---: | ---: |
| `binary16` | 11 | −14 | 15 |
| `binary32` | 24 | −126 | 127 |
| `binary64` | 53 | −1022 | 1023 |
| `binary128` | 113 | −16382 | 16383 |

### `BinaryContext::from_arithmetic_context`

Converts an `@lf_arith.ArithmeticContext`.

```mbti
pub fn BinaryContext::from_arithmetic_context(@arithmetic.ArithmeticContext) -> Self
```

Precision, rounding and the optional bounds are copied; the `clamp` field has
no binary meaning and is ignored; tininess is `AfterRounding`. A precision
outside $[1, 2^{28}]$ aborts, as in `new`.

### `BinaryContext::precision`, `BinaryContext::rounding`, `BinaryContext::e_min`, `BinaryContext::e_max`, `BinaryContext::tininess`

Read the fields of a context.

```mbti
pub fn BinaryContext::precision(Self) -> Int
pub fn BinaryContext::rounding(Self) -> BinaryRoundingMode
pub fn BinaryContext::e_min(Self) -> Int?
pub fn BinaryContext::e_max(Self) -> Int?
pub fn BinaryContext::tininess(Self) -> TininessDetection
```

`e_min` and `e_max` return the bounds as given (`None` for an unbounded side),
not intersected with the implementation range.

### `BinaryFlags`

The five IEEE 754 exception flags raised by one or more operations.

```mbti
pub struct BinaryFlags {
  // private fields
} derive(Eq, @debug.Debug)
```

Two flag sets are `==` when all five flags agree.

### `BinaryFlags::new`, `BinaryFlags::inexact`, `BinaryFlags::underflow`, `BinaryFlags::overflow`, `BinaryFlags::division_by_zero`, `BinaryFlags::invalid_operation`

Build an empty flag set and read the individual flags.

```mbti
pub fn BinaryFlags::new() -> Self
pub fn BinaryFlags::inexact(Self) -> Bool
pub fn BinaryFlags::underflow(Self) -> Bool
pub fn BinaryFlags::overflow(Self) -> Bool
pub fn BinaryFlags::division_by_zero(Self) -> Bool
pub fn BinaryFlags::invalid_operation(Self) -> Bool
```

`new()` has every flag clear. A contextual operation returns only the flags it
raised itself; nothing is sticky until you combine flags. The flags mean:
`inexact`, the returned value differs from the exact result; `underflow`, the
result is tiny and inexact; `overflow`, the rounded result exceeded the
largest finite value (always together with `inexact`); `division_by_zero`, an
exact infinite result from finite operands (such as $1/0$ or $\log 0$);
`invalid_operation`, no useful real result exists and a quiet NaN was
returned, or a signaling NaN was an operand. The non-`try` elementary
functions also raise it when they return NaN for a domain error or a
certification failure.

### `BinaryFlags::combine`

Returns the union of two flag sets.

```mbti
pub fn BinaryFlags::combine(Self, Self) -> Self
```

`combine` is a bitwise OR: associative, commutative and idempotent with
`new()` as identity, so the flags of a computation can be accumulated in any
order.

### `BinaryFlags::to_testfloat_bits`

Encodes the flags in the Berkeley TestFloat bit layout.

```mbti
pub fn BinaryFlags::to_testfloat_bits(Self) -> Int
```

Inexact is `0x01`, underflow `0x02`, overflow `0x04`, division by zero `0x08`
and invalid `0x10`.

## Contextual arithmetic

Every method in this group returns `(value, flags)`, rounds the exact result
once under the context, and applies the context exponent range: an overflow
returns $\pm\infty$ or the largest finite magnitude depending on the rounding
direction, and a tiny result is rounded on the subnormal grid with quantum
$2^{e_{\min}-p+1}$. The returned value carries the context precision. A NaN
operand produces the first NaN operand quieted, with its sign and payload, and
`invalid_operation` only when some operand was a signaling NaN.

### `BinFloat::round_ctx`

Rounds a value into a context.

```mbti
pub fn BinFloat::round_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
```

This is the IEEE conversion of a wider value to a narrower format. Finite
values are rounded with the full overflow, subnormal and tininess rules;
infinities are kept; a signaling NaN is quieted with `invalid_operation`.

### `BinFloat::add_ctx`, `BinFloat::sub_ctx`, `BinFloat::mul_ctx`, `BinFloat::div_ctx`

The four operations under a context.

```mbti
pub fn BinFloat::add_ctx(Self, Self, BinaryContext) -> (Self, BinaryFlags)
pub fn BinFloat::sub_ctx(Self, Self, BinaryContext) -> (Self, BinaryFlags)
pub fn BinFloat::mul_ctx(Self, Self, BinaryContext) -> (Self, BinaryFlags)
pub fn BinFloat::div_ctx(Self, Self, BinaryContext) -> (Self, BinaryFlags)
```

$$
\texttt{x.op\_ctx(y, ctx)} = \bigl(\circ(x \mathbin{\mathrm{op}} y),\ \text{flags}\bigr).
$$

Invalid operations ($\infty - \infty$ with equal signs after `sub`'s
negation, $0 \cdot \infty$, $0/0$, $\infty/\infty$) give a quiet NaN with
`invalid_operation`; a nonzero finite number divided by zero gives a signed
infinity with `division_by_zero`. An exact zero sum of operands with opposite
signs is $+0$, except $-0$ under `RoundTowardNegative`; $(-0) + (-0) = -0$
(IEEE 754-2019 clause 6.3).

### `BinFloat::sqrt_ctx`

Square root under a context.

```mbti
pub fn BinFloat::sqrt_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
```

$\sqrt{\pm 0} = \pm 0$, $\sqrt{+\infty} = +\infty$, and a negative nonzero
argument gives a quiet NaN with `invalid_operation`.

### `BinFloat::fma_ctx`

Fused multiply-add $\circ(x \cdot y + z)$ under a context.

```mbti
pub fn BinFloat::fma_ctx(Self, Self, Self, BinaryContext) -> (Self, BinaryFlags)
```

The product is formed exactly and the sum is rounded once (IEEE 754-2019
clause 5.4.1). A NaN operand propagates the first NaN of `self`, multiplier,
addend. `invalid_operation` is raised for a signaling NaN, for
$\infty \cdot 0$ (also when the addend is a quiet NaN, as SoftFloat does), and
for $\pm\infty \cdot y + (\mp\infty)$.

### `BinFloat::remainder_ctx`

IEEE 754 remainder under a context.

```mbti
pub fn BinFloat::remainder_ctx(Self, Self, BinaryContext) -> (Self, BinaryFlags)
```

The result is $r = x - n y$ with $n = \operatorname{round\_ties\_even}(x/y)$,
so $|r| \le |y|/2$. A zero result has the sign of $x$. $x = \pm\infty$ or
$y = 0$ gives a quiet NaN with `invalid_operation`; $y = \pm\infty$ or $x = 0$
returns $x$ rounded into the context. The exact $r$ is then rounded; for
operands representable in the context this rounding is exact and no flag is
raised. The quotient is never formed: the operands are reduced modulo $2y$,
so huge exponent gaps cost $O(\log)$ multiplications.

### `BinFloat::pow_int_ctx`, `BinFloat::pown_ctx`

Integer power $\circ(x^n)$ under a context.

```mbti
pub fn BinFloat::pow_int_ctx(Self, Int, BinaryContext) -> (Self, BinaryFlags)
pub fn BinFloat::pown_ctx(Self, Int, BinaryContext) -> (Self, BinaryFlags)
```

The two names are the same function, IEEE 754 `pown`. $x^0 = 1$ for every $x$
(NaN included, and a signaling NaN raises no flag); $(\pm 0)^{n<0} = \pm\infty$ (sign for odd $n$) with
`division_by_zero`; $(\pm\infty)^n$ is an infinity or zero with the sign of an
odd power. Small powers are computed exactly; otherwise a Ziv loop rounds an
enclosure, with an exact fallback, so the result is always correctly rounded.

```moonbit
///|
test "contextual operations return value and flags" {
  let ctx = @bin_float.BinaryContext::binary32()
  let one = @bin_float.BinFloat::one()
  let (third, flags) = one.div_ctx(@bin_float.BinFloat::from_int(3), ctx)
  inspect(third.to_shortest_string_ctx(ctx), content="0.33333334")
  inspect(flags.to_testfloat_bits(), content="1")
  let (inf, zero_flags) = one.div_ctx(@bin_float.BinFloat::zero(), ctx)
  inspect("\{inf} \{zero_flags.division_by_zero()}", content="inf true")
}
```

## IEEE 754 operations

### `BinFloat::to_integral_value_ctx`, `BinFloat::to_integral_exact_ctx`

Round to an integral value in the context's rounding direction.

```mbti
pub fn BinFloat::to_integral_value_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn BinFloat::to_integral_exact_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
```

These are IEEE `roundToIntegral` (in the context's direction) and
`roundToIntegralExact`. Only the rounding direction of the context is used;
the result keeps the operand's precision and the sign of a zero result.
`to_integral_exact_ctx` raises `inexact` when the value changed;
`to_integral_value_ctx` never raises it. Infinities are returned unchanged and
a signaling NaN is quieted with `invalid_operation`.

### `BinFloat::floor`, `BinFloat::ceil`, `BinFloat::trunc`, `BinFloat::round`, `BinFloat::round_ties_even`

Round to an integral value in a fixed direction.

```mbti
pub fn BinFloat::floor(Self) -> Self
pub fn BinFloat::ceil(Self) -> Self
pub fn BinFloat::trunc(Self) -> Self
pub fn BinFloat::round(Self) -> Self
pub fn BinFloat::round_ties_even(Self) -> Self
```

They are `roundToIntegralTowardNegative`, `…TowardPositive`, `…TowardZero`,
`…TiesToAway` and `…TiesToEven`. `round` rounds halfway cases away from zero:
`round(-2.5) = -3`, while `round_ties_even(-2.5) = -2`.

### `BinFloat::to_int_ctx`, `BinFloat::to_int64_ctx`, `BinFloat::to_uint_ctx`, `BinFloat::to_uint64_ctx`

IEEE `convertToInteger` to a machine integer, rounding in the context's
direction.

```mbti
pub fn BinFloat::to_int_ctx(Self, BinaryContext, exact? : Bool) -> (Int?, BinaryFlags)
pub fn BinFloat::to_int64_ctx(Self, BinaryContext, exact? : Bool) -> (Int64?, BinaryFlags)
pub fn BinFloat::to_uint_ctx(Self, BinaryContext, exact? : Bool) -> (UInt?, BinaryFlags)
pub fn BinFloat::to_uint64_ctx(Self, BinaryContext, exact? : Bool) -> (UInt64?, BinaryFlags)
```

The value is first rounded to an integer. If that integer fits the target type
the result is `Some`; with `exact=true` (`convertToIntegerExact`) `inexact` is
raised when rounding changed the value. A NaN, an infinity or an integer
outside the target range gives `None` with `invalid_operation`, where a C
implementation would return an unspecified sentinel. A negative value that
rounds to zero converts to `0` for the unsigned targets.

### `BinFloat::next_up_ctx`, `BinFloat::next_down_ctx`

IEEE `nextUp` and `nextDown` in the context's format.

```mbti
pub fn BinFloat::next_up_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn BinFloat::next_down_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
```

`next_up_ctx(x)` is the least value of the context's format (precision and
exponent range, subnormals included) that is greater than $x$; `next_down_ctx`
is $-\texttt{next\_up}(-x)$. The context's rounding direction is ignored. The
operations are quiet: $\operatorname{nextUp}(\pm 0)$ is the smallest positive
subnormal, $\operatorname{nextUp}(-\infty)$ is the most negative finite value,
$\operatorname{nextUp}(\Omega) = +\infty$ with no overflow flag, and only a
signaling NaN raises `invalid_operation`. An operand with more bits than the
context precision is accepted.

### `BinFloat::scaleb_ctx`, `BinFloat::logb_ctx`

IEEE `scaleB` and `logB`.

```mbti
pub fn BinFloat::scaleb_ctx(Self, Int, BinaryContext) -> (Self, BinaryFlags)
pub fn BinFloat::logb_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
```

`x.scaleb_ctx(n, ctx)` is $\circ(x \cdot 2^n)$ with the usual overflow and
underflow handling; it is exact unless the result leaves the normal range.
`x.logb_ctx(ctx)` is $\lfloor \log_2 |x| \rfloor$ as an exact integral value
(also for subnormal $x$): $\operatorname{logB}(0) = -\infty$ with
`division_by_zero`, $\operatorname{logB}(\pm\infty) = +\infty$, and a NaN
propagates.

```moonbit
///|
test "IEEE integral, integer and neighbour operations" {
  let ctx = @bin_float.BinaryContext::binary64()
  let x = @bin_float.BinFloat::from_string("-2.5").unwrap()
  inspect(
    "\{x.floor()} \{x.ceil()} \{x.trunc()} \{x.round()} \{x.round_ties_even()}",
    content="-3p0 -1p1 -1p1 -3p0 -1p1",
  )
  let (n, flags) = x.to_int_ctx(ctx, exact=true)
  inspect("\{n.unwrap()} \{flags.inexact()}", content="-2 true")
  let (up, _) = @bin_float.BinFloat::one().next_up_ctx(ctx)
  inspect(up.to_hex(), content="0x10000000000001p-52")
  let (tiny, _) = @bin_float.BinFloat::zero().next_up_ctx(ctx)
  inspect(tiny.to_shortest_string_ctx(ctx), content="5e-324")
}
```

## Comparison and ordering

### `BinFloat::compare`

Numerical three-way comparison that is total on every value.

```mbti
pub fn BinFloat::compare(Self, Self) -> Int
pub impl Compare for BinFloat
```

`compare` returns $-1$, $0$ or $1$ by numerical value, with $-0 = +0$ and
precision ignored. NaN has no numerical order, so `compare` places every NaN
equal to every other NaN and above every non-NaN value; it never aborts. The
result is a total preorder, which is what `Compare` (and sorting) needs, but
it is not the IEEE comparison: under it `nan > 1` holds. The operators `<`,
`<=`, `>`, `>=` and the promoted `op_*` methods use `compare`. For IEEE
semantics use `compare_checked`, the quiet and signaling predicates below, or
`total_order`. The [design page](../design/bin_float.md#ordering-nan-in-compare)
explains the choice.

### `BinFloat::compare_checked`

Numerical comparison that rejects NaN.

```mbti
pub fn BinFloat::compare_checked(Self, Self) -> Result[Int, @arithmetic.ArithmeticError]
pub impl @arithmetic.CompareChecked for BinFloat
```

Returns the same value as `compare` when neither operand is a NaN, and an
`unordered_comparison` error otherwise.

### `BinFloat::compare_quiet`, `BinFloat::compare_signaling`

IEEE comparison as a four-valued relation with flags.

```mbti
pub fn BinFloat::compare_quiet(Self, Self) -> (@def.PartialOrder, BinaryFlags)
pub fn BinFloat::compare_signaling(Self, Self) -> (@def.PartialOrder, BinaryFlags)
```

The relation is `Less`, `Equal`, `Greater` or `Unordered` (some operand is a
NaN), with $-0 = +0$. The quiet form raises `invalid_operation` only for a
signaling NaN; the signaling form raises it for every unordered comparison
(IEEE 754-2019 clause 5.11).

### `BinFloat::equal_quiet`, `BinFloat::less_quiet`, `BinFloat::less_equal_quiet`, `BinFloat::unordered_quiet`, `BinFloat::equal_signaling`, `BinFloat::less_signaling`, `BinFloat::less_equal_signaling`

The IEEE comparison predicates.

```mbti
pub fn BinFloat::equal_quiet(Self, Self) -> (Bool, BinaryFlags)
pub fn BinFloat::less_quiet(Self, Self) -> (Bool, BinaryFlags)
pub fn BinFloat::less_equal_quiet(Self, Self) -> (Bool, BinaryFlags)
pub fn BinFloat::unordered_quiet(Self, Self) -> (Bool, BinaryFlags)
pub fn BinFloat::equal_signaling(Self, Self) -> (Bool, BinaryFlags)
pub fn BinFloat::less_signaling(Self, Self) -> (Bool, BinaryFlags)
pub fn BinFloat::less_equal_signaling(Self, Self) -> (Bool, BinaryFlags)
```

`compareQuietEqual`, `compareQuietLess`, `compareQuietLessEqual`,
`compareQuietUnordered` and the signaling `Equal`, `Less`, `LessEqual`. Each is
derived from `compare_quiet` or `compare_signaling` and returns its flags; every
predicate except `unordered_quiet` is false on an unordered pair.

### `BinFloat::total_order`, `BinFloat::total_order_mag`, `BinFloat::total_order_compare`

The IEEE 754 `totalOrder` relation.

```mbti
pub fn BinFloat::total_order(Self, Self) -> Bool
pub fn BinFloat::total_order_mag(Self, Self) -> Bool
pub fn BinFloat::total_order_compare(Self, Self) -> Int
```

`total_order_compare` orders all values as

$$
-\mathrm{qNaN} < -\mathrm{sNaN} < -\infty < \text{negative finite} < -0 < +0 < \text{positive finite} < +\infty < +\mathrm{sNaN} < +\mathrm{qNaN},
$$

with NaNs of one sign and kind ordered by payload (reversed for the negative
side). `x.total_order(y)` is `total_order_compare(x, y) <= 0` and
`total_order_mag` compares absolute values. Values that are numerically equal
but differ in precision compare equal. The operations are quiet.

### `BinFloat::min`, `BinFloat::max`

The smaller or larger of two values, ignoring a NaN operand.

```mbti
pub fn BinFloat::min(Self, Self) -> Self
pub fn BinFloat::max(Self, Self) -> Self
```

When exactly one operand is a NaN the other is returned (the IEEE 754-2008
`minNum`/`maxNum` convention for quiet NaNs); a signaling NaN is ignored in the
same way, without quieting or a flag, and two NaNs give the argument. When the operands compare equal
under `compare` (for example $-0$ and $+0$) the receiver is returned. No flags
are produced.

### `BinFloat::clamp`, `BinFloat::clamp_checked`

Restrict a value to `[min, max]`.

```mbti
pub fn BinFloat::clamp(Self, min~ : Self, max~ : Self) -> Self
pub fn BinFloat::clamp_checked(Self, min~ : Self, max~ : Self) -> Result[Self, @arithmetic.ArithmeticError]
```

A NaN receiver is returned unchanged. `clamp` aborts when a bound is a NaN or
`min > max`; `clamp_checked` returns a `domain_error` in those cases.

```moonbit
///|
test "three different orders on BinFloat" {
  let nan = @bin_float.BinFloat::nan()
  let zero = @bin_float.BinFloat::zero()
  let neg_zero = @bin_float.BinFloat::negative_zero()
  inspect(nan.compare(zero), content="1")
  inspect(nan.compare_checked(zero) is Err(_), content="true")
  let (unordered, flags) = zero.unordered_quiet(nan)
  inspect("\{unordered} \{flags.invalid_operation()}", content="true false")
  inspect(neg_zero.compare(zero), content="0")
  inspect(neg_zero.total_order_compare(zero), content="-1")
  inspect(neg_zero == zero, content="false")
  let values = [nan, @bin_float.BinFloat::inf(@def.Sign::Positive), zero, @bin_float.BinFloat::from_int(-3)]
  values.sort()
  inspect(values.map(fn(v) { v.to_string() }).join(" "), content="-3p0 0 inf nan")
}
```

## Text and hexadecimal conversion

### `BinFloat::to_string`

Prints the exact stored value as `coefficient p exponent`.

```mbti
pub fn BinFloat::to_string(Self) -> String
pub impl Show for BinFloat
```

A finite nonzero value prints as `[-]<c>p<e>` with $c$ in decimal, meaning
$c \cdot 2^e$ (for example `3p-1` is $1.5$). Zeros print as `0` and `-0`,
infinities as `inf` and `-inf`, and every NaN as `nan`. The form is exact and
unambiguous but not a decimal rendering; use `to_shortest_string` for that.

### `BinFloat::from_string`, `BinFloat::from_string_ctx`

Parse a decimal literal with correct rounding (IEEE
`convertFromDecimalCharacter`).

```mbti
pub fn BinFloat::from_string(String, precision? : Int) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BinFloat::from_string_ctx(String, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
```

The accepted syntax is `[+-]digits[.digits][e[+-]digits]` (a leading or
trailing point is allowed, the exponent marker is `e` or `E`), and the
case-insensitive words `inf`, `infinity`, `nan`, `qnan` and `snan`, with
surrounding whitespace ignored. Anything else is a `parse_error`. The exact
decimal value $D \cdot 10^k$ is rounded once under the context, for any number
of digits and any exponent; overflow, underflow and inexact are reported as for
arithmetic. `from_string(s, precision=p)` uses `unbounded(p)` (default 53) and
drops the flags.

### `BinFloat::to_decimal_string_ctx`

Formats a value with a fixed number of significant decimal digits (IEEE
`convertToDecimalCharacter`).

```mbti
pub fn BinFloat::to_decimal_string_ctx(Self, Int, BinaryContext) -> (String, BinaryFlags)
```

The output is `[-]d.ddd…e±x` with exactly `digits` significant digits
(at least 1), correctly rounded in the context's rounding direction;
`inexact` is raised when nonzero digits were dropped. Only the rounding
direction of the context is used. Zero prints as `0.00…e+0` with its sign,
infinities as `inf`/`-inf`, NaNs as `nan`/`snan` with their sign. The text
parses back with `from_string_ctx`.

### `BinFloat::to_shortest_string`, `BinFloat::to_shortest_string_ctx`

Formats the shortest decimal that reads back as the same value.

```mbti
pub fn BinFloat::to_shortest_string(Self) -> String
pub fn BinFloat::to_shortest_string_ctx(Self, BinaryContext) -> String
```

`to_shortest_string_ctx(x, ctx)` returns the decimal with the fewest
significant digits that `from_string_ctx(_, ctx)` maps back to $x$ under
round-to-nearest-even (the context's own rounding direction is ignored). When
two candidates of that length read back, the nearer one is chosen, then the
one with an even last digit. The layout follows ECMAScript `Number#toString`:
positional notation for decimal exponents in $[-6, 21)$, otherwise
`d.ddde±x`; unlike ECMAScript, $-0$ prints as `-0`. For binary64 values in
`BinaryContext::binary64()` the result equals the host `Double` formatter.
`to_shortest_string()` uses `unbounded(precision())`, so it is the shortest
string that `from_string(text, precision=x.precision())` maps back to `x`. The
operand should be representable in the context.

### `BinFloat::from_hex`, `BinFloat::to_hex`

Read and write the exact value with a hexadecimal coefficient.

```mbti
pub fn BinFloat::from_hex(String, Int) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BinFloat::to_hex(Self) -> String
```

The syntax is `[+-]0x<hexdigits>p<decimal exponent>` and means the integer
coefficient times $2^{\text{exponent}}$: `0x3p-1` is $1.5$. There is no
hexadecimal point, so C-style `0x1.8p0` is a `parse_error`. `from_hex(s, p)`
rounds to precision `p` with nearest-even and also accepts `nan`, `inf` and
`infinity` with a sign. `to_hex` prints the stored coefficient in lower case,
`0x0p0` or `-0x0p0` for a zero, and `nan`/`inf` with a sign.

```moonbit
///|
test "decimal and hexadecimal text" {
  let tenth = @bin_float.BinFloat::from_string("0.1").unwrap()
  inspect(tenth, content="3602879701896397p-55")
  inspect(tenth.to_hex(), content="0xccccccccccccdp-55")
  inspect(tenth.to_shortest_string(), content="0.1")
  let ctx = @bin_float.BinaryContext::binary64()
  let (digits, flags) = tenth.to_decimal_string_ctx(25, ctx)
  inspect("\{digits} \{flags.inexact()}", content="1.000000000000000055511151e-1 true")
  let (single, _) = @bin_float.BinFloat::from_string_ctx("0.1", @bin_float.BinaryContext::binary32()).unwrap()
  inspect(single, content="13421773p-27")
  inspect(@bin_float.BinFloat::from_hex("0x3p-1", 53).unwrap(), content="3p-1")
}
```

## Interchange encodings

### `BinaryInterchangeFormat`

The four IEEE 754 binary interchange formats.

```mbti
pub(all) enum BinaryInterchangeFormat {
  Binary16
  Binary32
  Binary64
  Binary128
} derive(Eq, @debug.Debug)
```

### `BinaryInterchangeFormat::precision`, `BinaryInterchangeFormat::e_min`, `BinaryInterchangeFormat::e_max`, `BinaryInterchangeFormat::bias`, `BinaryInterchangeFormat::exponent_bits`, `BinaryInterchangeFormat::fraction_bits`, `BinaryInterchangeFormat::total_bits`

The parameters of a format.

```mbti
pub fn BinaryInterchangeFormat::precision(Self) -> Int
pub fn BinaryInterchangeFormat::e_min(Self) -> Int
pub fn BinaryInterchangeFormat::e_max(Self) -> Int
pub fn BinaryInterchangeFormat::bias(Self) -> Int
pub fn BinaryInterchangeFormat::exponent_bits(Self) -> Int
pub fn BinaryInterchangeFormat::fraction_bits(Self) -> Int
pub fn BinaryInterchangeFormat::total_bits(Self) -> Int
```

| Format | `total_bits` $k$ | `exponent_bits` $w$ | `fraction_bits` $p-1$ | `precision` $p$ | `bias` $= e_{\max}$ | `e_min` $= 1 - e_{\max}$ |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `Binary16` | 16 | 5 | 10 | 11 | 15 | −14 |
| `Binary32` | 32 | 8 | 23 | 24 | 127 | −126 |
| `Binary64` | 64 | 11 | 52 | 53 | 1023 | −1022 |
| `Binary128` | 128 | 15 | 112 | 113 | 16383 | −16382 |

### `BinaryInterchangeFormat::context`

Returns the `BinaryContext` of the format.

```mbti
pub fn BinaryInterchangeFormat::context(Self, rounding? : BinaryRoundingMode, tininess? : TininessDetection) -> BinaryContext
```

### `BinaryInterchange`

An encoded value: a format and its bit pattern.

```mbti
pub struct BinaryInterchange {
  // private fields
} derive(Eq)
```

Equality compares the format and the bits, so two encodings of NaN with
different payloads differ and $\pm 0$ differ.

### `BinaryInterchange::format`, `BinaryInterchange::bits`

Return the format and the bit pattern of an encoding.

```mbti
pub fn BinaryInterchange::format(Self) -> BinaryInterchangeFormat
pub fn BinaryInterchange::bits(Self) -> BinCoeff
```

`bits()` is the encoding as a natural number below $2^k$, $k$ = `total_bits`:
the sign bit is bit $k-1$, the biased exponent field the next $w$ bits and the
trailing significand field the low $p-1$ bits.

### `BinaryInterchange::from_bits`, `BinaryInterchange::from_hex`, `BinaryInterchange::to_hex`

Build or print an encoding.

```mbti
pub fn BinaryInterchange::from_bits(BinCoeff, BinaryInterchangeFormat) -> Self
pub fn BinaryInterchange::from_hex(String, BinaryInterchangeFormat) -> Self?
pub fn BinaryInterchange::to_hex(Self) -> String
```

`from_bits` keeps the low `total_bits` bits. `from_hex` needs exactly
`total_bits / 4` hexadecimal digits, optionally prefixed with `0x` or `#`, and
returns `None` otherwise. `to_hex` prints upper-case digits padded to the full
width.

### `BinaryInterchange::to_bin_float`

Decodes an encoding exactly.

```mbti
pub fn BinaryInterchange::to_bin_float(Self) -> BinFloat
```

The result has the format precision. Normal and subnormal numbers, signed
zeros and infinities decode exactly; a NaN keeps its sign and payload (the
fraction without the quiet bit), and a signaling NaN stays signaling. No host
`Float` or `Double` is involved.

### `BinaryInterchange::from_bin_float`, `BinFloat::to_interchange`

Round a value into a format and encode it.

```mbti
pub fn BinaryInterchange::from_bin_float(BinFloat, BinaryInterchangeFormat, rounding? : BinaryRoundingMode, tininess? : TininessDetection) -> (Self, BinaryFlags)
pub fn BinFloat::to_interchange(Self, BinaryInterchangeFormat, rounding? : BinaryRoundingMode, tininess? : TininessDetection) -> (BinaryInterchange, BinaryFlags)
```

The two are the same operation: `round_ctx` with the format's context, then
encoding. A signaling NaN is encoded as a quiet NaN with `invalid_operation`,
and a payload is truncated to the payload field.

```moonbit
///|
test "encode and decode interchange bits" {
  let b32 = @bin_float.BinaryInterchangeFormat::Binary32
  let tenth = @bin_float.BinFloat::from_string("0.1", precision=200).unwrap()
  let (nearest, flags) = tenth.to_interchange(b32)
  inspect("\{nearest.to_hex()} \{flags.inexact()}", content="3DCCCCCD true")
  let (chopped, _) = tenth.to_interchange(
    b32,
    rounding=@bin_float.BinaryRoundingMode::RoundTowardZero,
  )
  inspect(chopped.to_hex(), content="3DCCCCCC")
  let snan = @bin_float.BinaryInterchange::from_hex("7F800001", b32)
    .unwrap()
    .to_bin_float()
  let (quieted, nan_flags) = snan.to_interchange(b32)
  inspect("\{quieted.to_hex()} \{nan_flags.invalid_operation()}", content="7FC00001 true")
}
```

## Elementary functions

Each elementary function has three forms:

- `f(x)` rounds to nearest-even at the precision of `x` (the larger precision
  for two operands) with the implementation exponent range;
- `f_ctx(x, ctx)` rounds under `ctx` and returns `(value, flags)`;
- `try_f_ctx(x, ctx)` returns the same pair in `Ok`, or an
  `@lf_arith.ArithmeticError`.

All three run the same certified algorithm. It computes an enclosure
$[L, U] \ni f(x)$ whose every internal operation is rounded downward for $L$
and upward for $U$, at a working precision $w$ that starts at $p + 64$ bits
(or at the operand precision plus 16 when that is larger, for `rootn`, the
inverse trigonometric and the hyperbolic functions). If $L$ and $U$ round to
the same value with the same flags, that value is returned; otherwise $w$
grows by $\max(32, \lfloor w/2 \rfloor)$, for at most 12 attempts. Because
rounding is monotone, a returned value is the correctly rounded result
$\circ(f(x))$, never an uncertified approximation; the
[design page](../design/bin_float.md#certified-elementary-functions) gives the
argument and lists the cases where the flags can still be wrong.

When the attempts run out, `try_f_ctx` returns a `certification_failure`
error whose `CertificationFailureDetail` names the operation, the stage
(`RangeReduction` or `TargetRounding`), the reason and the last working
precision. An argument outside the real domain gives a `domain_error` from
`try_f_ctx`. The non-`try` forms turn both kinds of error into a quiet NaN
with `invalid_operation`. NaN operands propagate quietly (a signaling NaN
raises `invalid_operation`), and poles return a signed infinity with
`division_by_zero` (for example $\ln 0 = -\infty$,
$\operatorname{atanh}(1) = +\infty$). Exactly representable results that an
enclosure cannot isolate are detected before the loop, for example
$\log_2 2^k = k$, $2^n$ for integral $n$, $\sin(\pm 0) = \pm 0$ and
$\operatorname{sinpi}(1/2) = 1$; each function lists its own cases below.

> [!WARNING]
> Two families of inputs defeat the certification on the current branch.
>
> - **Tiny arguments.** For `exp`, `expm1`, `exp2`, `sin` and `atan` (and
>   possibly others built the same way) an argument so small that the series
>   stops after its first term yields an enclosure with one end exactly on a
>   representable number ($1$ for `exp`, $x$ itself for `sin`). That end
>   rounds without `inexact`, the other end with it, so the flags never agree
>   and the budget runs out. For example `try_sin_ctx` of $2^{-6000}$ at 53
>   bits, of $2^{-8000}$ in `binary128()`, and `try_exp_ctx` of $2^{-20000}$
>   at 53 bits all return a `certification_failure`, and the plain forms
>   return NaN. Arguments of binary64 size are not affected. For such tiny
>   $x$ use the first terms of the series yourself ($\sin x \approx x$,
>   $e^x \approx 1 + x$) with a directed rounding.
> - **Exact results that are not filtered.** A result that is exactly
>   representable but not recognised before the loop is returned with a
>   spurious `inexact` under nearest rounding and is a `certification_failure`
>   under a directed rounding. This happens for `pow` with a non-integral
>   exponent such as $16^{3/4} = 8$, for `rootn` with a negative degree such
>   as $8^{-1/3} = 1/2$ (and `pow(4, -0.5)`), and for $10^n$ and
>   $\log_{10} 10^n$ with $n > 4096$ at a precision large enough to hold
>   $10^n$.

### `BinFloat::exp`, `BinFloat::exp_ctx`, `BinFloat::try_exp_ctx`

The exponential $e^x$.

```mbti
pub fn BinFloat::exp(Self) -> Self
pub fn BinFloat::exp_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn BinFloat::try_exp_ctx(Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
```

Defined on all of $\mathbb{R}$: $e^{\pm 0} = 1$ exactly, $e^{-\infty} = +0$
and $e^{+\infty} = +\infty$. Results certainly beyond the exponent range are
decided from certified bounds on $\log_2 e$ before the main loop, so huge
arguments overflow or underflow with the correct flags instead of failing.

### `BinFloat::expm1`, `BinFloat::expm1_ctx`, `BinFloat::try_expm1_ctx`

$e^x - 1$ without the cancellation of `exp(x) - 1` near zero.

```mbti
pub fn BinFloat::expm1(Self) -> Self
pub fn BinFloat::expm1_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn BinFloat::try_expm1_ctx(Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
```

$\operatorname{expm1}(\pm 0) = \pm 0$, $\operatorname{expm1}(-\infty) = -1$
and $\operatorname{expm1}(+\infty) = +\infty$. For
$x \le -(p+3)\ln 2$ the value lies within $2^{-(p+3)}$ above $-1$, and the
result is decided from the rounding direction alone: $-1$, or
$-(1 - 2^{-p})$ when rounding toward zero or $+\infty$, always inexact.

### `BinFloat::exp2`, `BinFloat::exp2_ctx`, `BinFloat::try_exp2_ctx`

The power of two $2^x$.

```mbti
pub fn BinFloat::exp2(Self) -> Self
pub fn BinFloat::exp2_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn BinFloat::try_exp2_ctx(Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
```

An integral $x$ with $|x| < 2^{31}$ gives the exact $2^x$, rounded into the
context only when it leaves the exponent range. The other special values are
those of `exp`.

### `BinFloat::exp10`, `BinFloat::exp10_ctx`, `BinFloat::try_exp10_ctx`

The power of ten $10^x$.

```mbti
pub fn BinFloat::exp10(Self) -> Self
pub fn BinFloat::exp10_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn BinFloat::try_exp10_ctx(Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
```

An integral $x$ in $[0, 4096]$ gives the exact $10^x = 5^x 2^x$, rounded once.
A negative integral $x$ gives a value that is never dyadic, so it is always
inexact. The other special values are those of `exp`.

### `BinFloat::ln`, `BinFloat::ln_ctx`, `BinFloat::try_ln_ctx`

The natural logarithm $\ln x$.

```mbti
pub fn BinFloat::ln(Self) -> Self
pub fn BinFloat::ln_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn BinFloat::try_ln_ctx(Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
```

The domain is $x > 0$. $\ln 1 = +0$ exactly; $\ln(\pm 0) = -\infty$ with
`division_by_zero`; $\ln(+\infty) = +\infty$. A negative finite argument is a
`domain_error`, while $-\infty$ gives a quiet NaN with `invalid_operation`
also from `try_ln_ctx`.

### `BinFloat::log1p`, `BinFloat::log1p_ctx`, `BinFloat::try_log1p_ctx`

$\ln(1 + x)$ without the rounding of `1 + x`.

```mbti
pub fn BinFloat::log1p(Self) -> Self
pub fn BinFloat::log1p_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn BinFloat::try_log1p_ctx(Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
```

The domain is $x > -1$. $\operatorname{log1p}(\pm 0) = \pm 0$,
$\operatorname{log1p}(-1) = -\infty$ with `division_by_zero`, a finite
$x < -1$ is a `domain_error`, and $-\infty$ gives a quiet NaN with
`invalid_operation`.

### `BinFloat::log2`, `BinFloat::log2_ctx`, `BinFloat::try_log2_ctx`

The binary logarithm $\log_2 x$.

```mbti
pub fn BinFloat::log2(Self) -> Self
pub fn BinFloat::log2_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn BinFloat::try_log2_ctx(Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
```

Special values and domain as for `ln`. A power of two $2^k$ gives the exact
integer $k$, rounded into the context.

### `BinFloat::log10`, `BinFloat::log10_ctx`, `BinFloat::try_log10_ctx`

The decimal logarithm $\log_{10} x$.

```mbti
pub fn BinFloat::log10(Self) -> Self
pub fn BinFloat::log10_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn BinFloat::try_log10_ctx(Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
```

Special values and domain as for `ln`. $x = 10^k$ with $1 \le k \le 4096$
gives the exact integer $k$.

### `BinFloat::exp_ln`, `BinFloat::exp_ln_ctx`, `BinFloat::try_exp_ln_ctx`

The fused composition $\ln(e^x)$, which equals $x$.

```mbti
pub fn BinFloat::exp_ln(Self) -> Self
pub fn BinFloat::exp_ln_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn BinFloat::try_exp_ln_ctx(Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
```

The result is $x$ rounded once into the context, without two intermediate
roundings. The current implementation accepts finite arguments with
$|x| \le 1/8$ and infinities; any other finite argument is a
`certification_failure` at the range-reduction stage (reason
`RangeNotCertified`).

### `BinFloat::pow`, `BinFloat::pow_ctx`, `BinFloat::try_pow_ctx`

The real power $x^y$.

```mbti
pub fn BinFloat::pow(Self, Self) -> Self
pub fn BinFloat::pow_ctx(Self, Self, BinaryContext) -> (Self, BinaryFlags)
pub fn BinFloat::try_pow_ctx(Self, Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
```

The cases are tried in this order:

1. $x^{\pm 0} = 1$ for every $x$, and $1^y = 1$ for every $y$, NaN included
   (also a signaling NaN, without `invalid_operation`).
2. An integral $y$ with $|y| < 2^{31}$ is `pown_ctx(x, y)`.
3. $y = \pm 2^{-k}$ with $1 \le k \le 29$ is `try_rootn_ctx(x, \pm 2^k)`.
4. A NaN operand propagates.
5. A negative finite $x$, including $-0$, is a `domain_error`.
6. $(+0)^{y<0} = +\infty$ with `division_by_zero`, $(+0)^{y>0} = +0$;
   $(\pm\infty)^{y<0} = +0$, $(\pm\infty)^{y>0} = +\infty$.
7. An infinite $y$ gives $+\infty$ or $+0$ according to whether $|x^y|$ grows.
8. Otherwise the value is certified from enclosures of $e^{y \ln x}$, after
   certain overflow and underflow have been decided from $\log_2 x$.

> [!WARNING]
> Step 5 comes too early, and steps 6 and 7 ignore the sign of an infinite
> base, so `pow` departs from IEEE 754 `pow` for some inputs: a negative base
> with an integral exponent of magnitude at least $2^{31}$, a base of $-0$
> with any exponent not handled by steps 1 to 3, and a negative finite base
> with an infinite exponent (IEEE gives $1$ for $(-1)^{\pm\infty}$) are
> `domain_error`s; $(-\infty)^y$ for an odd integral $y$ with
> $|y| \ge 2^{31}$ has the wrong sign; and $(+0)^{-\infty} = +\infty$ raises
> `division_by_zero`, which IEEE does not. Dyadic results of non-integral
> exponents, such as $16^{3/4} = 8$, carry a spurious `inexact` or fail under
> directed rounding (see the warning above).

### `BinFloat::rootn`, `BinFloat::rootn_ctx`, `BinFloat::try_rootn_ctx`

The real $n$-th root $x^{1/n}$.

```mbti
pub fn BinFloat::rootn(Self, Int) -> Self
pub fn BinFloat::rootn_ctx(Self, Int, BinaryContext) -> (Self, BinaryFlags)
pub fn BinFloat::try_rootn_ctx(Self, Int, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
```

$n = 0$ is a `domain_error`, and $|n| > 10^9$ a `certification_failure`.
Odd $n$ accepts a negative $x$ ($\operatorname{rootn}(-8, 3) = -2$); a
negative finite $x$ with even $n$ is a `domain_error`. A negative $n$ gives
$x^{-1/|n|}$. Zeros: $\operatorname{rootn}(\pm 0, n > 0)$ is $\pm 0$ for odd
$n$ and $+0$ for even $n$; $\operatorname{rootn}(\pm 0, n < 0)$ is
$\pm\infty$ (odd) or $+\infty$ (even) with `division_by_zero`. For $n > 1$,
degree at most 64 and a coefficient of at most 4096 bits, an exact root is
detected and returned without `inexact`.

> [!WARNING]
> $\operatorname{rootn}(-\infty, n)$ with even $n$ returns $+\infty$ (and
> $+0$ for even negative $n$) instead of a `domain_error`, unlike a finite
> negative argument. Exact roots with a negative degree are not detected (see
> the warning at the start of this section).

### `BinFloat::hypot`, `BinFloat::hypot_ctx`, `BinFloat::try_hypot_ctx`

$\sqrt{x^2 + y^2}$ without intermediate overflow or underflow.

```mbti
pub fn BinFloat::hypot(Self, Self) -> Self
pub fn BinFloat::hypot_ctx(Self, Self, BinaryContext) -> (Self, BinaryFlags)
pub fn BinFloat::try_hypot_ctx(Self, Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
```

The squares are formed exactly and one correctly rounded square root is
taken, so the result is $\circ(\sqrt{x^2+y^2})$ and exact when the root is.
$\operatorname{hypot}(\pm\infty, y) = +\infty$ even when $y$ is a NaN
(`invalid_operation` is raised only for a signaling NaN). Because the exact
sum is built, operands whose stored exponents differ by more than $500\,000$
(possible only in wide or unbounded contexts) give a `certification_failure`.

### `BinFloat::sin`, `BinFloat::sin_ctx`, `BinFloat::try_sin_ctx`

The sine of an argument in radians.

```mbti
pub fn BinFloat::sin(Self) -> Self
pub fn BinFloat::sin_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn BinFloat::try_sin_ctx(Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
```

$\sin(\pm 0) = \pm 0$ exactly; an infinite argument is a `domain_error`. The
argument is reduced by an enclosure of $\pi/2$ computed at a working precision
of at least $p + \max(0, \lfloor\log_2|x|\rfloor + 1) + 96$ bits, so the
quadrant is certain for every finite input. When that starting precision
exceeds $10^6$ bits, that is for $|x| \ge 2^{10^6 - p - 96}$, the result is a
`certification_failure` with stage `RangeReduction` and reason
`ResourceLimit`, returned at once; no attempt goes beyond $10^6$ bits.

### `BinFloat::cos`, `BinFloat::cos_ctx`, `BinFloat::try_cos_ctx`

The cosine of an argument in radians.

```mbti
pub fn BinFloat::cos(Self) -> Self
pub fn BinFloat::cos_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn BinFloat::try_cos_ctx(Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
```

$\cos(\pm 0) = 1$ exactly. Reduction, domain and limits as for `sin`.

### `BinFloat::tan`, `BinFloat::tan_ctx`, `BinFloat::try_tan_ctx`

The tangent of an argument in radians.

```mbti
pub fn BinFloat::tan(Self) -> Self
pub fn BinFloat::tan_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn BinFloat::try_tan_ctx(Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
```

$\tan(\pm 0) = \pm 0$ exactly. Reduction, domain and limits as for `sin`. No
binary argument is an odd multiple of $\pi/2$, so there is no pole; an
enclosure of the cosine that contains zero is refined like any other.

### `BinFloat::sinpi`, `BinFloat::sinpi_ctx`, `BinFloat::try_sinpi_ctx`

$\sin(\pi x)$.

```mbti
pub fn BinFloat::sinpi(Self) -> Self
pub fn BinFloat::sinpi_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn BinFloat::try_sinpi_ctx(Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
```

The period is reduced exactly on the binary representation, so huge
arguments cost nothing extra. For integral $n$, $\operatorname{sinpi}(n)$ is
$\pm 0$ with the sign of $n$; at $n + \frac12$ it is $\pm 1$. An infinite
argument is a `domain_error`. By Niven's theorem these are the only dyadic
arguments with a dyadic result.

### `BinFloat::cospi`, `BinFloat::cospi_ctx`, `BinFloat::try_cospi_ctx`

$\cos(\pi x)$.

```mbti
pub fn BinFloat::cospi(Self) -> Self
pub fn BinFloat::cospi_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn BinFloat::try_cospi_ctx(Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
```

$\operatorname{cospi}(n) = (-1)^n$ for integral $n$ and
$\operatorname{cospi}(n + \frac12) = +0$. Reduction and domain as for
`sinpi`.

### `BinFloat::tanpi`, `BinFloat::tanpi_ctx`, `BinFloat::try_tanpi_ctx`

$\tan(\pi x)$.

```mbti
pub fn BinFloat::tanpi(Self) -> Self
pub fn BinFloat::tanpi_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn BinFloat::try_tanpi_ctx(Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
```

$\operatorname{tanpi}(n)$ is $\pm 0$ with the sign of $n$ for integral $n$;
$\operatorname{tanpi}(n + \frac12)$ is $+\infty$ for even $n$ and $-\infty$
for odd $n$, with `division_by_zero`; $\operatorname{tanpi}(n \pm \frac14) =
\pm 1$ exactly. Reduction and domain as for `sinpi`.

### `BinFloat::asin`, `BinFloat::asin_ctx`, `BinFloat::try_asin_ctx`

The arcsine, with values in $[-\pi/2, \pi/2]$.

```mbti
pub fn BinFloat::asin(Self) -> Self
pub fn BinFloat::asin_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn BinFloat::try_asin_ctx(Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
```

The domain is $[-1, 1]$; a finite argument outside it and both infinities are
a `domain_error`. $\operatorname{asin}(\pm 0) = \pm 0$ and
$\operatorname{asin}(\pm 1) = \pm\pi/2$ correctly rounded.

### `BinFloat::acos`, `BinFloat::acos_ctx`, `BinFloat::try_acos_ctx`

The arccosine, with values in $[0, \pi]$.

```mbti
pub fn BinFloat::acos(Self) -> Self
pub fn BinFloat::acos_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn BinFloat::try_acos_ctx(Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
```

The domain is $[-1, 1]$; a finite argument outside it and both infinities are
a `domain_error`, and a NaN propagates as for `asin`. On $[-1, 1]$ the result
is $\pi/2 - \operatorname{asin}(x)$ evaluated as one enclosure;
$\operatorname{acos}(1) = +0$ exactly and $\operatorname{acos}(-1) = \pi$
correctly rounded.

### `BinFloat::atan`, `BinFloat::atan_ctx`, `BinFloat::try_atan_ctx`

The arctangent, with values in $[-\pi/2, \pi/2]$.

```mbti
pub fn BinFloat::atan(Self) -> Self
pub fn BinFloat::atan_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn BinFloat::try_atan_ctx(Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
```

Defined on all of $\mathbb{R}$: $\operatorname{atan}(\pm 0) = \pm 0$ and
$\operatorname{atan}(\pm\infty) = \pm\pi/2$ correctly rounded.

### `BinFloat::atan2`, `BinFloat::atan2_ctx`, `BinFloat::try_atan2_ctx`

The angle of the point $(x, y)$ for `y.atan2(x)`, in $[-\pi, \pi]$.

```mbti
pub fn BinFloat::atan2(Self, Self) -> Self
pub fn BinFloat::atan2_ctx(Self, Self, BinaryContext) -> (Self, BinaryFlags)
pub fn BinFloat::try_atan2_ctx(Self, Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
```

The receiver is the ordinate $y$. Infinite operands follow IEEE 754: for
example $\operatorname{atan2}(\pm\infty, -\infty) = \pm 3\pi/4$,
$\operatorname{atan2}(\pm\infty, +\infty) = \pm\pi/4$,
$\operatorname{atan2}(y, -\infty) = \pm\pi$ and
$\operatorname{atan2}(y, +\infty) = \pm 0$ with the sign of $y$ for finite
$y$. $\operatorname{atan2}(\pm 0, x > 0) = \pm 0$ and
$\operatorname{atan2}(y \ne 0, \pm 0) = \pm\pi/2$.

> [!WARNING]
> `atan2` ignores the sign of a zero in two IEEE special cases:
> $\operatorname{atan2}(\pm 0, \pm 0)$ returns $\pm\pi/2$ (sign of $y$) instead
> of $\pm 0$ for $x = +0$ and $\pm\pi$ for $x = -0$, and
> $\operatorname{atan2}(-0, x < 0)$ returns $+\pi$ instead of $-\pi$.

### `BinFloat::sinh`, `BinFloat::sinh_ctx`, `BinFloat::try_sinh_ctx`

The hyperbolic sine.

```mbti
pub fn BinFloat::sinh(Self) -> Self
pub fn BinFloat::sinh_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn BinFloat::try_sinh_ctx(Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
```

$\sinh(\pm 0) = \pm 0$ and $\sinh(\pm\infty) = \pm\infty$. Certain overflow
is decided before the loop from $|\sinh x| \ge e^{|x|}/4$.

### `BinFloat::cosh`, `BinFloat::cosh_ctx`, `BinFloat::try_cosh_ctx`

The hyperbolic cosine.

```mbti
pub fn BinFloat::cosh(Self) -> Self
pub fn BinFloat::cosh_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn BinFloat::try_cosh_ctx(Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
```

$\cosh(\pm 0) = 1$ and $\cosh(\pm\infty) = +\infty$; certain overflow is
decided as for `sinh`.

### `BinFloat::tanh`, `BinFloat::tanh_ctx`, `BinFloat::try_tanh_ctx`

The hyperbolic tangent.

```mbti
pub fn BinFloat::tanh(Self) -> Self
pub fn BinFloat::tanh_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn BinFloat::try_tanh_ctx(Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
```

$\tanh(\pm 0) = \pm 0$ and $\tanh(\pm\infty) = \pm 1$ exactly.

### `BinFloat::asinh`, `BinFloat::asinh_ctx`, `BinFloat::try_asinh_ctx`

The inverse hyperbolic sine.

```mbti
pub fn BinFloat::asinh(Self) -> Self
pub fn BinFloat::asinh_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn BinFloat::try_asinh_ctx(Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
```

Defined on all of $\mathbb{R}$; $\operatorname{asinh}(\pm 0) = \pm 0$ and
$\operatorname{asinh}(\pm\infty) = \pm\infty$.

### `BinFloat::acosh`, `BinFloat::acosh_ctx`, `BinFloat::try_acosh_ctx`

The inverse hyperbolic cosine.

```mbti
pub fn BinFloat::acosh(Self) -> Self
pub fn BinFloat::acosh_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn BinFloat::try_acosh_ctx(Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
```

The domain is $x \ge 1$; any smaller argument, $-\infty$ included, is a
`domain_error`. $\operatorname{acosh}(1) = +0$ and
$\operatorname{acosh}(+\infty) = +\infty$.

### `BinFloat::atanh`, `BinFloat::atanh_ctx`, `BinFloat::try_atanh_ctx`

The inverse hyperbolic tangent.

```mbti
pub fn BinFloat::atanh(Self) -> Self
pub fn BinFloat::atanh_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn BinFloat::try_atanh_ctx(Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
```

The domain is $|x| \le 1$; outside it, infinities included, the result is a
`domain_error`. $\operatorname{atanh}(\pm 0) = \pm 0$ and
$\operatorname{atanh}(\pm 1) = \pm\infty$ with `division_by_zero`.

```moonbit
///|
test "elementary functions are correctly rounded" {
  let ctx = @bin_float.BinaryContext::binary64()
  let one = @bin_float.BinFloat::one()
  inspect(one.exp_ctx(ctx).0.to_shortest_string(), content="2.718281828459045")
  inspect(@bin_float.BinFloat::from_int(8).log2(), content="3p0")
  let (big, flags) = @bin_float.BinFloat::from_int(1000).exp_ctx(ctx)
  inspect("\{big} \{flags.overflow()}", content="inf true")
  match @bin_float.BinFloat::from_int(-1).try_ln_ctx(ctx) {
    Ok(_) => fail("ln(-1) has no real value")
    Err(error) => inspect(error.is_domain_error(), content="true")
  }
  let (nan, nan_flags) = @bin_float.BinFloat::from_int(-1).ln_ctx(ctx)
  inspect("\{nan} \{nan_flags.invalid_operation()}", content="nan true")
  let (root, root_flags) = @bin_float.BinFloat::from_int(-8).rootn_ctx(3, ctx)
  inspect("\{root} \{root_flags.inexact()}", content="-1p1 false")
  let (pole, pole_flags) = @bin_float.BinFloat::from_string("0.5")
    .unwrap()
    .tanpi_ctx(ctx)
  inspect("\{pole} \{pole_flags.division_by_zero()}", content="inf true")
}
```

## Trait implementations

### `BinFloat::equal`, `BinFloat::not_equal`

Structural equality, the derived `Eq`.

```mbti
pub fn BinFloat::equal(Self, Self) -> Bool
pub fn BinFloat::not_equal(Self, Self) -> Bool
```

See [`BinFloat`](#binfloat): this compares representations, not numbers, so
`==` distinguishes $\pm 0$ and precisions and identifies equal NaNs.

### `BinFloat::op_lt`, `BinFloat::op_le`, `BinFloat::op_gt`, `BinFloat::op_ge`

The `Compare` methods behind `<`, `<=`, `>` and `>=`.

```mbti
pub fn BinFloat::op_lt(Self, Self) -> Bool
pub fn BinFloat::op_le(Self, Self) -> Bool
pub fn BinFloat::op_gt(Self, Self) -> Bool
pub fn BinFloat::op_ge(Self, Self) -> Bool
```

They use [`compare`](#binfloatcompare), so NaN is greater than every number:
`nan > x` is `true`. Use the [IEEE predicates](#binfloatequal_quiet-binfloatless_quiet-binfloatless_equal_quiet-binfloatunordered_quiet-binfloatequal_signaling-binfloatless_signaling-binfloatless_equal_signaling)
when NaN must be unordered.

### `BinFloat::output`, `BinFloat::to_repr`

The `Show` and `Debug` methods.

```mbti
pub fn BinFloat::output(Self, &Logger) -> Unit
pub fn BinFloat::to_repr(Self) -> @debug.Repr
```

`output` writes the exact `c p e` form of [`to_string`](#binfloatto_string).
`to_repr` (used by `debug_inspect`) shows every private field.

### `@def.Floating`

The shared floating-point vocabulary of `floating`.

```mbti
pub impl @def.Floating for BinFloat
```

`classify`, `sign`, `precision`, `with_precision` and `normalized` are the
inherent methods above. Generic code uses `@def.is_finite`, `@def.is_nan`,
`@def.is_infinite` and `@def.is_zero`.

### `BinFloat::sqrt_checked`, `BinFloat::pow_nat_checked`, `BinFloat::pow_int_checked`

`@lf_arith` traits whose methods return `Result`.

```mbti
pub impl @arithmetic.SqrtChecked for BinFloat
pub impl @arithmetic.DivChecked for BinFloat
pub impl @arithmetic.CompareChecked for BinFloat
pub impl @arithmetic.PowNatChecked for BinFloat
pub impl @arithmetic.PowIntChecked for BinFloat
pub fn BinFloat::sqrt_checked(Self, @arithmetic.ArithmeticContext) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BinFloat::pow_nat_checked(Self, UInt, @arithmetic.ArithmeticContext) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BinFloat::pow_int_checked(Self, Int, @arithmetic.ArithmeticContext) -> Result[Self, @arithmetic.ArithmeticError]
```

Each converts the `ArithmeticContext` with
`BinaryContext::from_arithmetic_context` (which aborts for a precision above
`binary_precision_max`), runs the contextual operation and drops the flags.
`sqrt_checked` is a `domain_error` for a negative nonzero argument (as for
`sqrt`, this includes $-\infty$ and a NaN with its sign bit set);
`DivChecked::div_checked` is a `division_by_zero` error for a finite zero
divisor; `pow_int_checked` is a `division_by_zero` error for a zero base with
a negative exponent; `pow_nat_checked` never fails. The trait's
`div_checked(x, y, ctx)` takes a context; the inherent
[`BinFloat::div_checked`](#binfloatdiv_checked) does not.
`CompareChecked::compare_checked` is the inherent
[`compare_checked`](#binfloatcompare_checked).

### `BinFloat::add_contextual`, `BinFloat::sub_contextual`, `BinFloat::mul_contextual`, `BinFloat::div_contextual`, `BinFloat::abs_contextual`, `BinFloat::sqrt_contextual`, `BinFloat::exp_contextual`

`@lf_arith` traits that return an `ArithmeticOutcome` with diagnostics.

```mbti
pub impl @arithmetic.AddContextual for BinFloat
pub impl @arithmetic.SubContextual for BinFloat
pub impl @arithmetic.MulContextual for BinFloat
pub impl @arithmetic.DivContextual for BinFloat
pub impl @arithmetic.AbsContextual for BinFloat
pub impl @arithmetic.SqrtContextual for BinFloat
pub impl @arithmetic.ExpContextual for BinFloat
pub fn BinFloat::add_contextual(Self, Self, @arithmetic.ArithmeticContext) -> Result[@arithmetic.ArithmeticOutcome[Self], @arithmetic.ArithmeticError]
pub fn BinFloat::sub_contextual(Self, Self, @arithmetic.ArithmeticContext) -> Result[@arithmetic.ArithmeticOutcome[Self], @arithmetic.ArithmeticError]
pub fn BinFloat::mul_contextual(Self, Self, @arithmetic.ArithmeticContext) -> Result[@arithmetic.ArithmeticOutcome[Self], @arithmetic.ArithmeticError]
pub fn BinFloat::div_contextual(Self, Self, @arithmetic.ArithmeticContext) -> Result[@arithmetic.ArithmeticOutcome[Self], @arithmetic.ArithmeticError]
pub fn BinFloat::abs_contextual(Self, @arithmetic.ArithmeticContext) -> Result[@arithmetic.ArithmeticOutcome[Self], @arithmetic.ArithmeticError]
pub fn BinFloat::sqrt_contextual(Self, @arithmetic.ArithmeticContext) -> Result[@arithmetic.ArithmeticOutcome[Self], @arithmetic.ArithmeticError]
pub fn BinFloat::exp_contextual(Self, @arithmetic.ArithmeticContext) -> Result[@arithmetic.ArithmeticOutcome[Self], @arithmetic.ArithmeticError]
```

Each runs the matching `*_ctx` method (for `abs`, `abs` followed by
`round_ctx`; for `exp`, `try_exp_ctx`) under the converted context. A result
with `division_by_zero` becomes a `division_by_zero` error and one with
`invalid_operation` a `domain_error`; a certification failure of `exp` is
returned as is. Otherwise the value is returned with `ArithmeticDiagnostics`
whose `inexact` and `rounded` are the inexact flag and whose `overflow` and
`underflow` are the matching flags.

### `BinCoeff::op_lt`, `BinCoeff::op_le`, `BinCoeff::op_gt`, `BinCoeff::op_ge`, `BinCoeff::not_equal`

The `Compare` and `Eq` methods of `BinCoeff`, behind `<`, `<=`, `>`, `>=` and
`!=`.

```mbti
pub fn BinCoeff::op_lt(Self, Self) -> Bool
pub fn BinCoeff::op_le(Self, Self) -> Bool
pub fn BinCoeff::op_gt(Self, Self) -> Bool
pub fn BinCoeff::op_ge(Self, Self) -> Bool
pub fn BinCoeff::not_equal(Self, Self) -> Bool
pub impl Add for BinCoeff
pub impl Compare for BinCoeff
pub impl Eq for BinCoeff
pub impl Mul for BinCoeff
pub impl Shl for BinCoeff
pub impl Show for BinCoeff
pub impl Shr for BinCoeff
```

They agree with [`BinCoeff::compare`](#bincoeffcompare-bincoeffequal); `+`,
`*`, `<<` and `>>` are `add`, `mul`, `shl` and `shr`.

### `BinCoeff::output`, `BinCoeff::to_repr`

The `Show` and `Debug` methods of `BinCoeff`.

```mbti
pub fn BinCoeff::output(Self, &Logger) -> Unit
pub fn BinCoeff::to_repr(Self) -> @debug.Repr
```

`output` writes the decimal digits of [`to_string`](#bincoeffparse-bincoeffto_string-bincoeffto_radix_string).

### `BinaryRoundingMode::equal`, `BinaryRoundingMode::not_equal`, `BinaryRoundingMode::to_repr`

The derived `Eq` and `Debug` methods of `BinaryRoundingMode`.

```mbti
pub fn BinaryRoundingMode::equal(Self, Self) -> Bool
pub fn BinaryRoundingMode::not_equal(Self, Self) -> Bool
pub fn BinaryRoundingMode::to_repr(Self) -> @debug.Repr
```

### `TininessDetection::equal`, `TininessDetection::not_equal`, `TininessDetection::to_repr`

The derived `Eq` and `Debug` methods of `TininessDetection`.

```mbti
pub fn TininessDetection::equal(Self, Self) -> Bool
pub fn TininessDetection::not_equal(Self, Self) -> Bool
pub fn TininessDetection::to_repr(Self) -> @debug.Repr
```

### `BinaryContext::equal`, `BinaryContext::not_equal`, `BinaryContext::to_repr`

The derived `Eq` and `Debug` methods of `BinaryContext`.

```mbti
pub fn BinaryContext::equal(Self, Self) -> Bool
pub fn BinaryContext::not_equal(Self, Self) -> Bool
pub fn BinaryContext::to_repr(Self) -> @debug.Repr
```

Equality compares the fields as given: `BinaryContext::new(53)` is not equal
to `BinaryContext::new(53, e_max=binary_implementation_e_max)` although the
two behave identically.

### `BinaryFlags::equal`, `BinaryFlags::not_equal`, `BinaryFlags::to_repr`

The derived `Eq` and `Debug` methods of `BinaryFlags`.

```mbti
pub fn BinaryFlags::equal(Self, Self) -> Bool
pub fn BinaryFlags::not_equal(Self, Self) -> Bool
pub fn BinaryFlags::to_repr(Self) -> @debug.Repr
```

### `BinaryInterchangeFormat::equal`, `BinaryInterchangeFormat::not_equal`, `BinaryInterchangeFormat::to_repr`

The derived `Eq` and `Debug` methods of `BinaryInterchangeFormat`.

```mbti
pub fn BinaryInterchangeFormat::equal(Self, Self) -> Bool
pub fn BinaryInterchangeFormat::not_equal(Self, Self) -> Bool
pub fn BinaryInterchangeFormat::to_repr(Self) -> @debug.Repr
```

### `BinaryInterchange::equal`, `BinaryInterchange::not_equal`

The derived `Eq` of `BinaryInterchange`: format and bits must agree.

```mbti
pub fn BinaryInterchange::equal(Self, Self) -> Bool
pub fn BinaryInterchange::not_equal(Self, Self) -> Bool
```

## Complete public interface

<!-- generated-api-start -->
```mbti
// Generated using `moon info`, DON'T EDIT IT
package "Luna-Flow/floating/bin_float"

import {
  "Luna-Flow/arithmetic",
  "Luna-Flow/floating/def",
  "moonbitlang/core/debug",
}

// Values
pub let binary_implementation_e_max : Int

pub let binary_implementation_e_min : Int

pub let binary_precision_max : Int

pub fn sqrt_bounds_for_precision(BinFloat, Int) -> Result[(BinFloat, BinFloat), @arithmetic.ArithmeticError]

pub fn sqrt_for_precision(BinFloat, Int) -> Result[BinFloat, @arithmetic.ArithmeticError]

// Errors

// Types and methods
pub struct BinCoeff {
  // private fields
} derive(@debug.Debug)
pub fn BinCoeff::add(Self, Self) -> Self
pub fn BinCoeff::bit_and(Self, Self) -> Self
pub fn BinCoeff::bit_length(Self) -> Int
pub fn BinCoeff::bit_or(Self, Self) -> Self
pub fn BinCoeff::bit_xor(Self, Self) -> Self
pub fn BinCoeff::compare(Self, Self) -> Int
pub fn BinCoeff::ctz(Self) -> Int
pub fn BinCoeff::div_rem_checked(Self, Self) -> Result[(Self, Self), String]
pub fn BinCoeff::equal(Self, Self) -> Bool
pub fn BinCoeff::from_bytes_be(BytesView) -> Self
pub fn BinCoeff::from_uint64(UInt64) -> Self
pub fn BinCoeff::gcd(Self, Self) -> Self
pub fn BinCoeff::is_zero(Self) -> Bool
pub fn BinCoeff::mul(Self, Self) -> Self
pub fn BinCoeff::not_equal(Self, Self) -> Bool
pub fn BinCoeff::one() -> Self
pub fn BinCoeff::op_ge(Self, Self) -> Bool
pub fn BinCoeff::op_gt(Self, Self) -> Bool
pub fn BinCoeff::op_le(Self, Self) -> Bool
pub fn BinCoeff::op_lt(Self, Self) -> Bool
pub fn BinCoeff::output(Self, &Logger) -> Unit
pub fn BinCoeff::parse(String, radix? : Int) -> Result[Self, String]
pub fn BinCoeff::pow_nat(Self, UInt) -> Self
pub fn BinCoeff::shift_left(Self, Int) -> Self
pub fn BinCoeff::shift_right(Self, Int) -> Self
pub fn BinCoeff::shl(Self, Int) -> Self
pub fn BinCoeff::shr(Self, Int) -> Self
pub fn BinCoeff::square(Self) -> Self
pub fn BinCoeff::sub_checked(Self, Self) -> Result[Self, String]
pub fn BinCoeff::test_bit(Self, Int) -> Bool
pub fn BinCoeff::to_bytes_be(Self) -> Bytes
pub fn BinCoeff::to_radix_string(Self, Int) -> String
pub fn BinCoeff::to_repr(Self) -> @debug.Repr
pub fn BinCoeff::to_string(Self) -> String
pub fn BinCoeff::to_uint64(Self) -> UInt64?
pub fn BinCoeff::zero() -> Self
pub impl Add for BinCoeff
pub impl Compare for BinCoeff
pub impl Eq for BinCoeff
pub impl Mul for BinCoeff
pub impl Shl for BinCoeff
pub impl Show for BinCoeff
pub impl Shr for BinCoeff

pub struct BinFloat {
  // private fields
} derive(Eq, @debug.Debug)
pub fn BinFloat::abs(Self) -> Self
pub fn BinFloat::abs_contextual(Self, @arithmetic.ArithmeticContext) -> Result[@arithmetic.ArithmeticOutcome[Self], @arithmetic.ArithmeticError]
pub fn BinFloat::acos(Self) -> Self
pub fn BinFloat::acos_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn BinFloat::acosh(Self) -> Self
pub fn BinFloat::acosh_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn BinFloat::add(Self, Self) -> Self
pub fn BinFloat::add_contextual(Self, Self, @arithmetic.ArithmeticContext) -> Result[@arithmetic.ArithmeticOutcome[Self], @arithmetic.ArithmeticError]
pub fn BinFloat::add_ctx(Self, Self, BinaryContext) -> (Self, BinaryFlags)
pub fn BinFloat::asin(Self) -> Self
pub fn BinFloat::asin_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn BinFloat::asinh(Self) -> Self
pub fn BinFloat::asinh_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn BinFloat::atan(Self) -> Self
pub fn BinFloat::atan2(Self, Self) -> Self
pub fn BinFloat::atan2_ctx(Self, Self, BinaryContext) -> (Self, BinaryFlags)
pub fn BinFloat::atan_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn BinFloat::atanh(Self) -> Self
pub fn BinFloat::atanh_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn BinFloat::ceil(Self) -> Self
pub fn BinFloat::clamp(Self, min~ : Self, max~ : Self) -> Self
pub fn BinFloat::clamp_checked(Self, min~ : Self, max~ : Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BinFloat::classify(Self) -> @arithmetic.FpClass
pub fn BinFloat::coefficient(Self) -> BinCoeff
pub fn BinFloat::compare(Self, Self) -> Int
pub fn BinFloat::compare_checked(Self, Self) -> Result[Int, @arithmetic.ArithmeticError]
pub fn BinFloat::compare_quiet(Self, Self) -> (@def.PartialOrder, BinaryFlags)
pub fn BinFloat::compare_signaling(Self, Self) -> (@def.PartialOrder, BinaryFlags)
pub fn BinFloat::copy_sign(Self, Self) -> Self
pub fn BinFloat::cos(Self) -> Self
pub fn BinFloat::cos_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn BinFloat::cosh(Self) -> Self
pub fn BinFloat::cosh_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn BinFloat::cospi(Self) -> Self
pub fn BinFloat::cospi_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn BinFloat::div(Self, Self) -> Self
pub fn BinFloat::div_checked(Self, Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BinFloat::div_contextual(Self, Self, @arithmetic.ArithmeticContext) -> Result[@arithmetic.ArithmeticOutcome[Self], @arithmetic.ArithmeticError]
pub fn BinFloat::div_ctx(Self, Self, BinaryContext) -> (Self, BinaryFlags)
pub fn BinFloat::equal(Self, Self) -> Bool
pub fn BinFloat::equal_quiet(Self, Self) -> (Bool, BinaryFlags)
pub fn BinFloat::equal_signaling(Self, Self) -> (Bool, BinaryFlags)
pub fn BinFloat::exp(Self) -> Self
pub fn BinFloat::exp10(Self) -> Self
pub fn BinFloat::exp10_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn BinFloat::exp2(Self) -> Self
pub fn BinFloat::exp2_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn BinFloat::exp_contextual(Self, @arithmetic.ArithmeticContext) -> Result[@arithmetic.ArithmeticOutcome[Self], @arithmetic.ArithmeticError]
pub fn BinFloat::exp_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn BinFloat::exp_ln(Self) -> Self
pub fn BinFloat::exp_ln_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn BinFloat::expm1(Self) -> Self
pub fn BinFloat::expm1_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn BinFloat::exponent2(Self) -> Int
pub fn BinFloat::floor(Self) -> Self
pub fn BinFloat::fma(Self, Self, Self) -> Self
pub fn BinFloat::fma_ctx(Self, Self, Self, BinaryContext) -> (Self, BinaryFlags)
pub fn BinFloat::from_coefficient(BinCoeff, precision? : Int, negative? : Bool) -> Self
pub fn BinFloat::from_double(Double, precision? : Int) -> Self
pub fn BinFloat::from_float(Float, precision? : Int) -> Self
pub fn BinFloat::from_hex(String, Int) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BinFloat::from_int(Int, precision? : Int) -> Self
pub fn BinFloat::from_string(String, precision? : Int) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BinFloat::from_string_ctx(String, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
pub fn BinFloat::hypot(Self, Self) -> Self
pub fn BinFloat::hypot_ctx(Self, Self, BinaryContext) -> (Self, BinaryFlags)
pub fn BinFloat::inf(@def.Sign, precision? : Int) -> Self
pub fn BinFloat::is_negative(Self) -> Bool
pub fn BinFloat::is_negative_zero(Self) -> Bool
pub fn BinFloat::is_quiet_nan(Self) -> Bool
pub fn BinFloat::is_signaling_nan(Self) -> Bool
pub fn BinFloat::is_zero(Self) -> Bool
pub fn BinFloat::less_equal_quiet(Self, Self) -> (Bool, BinaryFlags)
pub fn BinFloat::less_equal_signaling(Self, Self) -> (Bool, BinaryFlags)
pub fn BinFloat::less_quiet(Self, Self) -> (Bool, BinaryFlags)
pub fn BinFloat::less_signaling(Self, Self) -> (Bool, BinaryFlags)
pub fn BinFloat::ln(Self) -> Self
pub fn BinFloat::ln_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn BinFloat::log10(Self) -> Self
pub fn BinFloat::log10_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn BinFloat::log1p(Self) -> Self
pub fn BinFloat::log1p_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn BinFloat::log2(Self) -> Self
pub fn BinFloat::log2_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn BinFloat::logb_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn BinFloat::make(BinCoeff, Int, Int, negative? : Bool, mode? : @arithmetic.RoundingMode) -> Self
pub fn BinFloat::max(Self, Self) -> Self
pub fn BinFloat::min(Self, Self) -> Self
pub fn BinFloat::mul(Self, Self) -> Self
pub fn BinFloat::mul_contextual(Self, Self, @arithmetic.ArithmeticContext) -> Result[@arithmetic.ArithmeticOutcome[Self], @arithmetic.ArithmeticError]
pub fn BinFloat::mul_ctx(Self, Self, BinaryContext) -> (Self, BinaryFlags)
pub fn BinFloat::nan(precision? : Int) -> Self
pub fn BinFloat::nan_payload(Self) -> BinCoeff
pub fn BinFloat::neg(Self) -> Self
pub fn BinFloat::negative_zero(precision? : Int) -> Self
pub fn BinFloat::next_down_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn BinFloat::next_up_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn BinFloat::normalized(Self) -> Self
pub fn BinFloat::not_equal(Self, Self) -> Bool
pub fn BinFloat::one(precision? : Int) -> Self
pub fn BinFloat::op_ge(Self, Self) -> Bool
pub fn BinFloat::op_gt(Self, Self) -> Bool
pub fn BinFloat::op_le(Self, Self) -> Bool
pub fn BinFloat::op_lt(Self, Self) -> Bool
pub fn BinFloat::output(Self, &Logger) -> Unit
pub fn BinFloat::pow(Self, Self) -> Self
pub fn BinFloat::pow_ctx(Self, Self, BinaryContext) -> (Self, BinaryFlags)
pub fn BinFloat::pow_int(Self, Int) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BinFloat::pow_int_checked(Self, Int, @arithmetic.ArithmeticContext) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BinFloat::pow_int_ctx(Self, Int, BinaryContext) -> (Self, BinaryFlags)
pub fn BinFloat::pow_nat_checked(Self, UInt, @arithmetic.ArithmeticContext) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BinFloat::pown(Self, Int) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BinFloat::pown_ctx(Self, Int, BinaryContext) -> (Self, BinaryFlags)
pub fn BinFloat::precision(Self) -> Int
pub fn BinFloat::quiet_nan(payload? : BinCoeff, negative? : Bool, precision? : Int) -> Self
pub fn BinFloat::remainder(Self, Self) -> Self
pub fn BinFloat::remainder_ctx(Self, Self, BinaryContext) -> (Self, BinaryFlags)
pub fn BinFloat::rootn(Self, Int) -> Self
pub fn BinFloat::rootn_ctx(Self, Int, BinaryContext) -> (Self, BinaryFlags)
pub fn BinFloat::round(Self) -> Self
pub fn BinFloat::round_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn BinFloat::round_ties_even(Self) -> Self
pub fn BinFloat::scaleb_ctx(Self, Int, BinaryContext) -> (Self, BinaryFlags)
pub fn BinFloat::sign(Self) -> @def.Sign
pub fn BinFloat::signaling_nan(payload? : BinCoeff, negative? : Bool, precision? : Int) -> Self
pub fn BinFloat::sin(Self) -> Self
pub fn BinFloat::sin_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn BinFloat::sinh(Self) -> Self
pub fn BinFloat::sinh_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn BinFloat::sinpi(Self) -> Self
pub fn BinFloat::sinpi_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn BinFloat::sqrt(Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BinFloat::sqrt_checked(Self, @arithmetic.ArithmeticContext) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BinFloat::sqrt_contextual(Self, @arithmetic.ArithmeticContext) -> Result[@arithmetic.ArithmeticOutcome[Self], @arithmetic.ArithmeticError]
pub fn BinFloat::sqrt_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn BinFloat::sub(Self, Self) -> Self
pub fn BinFloat::sub_contextual(Self, Self, @arithmetic.ArithmeticContext) -> Result[@arithmetic.ArithmeticOutcome[Self], @arithmetic.ArithmeticError]
pub fn BinFloat::sub_ctx(Self, Self, BinaryContext) -> (Self, BinaryFlags)
pub fn BinFloat::tan(Self) -> Self
pub fn BinFloat::tan_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn BinFloat::tanh(Self) -> Self
pub fn BinFloat::tanh_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn BinFloat::tanpi(Self) -> Self
pub fn BinFloat::tanpi_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn BinFloat::to_decimal_string_ctx(Self, Int, BinaryContext) -> (String, BinaryFlags)
pub fn BinFloat::to_hex(Self) -> String
pub fn BinFloat::to_int64_ctx(Self, BinaryContext, exact? : Bool) -> (Int64?, BinaryFlags)
pub fn BinFloat::to_int_ctx(Self, BinaryContext, exact? : Bool) -> (Int?, BinaryFlags)
pub fn BinFloat::to_integral_exact_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn BinFloat::to_integral_value_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn BinFloat::to_interchange(Self, BinaryInterchangeFormat, rounding? : BinaryRoundingMode, tininess? : TininessDetection) -> (BinaryInterchange, BinaryFlags)
pub fn BinFloat::to_repr(Self) -> @debug.Repr
pub fn BinFloat::to_shortest_string(Self) -> String
pub fn BinFloat::to_shortest_string_ctx(Self, BinaryContext) -> String
pub fn BinFloat::to_string(Self) -> String
pub fn BinFloat::to_uint64_ctx(Self, BinaryContext, exact? : Bool) -> (UInt64?, BinaryFlags)
pub fn BinFloat::to_uint_ctx(Self, BinaryContext, exact? : Bool) -> (UInt?, BinaryFlags)
pub fn BinFloat::total_order(Self, Self) -> Bool
pub fn BinFloat::total_order_compare(Self, Self) -> Int
pub fn BinFloat::total_order_mag(Self, Self) -> Bool
pub fn BinFloat::trunc(Self) -> Self
pub fn BinFloat::try_acos_ctx(Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
pub fn BinFloat::try_acosh_ctx(Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
pub fn BinFloat::try_asin_ctx(Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
pub fn BinFloat::try_asinh_ctx(Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
pub fn BinFloat::try_atan2_ctx(Self, Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
pub fn BinFloat::try_atan_ctx(Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
pub fn BinFloat::try_atanh_ctx(Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
pub fn BinFloat::try_cos_ctx(Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
pub fn BinFloat::try_cosh_ctx(Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
pub fn BinFloat::try_cospi_ctx(Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
pub fn BinFloat::try_exp10_ctx(Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
pub fn BinFloat::try_exp2_ctx(Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
pub fn BinFloat::try_exp_ctx(Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
pub fn BinFloat::try_exp_ln_ctx(Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
pub fn BinFloat::try_expm1_ctx(Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
pub fn BinFloat::try_hypot_ctx(Self, Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
pub fn BinFloat::try_ln_ctx(Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
pub fn BinFloat::try_log10_ctx(Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
pub fn BinFloat::try_log1p_ctx(Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
pub fn BinFloat::try_log2_ctx(Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
pub fn BinFloat::try_pow_ctx(Self, Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
pub fn BinFloat::try_rootn_ctx(Self, Int, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
pub fn BinFloat::try_sin_ctx(Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
pub fn BinFloat::try_sinh_ctx(Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
pub fn BinFloat::try_sinpi_ctx(Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
pub fn BinFloat::try_tan_ctx(Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
pub fn BinFloat::try_tanh_ctx(Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
pub fn BinFloat::try_tanpi_ctx(Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
pub fn BinFloat::ulp(Self) -> Self
pub fn BinFloat::unordered_quiet(Self, Self) -> (Bool, BinaryFlags)
pub fn BinFloat::with_precision(Self, Int, @arithmetic.RoundingMode) -> Self
pub fn BinFloat::zero(precision? : Int) -> Self
pub impl @arithmetic.AbsContextual for BinFloat
pub impl @arithmetic.AddContextual for BinFloat
pub impl @arithmetic.CompareChecked for BinFloat
pub impl @arithmetic.DivChecked for BinFloat
pub impl @arithmetic.DivContextual for BinFloat
pub impl @arithmetic.ExpContextual for BinFloat
pub impl @arithmetic.MulContextual for BinFloat
pub impl @arithmetic.PowIntChecked for BinFloat
pub impl @arithmetic.PowNatChecked for BinFloat
pub impl @arithmetic.SqrtChecked for BinFloat
pub impl @arithmetic.SqrtContextual for BinFloat
pub impl @arithmetic.SubContextual for BinFloat
pub impl @def.Floating for BinFloat
pub impl Add for BinFloat
pub impl Compare for BinFloat
pub impl Div for BinFloat
pub impl Mul for BinFloat
pub impl Neg for BinFloat
pub impl Show for BinFloat
pub impl Sub for BinFloat

pub struct BinaryContext {
  // private fields
} derive(Eq, @debug.Debug)
pub fn BinaryContext::binary128(rounding? : BinaryRoundingMode, tininess? : TininessDetection) -> Self
pub fn BinaryContext::binary16(rounding? : BinaryRoundingMode, tininess? : TininessDetection) -> Self
pub fn BinaryContext::binary32(rounding? : BinaryRoundingMode, tininess? : TininessDetection) -> Self
pub fn BinaryContext::binary64(rounding? : BinaryRoundingMode, tininess? : TininessDetection) -> Self
pub fn BinaryContext::e_max(Self) -> Int?
pub fn BinaryContext::e_min(Self) -> Int?
pub fn BinaryContext::equal(Self, Self) -> Bool
pub fn BinaryContext::from_arithmetic_context(@arithmetic.ArithmeticContext) -> Self
pub fn BinaryContext::new(Int, rounding? : BinaryRoundingMode, e_min? : Int, e_max? : Int, tininess? : TininessDetection) -> Self
pub fn BinaryContext::not_equal(Self, Self) -> Bool
pub fn BinaryContext::precision(Self) -> Int
pub fn BinaryContext::rounding(Self) -> BinaryRoundingMode
pub fn BinaryContext::tininess(Self) -> TininessDetection
pub fn BinaryContext::to_repr(Self) -> @debug.Repr
pub fn BinaryContext::try_new(Int, rounding? : BinaryRoundingMode, e_min? : Int, e_max? : Int, tininess? : TininessDetection) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BinaryContext::unbounded(Int, rounding? : BinaryRoundingMode) -> Self

pub struct BinaryFlags {
  // private fields
} derive(Eq, @debug.Debug)
pub fn BinaryFlags::combine(Self, Self) -> Self
pub fn BinaryFlags::division_by_zero(Self) -> Bool
pub fn BinaryFlags::equal(Self, Self) -> Bool
pub fn BinaryFlags::inexact(Self) -> Bool
pub fn BinaryFlags::invalid_operation(Self) -> Bool
pub fn BinaryFlags::new() -> Self
pub fn BinaryFlags::not_equal(Self, Self) -> Bool
pub fn BinaryFlags::overflow(Self) -> Bool
pub fn BinaryFlags::to_repr(Self) -> @debug.Repr
pub fn BinaryFlags::to_testfloat_bits(Self) -> Int
pub fn BinaryFlags::underflow(Self) -> Bool

pub struct BinaryInterchange {
  // private fields
} derive(Eq)
pub fn BinaryInterchange::bits(Self) -> BinCoeff
pub fn BinaryInterchange::equal(Self, Self) -> Bool
pub fn BinaryInterchange::format(Self) -> BinaryInterchangeFormat
pub fn BinaryInterchange::from_bin_float(BinFloat, BinaryInterchangeFormat, rounding? : BinaryRoundingMode, tininess? : TininessDetection) -> (Self, BinaryFlags)
pub fn BinaryInterchange::from_bits(BinCoeff, BinaryInterchangeFormat) -> Self
pub fn BinaryInterchange::from_hex(String, BinaryInterchangeFormat) -> Self?
pub fn BinaryInterchange::not_equal(Self, Self) -> Bool
pub fn BinaryInterchange::to_bin_float(Self) -> BinFloat
pub fn BinaryInterchange::to_hex(Self) -> String

pub(all) enum BinaryInterchangeFormat {
  Binary16
  Binary32
  Binary64
  Binary128
} derive(Eq, @debug.Debug)
pub fn BinaryInterchangeFormat::bias(Self) -> Int
pub fn BinaryInterchangeFormat::context(Self, rounding? : BinaryRoundingMode, tininess? : TininessDetection) -> BinaryContext
pub fn BinaryInterchangeFormat::e_max(Self) -> Int
pub fn BinaryInterchangeFormat::e_min(Self) -> Int
pub fn BinaryInterchangeFormat::equal(Self, Self) -> Bool
pub fn BinaryInterchangeFormat::exponent_bits(Self) -> Int
pub fn BinaryInterchangeFormat::fraction_bits(Self) -> Int
pub fn BinaryInterchangeFormat::not_equal(Self, Self) -> Bool
pub fn BinaryInterchangeFormat::precision(Self) -> Int
pub fn BinaryInterchangeFormat::to_repr(Self) -> @debug.Repr
pub fn BinaryInterchangeFormat::total_bits(Self) -> Int

pub(all) enum BinaryRoundingMode {
  RoundTiesToEven
  RoundTiesToAway
  RoundTowardZero
  RoundTowardPositive
  RoundTowardNegative
  RoundAwayFromZero
} derive(Eq, @debug.Debug)
pub fn BinaryRoundingMode::equal(Self, Self) -> Bool
pub fn BinaryRoundingMode::from_arithmetic(@arithmetic.RoundingMode) -> Self
pub fn BinaryRoundingMode::not_equal(Self, Self) -> Bool
pub fn BinaryRoundingMode::to_arithmetic(Self) -> @arithmetic.RoundingMode?
pub fn BinaryRoundingMode::to_repr(Self) -> @debug.Repr

pub(all) enum TininessDetection {
  BeforeRounding
  AfterRounding
} derive(Eq, @debug.Debug)
pub fn TininessDetection::equal(Self, Self) -> Bool
pub fn TininessDetection::not_equal(Self, Self) -> Bool
pub fn TininessDetection::to_repr(Self) -> @debug.Repr

// Type aliases

// Traits
```
<!-- generated-api-end -->
