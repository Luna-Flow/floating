# binary API

## Purpose

`binary` is the binary floating-point core of `floating`. A `Binary` is
a signed dyadic number $(-1)^s \cdot c \cdot 2^{e}$ with an arbitrary-precision
coefficient, an attached working precision, and the IEEE 754 special values
(signed zero, infinities, quiet and signaling NaNs with payloads). Every
arithmetic operation rounds the exact result once. A `BinaryContext` gives the
precision, exponent range, rounding direction and tininess rule of one
operation, and the `*_ctx` methods return the IEEE status flags with the value.
The [tutorial](../tutorial/binary.md) shows the common workflows and the
[design page](../design/binary.md) derives the rounding, range and
certification rules used below. The verified IEEE 754 scope is listed in
[conformance](../conformance/binary.md).

Throughout this page, $p$ is a precision in bits, $\circ(x)$ is the rounding of
the real number $x$ under the active context, and "the flags" are the five IEEE
exception flags of a `BinaryFlags` value.

## Importing

Add the package to your `moon.pkg`, together with the two packages whose types
appear in its signatures:

```moonbit nocheck
import {
  "Luna-Flow/floating/binary",
  "Luna-Flow/floating/def",
  "Luna-Flow/arithmetic" @lf_arith,
}
```

The examples call the package as `@binary.`. `@lf_arith` is
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
| plain | `x + y`, `x.exp()` | `BinaryContext::new(precision=p)`, nearest-even, `p` the precision of the operands | the value only |
| contextual | `x.add_ctx(y, ctx)`, `x.exp_ctx(ctx)` | the given `BinaryContext` | `(value, flags)` |
| checked | `x.try_exp_ctx(ctx)`, `DivChecked::div_checked(x, y, ctx)` | the given context | `Result` with an `@lf_arith.ArithmeticError` |

The plain form of a binary operation works at the larger precision of the two
operands (the largest of three for `fma`). Its context is the extendable
precision format of IEEE 754-2019 3.7 given by $p$ alone (see `BinaryContext`),
whose exponent range is the implementation range below, so it overflows to an
infinity and underflows to a signed zero or a tiny value only at about
$2^{\pm 2^{30}}$.

## Values and limits

### `binary_implementation_e_max`, `binary_implementation_e_min`

The largest and smallest exponent of the leading bit that a finite `Binary`
may carry.

```mbti
pub let binary_implementation_e_max : Int
pub let binary_implementation_e_min : Int
```

They are $2^{30}-1 = 1073741823$ and $1 - (2^{30}-1) = -1073741822$, so
$e_{\min} = 1 - e_{\max}$ as IEEE 754-2019 3.3 requires of every format. A
context given by its precision alone, and every plain operation, uses them as
$e_{\max}$ and $e_{\min}$: a result whose leading bit would lie above $e_{\max}$
overflows, and below $e_{\min}$ the value is subnormal with quantum
$2^{e_{\min}-p+1}$. The range of a context given by its precision alone is this range, so every
stored value is a member of that context.

### `binary_precision_max`

The largest precision a `BinaryContext` accepts and the largest precision a
`Binary` may carry. Every constructor that takes a precision checks it
against `1..=binary_precision_max`: a value-returning constructor aborts with a
message that names the constructor, the range and the offending value, and a
constructor that returns a `Result` (`from_string`, `from_hex`, and the
constructors of `BinaryChecked`) returns an `ArithmeticError` of kind
`DomainError`. A precision is never replaced by another one.

```mbti
pub let binary_precision_max : Int
```

It is $2^{28} = 268435456$ bits. Together with the exponent range it keeps
every coefficient exponent inside the 32-bit `Int` range.

## Exact coefficients

### `BinCoeff`

A non-negative arbitrary-precision integer, used as the coefficient of a
`Binary` and as the bit pattern of an interchange encoding.

```mbti
type BinCoeff
```

The inner type `@binary_kernel.Coeff` belongs to the internal package
`internal/binary_kernel`, which only code inside `Luna-Flow/floating` can import.
It carries no compatibility promise and a user cannot call a method on it, read
it, compare it or build one: from outside the module a `BinCoeff` is abstract.
Neither its constructor nor its field is visible outside `binary`; the other
packages of the library reach the kernel type through the bridge `to_kernel` and
`from_kernel` (below).
The value is exact: on the native, LLVM and Wasm targets an inline
64- or 128-bit word or an array of 64-bit limbs, on JavaScript a host
`bigint`; the representation is not observable, and the algorithm selection
(schoolbook, Karatsuba, Toom-3, number-theoretic transform, staged division) is
described in the [design page](../design/binary.md#the-coefficient-kernel).
`Debug` prints the integer value.

### `BinCoeff::to_kernel`, `BinCoeff::from_kernel` (internal bridge)

The bridge between `BinCoeff` and the kernel type, for the packages of this
module only. Code outside `Luna-Flow/floating` cannot name the kernel type and
has no use for them; they carry no compatibility promise, and the kernel type
they exchange may change in any release.

```mbti
pub fn BinCoeff::to_kernel(Self) -> @binary_kernel.Coeff
pub fn BinCoeff::from_kernel(@binary_kernel.Coeff) -> Self
```

Both carry `#internal`, which changes neither the generated interface nor the documentation tool, so this heading and the doc comments are what mark them as internal. Both are free: `BinCoeff` is a one-field tuple structure over the kernel type, and the bridge reads and wraps that field.

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

### `BinCoeff::is_zero`, `BinCoeff::bit_length`

Queries.

```mbti
pub fn BinCoeff::is_zero(Self) -> Bool
pub fn BinCoeff::bit_length(Self) -> Int
```

`bit_length` is $\lfloor \log_2 c \rfloor + 1$ for $c > 0$ and $0$ for zero.

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

`BinCoeff` also implements `Eq`, `Compare`, `Show` and `Debug`; the promoted
trait methods are listed under [Trait implementations](#trait-implementations).
It has no arithmetic, shifts, bit operations or GCD: they are internal to the
library (the package `internal/binary_kernel`), and arithmetic on values is done
with `Binary` or, on a coefficient read with `coefficient()`, after
converting it with `to_string` or `to_bytes_be`.

```moonbit
///|
test "BinCoeff converts and compares exact natural numbers" {
  let c = @binary.BinCoeff::parse("ff", radix=16).unwrap()
  let ten = @binary.BinCoeff::from_uint64(10UL)
  inspect("\{c} \{ten} \{c.bit_length()}", content="255 10 8")
  inspect(c.compare(ten), content="1")
  inspect(c.to_bytes_be(), content="b\"\\xff\"")
  inspect(@binary.BinCoeff::parse("-1") is Err(_), content="true")
}
```

## The value type

### `Binary`

A binary floating-point value: a finite dyadic number, a signed infinity or a
NaN, with a working precision. Its representation is an internal type
(`@binary_kernel.BinRepr`, like the coefficient of `BinCoeff`) that carries no
compatibility promise and is read only inside the package; a value is one heap
object.

```mbti
pub struct Binary(@binary_kernel.BinRepr) derive(@debug.Debug)
```

A finite value is $(-1)^s \cdot c \cdot 2^{e}$ with $s$ the sign bit, $c$ a
`BinCoeff` and $e$ = `exponent2()`. Every value built through this API is
normalized: a nonzero $c$ is odd (factors of two are moved into $e$), a zero
has $c = 0$ and $e = 0$ and keeps its sign, and $c$ has at most `precision()`
bits. The precision is an attribute of the value: plain operations work at the
larger precision of their operands, and contextual operations stamp the
context precision on their result.

`==` agrees with `compare`: `a == b` exactly when `a.compare(b) == 0`, so two values
are equal when they are the same number, whatever their precisions
(`one(precision=53) == one(precision=24)`, `-0 == +0`), and every NaN equals every
other NaN. This is the total preorder in which `<`, `<=` and sorting work (every NaN
equal to every NaN and above every number), the rule of `Decimal` too. It is not IEEE
equality: use `compare_quiet_equal` (IEEE Std 754-2019 5.6.1, 5.11) when a NaN must be
unordered. `Binary` has no `Hash`. `identical` is the structural question.

### `Binary::identical`

```mbti
pub fn Binary::identical(Self, Self) -> Bool
```

The structural equality of two values: the same class, sign (the sign of a zero
included), coefficient, exponent and precision, and for a NaN the same signaling
bit and payload. It distinguishes `-0` from `+0`, a value of precision 53 from the
same value of precision 24, and two NaNs of different kind or payload, and a NaN
is identical to an identical NaN. It is what `==` was before 0.12; use it where a
result is checked as a datum (a test of the sign of a zero or of the precision
stamped by a contextual operation), and `==` where the number is meant.

### `Binary::make`

Builds a finite value $(-1)^{\text{negative}} \cdot c \cdot 2^{e}$ rounded to
`precision` bits.

```mbti
pub fn Binary::make(BinCoeff, Int, Int, negative? : Bool, mode? : @arithmetic.RoundingMode) -> Self
```

The arguments are the coefficient, the exponent $e$ and the precision. When
the coefficient has more significant bits than the precision it is rounded
with `mode` (default `ToNearestEven`). The result is normalized. A precision
outside `1..=binary_precision_max` aborts. A value outside the implementation exponent range is
replaced as an overflow or underflow would be: above it by $\pm\infty$ or, for
a mode that rounds toward zero, the largest finite magnitude
$(2^p - 1)\,2^{e_{\max} - p + 1}$; below the smallest implementation subnormal
$2^{e_{\min} - p + 1}$ by $\pm 0$ or, for a mode that rounds away from zero
(and for nearest when the value exceeds half of it), by that subnormal.
`make` rounds precision and range together, in `mode`: a value between the
smallest subnormal and $2^{e_{\min}}$ keeps only the bits on the subnormal
grid $2^{e_{\min} - p + 1}$ (at least one), so the stored value never has a bit
below that grid. This matters only at magnitudes near $2^{-2^{30}}$; `apply_ctx`
additionally reports the flags.

### `Binary::from_coefficient`, `Binary::from_int`

Build a value from an integer.

```mbti
pub fn Binary::from_coefficient(BinCoeff, precision? : Int, negative? : Bool) -> Self
pub fn Binary::from_int(Int, precision? : Int) -> Self
```

The default precision is 53. The integer is rounded to nearest-even when it
has more significant bits than the precision; `from_int(n)` is exact for every
`Int` at the default precision.

### `Binary::from_double`, `Binary::from_float`

Decode a host binary64 or binary32 value exactly.

```mbti
pub fn Binary::from_double(Double, precision? : Int) -> Self
pub fn Binary::from_float(Float, precision? : Int) -> Self
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

### `Binary::zero`, `Binary::negative_zero`, `Binary::one`, `Binary::inf`

Build the constants $+0$, $-0$, $1$ and $\pm\infty$.

```mbti
pub fn Binary::zero(precision? : Int) -> Self
pub fn Binary::negative_zero(precision? : Int) -> Self
pub fn Binary::one(precision? : Int) -> Self
pub fn Binary::inf(negative? : Bool, precision? : Int) -> Self
```

The default precision is 53, and it must be within
`1..=binary_precision_max` (see `binary_precision_max`). `inf(negative=true)` is
$-\infty$; the default is $+\infty$, as `Decimal::inf` has it.

### `Binary::nan`, `Binary::quiet_nan`, `Binary::signaling_nan`

Build NaNs.

```mbti
pub fn Binary::nan(precision? : Int) -> Self
pub fn Binary::quiet_nan(payload? : BinCoeff, negative? : Bool, precision? : Int) -> Self
pub fn Binary::signaling_nan(payload? : BinCoeff, negative? : Bool, precision? : Int) -> Self
```

`nan()` is a positive quiet NaN with payload 0. A signaling NaN always has a
nonzero payload (the default and a requested 0 both become 1).

A NaN of precision $p$ has $p - 2$ payload bits (IEEE 754-2019 6.2.1: the
trailing significand field has $p - 1$ bits and the first is the quiet bit), so
none for $p \le 2$. `quiet_nan` and `signaling_nan` abort when the payload is
wider, and `signaling_nan` aborts for $p < 3$, where no signaling NaN exists
(a signaling NaN needs a non-zero payload bit). Conversions never abort: a
payload that the destination cannot hold keeps its low bits (6.2.3), and a
signaling NaN whose payload does not survive becomes quiet. This is the rule of
`with_precision`, `from_double`, `from_float`, `from_hex` (a `snan` literal below
precision 3 is a quiet NaN), every operation that returns a quiet NaN under a
context (the payload is cut to the context precision) and the interchange
encodings.

## Observing a value

### `Binary::classify`, `Binary::sign`, `Binary::is_sign_minus`

Report the class and sign of a value.

```mbti
pub fn Binary::classify(Self) -> @arithmetic.FpClass
pub fn Binary::sign(Self) -> @def.Sign
pub fn Binary::is_sign_minus(Self) -> Bool
```

`classify` returns `Finite`, `Infinity` or `NaN` (zeros are `Finite`). `sign`
is `Zero` for every zero and every NaN, and `Positive` or `Negative` otherwise.
`is_sign_minus` returns the sign bit itself, which is set for $-0$, $-\infty$
and negative NaNs. `@def.is_finite`, `@def.is_nan`, `@def.is_infinite` and
`@def.is_zero` work on `Binary` through the `Floating` trait; the
methods of the next section give the same answers without the trait.

### `Binary::class_of`, `Binary::is_normal`, `Binary::is_subnormal`, `Binary::is_finite`, `Binary::is_infinite`, `Binary::is_nan`

The ten-valued class of IEEE 754-2019 clause 5.7.2 and its predicates.

```mbti
pub fn Binary::class_of(Self, BinaryContext) -> @def.IeeeClass
pub fn Binary::is_normal(Self, BinaryContext) -> Bool
pub fn Binary::is_subnormal(Self, BinaryContext) -> Bool
pub fn Binary::is_finite(Self) -> Bool
pub fn Binary::is_infinite(Self) -> Bool
pub fn Binary::is_nan(Self) -> Bool
```

`class_of` returns one of the ten values of [`IeeeClass`](def.md#ieeeclass):
`SignalingNaN`, `QuietNaN`, `NegativeInfinity`, `NegativeNormal`,
`NegativeSubnormal`, `NegativeZero`, `PositiveZero`, `PositiveSubnormal`,
`PositiveNormal` and `PositiveInfinity`. A nonzero finite value is normal when
the exponent of its leading bit is at least the context's $e_{\min}$ and
subnormal when it is below; a `Binary` carries no format, so the context
decides, and `BinaryInterchangeFormat::context` gives the one of a binary
interchange format. A context given by its precision alone has the implementation limit
`binary_implementation_e_min` as `e_min`. `is_normal` and `is_subnormal` are true exactly
for the normal and subnormal classes; `is_finite` is true for zeros,
subnormals and normals, `is_infinite` for the two infinities and `is_nan` for
both NaNs. None of them rounds or raises a flag, and `classify` keeps its
three-valued meaning.

### `Binary::is_zero`, `Binary::is_negative_zero`, `Binary::is_quiet_nan`, `Binary::is_signaling_nan`, `Binary::nan_payload`

Special-value predicates.

```mbti
pub fn Binary::is_zero(Self) -> Bool
pub fn Binary::is_negative_zero(Self) -> Bool
pub fn Binary::is_quiet_nan(Self) -> Bool
pub fn Binary::is_signaling_nan(Self) -> Bool
pub fn Binary::nan_payload(Self) -> BinCoeff
```

`nan_payload` is zero for a value that is not a NaN.

### `Binary::coefficient`, `Binary::exponent2`, `Binary::precision`

Return the stored representation.

```mbti
pub fn Binary::coefficient(Self) -> BinCoeff
pub fn Binary::exponent2(Self) -> Int
pub fn Binary::precision(Self) -> Int
```

For a finite value the number is `coefficient()` $\times 2^{\texttt{exponent2()}}$
with the sign applied. The coefficient and exponent of an infinity or NaN
carry no meaning.

`coefficient()` builds a `BinCoeff` on each call for a value of at most 128
coefficient bits (the value stores its coefficient as one or two machine
words), so it allocates there; for a wider value it returns the stored
coefficient. A loop that reads the coefficient of many small values pays one
allocation per call. `Binary` has no public word reader; the result's
`BinCoeff::to_uint64` gives the value when it fits 64 bits. The exponent of the
leading bit, which is what most callers read the coefficient for, is
`ilogb()`, which does not allocate.

### `Binary::normalized`

Returns the canonical representation of a finite value at its own precision.

```mbti
pub fn Binary::normalized(Self) -> Self
```

Values built through the public API are already canonical, so this is the
identity on them; infinities and NaNs are returned unchanged.

### `Binary::with_precision`

Rounds a value to a new working precision.

```mbti
pub fn Binary::with_precision(Self, Int, @arithmetic.RoundingMode) -> Self
```

A finite value with more significant bits than the new precision is rounded
in the given direction (`@lf_arith.RoundingMode` has no ties-to-away mode;
use `apply_ctx` for it). Zeros, infinities and NaNs only change their
precision attribute. No flags are reported; use `apply_ctx` when they matter.

### `Binary::ulp`

Returns the unit in the last place of a finite value at its own precision.

```mbti
pub fn Binary::ulp(Self) -> Self
```

For $x \ne 0$ with leading-bit exponent $t = \lfloor \log_2 |x| \rfloor$ the
result is $2^{t-p+1}$. For zero it is $2^{1-p}$, and for an infinity or NaN it
is a quiet NaN. The spacing ignores any context exponent range, so it is not
the subnormal spacing of an IEEE format.

```moonbit
///|
test "make normalizes and rounds to the precision" {
  let twelve = @binary.Binary::make(
    @binary.BinCoeff::from_uint64(12UL),
    0,
    2,
  )
  inspect(
    "\{twelve} \{twelve.coefficient()} \{twelve.exponent2()}",
    content="3p2 3 2",
  )
  // 13 needs four bits; at two bits it rounds to nearest-even 12.
  let thirteen = @binary.Binary::make(
    @binary.BinCoeff::from_uint64(13UL),
    0,
    2,
  )
  inspect(thirteen, content="3p2")
  inspect(@binary.Binary::one().ulp(), content="1p-52")
}
```

## Plain arithmetic

### `Binary::add`, `Binary::sub`, `Binary::mul`, `Binary::div`, `Binary::neg`

The four operations and negation, also available as `+`, `-`, `*`, `/` and
unary `-`.

```mbti
pub fn Binary::add(Self, Self) -> Self
pub fn Binary::sub(Self, Self) -> Self
pub fn Binary::mul(Self, Self) -> Self
pub fn Binary::div(Self, Self) -> Self
pub fn Binary::neg(Self) -> Self
pub impl Add for Binary
pub impl Sub for Binary
pub impl Mul for Binary
pub impl Div for Binary
pub impl Neg for Binary
```

The result is the exact sum, difference, product or quotient rounded once to
nearest-even at the larger operand precision, with the implementation exponent
range. Special values follow IEEE 754: NaNs propagate (the first NaN operand,
quieted), $\infty - \infty$, $0 \cdot \infty$, $0/0$ and $\infty/\infty$ are
NaN, and a nonzero number divided by zero is a signed infinity. Flags are
discarded; use the [contextual forms](#contextual-arithmetic) to observe them.
`neg` flips the sign bit of every value, including zeros and NaNs, and never
rounds.

### `Binary::abs`, `Binary::copy_sign`

Clear or copy the sign bit.

```mbti
pub fn Binary::abs(Self) -> Self
pub fn Binary::copy_sign(Self, Self) -> Self
```

Both are quiet IEEE sign-bit operations: they never round, never raise a flag
and keep NaN payloads. `x.copy_sign(y)` has the magnitude of `x` and the sign
bit of `y`.

### `Binary::sqrt`

Correctly rounded square root.

```mbti
pub fn Binary::sqrt(Self) -> Self
```

`x.sqrt()` rounds $\sqrt{x}$ to nearest-even at the precision of `x`: it is
`sqrt_ctx` under the working context and never fails. An invalid operation (IEEE
754-2019 7.2: a negative nonzero argument, $-\infty$ included, or a signaling NaN)
is a quiet NaN, and the flag is read through `sqrt_ctx(...).1.invalid_operation()`.
$\sqrt{-0} = -0$, and a quiet NaN of either sign gives a quiet NaN. For a square root at another precision
or rounding direction use `sqrt_ctx`; its results under `RoundTowardNegative`
and `RoundTowardPositive` enclose $\sqrt{x}$ and coincide when the root is
exact.

### `Binary::pown`

Raise a value to an integer power.

```mbti
pub fn Binary::pown(Self, Int) -> Self
```

The result is $x^n$ correctly rounded to
nearest-even at the precision of `x`, computed as in `pown_ctx`, and never fails. A zero
base with a negative exponent is an infinity (the sign of the base for an odd
exponent; `pown_ctx(...).1.division_by_zero()` is the pole), and a signaling
NaN base a quiet NaN for every exponent, zero included (IEEE 754-2019
§9.2.1 excludes it from $x^0 = 1$; `invalid_operation` through `pown_ctx`);
$x^0 = 1$ for every other $x$, a quiet NaN included.

### `Binary::fma`

Fused multiply-add: $x \cdot y + z$ with a single rounding.

```mbti
pub fn Binary::fma(Self, Self, Self) -> Self
```

The precision is the largest of the three operand precisions. See
[`fma_ctx`](#binaryfma_ctx) for the special cases.

### `Binary::remainder`

IEEE 754 remainder $x - n y$, where $n$ is the integer nearest $x/y$ with ties
to even.

```mbti
pub fn Binary::remainder(Self, Self) -> Self
```

The result is exact whenever it fits the larger operand precision, which is
always the case for operands of that precision (the proof is on the
[design page](../design/binary.md#ieee-remainder-is-exact)). See
[`remainder_ctx`](#binaryremainder_ctx).

```moonbit
///|
test "plain arithmetic rounds once at the operand precision" {
  let one = @binary.Binary::one()
  let three = @binary.Binary::from_int(3)
  let third = one / three
  inspect(third, content="6004799503160661p-54")
  inspect(third.to_shortest_string(), content="0.3333333333333333")
  inspect(one / @binary.Binary::zero(), content="inf")
  inspect(@binary.Binary::from_int(7).remainder(@binary.Binary::from_int(2)), content="-1p0")
  inspect(@binary.Binary::from_int(3).pown(-2).to_shortest_string(), content="0.1111111111111111")
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
} derive(Eq, @debug.Debug)
```

These are the five IEEE 754-2019 rounding-direction attributes (clauses 4.3.1
and 4.3.2); `RoundTiesToAway` is not required of a binary format but is defined.
There is no away-from-zero mode: `@lf_arith.RoundingMode::AwayFromZero` has no
IEEE 754-2019 counterpart and is refused by `from_arithmetic` and
`from_arithmetic_context`. Each mode is a monotone
map $\mathbb{R} \to F \cup \{\pm\infty\}$; the
[design page](../design/binary.md#rounding-functions) defines them.

### `BinaryRoundingMode::from_arithmetic`, `BinaryRoundingMode::to_arithmetic`

Convert to and from `@lf_arith.RoundingMode`.

```mbti
pub fn BinaryRoundingMode::from_arithmetic(@arithmetic.RoundingMode) -> Self?
pub fn BinaryRoundingMode::to_arithmetic(Self) -> @arithmetic.RoundingMode?
```

`to_arithmetic(RoundTiesToAway)` is `None`, because `@lf_arith.RoundingMode`
has no ties-to-away mode, and `from_arithmetic(AwayFromZero)` is `None`, because
IEEE 754-2019 4.3 has no such attribute; the other modes map one to one.

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

The format and the attributes of one operation: the precision $p$, the
exponent $e_{\max}$ (with $e_{\min} = 1 - e_{\max}$, IEEE 754-2019 3.3), the
rounding-direction attribute and the tininess rule.

```mbti
pub struct BinaryContext {
  // private fields
} derive(Eq, @debug.Debug)
```

A context is an immutable value; there is no global or thread state.
$e_{\min}$ and $e_{\max}$ are exponents of the leading bit, as in IEEE 754: a
normal number satisfies $2^{e_{\min}} \le |x| < 2^{e_{\max}+1}$, the largest
finite value is $(2 - 2^{1-p})\,2^{e_{\max}}$ and the smallest positive
subnormal is $2^{e_{\min}-p+1}$. A context has no separate $e_{\min}$: it is
$1 - e_{\max}$. Without an `e_max` the context is the extendable precision
format of IEEE 754-2019 3.7 specified by $p$ alone, and $e_{\max}$ is
`binary_implementation_e_max`.

### `BinaryContext::new`, `BinaryContext::try_new`

Build a context.

```mbti
pub fn BinaryContext::new(precision=precision? : Int32, e_max? : Int32, rounding? : BinaryRoundingMode, tininess? : TininessDetection) -> Self
pub fn BinaryContext::try_new(precision=precision? : Int32, e_max? : Int32, rounding? : BinaryRoundingMode, tininess? : TininessDetection) -> Result[Self, @arithmetic.ArithmeticError]
```

Defaults: $p = 53$, `e_max = binary_implementation_e_max`, `RoundTiesToEven`,
`AfterRounding`; `new()` is therefore the extendable format of 53 bits, and every
operation of the package runs in it. `new` aborts when $p$ is outside $[1, 2^{28}]$ or $e_{\max}$ is outside
$[1, 2^{30}-1]$, naming the parameter; `try_new`
returns a `domain_error` in those cases. $e_{\max} \ge 1$ is what makes
$e_{\min} = 1 - e_{\max} \le e_{\max}$; IEEE 754-2019 3.7 NOTE 3 recommends
$p \ge 3$ and $e_{\max} \ge 2$, which are not enforced. There is no one-sided or
asymmetric range: `unbounded(p)` and the `e_min` argument no longer exist.

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
pub fn BinaryContext::from_arithmetic_context(@arithmetic.ArithmeticContext) -> Result[Self, @arithmetic.ArithmeticError]
```

Precision and rounding are copied; the `clamp` field has no binary meaning and is
ignored; tininess is `AfterRounding`. A given `e_min` must equal $1 - e_{\max}$,
and `e_min` alone gives $e_{\max} = 1 - e_{\min}$. The result is an `Err` for
`AwayFromZero`, an `e_min` that is not $1 - e_{\max}$, and a precision or
`e_max` outside the limits of `try_new`.

### `BinaryContext::precision`, `BinaryContext::rounding`, `BinaryContext::e_min`, `BinaryContext::e_max`, `BinaryContext::tininess`

Read the fields of a context.

```mbti
pub fn BinaryContext::precision(Self) -> Int
pub fn BinaryContext::rounding(Self) -> BinaryRoundingMode
pub fn BinaryContext::e_min(Self) -> Int32
pub fn BinaryContext::e_max(Self) -> Int32
pub fn BinaryContext::tininess(Self) -> TininessDetection
```

`e_min` is always $1 - e_{\max}$; both are plain integers.

### `BinaryContext::with_precision`, `with_rounding`, `with_e_max`, `with_tininess`

Copy a context with one parameter changed.

```mbti
pub fn BinaryContext::with_precision(Self, Int32) -> Self
pub fn BinaryContext::with_rounding(Self, BinaryRoundingMode) -> Self
pub fn BinaryContext::with_e_max(Self, Int32) -> Self
pub fn BinaryContext::with_tininess(Self, TininessDetection) -> Self
```

`with_precision` and `with_e_max` abort outside the limits of `new`; there is no
`try_with_*`.

### `BinaryContext::refinement_limit`, `BinaryContext::with_refinement_limit`

Read and set the refinement limit of the certified elementary functions.

```mbti
pub fn BinaryContext::refinement_limit(Self) -> Int32?
pub fn BinaryContext::with_refinement_limit(Self, Int32?) -> Self
```

Every certified elementary function (`exp`, `ln`, the trigonometric,
hyperbolic and inverse functions, `pow`, `rootn`, `hypot`, `atan2` and their
`try_*_ctx` forms) evaluates an enclosure at a growing working precision until
both ends round alike. The limit is the number of refinement steps: `Some(n)`
allows `n` of them (a value below 1 counts as 1), the default is `Some(12)`,
and `None` removes the count limit. When the limit is reached without a
decision, `try_*_ctx` returns the `CertificationFailure` error with the
refinement count, as before, and the plain and `*_ctx` forms return a quiet
NaN with `invalid_operation`. With `None` the loop still stops when the working
precision passes a cap, the larger of 8,000,000 bits and 256 times the first
working precision, and the trigonometric work limit of 8,000,000 bits still
refuses an argument that would need more. The default changes no result.
The field takes part in `==`: two contexts that differ only in the limit are
different.

```moonbit
///|
test "a refinement limit makes a hard-to-round result fail" {
  let wide = @binary.BinaryContext::new(precision=330)
  let one = @binary.Binary::from_int(1, precision=330)
  let midpoint = one.add_ctx(one.scaleb_ctx(@binary.Binary::from_int(-53), wide).0, wide).0
  // exp(x) is within 2^-330 of the midpoint 1 + 2^-53.
  let x = midpoint.try_ln_ctx(wide).unwrap().0
  let context = @binary.BinaryContext::new(precision=53)
  inspect(context.refinement_limit() == Some(12), content="true")
  let short = context.with_refinement_limit(Some(1))
  inspect(x.try_exp_ctx(short) is Err(_), content="true")
  let unlimited = context.with_refinement_limit(None)
  inspect(x.try_exp_ctx(unlimited) is Ok(_), content="true")
}
```

### `BinaryFlags`

The five IEEE 754 exception flags raised by one or more operations, and
`not_computed`, which reports a result the library could not compute.

```mbti
pub struct BinaryFlags {
  // private fields
} derive(Eq, @debug.Debug)
```

Two flag sets are `==` when all six flags agree.

### `BinaryFlags::new`, `BinaryFlags::inexact`, `BinaryFlags::underflow`, `BinaryFlags::overflow`, `BinaryFlags::division_by_zero`, `BinaryFlags::invalid_operation`, `BinaryFlags::not_computed`

Build an empty flag set and read the individual flags.

```mbti
pub fn BinaryFlags::new() -> Self
pub fn BinaryFlags::inexact(Self) -> Bool
pub fn BinaryFlags::underflow(Self) -> Bool
pub fn BinaryFlags::overflow(Self) -> Bool
pub fn BinaryFlags::division_by_zero(Self) -> Bool
pub fn BinaryFlags::invalid_operation(Self) -> Bool
pub fn BinaryFlags::not_computed(Self) -> Bool
```

`new()` has every flag clear. There is no `contains`: that method exists only where a package has a signal enum, and the six accessors cover the six flags. A contextual operation returns only the flags it
raised itself; nothing is sticky until you combine flags. The flags mean:
`inexact`, the returned value differs from the exact result; `underflow`, the
result is tiny and inexact; `overflow`, the rounded result exceeded the
largest finite value (always together with `inexact`); `division_by_zero`, an
exact infinite result from finite operands (such as $1/0$ or $\log 0$);
`invalid_operation`, no useful real result exists and a quiet NaN was
returned, or a signaling NaN was an operand. The non-`try` elementary
functions also raise it when they return NaN for a domain error (the `try_`
forms still return an `Err` for one; they become values in a later step of S4).
`not_computed`, the operation could not be carried out within a limit of the
implementation (a certification that did not conclude, a context beyond what the
kernels support) and the value is a NaN; it is not a flag of IEEE 754-2019 and
is distinct from `invalid_operation`. The non-`try` elementary functions raise it
when the `try_` form returns an `Err` of the certification-failure kind (they
raised `invalid_operation` before), and the checked tiers turn it into that
`Err`.

### `BinaryFlags::combine`

Returns the union of two flag sets.

```mbti
pub fn BinaryFlags::combine(Self, Self) -> Self
```

`combine` is a bitwise OR: associative, commutative and idempotent with
`new()` as identity, so the flags of a computation can be accumulated in any
order.

## Contextual arithmetic

Every method in this group returns `(value, flags)`, rounds the exact result
once under the context, and applies the context exponent range: an overflow
returns $\pm\infty$ or the largest finite magnitude depending on the rounding
direction, and a tiny result is rounded on the subnormal grid with quantum
$2^{e_{\min}-p+1}$. The returned value carries the context precision. A NaN
operand produces the first NaN operand quieted, with its sign and payload, and
`invalid_operation` only when some operand was a signaling NaN.

### `Binary::apply_ctx`

Rounds a value into a context.

```mbti
pub fn Binary::apply_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
```

This is the IEEE conversion of a wider value to a narrower format. Finite
values are rounded with the full overflow, subnormal and tininess rules;
infinities are kept; a signaling NaN is quieted with `invalid_operation`.

### `Binary::add_ctx`, `Binary::sub_ctx`, `Binary::mul_ctx`, `Binary::div_ctx`

The four operations under a context.

```mbti
pub fn Binary::add_ctx(Self, Self, BinaryContext) -> (Self, BinaryFlags)
pub fn Binary::sub_ctx(Self, Self, BinaryContext) -> (Self, BinaryFlags)
pub fn Binary::mul_ctx(Self, Self, BinaryContext) -> (Self, BinaryFlags)
pub fn Binary::div_ctx(Self, Self, BinaryContext) -> (Self, BinaryFlags)
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

### `Binary::sqrt_ctx`

Square root under a context.

```mbti
pub fn Binary::sqrt_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
```

$\sqrt{\pm 0} = \pm 0$, $\sqrt{+\infty} = +\infty$, and a negative nonzero
argument gives a quiet NaN with `invalid_operation`.

### `Binary::fma_ctx`

Fused multiply-add $\circ(x \cdot y + z)$ under a context.

```mbti
pub fn Binary::fma_ctx(Self, Self, Self, BinaryContext) -> (Self, BinaryFlags)
```

The product is formed exactly and the sum is rounded once (IEEE 754-2019
clause 5.4.1). A NaN operand propagates the first NaN of `self`, multiplier,
addend. `invalid_operation` is raised for a signaling NaN, for
$\infty \cdot 0$ (also when the addend is a quiet NaN, as SoftFloat does), and
for $\pm\infty \cdot y + (\mp\infty)$.

### `Binary::remainder_ctx`

IEEE 754 remainder under a context.

```mbti
pub fn Binary::remainder_ctx(Self, Self, BinaryContext) -> (Self, BinaryFlags)
```

The result is $r = x - n y$ with $n = \operatorname{round\_ties\_even}(x/y)$,
so $|r| \le |y|/2$. A zero result has the sign of $x$. $x = \pm\infty$ or
$y = 0$ gives a quiet NaN with `invalid_operation`; $y = \pm\infty$ or $x = 0$
returns $x$ rounded into the context. The exact $r$ is then rounded; for
operands representable in the context this rounding is exact and no flag is
raised. The quotient is never formed: the operands are reduced modulo $2y$,
so huge exponent gaps cost $O(\log)$ multiplications.

### `Binary::pown_ctx`

Integer power $\circ(x^n)$ under a context.

```mbti
pub fn Binary::pown_ctx(Self, Int, BinaryContext) -> (Self, BinaryFlags)
```

This is IEEE 754 `pown`. $x^0 = 1$ without a
flag for every $x$ except a signaling NaN (a quiet NaN included); a signaling
NaN base gives a quiet NaN with its payload and `invalid_operation` for every
exponent, zero included (§9.2.1, §7.2 a); $(\pm 0)^{n<0} = \pm\infty$ (sign for odd $n$) with
`division_by_zero`; $(\pm\infty)^n$ is an infinity or zero with the sign of an
odd power. Small powers are computed exactly; otherwise a Ziv loop rounds an
enclosure, with an exact fallback, so the result is always correctly rounded.

```moonbit
///|
test "contextual operations return value and flags" {
  let ctx = @binary.BinaryContext::binary32()
  let one = @binary.Binary::one()
  let (third, flags) = one.div_ctx(@binary.Binary::from_int(3), ctx)
  inspect(third.to_shortest_string_ctx(ctx).0, content="0.33333334")
  inspect(flags.inexact(), content="true")
  let (inf, zero_flags) = one.div_ctx(@binary.Binary::zero(), ctx)
  inspect("\{inf} \{zero_flags.division_by_zero()}", content="inf true")
}
```

## IEEE 754 operations

### `Binary::to_integral_value_ctx`, `Binary::to_integral_exact_ctx`

Round to an integral value in the context's rounding direction.

```mbti
pub fn Binary::to_integral_value_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn Binary::to_integral_exact_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
```

These are IEEE `roundToIntegral` (in the context's direction) and
`roundToIntegralExact`. Only the rounding direction of the context is used;
the result keeps the operand's precision and the sign of a zero result.
`to_integral_exact_ctx` raises `inexact` when the value changed;
`to_integral_value_ctx` never raises it. Infinities are returned unchanged and
a signaling NaN is quieted with `invalid_operation`.

### `Binary::floor`, `Binary::ceil`, `Binary::trunc`, `Binary::round`, `Binary::round_ties_to_even`

Round to an integral value in a fixed direction.

```mbti
pub fn Binary::floor(Self) -> Self
pub fn Binary::ceil(Self) -> Self
pub fn Binary::trunc(Self) -> Self
pub fn Binary::round(Self) -> Self
pub fn Binary::round_ties_to_even(Self) -> Self
```

They are `roundToIntegralTowardNegative`, `…TowardPositive`, `…TowardZero`,
`…TiesToAway` and `…TiesToEven`. `round` rounds halfway cases away from zero:
`round(-2.5) = -3`, while `round_ties_to_even(-2.5) = -2`.

### `Binary::to_int_ctx`, `Binary::to_int64_ctx`, `Binary::to_uint_ctx`, `Binary::to_uint64_ctx`

IEEE `convertToInteger` to a machine integer, rounding in the context's
direction.

```mbti
pub fn Binary::to_int_ctx(Self, BinaryContext, exact? : Bool) -> (Int?, BinaryFlags)
pub fn Binary::to_int64_ctx(Self, BinaryContext, exact? : Bool) -> (Int64?, BinaryFlags)
pub fn Binary::to_uint_ctx(Self, BinaryContext, exact? : Bool) -> (UInt?, BinaryFlags)
pub fn Binary::to_uint64_ctx(Self, BinaryContext, exact? : Bool) -> (UInt64?, BinaryFlags)
```

The value is first rounded to an integer. If that integer fits the target type
the result is `Some`; with `exact=true` (`convertToIntegerExact`) `inexact` is
raised when rounding changed the value. A NaN, an infinity or an integer
outside the target range gives `None` with `invalid_operation`, where a C
implementation would return an unspecified sentinel. A negative value that
rounds to zero converts to `0` for the unsigned targets.

### `Binary::next_up_ctx`, `Binary::next_down_ctx`

IEEE `nextUp` and `nextDown` in the context's format.

```mbti
pub fn Binary::next_up_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn Binary::next_down_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
```

`next_up_ctx(x)` is the least value of the context's format (precision and
exponent range, subnormals included) that is greater than $x$; `next_down_ctx`
is $-\texttt{next\_up}(-x)$. The context's rounding direction is ignored. The
operations are quiet: $\operatorname{nextUp}(\pm 0)$ is the smallest positive
subnormal, $\operatorname{nextUp}(-\infty)$ is the most negative finite value,
$\operatorname{nextUp}(\Omega) = +\infty$ with no overflow flag, and only a
signaling NaN raises `invalid_operation`. An operand with more bits than the
context precision is accepted.

### `Binary::scaleb_ctx`, `Binary::logb_ctx`, `Binary::ilogb`

IEEE `scaleB` and `logB`.

```mbti
pub fn Binary::scaleb_ctx(Self, Self, BinaryContext) -> (Self, BinaryFlags)
pub fn Binary::logb_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn Binary::ilogb(Self) -> Int32?
```

`x.scaleb_ctx(n, ctx)` is $\circ(x \cdot 2^n)$ with the usual overflow and
underflow handling; it is exact unless the result leaves the normal range. The
count `n` is a `Binary`, the kind `logb_ctx` returns, as in `Decimal::scaleb_ctx`
and `decimal_gda`: it must be an integer value. A NaN count propagates (invalid
for a signaling NaN); an infinite or non-integer count is a NaN with
`invalid_operation`, whatever the receiver is (an infinite receiver with a
finite count is returned as it is); an integer count beyond the `Int` range
acts as the largest count of its sign, which overflows or underflows every
finite non-zero value of any format. IEEE 754-2019 5.3.3 defines scaleB for integral counts only and leaves a
non-integral second operand (an infinity is not integral) to the language: the
NaN with `invalid_operation` is this library's choice, as in `decimal`.
`x.logb_ctx(ctx)` is $\lfloor \log_2 |x| \rfloor$ as an exact integral value
(also for subnormal $x$): $\operatorname{logB}(0) = -\infty$ with
`division_by_zero`, $\operatorname{logB}(\pm\infty) = +\infty$, and a NaN
propagates.

`x.ilogb()` is the same exponent as an integer: the $e$ with
$2^e \le |x| < 2^{e+1}$, that is $\texttt{exponent2()} +
\texttt{coefficient().bit\_length()} - 1$, read from the value without
building its coefficient. It is `logB` of IEEE 754-2019 5.3.3 with an integral
`logBFormat`: the standard defines $\operatorname{logB}(x)$ as the exponent of
$x$ "determined as though x were represented with infinite range and minimum
exponent", so a subnormal $x$ gives the exponent of its leading bit. For
$\operatorname{logB}(0)$, $\operatorname{logB}(\pm\infty)$ and
$\operatorname{logB}(\text{NaN})$ with an integer `logBFormat` the standard
returns language-defined values outside $\pm 2 (e_{\max} + p - 1)$ and signals
the invalid operation exception (5.3.3 and 7.2); `ilogb` renders those three
cases as `None` and raises no flag. `logb_ctx` is the operation with a
floating-point `logBFormat` ($-\infty$ with `division_by_zero`, $+\infty$, NaN).

```moonbit
///|
test "ilogb" {
  inspect(@binary.Binary::from_int(12).ilogb().unwrap(), content="3")
  inspect(@binary.Binary::zero().ilogb() is None, content="true")
}
```

```moonbit
///|
test "IEEE integral, integer and neighbour operations" {
  let ctx = @binary.BinaryContext::binary64()
  let x = @binary.Binary::from_string("-2.5").unwrap()
  inspect(
    "\{x.floor()} \{x.ceil()} \{x.trunc()} \{x.round()} \{x.round_ties_to_even()}",
    content="-3p0 -1p1 -1p1 -3p0 -1p1",
  )
  let (n, flags) = x.to_int_ctx(ctx, exact=true)
  inspect("\{n.unwrap()} \{flags.inexact()}", content="-2 true")
  let (up, _) = @binary.Binary::one().next_up_ctx(ctx)
  inspect(up.to_hex(), content="0x10000000000001p-52")
  let (tiny, _) = @binary.Binary::zero().next_up_ctx(ctx)
  inspect(tiny.to_shortest_string_ctx(ctx).0, content="5e-324")
}
```

## Comparison and ordering

### `Binary::compare`

Numerical three-way comparison that is total on every value.

```mbti
pub fn Binary::compare(Self, Self) -> Int
pub impl Compare for Binary
```

`compare` returns $-1$, $0$ or $1$ by numerical value, with $-0 = +0$ and
precision ignored. NaN has no numerical order, so `compare` places every NaN
equal to every other NaN and above every non-NaN value; it never aborts. The
result is a total preorder, which is what `Compare` (and sorting) needs, but
it is not the IEEE comparison: under it `nan > 1` holds. The operators `<`,
`<=`, `>`, `>=` and the promoted `op_*` methods use `compare`. For IEEE
semantics use `compare_checked`, the quiet and signaling predicates below, or
`total_order`. The [design page](../design/binary.md#ordering-nan-in-compare)
explains the choice.

### `Binary::compare_checked`

Numerical comparison that rejects NaN.

```mbti
pub fn Binary::compare_checked(Self, Self) -> Result[Int, @arithmetic.ArithmeticError]
pub impl @arithmetic.CompareChecked for Binary
```

Returns the same value as `compare` when neither operand is a NaN, and an
`unordered_comparison` error otherwise.

### `Binary::compare_quiet`, `Binary::compare_signaling`

IEEE comparison as a four-valued relation with flags.

```mbti
pub fn Binary::compare_quiet(Self, Self) -> (@def.PartialOrder, BinaryFlags)
pub fn Binary::compare_signaling(Self, Self) -> (@def.PartialOrder, BinaryFlags)
```

The relation is `Less`, `Equal`, `Greater` or `Unordered` (some operand is a
NaN), with $-0 = +0$. The quiet form raises `invalid_operation` only for a
signaling NaN; the signaling form raises it for every unordered comparison
(IEEE 754-2019 clause 5.11).

### `Binary::compare_quiet_equal`, `Binary::compare_quiet_less`, `Binary::compare_quiet_less_equal`, `Binary::compare_quiet_unordered`, `Binary::compare_signaling_equal`, `Binary::compare_signaling_less`, `Binary::compare_signaling_less_equal`

The IEEE comparison predicates.

```mbti
pub fn Binary::compare_quiet_equal(Self, Self) -> (Bool, BinaryFlags)
pub fn Binary::compare_quiet_less(Self, Self) -> (Bool, BinaryFlags)
pub fn Binary::compare_quiet_less_equal(Self, Self) -> (Bool, BinaryFlags)
pub fn Binary::compare_quiet_unordered(Self, Self) -> (Bool, BinaryFlags)
pub fn Binary::compare_signaling_equal(Self, Self) -> (Bool, BinaryFlags)
pub fn Binary::compare_signaling_less(Self, Self) -> (Bool, BinaryFlags)
pub fn Binary::compare_signaling_less_equal(Self, Self) -> (Bool, BinaryFlags)
```

`compareQuietEqual`, `compareQuietLess`, `compareQuietLessEqual`,
`compareQuietUnordered` and the signaling `Equal`, `Less`, `LessEqual`. Each is
derived from `compare_quiet` or `compare_signaling` and returns its flags; every
predicate except `compare_quiet_unordered` is false on an unordered pair.

### `Binary::compare_quiet_not_equal` and the other comparison predicates of Tables 5.1 and 5.2

The fifteen predicates of IEEE 754-2019 5.11 not listed above.

```mbti
pub fn Binary::compare_quiet_greater(Self, Self) -> (Bool, BinaryFlags)
pub fn Binary::compare_quiet_greater_equal(Self, Self) -> (Bool, BinaryFlags)
pub fn Binary::compare_quiet_greater_unordered(Self, Self) -> (Bool, BinaryFlags)
pub fn Binary::compare_quiet_less_unordered(Self, Self) -> (Bool, BinaryFlags)
pub fn Binary::compare_quiet_not_equal(Self, Self) -> (Bool, BinaryFlags)
pub fn Binary::compare_quiet_not_greater(Self, Self) -> (Bool, BinaryFlags)
pub fn Binary::compare_quiet_not_less(Self, Self) -> (Bool, BinaryFlags)
pub fn Binary::compare_quiet_ordered(Self, Self) -> (Bool, BinaryFlags)
pub fn Binary::compare_signaling_greater(Self, Self) -> (Bool, BinaryFlags)
pub fn Binary::compare_signaling_greater_equal(Self, Self) -> (Bool, BinaryFlags)
pub fn Binary::compare_signaling_greater_unordered(Self, Self) -> (Bool, BinaryFlags)
pub fn Binary::compare_signaling_less_unordered(Self, Self) -> (Bool, BinaryFlags)
pub fn Binary::compare_signaling_not_equal(Self, Self) -> (Bool, BinaryFlags)
pub fn Binary::compare_signaling_not_greater(Self, Self) -> (Bool, BinaryFlags)
pub fn Binary::compare_signaling_not_less(Self, Self) -> (Bool, BinaryFlags)
```

Clause 5.11 lists 22 predicates, 10 in Table 5.1 (with the common mathematical
symbols) and 12 in Table 5.2; with the seven above every one of them has a
function. Each is defined from `compare_quiet` or `compare_signaling` through
the relations that make it true, which is how the tables define it, and returns
the flags of that comparison: a quiet predicate raises `invalid_operation` for
a signaling NaN only, a signaling predicate for every NaN operand. The
doc comment of each names its row. Name spelling follows the seven above:
`compare_`, `quiet` or `signaling`, then the predicate name of the table in
snake case. The pairs the standard states as negations of one another (the two
predicates of one line of a table) return opposite values and the same flags.

| Table | predicate | true relations |
| --- | --- | --- |
| 5.1 | `Binary::compare_quiet_equal` (`compareQuietEqual`) | equal |
| 5.1 | `Binary::compare_quiet_not_equal` (`compareQuietNotEqual`) | less, greater, unordered |
| 5.1 | `Binary::compare_signaling_greater` (`compareSignalingGreater`) | greater |
| 5.1 | `Binary::compare_signaling_not_greater` (`compareSignalingNotGreater`) | less, equal, unordered |
| 5.1 | `Binary::compare_signaling_greater_equal` (`compareSignalingGreaterEqual`) | equal, greater |
| 5.1 | `Binary::compare_signaling_less_unordered` (`compareSignalingLessUnordered`) | less, unordered |
| 5.1 | `Binary::compare_signaling_less` (`compareSignalingLess`) | less |
| 5.1 | `Binary::compare_signaling_not_less` (`compareSignalingNotLess`) | equal, greater, unordered |
| 5.1 | `Binary::compare_signaling_less_equal` (`compareSignalingLessEqual`) | less, equal |
| 5.1 | `Binary::compare_signaling_greater_unordered` (`compareSignalingGreaterUnordered`) | greater, unordered |
| 5.2 | `Binary::compare_signaling_equal` (`compareSignalingEqual`) | equal |
| 5.2 | `Binary::compare_signaling_not_equal` (`compareSignalingNotEqual`) | less, greater, unordered |
| 5.2 | `Binary::compare_quiet_greater` (`compareQuietGreater`) | greater |
| 5.2 | `Binary::compare_quiet_not_greater` (`compareQuietNotGreater`) | less, equal, unordered |
| 5.2 | `Binary::compare_quiet_greater_equal` (`compareQuietGreaterEqual`) | equal, greater |
| 5.2 | `Binary::compare_quiet_less_unordered` (`compareQuietLessUnordered`) | less, unordered |
| 5.2 | `Binary::compare_quiet_less` (`compareQuietLess`) | less |
| 5.2 | `Binary::compare_quiet_not_less` (`compareQuietNotLess`) | equal, greater, unordered |
| 5.2 | `Binary::compare_quiet_less_equal` (`compareQuietLessEqual`) | less, equal |
| 5.2 | `Binary::compare_quiet_greater_unordered` (`compareQuietGreaterUnordered`) | greater, unordered |
| 5.2 | `Binary::compare_quiet_unordered` (`compareQuietUnordered`) | unordered |
| 5.2 | `Binary::compare_quiet_ordered` (`compareQuietOrdered`) | less, equal, greater |


### `Binary::total_order`, `Binary::total_order_mag`, `Binary::total_order_compare`

The IEEE 754 `totalOrder` relation.

```mbti
pub fn Binary::total_order(Self, Self) -> Bool
pub fn Binary::total_order_mag(Self, Self) -> Bool
pub fn Binary::total_order_compare(Self, Self) -> Int
```

`total_order_compare` orders all values as

$$
-\mathrm{qNaN} < -\mathrm{sNaN} < -\infty < \text{negative finite} < -0 < +0 < \text{positive finite} < +\infty < +\mathrm{sNaN} < +\mathrm{qNaN},
$$

with NaNs of one sign and kind ordered by payload (reversed for the negative
side). `x.total_order(y)` is `total_order_compare(x, y) <= 0` and
`total_order_mag` compares absolute values. Values that are numerically equal
but differ in precision compare equal. The operations are quiet.

### `Binary::min`, `Binary::max`

The smaller or larger of two values, ignoring a NaN operand.

```mbti
pub fn Binary::min(Self, Self) -> Self
pub fn Binary::max(Self, Self) -> Self
```

When exactly one operand is a NaN the other is returned (the IEEE 754-2008
`minNum`/`maxNum` convention for quiet NaNs); a signaling NaN is ignored in the
same way, without quieting or a flag, and two NaNs give the argument. When the operands compare equal
under `compare` (for example $-0$ and $+0$) the receiver is returned. No flags
are produced.

### `Binary::clamp`, `Binary::clamp_checked`

Restrict a value to `[min, max]`.

```mbti
pub fn Binary::clamp(Self, min~ : Self, max~ : Self) -> Self
pub fn Binary::clamp_checked(Self, min~ : Self, max~ : Self) -> Result[Self, @arithmetic.ArithmeticError]
```

A NaN receiver is returned unchanged. `clamp` aborts when a bound is a NaN or
`min > max`; `clamp_checked` returns a `domain_error` in those cases.

```moonbit
///|
test "three different orders on Binary" {
  let nan = @binary.Binary::nan()
  let zero = @binary.Binary::zero()
  let neg_zero = @binary.Binary::negative_zero()
  inspect(nan.compare(zero), content="1")
  inspect(nan.compare_checked(zero) is Err(_), content="true")
  let (unordered, flags) = zero.compare_quiet_unordered(nan)
  inspect("\{unordered} \{flags.invalid_operation()}", content="true false")
  inspect(neg_zero.compare(zero), content="0")
  inspect(neg_zero.total_order_compare(zero), content="-1")
  inspect(neg_zero == zero, content="true")
  inspect(neg_zero.identical(zero), content="false")
  inspect(nan == nan, content="true")
  let values = [nan, @binary.Binary::inf(), zero, @binary.Binary::from_int(-3)]
  values.sort()
  inspect(values.map(fn(v) { v.to_string() }).join(" "), content="-3p0 0 inf nan")
}
```

## Text and hexadecimal conversion

### `Binary::to_string`

Prints the exact stored value as `coefficient p exponent`.

```mbti
pub fn Binary::to_string(Self) -> String
pub impl Show for Binary
```

A finite nonzero value prints as `[-]<c>p<e>` with $c$ in decimal, meaning
$c \cdot 2^e$ (for example `3p-1` is $1.5$). Zeros print as `0` and `-0`,
infinities as `inf` and `-inf`, and every NaN as `nan`. The form is exact and
unambiguous but not a decimal rendering; use `to_shortest_string` for that.

### `Binary::from_string`, `Binary::from_string_ctx`

Parse a decimal literal with correct rounding (IEEE
`convertFromDecimalCharacter`).

```mbti
pub fn Binary::from_string(String, precision? : Int) -> Result[Self, @arithmetic.ArithmeticError]
pub fn Binary::from_string_ctx(String, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
```

The accepted syntax is `[+-]digits[.digits][e[+-]digits]` (a leading or
trailing point is allowed, the exponent marker is `e` or `E`), and the
case-insensitive words `inf`, `infinity`, `nan`, `qnan` and `snan`, with
surrounding whitespace ignored. Anything else is a `parse_error`. The exact
decimal value $D \cdot 10^k$ is rounded once under the context, for any number
of digits and any exponent; overflow, underflow and inexact are reported as for
arithmetic. `from_string(s, precision=p)` uses `BinaryContext::new(precision=p)` (default 53) and
drops the flags.

### `Binary::to_decimal_string_ctx`

Formats a value with a fixed number of significant decimal digits (IEEE
`convertToDecimalCharacter`).

```mbti
pub fn Binary::to_decimal_string_ctx(Self, Int, BinaryContext) -> (String, BinaryFlags)
```

The output is `[-]d.ddd…e±x` with exactly `digits` significant digits
(at least 1), correctly rounded in the context's rounding direction;
`inexact` is raised when nonzero digits were dropped. Only the rounding
direction of the context is used. Zero prints as `0.00…e+0` with its sign,
infinities as `inf`/`-inf`, NaNs as `nan`/`snan` with their sign. The text
parses back with `from_string_ctx`.

### `Binary::to_shortest_string`, `Binary::to_shortest_string_ctx`

Formats the shortest decimal that reads back as the same value.

```mbti
pub fn Binary::to_shortest_string(Self) -> String
pub fn Binary::to_shortest_string_ctx(Self, BinaryContext) -> (String, BinaryFlags)
```

`to_shortest_string_ctx(x, ctx)` returns the decimal with the fewest
significant digits that `from_string_ctx(_, ctx)` maps back to $x$ under
round-to-nearest-even (the context's own rounding direction is ignored). When
two candidates of that length read back, the nearer one is chosen, then the
one with an even last digit. The layout follows ECMAScript `Number#toString`:
positional notation for decimal exponents in $[-6, 21)$, otherwise
`d.ddde±x`; unlike ECMAScript, $-0$ prints as `-0`. For binary64 values in
`BinaryContext::binary64()` the result equals the host `Double` formatter.
`to_shortest_string()` uses `BinaryContext::new(precision=precision())`, so it is the shortest
string that `from_string(text, precision=x.precision())` maps back to `x`. An
operand that is not representable in the context is first rounded into it
(`apply_ctx`, in the rounding direction of the context, with the overflow and
underflow of the context), and the result is the shortest string of that
rounded value: `inf` or `-inf` on overflow, `0` or `-0` on underflow (the
largest finite value for a direction that rounds toward zero). A value of the
format prints as itself. The second component is the flags of that rounding
(`inexact`, `overflow`, `underflow`); it is empty for a value of the format, a
NaN or an infinity.

### `Binary::from_hex`, `Binary::from_hex_ctx`, `Binary::to_hex`

Read and write the exact value with a hexadecimal coefficient.

```mbti
pub fn Binary::from_hex(String, Int) -> Result[Self, @arithmetic.ArithmeticError]
pub fn Binary::from_hex_ctx(String, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
pub fn Binary::to_hex(Self) -> String
```

The syntax is the IEEE 754-2019 §5.12.3 hexSequence: an optional sign, `0x`
or `0X`, hexadecimal digits with at most one point (`1.8`, `.8` or `1.`), and a
required `p` or `P` exponent with an optional sign and decimal digits. The
value is the hexadecimal significand times $2^{\text{exponent}}$, so `0x3p-1`
and `0x1.8p0` are both $1.5$. `from_hex(s, p)` rounds once to precision `p`
with nearest-even and reports no flags; a `p` outside
`1..=binary_precision_max` is an `Err`. `from_hex_ctx(s, context)` is the
§5.12.3 conversion: it rounds the exact value once under the rounding direction,
precision, exponent range and tininess rule of `context` and returns the
`inexact`, `underflow` and `overflow` flags, like `from_string_ctx`. An exponent
field of any length is a valid text: it is read with saturation at $2^{60}$, as the
decimal reader does, so an exponent outside the 32-bit range overflows or
underflows there (the result of the context with its flags, in every rounding
direction) instead of being a parse error, and a zero significand is the zero
of the sign for any exponent. `from_hex`, which stores the exact value, reports
an exponent outside the 32-bit range as a parse error (a zero significand is
still a zero). Both accept
`inf`, `infinity`, `nan` and `snan` in any case with an optional sign
(§5.12.1); `snan` gives a signaling NaN. Surrounding whitespace is trimmed;
any other text is a `parse_error`. `to_hex` prints the stored coefficient in
lower case, `0x0p0` or `-0x0p0` for a zero, and `nan`/`inf` with a sign.

```moonbit
///|
test "decimal and hexadecimal text" {
  let tenth = @binary.Binary::from_string("0.1").unwrap()
  inspect(tenth, content="3602879701896397p-55")
  inspect(tenth.to_hex(), content="0xccccccccccccdp-55")
  inspect(tenth.to_shortest_string(), content="0.1")
  let ctx = @binary.BinaryContext::binary64()
  let (digits, flags) = tenth.to_decimal_string_ctx(25, ctx)
  inspect("\{digits} \{flags.inexact()}", content="1.000000000000000055511151e-1 true")
  let (single, _) = @binary.Binary::from_string_ctx("0.1", @binary.BinaryContext::binary32()).unwrap()
  inspect(single, content="13421773p-27")
  inspect(@binary.Binary::from_hex("0x3p-1", 53).unwrap(), content="3p-1")
  // 0x1.00000000000008p0 has 57 significant bits: binary64 rounds it, inexact.
  let (rounded, hex_flags) = @binary.Binary::from_hex_ctx("0x1.00000000000008p0", ctx).unwrap()
  inspect(rounded, content="1p0")
  inspect(hex_flags.inexact(), content="true")
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

### `BinaryInterchangeFormat::precision`, `BinaryInterchangeFormat::e_min`, `BinaryInterchangeFormat::e_max`, `BinaryInterchangeFormat::bias`, `BinaryInterchangeFormat::exponent_field_width`, `BinaryInterchangeFormat::trailing_significand_field_width`, `BinaryInterchangeFormat::storage_width`

The parameters of a format.

```mbti
pub fn BinaryInterchangeFormat::precision(Self) -> Int
pub fn BinaryInterchangeFormat::e_min(Self) -> Int
pub fn BinaryInterchangeFormat::e_max(Self) -> Int
pub fn BinaryInterchangeFormat::bias(Self) -> Int
pub fn BinaryInterchangeFormat::exponent_field_width(Self) -> Int
pub fn BinaryInterchangeFormat::trailing_significand_field_width(Self) -> Int
pub fn BinaryInterchangeFormat::storage_width(Self) -> Int
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

### `BinaryInterchange::to_binary`

Decodes an encoding exactly.

```mbti
pub fn BinaryInterchange::to_binary(Self) -> Binary
```

The result has the format precision. Normal and subnormal numbers, signed
zeros and infinities decode exactly; a NaN keeps its sign and payload (the
fraction without the quiet bit), and a signaling NaN stays signaling. No host
`Float` or `Double` is involved.

### `Binary::convert_format`

Convert a value to a binary interchange format and return it as a `Binary`.

```mbti
pub fn Binary::convert_format(Self, BinaryInterchangeFormat, rounding? : BinaryRoundingMode, tininess? : TininessDetection) -> (Self, BinaryFlags)
```

The IEEE 754-2019 §5.4.2 formatOf-convertFormat operation, with the parameters of
`to_interchange` and the value instead of the encoding. A conversion to a wider
precision and range is exact and raises nothing; to a narrower one the value is
rounded under `rounding` and `tininess` with `inexact`, `underflow` and
`overflow`. A signaling NaN gives a quiet NaN and `invalid_operation`, also when
the source already has the destination's precision (the canonicalizing
conversion). A NaN payload is kept when the destination holds it and truncated to
its low bits otherwise (§6.2.3), so the result is exactly what decoding
`to_interchange` returns. `apply_ctx` and `to_interchange` stay.

```moonbit
///|
test "convert a value between formats" {
  let b32 = @binary.BinaryInterchangeFormat::Binary32
  let tenth = @binary.Binary::from_string("0.1", precision=200).unwrap()
  let (single, flags) = tenth.convert_format(b32)
  inspect(single.precision(), content="24")
  inspect(flags.inexact(), content="true")
  let (up, _) = tenth.convert_format(
    b32,
    rounding=@binary.BinaryRoundingMode::RoundTowardPositive,
  )
  inspect(up.compare(single), content="0")
}
```

### `BinaryInterchange::from_binary`, `Binary::to_interchange`

Round a value into a format and encode it.

```mbti
pub fn BinaryInterchange::from_binary(Binary, BinaryInterchangeFormat, rounding? : BinaryRoundingMode, tininess? : TininessDetection) -> (Self, BinaryFlags)
pub fn Binary::to_interchange(Self, BinaryInterchangeFormat, rounding? : BinaryRoundingMode, tininess? : TininessDetection) -> (BinaryInterchange, BinaryFlags)
```

The two are the same operation: `apply_ctx` with the format's context, then
encoding. A signaling NaN is encoded as a quiet NaN with `invalid_operation`,
and a payload is truncated to the payload field.

```moonbit
///|
test "encode and decode interchange bits" {
  let b32 = @binary.BinaryInterchangeFormat::Binary32
  let tenth = @binary.Binary::from_string("0.1", precision=200).unwrap()
  let (nearest, flags) = tenth.to_interchange(b32)
  inspect("\{nearest.to_hex()} \{flags.inexact()}", content="3DCCCCCD true")
  let (chopped, _) = tenth.to_interchange(
    b32,
    rounding=@binary.BinaryRoundingMode::RoundTowardZero,
  )
  inspect(chopped.to_hex(), content="3DCCCCCC")
  let snan = @binary.BinaryInterchange::from_hex("7F800001", b32)
    .unwrap()
    .to_binary()
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
[design page](../design/binary.md#certified-elementary-functions) gives the
argument for the value and the flags.

When the attempts run out, `try_f_ctx` returns a `certification_failure`
error whose `CertificationFailureDetail` names the operation, the stage
(`RangeReduction` or `TargetRounding`), the reason and the last working
precision. An argument outside the real domain of `ln`, `log2`, `log10`, `log1p`, `log2p1`,
`log10p1`, `asin`, `acos`, `acosh`, `atanh`, `asinpi` and `acospi`, and an infinite
argument of the trigonometric functions (`sin`, `cos`, `tan`, `sinpi`, `cospi`,
`tanpi`), is a value of `try_f_ctx`, a NaN with `invalid_operation`, as it is for the
plain form, and so is a domain case of `rootn`, `pow`, `powr`, `rsqrt` and
`compound`: `try_f_ctx` returns `Err` only for a result that could not be computed. The non-`try` forms turn that `Err` into a quiet NaN with `not_computed`. NaN operands propagate quietly (a signaling NaN
raises `invalid_operation`), and poles return a signed infinity with
`division_by_zero` (for example $\ln 0 = -\infty$,
$\operatorname{atanh}(1) = +\infty$). Exactly representable results that an
enclosure cannot isolate are detected before the loop, for example
$\log_2 2^k = k$, $2^n$ for integral $n$, $10^n$ for integral $n \ge 0$,
dyadic powers such as $16^{3/4} = 8$, exact roots such as
$\operatorname{rootn}(8, -3) = 1/2$, $\sin(\pm 0) = \pm 0$ and
$\operatorname{sinpi}(1/2) = 1$; each function lists its own cases below.
They are rounded once from their exact value, so their flags are right in
every rounding mode.

Every result that reaches the loop is not a rounding breakpoint, so an
enclosure end that is itself representable (such as $1$ for $e^x$ or $x$ for
$\sin x$ at a tiny $x$) cannot be the result. The functions other than
`rootn` move such an end just inside the enclosure before rounding it; `pow`
does so once its exactness test has excluded a breakpoint.
In addition, `sin`, `tan`, `asin`, `sinh`, `tanh`, `asinh` and `atanh` decide
an argument with $|x|^3$ below the target spacing at $x$ directly from
$|f(x) - x| \le |x|^3$, and `cos`, `cosh`, `expm1` and `log1p` do the same with
$x^2$ (around $1$ for `cos` and `cosh`, around $x$ for the others), before the
loop. Tiny arguments are therefore certified in every rounding mode: `sin` of
$2^{-6000}$ at 53 bits is $2^{-6000}$ with `inexact`, and $e^{2^{-20000}}$
rounded toward zero is $1$ with `inexact`.

### `Binary::exp`, `Binary::exp_ctx`, `Binary::try_exp_ctx`

The exponential $e^x$.

```mbti
pub fn Binary::exp(Self) -> Self
pub fn Binary::exp_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn Binary::try_exp_ctx(Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
```

Defined on all of $\mathbb{R}$: $e^{\pm 0} = 1$ exactly, $e^{-\infty} = +0$
and $e^{+\infty} = +\infty$. Results certainly beyond the exponent range are
decided from certified bounds on $\log_2 e$ before the main loop, so huge
arguments overflow or underflow with the correct flags instead of failing.

### `Binary::expm1`, `Binary::expm1_ctx`, `Binary::try_expm1_ctx`

$e^x - 1$ without the cancellation of `exp(x) - 1` near zero.

```mbti
pub fn Binary::expm1(Self) -> Self
pub fn Binary::expm1_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn Binary::try_expm1_ctx(Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
```

$\operatorname{expm1}(\pm 0) = \pm 0$, $\operatorname{expm1}(-\infty) = -1$
and $\operatorname{expm1}(+\infty) = +\infty$. For
$x \le -(p+3)\ln 2$ the value lies within $2^{-(p+3)}$ above $-1$, and the
result is decided from the rounding direction alone: $-1$, or
$-(1 - 2^{-p})$ when rounding toward zero or $+\infty$, always inexact.

### `Binary::exp2m1`, `Binary::exp2m1_ctx`, `Binary::try_exp2m1_ctx`

$2^x - 1$ without the cancellation of `exp2(x) - 1` near zero.

```mbti
pub fn Binary::exp2m1(Self) -> Self
pub fn Binary::exp2m1_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn Binary::try_exp2m1_ctx(Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
```

IEEE 754-2019 §9.2: $\operatorname{exp2m1}(\pm 0) = \pm 0$,
$\operatorname{exp2m1}(-\infty) = -1$ and $\operatorname{exp2m1}(+\infty) = +\infty$,
with no exception. An integral $x$ gives the exact integer $2^x - 1$ (or
$-(1 - 2^{x})$ for $x < 0$), rounded as a dyadic: exact or a rounding tie while
it has at most $p + 1$ bits, and otherwise the neighbour of $2^x$ chosen by the
rounding direction without forming $2^x - 1$. For $x \le -(p + 3)$ the value
lies within $2^{-(p+3)}$ above $-1$ and the rounding direction alone decides
(as for `expm1`). A result certainly beyond the exponent range is decided before
the main loop, so $x$ near $e_{\max} + 1$ overflows with the correct flags.

### `Binary::exp10m1`, `Binary::exp10m1_ctx`, `Binary::try_exp10m1_ctx`

$10^x - 1$ without the cancellation of `exp10(x) - 1` near zero.

```mbti
pub fn Binary::exp10m1(Self) -> Self
pub fn Binary::exp10m1_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn Binary::try_exp10m1_ctx(Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
```

IEEE 754-2019 §9.2: the special values of `exp2m1`. A positive integer
$x \le \max(4096, p)$ gives the exact integer $10^x - 1$, rounded as a dyadic.
Saturation towards $-1$ and the overflow decision follow `exp2m1`, with
$\log_2 10$ in place of 1.

### `Binary::exp2`, `Binary::exp2_ctx`, `Binary::try_exp2_ctx`

The power of two $2^x$.

```mbti
pub fn Binary::exp2(Self) -> Self
pub fn Binary::exp2_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn Binary::try_exp2_ctx(Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
```

An integral $x$ with $|x| < 2^{31}$ gives the exact $2^x$, rounded into the
context only when it leaves the exponent range. The other special values are
those of `exp`.

### `Binary::exp10`, `Binary::exp10_ctx`, `Binary::try_exp10_ctx`

The power of ten $10^x$.

```mbti
pub fn Binary::exp10(Self) -> Self
pub fn Binary::exp10_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn Binary::try_exp10_ctx(Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
```

An integral $x$ in $[0, \max(4096, p)]$ gives the exact $10^x = 5^x 2^x$,
rounded once. For a larger integral $x$ the odd part $5^x$ has more than
$p + 1$ bits, so the result is neither representable nor a midpoint, and a
negative integral $x$ gives a value that is never dyadic; both are always
inexact. The other special values are those of `exp`.

### `Binary::ln`, `Binary::ln_ctx`, `Binary::try_ln_ctx`

The natural logarithm $\ln x$.

```mbti
pub fn Binary::ln(Self) -> Self
pub fn Binary::ln_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn Binary::try_ln_ctx(Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
```

The domain is $x > 0$. $\ln 1 = +0$ exactly; $\ln(\pm 0) = -\infty$ with
`division_by_zero`; $\ln(+\infty) = +\infty$. A negative finite argument is a
`domain_error`, while $-\infty$ gives a quiet NaN with `invalid_operation`
also from `try_ln_ctx`.

### `Binary::try_exp_directed_pair`, `Binary::try_ln_directed_pair`

The two directed roundings of $e^x$ or $\ln x$ in one call, for the interval types.

```mbti
pub fn Binary::try_exp_directed_pair(Self, Int32) -> Result[(Self, Self), @arithmetic.ArithmeticError]
pub fn Binary::try_ln_directed_pair(Self, Int32) -> Result[(Self, Self), @arithmetic.ArithmeticError]
```

`x.try_exp_directed_pair(p)` returns the values of `x.try_exp_ctx` at precision $p$ under `RoundTowardNegative` and under `RoundTowardPositive`, as `(low, high)`, and the error of the first of the two calls that fails; `try_ln_directed_pair` is the same for `try_ln_ctx`. For every operand the result is exactly what the two calls give. Where one certified enclosure can decide both roundings (a finite $x \ne 0$ with an in-range result for `exp`, a finite positive $x \ne 1$ for `ln`) it costs one evaluation instead of two; every other operand is answered by the two calls themselves.

### `Binary::log1p`, `Binary::log1p_ctx`, `Binary::try_log1p_ctx`

$\ln(1 + x)$ without the rounding of `1 + x`.

```mbti
pub fn Binary::log1p(Self) -> Self
pub fn Binary::log1p_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn Binary::try_log1p_ctx(Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
```

The domain is $x > -1$. $\operatorname{log1p}(\pm 0) = \pm 0$,
$\operatorname{log1p}(-1) = -\infty$ with `division_by_zero`, a finite
$x < -1$ is a `domain_error`, and $-\infty$ gives a quiet NaN with
`invalid_operation`.

### `Binary::log2p1`, `Binary::log2p1_ctx`, `Binary::try_log2p1_ctx`

$\log_2(1 + x)$ without the rounding of `1 + x`.

```mbti
pub fn Binary::log2p1(Self) -> Self
pub fn Binary::log2p1_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn Binary::try_log2p1_ctx(Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
```

The domain is $x \ge -1$ (Table 9.1). $\operatorname{log2p1}(\pm 0) = \pm 0$,
$\operatorname{log2p1}(+\infty) = +\infty$, $\operatorname{log2p1}(-1) = -\infty$
with `division_by_zero`, a finite $x < -1$ is a `domain_error`, and $-\infty$
gives a quiet NaN with `invalid_operation`. $x = 2^k - 1$ (and
$x = -(1 - 2^{-k})$) gives the exact integer $k$ (and $-k$).

### `Binary::log10p1`, `Binary::log10p1_ctx`, `Binary::try_log10p1_ctx`

$\log_{10}(1 + x)$ without the rounding of `1 + x`.

```mbti
pub fn Binary::log10p1(Self) -> Self
pub fn Binary::log10p1_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn Binary::try_log10p1_ctx(Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
```

The special values of `log2p1`. $x = 10^k - 1$ for an integer $k \ge 1$ gives
the exact integer $k$.

### `Binary::log2`, `Binary::log2_ctx`, `Binary::try_log2_ctx`

The binary logarithm $\log_2 x$.

```mbti
pub fn Binary::log2(Self) -> Self
pub fn Binary::log2_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn Binary::try_log2_ctx(Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
```

Special values and domain as for `ln`. A power of two $2^k$ gives the exact
integer $k$, rounded into the context.

### `Binary::log10`, `Binary::log10_ctx`, `Binary::try_log10_ctx`

The decimal logarithm $\log_{10} x$.

```mbti
pub fn Binary::log10(Self) -> Self
pub fn Binary::log10_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn Binary::try_log10_ctx(Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
```

Special values and domain as for `ln`. $x = 10^k$ with $k \ge 1$ (stored as
the coefficient $5^k$ and exponent $k$) gives the exact integer $k$, rounded
into the context, at any precision that holds $10^k$.

### `Binary::pow`, `Binary::pow_ctx`, `Binary::try_pow_ctx`

The real power $x^y$.

```mbti
pub fn Binary::pow(Self, Self) -> Self
pub fn Binary::pow_ctx(Self, Self, BinaryContext) -> (Self, BinaryFlags)
pub fn Binary::try_pow_ctx(Self, Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
```

The cases are tried in this order, as in IEEE 754-2019 §9.2.1:

1. $x^{\pm 0} = 1$ for every $x$, and $1^y = 1$ for every $y$, NaN included
   (also a signaling NaN, without `invalid_operation`).
2. An integral $y$ with $|y| < 2^{31}$ is `pown_ctx(x, y)`.
3. A NaN operand propagates.
4. An infinite $y$: $(\pm 1)^{\pm\infty} = 1$; otherwise the result is
   $+\infty$ when $|x| > 1$ and $y = +\infty$ or $|x| < 1$ and $y = -\infty$,
   and $+0$ in the other two cases, $x = \pm 0$ included
   ($(\pm 0)^{-\infty} = +\infty$). No flag is raised.
5. An infinite $x$: $(\pm\infty)^{y < 0}$ is a zero and
   $(\pm\infty)^{y > 0}$ an infinity, negative only for $x = -\infty$ and an
   odd integral $y$. No flag is raised.
6. A zero $x$: $(\pm 0)^{y < 0}$ is an infinity with `division_by_zero` and
   $(\pm 0)^{y > 0}$ a zero, negative only for $x = -0$ and an odd integral
   $y$; so $(-0)^{3/4} = +0$.
7. A negative finite $x$ with a non-integral $y$ is a `domain_error`. With an
   integral $y$ (here $|y| \ge 2^{31}$) the result is $|x|^y$ for an even $y$
   and $-|x|^y$ for an odd one, computed with the directed rounding modes
   swapped.
8. $y = \pm 2^{-k}$ with $1 \le k \le 29$ is `try_rootn_ctx(x, \pm 2^k)`.
9. A result certainly outside the exponent range is decided from certified
   bounds on $\log_2 x$.
10. An exactly dyadic result is computed and rounded once. For
    $x = c \cdot 2^e$ and $y = m / 2^k$ ($c$, $m$ odd, $1 \le k \le 30$) it
    exists exactly when $2^k$ divides $e$ and $c$ is a perfect $2^k$-th power
    $r$ (tested as for `rootn`, for coefficients of any size); then
    $x^y = r^m \cdot 2^{me/2^k}$, which is dyadic for $m < 0$ only when
    $r = 1$. So $16^{3/4} = 8$ without `inexact`. A dyadic result whose odd part would
    need more than $2p + 64$ bits is not a rounding breakpoint and is left to
    the next step.
11. Otherwise the value is certified from enclosures of $e^{y \ln x}$.

Integrality and parity of $y$ are read from its odd coefficient: a finite
nonzero $y$ is integral when `exponent2()` $\ge 0$ and odd when it is $0$.
When step 10 has shown that the result is not a rounding breakpoint, step 11
moves a representable enclosure end just inside before rounding, so an
exponent so small that $x^y$ lies closer to $1$ than the target spacing is
still certified: $2^{2^{-16000}}$ in `binary128()` is $1$ with `inexact`. A
few results with a power-of-two base that step 10 cannot classify (an
exponent of magnitude at least $2^{31}$, or a scale outside the 32-bit range)
keep the plain test.

### `Binary::rootn`, `Binary::rootn_ctx`, `Binary::try_rootn_ctx`

The real $n$-th root $x^{1/n}$.

```mbti
pub fn Binary::rootn(Self, Int) -> Self
pub fn Binary::rootn_ctx(Self, Int, BinaryContext) -> (Self, BinaryFlags)
pub fn Binary::try_rootn_ctx(Self, Int, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
```

$n = 0$ is a `domain_error`, an invalid operation, for every $x$, a quiet NaN and $\pm 0$ included (IEEE 754-2019 Table 9.1, "n = 0: invalid operation"); it is not `division_by_zero`, which §7.3 keeps for an exact infinite result on finite operands, here $\operatorname{rootn}(\pm 0, n)$ with $n < 0$. `rootn_ctx` then returns a quiet NaN with `invalid`. Every other `Int` degree is supported, including
`Int.min`; a NaN propagates. A negative $n$ gives $x^{-1/|n|}$.

| $x$ | odd $n > 0$ | even $n > 0$ | odd $n < 0$ | even $n < 0$ |
| --- | --- | --- | --- | --- |
| $+\infty$ | $+\infty$ | $+\infty$ | $+0$ | $+0$ |
| $-\infty$ | $-\infty$ | `domain_error` | $-0$ | `domain_error` |
| $+0$ | $+0$ | $+0$ | $+\infty$, `division_by_zero` | $+\infty$, `division_by_zero` |
| $-0$ | $-0$ | $+0$ | $-\infty$, `division_by_zero` | $+\infty$, `division_by_zero` |
| finite $x < 0$ | $-\vert x\vert^{1/n}$ | `domain_error` | $-\vert x\vert^{1/n}$ | `domain_error` |

So $\operatorname{rootn}(-8, 3) = -2$. $n = 1$ rounds $x$ into the context and
$n = -1$ is the correctly rounded $1/x$. For any other degree an exact root is
detected when $|n|$ divides the exponent of $x = c \cdot 2^e$ and the odd
coefficient $c$ (of any size) is a perfect $|n|$-th power $r$; the
result is then $\pm r \cdot 2^{e/|n|}$ rounded once, or for $n < 0$ the
correctly rounded reciprocal of it. So $\operatorname{rootn}(8, -3) = 1/2$
without `inexact` in every rounding mode, and an exact square root of a
6001-bit coefficient is found as well.

### `Binary::rsqrt`, `Binary::rsqrt_ctx`, `Binary::try_rsqrt_ctx`

The reciprocal square root $1/\sqrt{x}$ (`rSqrt` of IEEE 754-2019 §9.2).

```mbti
pub fn Binary::rsqrt(Self) -> Self
pub fn Binary::rsqrt_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn Binary::try_rsqrt_ctx(Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
```

§9.2.1: $\operatorname{rSqrt}(+\infty) = +0$ with no exception and
$\operatorname{rSqrt}(\pm 0) = \pm\infty$ with `division_by_zero`, so
$\operatorname{rSqrt}(-0) = -\infty$ (MPFR's `mpfr_rec_sqrt` returns $+\infty$
there by its own convention, and the oracle rows follow the standard). A
negative finite $x$ and $-\infty$ are a `domain_error` (Table 9.1,
"$x < 0$: invalid operation"); a signaling NaN is invalid and a quiet NaN
propagates. A positive finite $x$ is `rootn_ctx(x, -2)`: a power of four
$4^k$ gives the exact $2^{-k}$ without `inexact`, and an exponent far outside
the range is decided without forming the root.

### `Binary::compound`, `Binary::compound_ctx`, `Binary::try_compound_ctx`

The compound factor $(1 + x)^n$ for an integer $n$, with the exact sum $1 + x$
(interest and growth rates, without the rounding of `1 + x`).

```mbti
pub fn Binary::compound(Self, Int) -> Self
pub fn Binary::compound_ctx(Self, Int, BinaryContext) -> (Self, BinaryFlags)
pub fn Binary::try_compound_ctx(Self, Int, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
```

The special values of §9.2.1 are decided first, a signaling NaN before any of
them:

| $x$ | $n < 0$ | $n = 0$ | $n > 0$ |
| --- | --- | --- | --- |
| quiet NaN | quiet NaN | $1$ | quiet NaN |
| $-\infty$, finite $x < -1$ | `domain_error` | `domain_error` | `domain_error` |
| $-1$ | $+\infty$, `division_by_zero` | $1$ | $+0$ |
| $\pm 0$ | $1$ | $1$ | $1$ |
| $+\infty$ | $+0$ | $1$ | $+\infty$ |

Otherwise $1 + x$ is formed exactly (for any operand up to $2^{26}$ bits) and
the result is `pown_ctx(1 + x, n)`, so the exact cases, the range decision and
the single rounding are those of `pown`. When $|n x|$ is below
$2^{-(p + 9)}$ the result is the neighbour of $1$ (or $1$) that the rounding
direction chooses, always inexact and never an underflow. A wider operand
(beyond $2^{26}$ bits) is not representable in the context and is certified
from $n \cdot \operatorname{log1p}(x)$.

### `Binary::powr`, `Binary::powr_ctx`, `Binary::try_powr_ctx`

The real power $x^y$ defined as $\exp(y \ln x)$, so that the domain excludes a
negative $x$ (`powr` of IEEE 754-2019 §9.2).

```mbti
pub fn Binary::powr(Self, Self) -> Self
pub fn Binary::powr_ctx(Self, Self, BinaryContext) -> (Self, BinaryFlags)
pub fn Binary::try_powr_ctx(Self, Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
```

The cases are tried in this order, as in §9.2.1; every `domain_error` below is
a quiet NaN with `invalid_operation` from `powr_ctx`:

1. A signaling NaN operand is invalid; a quiet NaN base gives a quiet NaN.
2. A negative $x$ ($-\infty$ included, a quiet NaN exponent too) is invalid:
   $\operatorname{powr}(x, y)$ for $x < 0$ is never a real number.
3. A quiet NaN $y$ gives a quiet NaN.
4. $x = \pm 0$: $y = \pm 0$ is invalid; $y = -\infty$ gives $+\infty$ with no
   exception; a finite $y < 0$ gives $+\infty$ with `division_by_zero`; $y > 0$
   gives $+0$.
5. $x = +\infty$: $y = \pm 0$ is invalid; $y < 0$ gives $+0$; $y > 0$ gives
   $+\infty$.
6. $x = +1$: $\pm\infty$ is invalid, any other $y$ gives $1$.
7. $y = \pm 0$ gives $1$.
8. Otherwise $x > 0$ and $y$ is finite and nonzero: `try_pow_ctx(x, y)`, which
   owns the exact dyadic cases, the range decision and the rounding.

So $\operatorname{powr}(\pm 0, \pm 0)$, $\operatorname{powr}(+\infty, \pm 0)$
and $\operatorname{powr}(1, \pm\infty)$ are invalid operations, where
`pow` gives $1$ for the first two and for $1^{\pm\infty}$ (§9.2.1).

### `Binary::hypot`, `Binary::hypot_ctx`, `Binary::try_hypot_ctx`

$\sqrt{x^2 + y^2}$ without intermediate overflow or underflow.

```mbti
pub fn Binary::hypot(Self, Self) -> Self
pub fn Binary::hypot_ctx(Self, Self, BinaryContext) -> (Self, BinaryFlags)
pub fn Binary::try_hypot_ctx(Self, Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
```

The squares are formed exactly and one correctly rounded square root is
taken, so the result is $\circ(\sqrt{x^2+y^2})$ and exact when the root is.
$\operatorname{hypot}(\pm\infty, y) = +\infty$ even when $y$ is a NaN
(`invalid_operation` is raised only for a signaling NaN). When the smaller
operand $b$ is too small to move $\sqrt{a^2 + b^2}$ past the next rounding
breakpoint above $|a|$, it is replaced by a power of two that rounds the same
way: for $|a| = c \cdot 2^e$ with leading bit $2^t$ and
$g = \min(e, t - p - 1)$, every $|b| < 2^{g - 3}$ becomes $2^{g - 3}$. The
exact sum stays small however far apart the exponents are:
$\operatorname{hypot}(1, 2^{-600000})$ is $1$ with `inexact`. The exact sum is refused with a
`certification_failure` only when its two squares would still be shifted
against each other by more than $10^6$ bits, which needs an operand or target
precision near $500\,000$ bits.

### `Binary::sin`, `Binary::sin_ctx`, `Binary::try_sin_ctx`

The sine of an argument in radians.

```mbti
pub fn Binary::sin(Self) -> Self
pub fn Binary::sin_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn Binary::try_sin_ctx(Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
```

$\sin(\pm 0) = \pm 0$ exactly; an infinite argument is a `domain_error`. The
argument is reduced by an enclosure of $\pi/2$ computed at a working precision
of at least $p + \max(0, \lfloor\log_2|x|\rfloor + 1) + 96$ bits, so the
quadrant is certain for every finite input. When that starting precision
exceeds $10^6$ bits, that is for $|x| \ge 2^{10^6 - p - 96}$, the result is a
`certification_failure` with stage `RangeReduction` and reason
`ResourceLimit`, returned at once; no attempt goes beyond $10^6$ bits.

### `Binary::cos`, `Binary::cos_ctx`, `Binary::try_cos_ctx`

The cosine of an argument in radians.

```mbti
pub fn Binary::cos(Self) -> Self
pub fn Binary::cos_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn Binary::try_cos_ctx(Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
```

$\cos(\pm 0) = 1$ exactly. Reduction, domain and limits as for `sin`.

### `Binary::tan`, `Binary::tan_ctx`, `Binary::try_tan_ctx`

The tangent of an argument in radians.

```mbti
pub fn Binary::tan(Self) -> Self
pub fn Binary::tan_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn Binary::try_tan_ctx(Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
```

$\tan(\pm 0) = \pm 0$ exactly. Reduction, domain and limits as for `sin`. No
binary argument is an odd multiple of $\pi/2$, so there is no pole; an
enclosure of the cosine that contains zero is refined like any other.

### `Binary::sinpi`, `Binary::sinpi_ctx`, `Binary::try_sinpi_ctx`

$\sin(\pi x)$.

```mbti
pub fn Binary::sinpi(Self) -> Self
pub fn Binary::sinpi_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn Binary::try_sinpi_ctx(Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
```

The period is reduced exactly on the binary representation, so huge
arguments cost nothing extra. For integral $n$, $\operatorname{sinpi}(n)$ is
$\pm 0$ with the sign of $n$; at $n + \frac12$ it is $\pm 1$. An infinite
argument is a `domain_error`. By Niven's theorem these are the only dyadic
arguments with a dyadic result.

### `Binary::cospi`, `Binary::cospi_ctx`, `Binary::try_cospi_ctx`

$\cos(\pi x)$.

```mbti
pub fn Binary::cospi(Self) -> Self
pub fn Binary::cospi_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn Binary::try_cospi_ctx(Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
```

$\operatorname{cospi}(n) = (-1)^n$ for integral $n$ and
$\operatorname{cospi}(n + \frac12) = +0$. Reduction and domain as for
`sinpi`.

### `Binary::tanpi`, `Binary::tanpi_ctx`, `Binary::try_tanpi_ctx`

$\tan(\pi x)$.

```mbti
pub fn Binary::tanpi(Self) -> Self
pub fn Binary::tanpi_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn Binary::try_tanpi_ctx(Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
```

For integral $n$, $\operatorname{tanpi}(n)$ is a zero with the sign of
$\operatorname{sinpi}(n) / \operatorname{cospi}(n)$: $-0$ for positive odd and
negative even $n$ (including $-0$), $+0$ otherwise, so `tanpi(1)` is $-0$
and `tanpi(-1)` is $+0$. $\operatorname{tanpi}(n + \frac12)$ is $+\infty$ for
even $n$ and $-\infty$ for odd $n$, with `division_by_zero`;
$\operatorname{tanpi}(n \pm \frac14) = \pm 1$ exactly. Reduction and domain
as for `sinpi`.

### `Binary::asin`, `Binary::asin_ctx`, `Binary::try_asin_ctx`

The arcsine, with values in $[-\pi/2, \pi/2]$.

```mbti
pub fn Binary::asin(Self) -> Self
pub fn Binary::asin_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn Binary::try_asin_ctx(Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
```

The domain is $[-1, 1]$; a finite argument outside it and both infinities are
a `domain_error`. $\operatorname{asin}(\pm 0) = \pm 0$ and
$\operatorname{asin}(\pm 1) = \pm\pi/2$ correctly rounded.

### `Binary::acos`, `Binary::acos_ctx`, `Binary::try_acos_ctx`

The arccosine, with values in $[0, \pi]$.

```mbti
pub fn Binary::acos(Self) -> Self
pub fn Binary::acos_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn Binary::try_acos_ctx(Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
```

The domain is $[-1, 1]$; a finite argument outside it and both infinities are
a `domain_error`, and a NaN propagates as for `asin`. On $[-1, 1]$ the result
is $\pi/2 - \operatorname{asin}(x)$ evaluated as one enclosure;
$\operatorname{acos}(1) = +0$ exactly and $\operatorname{acos}(-1) = \pi$
correctly rounded.

### `Binary::atan`, `Binary::atan_ctx`, `Binary::try_atan_ctx`

The arctangent, with values in $[-\pi/2, \pi/2]$.

```mbti
pub fn Binary::atan(Self) -> Self
pub fn Binary::atan_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn Binary::try_atan_ctx(Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
```

Defined on all of $\mathbb{R}$: $\operatorname{atan}(\pm 0) = \pm 0$ and
$\operatorname{atan}(\pm\infty) = \pm\pi/2$ correctly rounded.

### `Binary::atan2`, `Binary::atan2_ctx`, `Binary::try_atan2_ctx`

The angle of the point $(x, y)$ for `y.atan2(x)`, in $[-\pi, \pi]$.

```mbti
pub fn Binary::atan2(Self, Self) -> Self
pub fn Binary::atan2_ctx(Self, Self, BinaryContext) -> (Self, BinaryFlags)
pub fn Binary::try_atan2_ctx(Self, Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
```

The receiver is the ordinate $y$. The special cases follow IEEE 754-2019
§9.2.1; $x \ge +0$ below means $+0$ or a positive $x$, $x \le -0$ means $-0$
or a negative $x$, infinities included:

| $y$ | $x$ | result |
| --- | --- | --- |
| $\pm 0$ | $x \ge +0$ | $\pm 0$ (exact) |
| $\pm 0$ | $x \le -0$ | $\pm\pi$ |
| $\pm\infty$ | $+\infty$ | $\pm\pi/4$ |
| $\pm\infty$ | $-\infty$ | $\pm 3\pi/4$ |
| $\pm\infty$ | finite | $\pm\pi/2$ |
| finite $y \ne 0$ | $\pm 0$ | $\pm\pi/2$ (sign of $y$) |
| finite $y \ne 0$ | $+\infty$ | $\pm 0$ (sign of $y$, exact) |
| finite $y \ne 0$ | $-\infty$ | $\pm\pi$ (sign of $y$) |

A NaN operand propagates. Multiples of $\pi$ are correctly rounded and
`inexact`. So $\operatorname{atan2}(-0, -0) = -\pi$ and
$\operatorname{atan2}(-0, +0) = -0$.

### `Binary::asinpi`, `Binary::asinpi_ctx`, `Binary::try_asinpi_ctx`

$\operatorname{asin}(x)/\pi$, the angle in half-revolutions (`asinPi` of IEEE 754-2019 §9.2).

```mbti
pub fn Binary::asinpi(Self) -> Self
pub fn Binary::asinpi_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn Binary::try_asinpi_ctx(Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
```

The domain is $[-1, 1]$ (Table 9.1): $|x| > 1$ and $\pm\infty$ are a
`domain_error` (a quiet NaN with `invalid_operation` from `asinpi_ctx`).
$\operatorname{asinPi}(\pm 0) = \pm 0$ with no exception, and
$\operatorname{asinPi}(\pm 1) = \pm 1/2$ exactly. $\operatorname{asinPi}(\pm 1/2)
= \pm 1/6$ is rational but not dyadic, so it is rounded and `inexact` like every
other argument (by Niven's theorem these are the only rational values).
For a tiny $x$ the result is $x/\pi$ up to a relative error of order $x^2$ and
is rounded from a certified enclosure whatever the exponent range, down to the
implementation subnormal limit.

### `Binary::acospi`, `Binary::acospi_ctx`, `Binary::try_acospi_ctx`

$\operatorname{acos}(x)/\pi$.

```mbti
pub fn Binary::acospi(Self) -> Self
pub fn Binary::acospi_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn Binary::try_acospi_ctx(Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
```

The domain is $[-1, 1]$ as for `asinpi`. $\operatorname{acosPi}(1) = +0$,
$\operatorname{acosPi}(-1) = 1$ and $\operatorname{acosPi}(\pm 0) = 1/2$,
exact and without exception (§9.2.1). For a tiny $|x|$ the result is $1/2 \mp
\delta$ with $0 < \delta < |x|/2$, so it clusters at the representable $1/2$:
when $|x| < 2^{-(p + 4)}$ the rounding direction alone decides between $1/2$ and
its neighbour on that side (below for $x > 0$, above for $x < 0$), before the
main loop, and the result is always `inexact`.

### `Binary::atanpi`, `Binary::atanpi_ctx`, `Binary::try_atanpi_ctx`

$\operatorname{atan}(x)/\pi$.

```mbti
pub fn Binary::atanpi(Self) -> Self
pub fn Binary::atanpi_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn Binary::try_atanpi_ctx(Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
```

Defined on all of $\mathbb{R}$. $\operatorname{atanPi}(\pm 0) = \pm 0$ with no
exception, $\operatorname{atanPi}(\pm\infty) = \pm 1/2$ with no exception (§9.2.1)
and $\operatorname{atanPi}(\pm 1) = \pm 1/4$ exactly. For $|x| \ge 2^{p + 8}$ the
result is $\pm(1/2 - \delta)$ with $0 < \delta < 2^{-t}$ for $2^t \le |x|$, so
the rounding direction alone decides between $\pm 1/2$ and its neighbour inside,
without forming a value that close to $1/2$. A tiny $x$ gives $x/\pi$ rounded
from a certified enclosure (underflow with the flags of §7.5 and §7.6).

### `Binary::atan2pi`, `Binary::atan2pi_ctx`, `Binary::try_atan2pi_ctx`

$\operatorname{atan2}(y, x)/\pi$ for `y.atan2pi(x)`, in $[-1, 1]$.

```mbti
pub fn Binary::atan2pi(Self, Self) -> Self
pub fn Binary::atan2pi_ctx(Self, Self, BinaryContext) -> (Self, BinaryFlags)
pub fn Binary::try_atan2pi_ctx(Self, Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
```

The receiver is the ordinate $y$. Every special case of §9.2.1 is an exact
constant that signals no exception:

| $y$ | $x$ | result |
| --- | --- | --- |
| $\pm 0$ | $x \ge +0$ | $\pm 0$ |
| $\pm 0$ | $x \le -0$ | $\pm 1$ |
| $\pm\infty$ | $+\infty$ | $\pm 1/4$ |
| $\pm\infty$ | $-\infty$ | $\pm 3/4$ |
| $\pm\infty$ | finite | $\pm 1/2$ |
| finite $y \ne 0$ | $\pm 0$ | $\pm 1/2$ (sign of $y$) |
| finite $y \ne 0$ | $+\infty$ | $\pm 0$ (sign of $y$) |
| finite $y \ne 0$ | $-\infty$ | $\pm 1$ (sign of $y$) |

For finite nonzero operands $\operatorname{atan2Pi}(y, x)$ is
$\operatorname{atan}(|y/x|)/\pi$ for $x > 0$ and $1 - \operatorname{atan}(|y/x|)/\pi$
for $x < 0$, with the sign of $y$. $|y| = |x|$ gives the exact $\pm 1/4$ or
$\pm 3/4$. With $D$ the difference of the leading-bit exponents of $y$ and $x$
(so $2^{D-1} < |y/x| < 2^{D+1}$), an extreme ratio is decided from the anchors
before the main loop, from $|D| \ge p + 8$: $D \ge p + 8$ gives $1/2 - \delta$
($1/2 + \delta$ for $x < 0$) with $0 < \delta < 2^{-D}$, and $D \le -(p + 8)$
with $x < 0$ gives $1 - \delta$ with $0 < \delta < 2^{D}$, each rounded by
direction alone. With $x > 0$ and a tiny ratio the result is $\approx t/\pi$;
when $D$ is below a quarter of the smallest subnormal ($D \le e_{\min} - p - 1$)
it is the tiny nonzero result of the direction with `underflow` and `inexact`.
The ratio $y/x$ itself is never formed outside the range where it is
representable, so operands at the two ends of the exponent range are handled.

### `Binary::sinh`, `Binary::sinh_ctx`, `Binary::try_sinh_ctx`

The hyperbolic sine.

```mbti
pub fn Binary::sinh(Self) -> Self
pub fn Binary::sinh_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn Binary::try_sinh_ctx(Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
```

$\sinh(\pm 0) = \pm 0$ and $\sinh(\pm\infty) = \pm\infty$. Certain overflow
is decided before the loop from $|\sinh x| \ge e^{|x|}/4$.

### `Binary::cosh`, `Binary::cosh_ctx`, `Binary::try_cosh_ctx`

The hyperbolic cosine.

```mbti
pub fn Binary::cosh(Self) -> Self
pub fn Binary::cosh_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn Binary::try_cosh_ctx(Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
```

$\cosh(\pm 0) = 1$ and $\cosh(\pm\infty) = +\infty$; certain overflow is
decided as for `sinh`.

### `Binary::tanh`, `Binary::tanh_ctx`, `Binary::try_tanh_ctx`

The hyperbolic tangent.

```mbti
pub fn Binary::tanh(Self) -> Self
pub fn Binary::tanh_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn Binary::try_tanh_ctx(Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
```

$\tanh(\pm 0) = \pm 0$ and $\tanh(\pm\infty) = \pm 1$ exactly.

### `Binary::asinh`, `Binary::asinh_ctx`, `Binary::try_asinh_ctx`

The inverse hyperbolic sine.

```mbti
pub fn Binary::asinh(Self) -> Self
pub fn Binary::asinh_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn Binary::try_asinh_ctx(Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
```

Defined on all of $\mathbb{R}$; $\operatorname{asinh}(\pm 0) = \pm 0$ and
$\operatorname{asinh}(\pm\infty) = \pm\infty$.

### `Binary::acosh`, `Binary::acosh_ctx`, `Binary::try_acosh_ctx`

The inverse hyperbolic cosine.

```mbti
pub fn Binary::acosh(Self) -> Self
pub fn Binary::acosh_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn Binary::try_acosh_ctx(Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
```

The domain is $x \ge 1$; any smaller argument, $-\infty$ included, is a
`domain_error`. $\operatorname{acosh}(1) = +0$ and
$\operatorname{acosh}(+\infty) = +\infty$.

### `Binary::atanh`, `Binary::atanh_ctx`, `Binary::try_atanh_ctx`

The inverse hyperbolic tangent.

```mbti
pub fn Binary::atanh(Self) -> Self
pub fn Binary::atanh_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn Binary::try_atanh_ctx(Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
```

The domain is $|x| \le 1$; outside it, infinities included, the result is a
`domain_error`. $\operatorname{atanh}(\pm 0) = \pm 0$ and
$\operatorname{atanh}(\pm 1) = \pm\infty$ with `division_by_zero`.

```moonbit
///|
test "elementary functions are correctly rounded" {
  let ctx = @binary.BinaryContext::binary64()
  let one = @binary.Binary::one()
  inspect(one.exp_ctx(ctx).0.to_shortest_string(), content="2.718281828459045")
  inspect(@binary.Binary::from_int(8).log2(), content="3p0")
  let (big, flags) = @binary.Binary::from_int(1000).exp_ctx(ctx)
  inspect("\{big} \{flags.overflow()}", content="inf true")
  // a domain case is a value in the try_ form too: a NaN with invalid_operation
  match @binary.Binary::from_int(-1).try_ln_ctx(ctx) {
    Ok((value, flags)) => inspect("\{value} \{flags.invalid_operation()}", content="nan true")
    Err(_) => fail("a domain case is not an Err")
  }
  let (nan, nan_flags) = @binary.Binary::from_int(-1).ln_ctx(ctx)
  inspect("\{nan} \{nan_flags.invalid_operation()}", content="nan true")
  let (root, root_flags) = @binary.Binary::from_int(-8).rootn_ctx(3, ctx)
  inspect("\{root} \{root_flags.inexact()}", content="-1p1 false")
  let (pole, pole_flags) = @binary.Binary::from_string("0.5")
    .unwrap()
    .tanpi_ctx(ctx)
  inspect("\{pole} \{pole_flags.division_by_zero()}", content="inf true")
  let rz = @binary.BinaryContext::binary64(
    rounding=@binary.BinaryRoundingMode::RoundTowardZero,
  )
  let three_quarters = @binary.Binary::from_string("0.75").unwrap()
  let (eight, eight_flags) = @binary.Binary::from_int(16).pow_ctx(
    three_quarters, rz,
  )
  inspect("\{eight} \{eight_flags.inexact()}", content="1p3 false")
  let (half, half_flags) = @binary.Binary::from_int(8).rootn_ctx(-3, rz)
  inspect("\{half} \{half_flags.inexact()}", content="1p-1 false")
  inspect(@binary.Binary::from_int(1).tanpi(), content="-0")
  let negative_zero = @binary.Binary::negative_zero()
  inspect(negative_zero.atan2(negative_zero), content="-884279719003555p-48")
  let tiny = @binary.Binary::make(@binary.BinCoeff::one(), -6000, 53)
  inspect(tiny.sin(), content="1p-6000")
}
```

## Trait implementations

### `Binary::equal`, `Binary::not_equal`

Structural equality, the derived `Eq`.

```mbti
pub fn Binary::equal(Self, Self) -> Bool
pub fn Binary::not_equal(Self, Self) -> Bool
```

See [`Binary`](#binary): this compares representations, not numbers, so
`==` distinguishes $\pm 0$ and precisions and identifies equal NaNs.

### `Binary::op_lt`, `Binary::op_le`, `Binary::op_gt`, `Binary::op_ge`

The `Compare` methods behind `<`, `<=`, `>` and `>=`.

```mbti
pub fn Binary::op_lt(Self, Self) -> Bool
pub fn Binary::op_le(Self, Self) -> Bool
pub fn Binary::op_gt(Self, Self) -> Bool
pub fn Binary::op_ge(Self, Self) -> Bool
```

They use [`compare`](#binarycompare), so NaN is greater than every number:
`nan > x` is `true`. Use the [IEEE predicates](#binarycompare_quiet_equal-binarycompare_quiet_less-binarycompare_quiet_less_equal-binarycompare_quiet_unordered-binarycompare_signaling_equal-binarycompare_signaling_less-binarycompare_signaling_less_equal)
when NaN must be unordered.

### `Binary::output`, `Binary::to_repr`

The `Show` and `Debug` methods.

```mbti
pub fn Binary::output(Self, &Logger) -> Unit
pub fn Binary::to_repr(Self) -> @debug.Repr
```

`output` writes the exact `c p e` form of [`to_string`](#binaryto_string).
`to_repr` (used by `debug_inspect`) shows every private field.

### `@def.Floating`

The shared floating-point vocabulary of `floating`.

```mbti
pub impl @def.Floating for Binary
```

`classify`, `sign`, `precision`, `with_precision` and `normalized` are the
inherent methods above. Generic code uses `@def.is_finite`, `@def.is_nan`,
`@def.is_infinite` and `@def.is_zero`.

### `Binary::sqrt_checked`, `Binary::pow_nat_checked`, `Binary::pow_int_checked`

`@lf_arith` traits whose methods return `Result`.

```mbti
pub impl @arithmetic.SqrtChecked for Binary
pub impl @arithmetic.DivChecked for Binary
pub impl @arithmetic.CompareChecked for Binary
pub impl @arithmetic.PowNatChecked for Binary
pub impl @arithmetic.PowIntChecked for Binary
pub fn Binary::sqrt_checked(Self, @arithmetic.ArithmeticContext) -> Result[Self, @arithmetic.ArithmeticError]
pub fn Binary::pow_nat_checked(Self, UInt, @arithmetic.ArithmeticContext) -> Result[Self, @arithmetic.ArithmeticError]
pub fn Binary::pow_int_checked(Self, Int, @arithmetic.ArithmeticContext) -> Result[Self, @arithmetic.ArithmeticError]
```

Each converts the `ArithmeticContext` with
`BinaryContext::from_arithmetic_context` (an `Err` for `AwayFromZero`, a range
that is not of the IEEE 754-2019 3.3 shape or a precision above
`binary_precision_max`) and runs the contextual operation. The invalid flag
becomes a `domain_error` and the division-by-zero flag a `division_by_zero`
error; the other flags are dropped, so a NaN, an infinity, an overflow or an
underflow is the IEEE 754-2019 default result in `Ok`, as for the `Double`
instances of Luna-Flow/arithmetic. `sqrt_checked` is a `domain_error` for a
negative nonzero argument (including $-\infty$) and a signaling NaN; a quiet
NaN of either sign is `Ok`. `DivChecked::div_checked` is a `domain_error`
for $0/0$, $\infty/\infty$ and a signaling NaN operand, and a
`division_by_zero` error for a finite non-zero dividend over a signed zero;
NaN$/0$ and $\infty/0$ are `Ok`. `pow_int_checked` is a `division_by_zero`
error for a zero base with a negative exponent, and both powers are a
`domain_error` for a signaling NaN base, zero exponent included. There is no
inherent `div_checked`: the trait form takes the context, and `BinaryChecked::div`
is the chained form at the larger precision of the operands.
`CompareChecked::compare_checked` is the inherent
[`compare_checked`](#binarycompare_checked).

### `Binary::add_contextual`, `Binary::sub_contextual`, `Binary::mul_contextual`, `Binary::div_contextual`, `Binary::abs_contextual`, `Binary::sqrt_contextual`, `Binary::exp_contextual`

`@lf_arith` traits that return an `ArithmeticOutcome` with diagnostics.

```mbti
pub impl @arithmetic.AddContextual for Binary
pub impl @arithmetic.SubContextual for Binary
pub impl @arithmetic.MulContextual for Binary
pub impl @arithmetic.DivContextual for Binary
pub impl @arithmetic.AbsContextual for Binary
pub impl @arithmetic.SqrtContextual for Binary
pub impl @arithmetic.ExpContextual for Binary
pub fn Binary::add_contextual(Self, Self, @arithmetic.ArithmeticContext) -> Result[@arithmetic.ArithmeticOutcome[Self], @arithmetic.ArithmeticError]
pub fn Binary::sub_contextual(Self, Self, @arithmetic.ArithmeticContext) -> Result[@arithmetic.ArithmeticOutcome[Self], @arithmetic.ArithmeticError]
pub fn Binary::mul_contextual(Self, Self, @arithmetic.ArithmeticContext) -> Result[@arithmetic.ArithmeticOutcome[Self], @arithmetic.ArithmeticError]
pub fn Binary::div_contextual(Self, Self, @arithmetic.ArithmeticContext) -> Result[@arithmetic.ArithmeticOutcome[Self], @arithmetic.ArithmeticError]
pub fn Binary::abs_contextual(Self, @arithmetic.ArithmeticContext) -> Result[@arithmetic.ArithmeticOutcome[Self], @arithmetic.ArithmeticError]
pub fn Binary::sqrt_contextual(Self, @arithmetic.ArithmeticContext) -> Result[@arithmetic.ArithmeticOutcome[Self], @arithmetic.ArithmeticError]
pub fn Binary::exp_contextual(Self, @arithmetic.ArithmeticContext) -> Result[@arithmetic.ArithmeticOutcome[Self], @arithmetic.ArithmeticError]
```

Each runs the matching `*_ctx` method (for `abs`, `abs` followed by
`apply_ctx`; for `exp`, `try_exp_ctx`) under the converted context. A result
with `division_by_zero` becomes a `division_by_zero` error and one with
`invalid_operation` a `domain_error`, one with `not_computed` a
`certification_failure`; a certification failure of `exp` is returned as is. Otherwise the value is returned with `ArithmeticDiagnostics`
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
pub impl Compare for BinCoeff
pub impl Eq for BinCoeff
pub impl Show for BinCoeff
pub impl @debug.Debug for BinCoeff
```

They agree with [`BinCoeff::compare`](#bincoeffcompare-bincoeffequal).

### `BinCoeff::output`, `BinCoeff::to_repr`

The `Show` and `Debug` methods of `BinCoeff`; `to_repr` is the integer value.

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

Equality compares the fields, so `BinaryContext::new(precision=53)` equals
`BinaryContext::new(precision=53, e_max=binary_implementation_e_max)`: there is
one representation of every context.

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
package "Luna-Flow/floating/binary"

import {
  "Luna-Flow/arithmetic",
  "Luna-Flow/floating/def",
  "Luna-Flow/floating/internal/binary_kernel",
  "moonbitlang/core/debug",
}

// Values
pub let binary_implementation_e_max : Int32

pub let binary_implementation_e_min : Int32

pub let binary_precision_max : Int32

// Errors

// Types and methods
type BinCoeff
pub fn BinCoeff::bit_length(Self) -> Int32
pub fn BinCoeff::compare(Self, Self) -> Int32
pub fn BinCoeff::equal(Self, Self) -> Bool
pub fn BinCoeff::from_bytes_be(BytesView) -> Self
pub fn BinCoeff::from_kernel(@binary_kernel.Coeff) -> Self
pub fn BinCoeff::from_uint64(UInt64) -> Self
pub fn BinCoeff::is_zero(Self) -> Bool
pub fn BinCoeff::not_equal(Self, Self) -> Bool
pub fn BinCoeff::one() -> Self
pub fn BinCoeff::op_ge(Self, Self) -> Bool
pub fn BinCoeff::op_gt(Self, Self) -> Bool
pub fn BinCoeff::op_le(Self, Self) -> Bool
pub fn BinCoeff::op_lt(Self, Self) -> Bool
pub fn BinCoeff::output(Self, &Logger) -> Unit
pub fn BinCoeff::parse(String, radix? : Int32) -> Result[Self, String]
pub fn BinCoeff::to_bytes_be(Self) -> Bytes
pub fn BinCoeff::to_kernel(Self) -> @binary_kernel.Coeff
pub fn BinCoeff::to_radix_string(Self, Int32) -> String
pub fn BinCoeff::to_repr(Self) -> @debug.Repr
pub fn BinCoeff::to_string(Self) -> String
pub fn BinCoeff::to_uint64(Self) -> UInt64?
pub fn BinCoeff::zero() -> Self
pub impl Compare for BinCoeff
pub impl Eq for BinCoeff
pub impl Show for BinCoeff
pub impl @debug.Debug for BinCoeff

#derive(@debug.Debug)
pub struct Binary(@binary_kernel.BinRepr)
pub fn Binary::abs(Self) -> Self
pub fn Binary::abs_contextual(Self, @arithmetic.ArithmeticContext) -> Result[@arithmetic.ArithmeticOutcome[Self], @arithmetic.ArithmeticError]
pub fn Binary::acos(Self) -> Self
pub fn Binary::acos_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn Binary::acosh(Self) -> Self
pub fn Binary::acosh_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn Binary::acospi(Self) -> Self
pub fn Binary::acospi_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn Binary::add(Self, Self) -> Self
pub fn Binary::add_contextual(Self, Self, @arithmetic.ArithmeticContext) -> Result[@arithmetic.ArithmeticOutcome[Self], @arithmetic.ArithmeticError]
pub fn Binary::add_ctx(Self, Self, BinaryContext) -> (Self, BinaryFlags)
pub fn Binary::apply_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn Binary::asin(Self) -> Self
pub fn Binary::asin_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn Binary::asinh(Self) -> Self
pub fn Binary::asinh_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn Binary::asinpi(Self) -> Self
pub fn Binary::asinpi_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn Binary::atan(Self) -> Self
pub fn Binary::atan2(Self, Self) -> Self
pub fn Binary::atan2_ctx(Self, Self, BinaryContext) -> (Self, BinaryFlags)
pub fn Binary::atan2pi(Self, Self) -> Self
pub fn Binary::atan2pi_ctx(Self, Self, BinaryContext) -> (Self, BinaryFlags)
pub fn Binary::atan_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn Binary::atanh(Self) -> Self
pub fn Binary::atanh_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn Binary::atanpi(Self) -> Self
pub fn Binary::atanpi_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn Binary::ceil(Self) -> Self
pub fn Binary::clamp(Self, min~ : Self, max~ : Self) -> Self
pub fn Binary::clamp_checked(Self, min~ : Self, max~ : Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn Binary::class_of(Self, BinaryContext) -> @def.IeeeClass
pub fn Binary::classify(Self) -> @arithmetic.FpClass
pub fn Binary::coefficient(Self) -> BinCoeff
pub fn Binary::compare(Self, Self) -> Int32
pub fn Binary::compare_checked(Self, Self) -> Result[Int32, @arithmetic.ArithmeticError]
pub fn Binary::compare_quiet(Self, Self) -> (@def.PartialOrder, BinaryFlags)
pub fn Binary::compare_quiet_equal(Self, Self) -> (Bool, BinaryFlags)
pub fn Binary::compare_quiet_greater(Self, Self) -> (Bool, BinaryFlags)
pub fn Binary::compare_quiet_greater_equal(Self, Self) -> (Bool, BinaryFlags)
pub fn Binary::compare_quiet_greater_unordered(Self, Self) -> (Bool, BinaryFlags)
pub fn Binary::compare_quiet_less(Self, Self) -> (Bool, BinaryFlags)
pub fn Binary::compare_quiet_less_equal(Self, Self) -> (Bool, BinaryFlags)
pub fn Binary::compare_quiet_less_unordered(Self, Self) -> (Bool, BinaryFlags)
pub fn Binary::compare_quiet_not_equal(Self, Self) -> (Bool, BinaryFlags)
pub fn Binary::compare_quiet_not_greater(Self, Self) -> (Bool, BinaryFlags)
pub fn Binary::compare_quiet_not_less(Self, Self) -> (Bool, BinaryFlags)
pub fn Binary::compare_quiet_ordered(Self, Self) -> (Bool, BinaryFlags)
pub fn Binary::compare_quiet_unordered(Self, Self) -> (Bool, BinaryFlags)
pub fn Binary::compare_signaling(Self, Self) -> (@def.PartialOrder, BinaryFlags)
pub fn Binary::compare_signaling_equal(Self, Self) -> (Bool, BinaryFlags)
pub fn Binary::compare_signaling_greater(Self, Self) -> (Bool, BinaryFlags)
pub fn Binary::compare_signaling_greater_equal(Self, Self) -> (Bool, BinaryFlags)
pub fn Binary::compare_signaling_greater_unordered(Self, Self) -> (Bool, BinaryFlags)
pub fn Binary::compare_signaling_less(Self, Self) -> (Bool, BinaryFlags)
pub fn Binary::compare_signaling_less_equal(Self, Self) -> (Bool, BinaryFlags)
pub fn Binary::compare_signaling_less_unordered(Self, Self) -> (Bool, BinaryFlags)
pub fn Binary::compare_signaling_not_equal(Self, Self) -> (Bool, BinaryFlags)
pub fn Binary::compare_signaling_not_greater(Self, Self) -> (Bool, BinaryFlags)
pub fn Binary::compare_signaling_not_less(Self, Self) -> (Bool, BinaryFlags)
pub fn Binary::compound(Self, Int32) -> Self
pub fn Binary::compound_ctx(Self, Int32, BinaryContext) -> (Self, BinaryFlags)
pub fn Binary::convert_format(Self, BinaryInterchangeFormat, rounding? : BinaryRoundingMode, tininess? : TininessDetection) -> (Self, BinaryFlags)
pub fn Binary::copy_sign(Self, Self) -> Self
pub fn Binary::cos(Self) -> Self
pub fn Binary::cos_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn Binary::cosh(Self) -> Self
pub fn Binary::cosh_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn Binary::cospi(Self) -> Self
pub fn Binary::cospi_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn Binary::div(Self, Self) -> Self
pub fn Binary::div_contextual(Self, Self, @arithmetic.ArithmeticContext) -> Result[@arithmetic.ArithmeticOutcome[Self], @arithmetic.ArithmeticError]
pub fn Binary::div_ctx(Self, Self, BinaryContext) -> (Self, BinaryFlags)
pub fn Binary::equal(Self, Self) -> Bool
pub fn Binary::exp(Self) -> Self
pub fn Binary::exp10(Self) -> Self
pub fn Binary::exp10_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn Binary::exp10m1(Self) -> Self
pub fn Binary::exp10m1_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn Binary::exp2(Self) -> Self
pub fn Binary::exp2_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn Binary::exp2m1(Self) -> Self
pub fn Binary::exp2m1_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn Binary::exp_contextual(Self, @arithmetic.ArithmeticContext) -> Result[@arithmetic.ArithmeticOutcome[Self], @arithmetic.ArithmeticError]
pub fn Binary::exp_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn Binary::expm1(Self) -> Self
pub fn Binary::expm1_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn Binary::exponent2(Self) -> Int32
pub fn Binary::floor(Self) -> Self
pub fn Binary::fma(Self, Self, Self) -> Self
pub fn Binary::fma_ctx(Self, Self, Self, BinaryContext) -> (Self, BinaryFlags)
pub fn Binary::from_coefficient(BinCoeff, precision? : Int32, negative? : Bool) -> Self
pub fn Binary::from_double(Double, precision? : Int32) -> Self
pub fn Binary::from_float(Float, precision? : Int32) -> Self
pub fn Binary::from_hex(String, Int32) -> Result[Self, @arithmetic.ArithmeticError]
pub fn Binary::from_hex_ctx(String, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
pub fn Binary::from_int(Int32, precision? : Int32) -> Self
pub fn Binary::from_string(String, precision? : Int32) -> Result[Self, @arithmetic.ArithmeticError]
pub fn Binary::from_string_ctx(String, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
pub fn Binary::hypot(Self, Self) -> Self
pub fn Binary::hypot_ctx(Self, Self, BinaryContext) -> (Self, BinaryFlags)
pub fn Binary::identical(Self, Self) -> Bool
pub fn Binary::ilogb(Self) -> Int32?
pub fn Binary::inf(negative? : Bool, precision? : Int32) -> Self
pub fn Binary::is_finite(Self) -> Bool
pub fn Binary::is_infinite(Self) -> Bool
pub fn Binary::is_nan(Self) -> Bool
pub fn Binary::is_negative_zero(Self) -> Bool
pub fn Binary::is_normal(Self, BinaryContext) -> Bool
pub fn Binary::is_quiet_nan(Self) -> Bool
pub fn Binary::is_sign_minus(Self) -> Bool
pub fn Binary::is_signaling_nan(Self) -> Bool
pub fn Binary::is_subnormal(Self, BinaryContext) -> Bool
pub fn Binary::is_zero(Self) -> Bool
pub fn Binary::ln(Self) -> Self
pub fn Binary::ln_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn Binary::log10(Self) -> Self
pub fn Binary::log10_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn Binary::log10p1(Self) -> Self
pub fn Binary::log10p1_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn Binary::log1p(Self) -> Self
pub fn Binary::log1p_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn Binary::log2(Self) -> Self
pub fn Binary::log2_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn Binary::log2p1(Self) -> Self
pub fn Binary::log2p1_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn Binary::logb_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn Binary::make(BinCoeff, Int32, Int32, negative? : Bool, mode? : BinaryRoundingMode) -> Self
pub fn Binary::max(Self, Self) -> Self
pub fn Binary::min(Self, Self) -> Self
pub fn Binary::mul(Self, Self) -> Self
pub fn Binary::mul_contextual(Self, Self, @arithmetic.ArithmeticContext) -> Result[@arithmetic.ArithmeticOutcome[Self], @arithmetic.ArithmeticError]
pub fn Binary::mul_ctx(Self, Self, BinaryContext) -> (Self, BinaryFlags)
pub fn Binary::nan(precision? : Int32) -> Self
pub fn Binary::nan_payload(Self) -> BinCoeff
pub fn Binary::neg(Self) -> Self
pub fn Binary::negative_zero(precision? : Int32) -> Self
pub fn Binary::next_down_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn Binary::next_up_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn Binary::normalized(Self) -> Self
pub fn Binary::not_equal(Self, Self) -> Bool
pub fn Binary::one(precision? : Int32) -> Self
pub fn Binary::op_ge(Self, Self) -> Bool
pub fn Binary::op_gt(Self, Self) -> Bool
pub fn Binary::op_le(Self, Self) -> Bool
pub fn Binary::op_lt(Self, Self) -> Bool
pub fn Binary::output(Self, &Logger) -> Unit
pub fn Binary::pow(Self, Self) -> Self
pub fn Binary::pow_ctx(Self, Self, BinaryContext) -> (Self, BinaryFlags)
pub fn Binary::pow_int_checked(Self, Int32, @arithmetic.ArithmeticContext) -> Result[Self, @arithmetic.ArithmeticError]
pub fn Binary::pow_nat_checked(Self, UInt32, @arithmetic.ArithmeticContext) -> Result[Self, @arithmetic.ArithmeticError]
pub fn Binary::pown(Self, Int32) -> Self
pub fn Binary::pown_ctx(Self, Int32, BinaryContext) -> (Self, BinaryFlags)
pub fn Binary::powr(Self, Self) -> Self
pub fn Binary::powr_ctx(Self, Self, BinaryContext) -> (Self, BinaryFlags)
pub fn Binary::precision(Self) -> Int32
pub fn Binary::quiet_nan(payload? : BinCoeff, negative? : Bool, precision? : Int32) -> Self
pub fn Binary::remainder(Self, Self) -> Self
pub fn Binary::remainder_ctx(Self, Self, BinaryContext) -> (Self, BinaryFlags)
pub fn Binary::rootn(Self, Int32) -> Self
pub fn Binary::rootn_ctx(Self, Int32, BinaryContext) -> (Self, BinaryFlags)
pub fn Binary::round(Self) -> Self
pub fn Binary::round_ties_to_even(Self) -> Self
pub fn Binary::rsqrt(Self) -> Self
pub fn Binary::rsqrt_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn Binary::scaleb_ctx(Self, Self, BinaryContext) -> (Self, BinaryFlags)
pub fn Binary::sign(Self) -> @def.Sign
pub fn Binary::signaling_nan(payload? : BinCoeff, negative? : Bool, precision? : Int32) -> Self
pub fn Binary::sin(Self) -> Self
pub fn Binary::sin_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn Binary::sinh(Self) -> Self
pub fn Binary::sinh_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn Binary::sinpi(Self) -> Self
pub fn Binary::sinpi_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn Binary::sqrt(Self) -> Self
pub fn Binary::sqrt_checked(Self, @arithmetic.ArithmeticContext) -> Result[Self, @arithmetic.ArithmeticError]
pub fn Binary::sqrt_contextual(Self, @arithmetic.ArithmeticContext) -> Result[@arithmetic.ArithmeticOutcome[Self], @arithmetic.ArithmeticError]
pub fn Binary::sqrt_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn Binary::sub(Self, Self) -> Self
pub fn Binary::sub_contextual(Self, Self, @arithmetic.ArithmeticContext) -> Result[@arithmetic.ArithmeticOutcome[Self], @arithmetic.ArithmeticError]
pub fn Binary::sub_ctx(Self, Self, BinaryContext) -> (Self, BinaryFlags)
pub fn Binary::tan(Self) -> Self
pub fn Binary::tan_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn Binary::tanh(Self) -> Self
pub fn Binary::tanh_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn Binary::tanpi(Self) -> Self
pub fn Binary::tanpi_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn Binary::to_decimal_string_ctx(Self, Int32, BinaryContext) -> (String, BinaryFlags)
pub fn Binary::to_hex(Self) -> String
pub fn Binary::to_int64_ctx(Self, BinaryContext, exact? : Bool) -> (Int64?, BinaryFlags)
pub fn Binary::to_int_ctx(Self, BinaryContext, exact? : Bool) -> (Int32?, BinaryFlags)
pub fn Binary::to_integral_exact_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn Binary::to_integral_value_ctx(Self, BinaryContext) -> (Self, BinaryFlags)
pub fn Binary::to_interchange(Self, BinaryInterchangeFormat, rounding? : BinaryRoundingMode, tininess? : TininessDetection) -> (BinaryInterchange, BinaryFlags)
pub fn Binary::to_repr(Self) -> @debug.Repr
pub fn Binary::to_shortest_string(Self) -> String
pub fn Binary::to_shortest_string_ctx(Self, BinaryContext) -> (String, BinaryFlags)
pub fn Binary::to_string(Self) -> String
pub fn Binary::to_uint64_ctx(Self, BinaryContext, exact? : Bool) -> (UInt64?, BinaryFlags)
pub fn Binary::to_uint_ctx(Self, BinaryContext, exact? : Bool) -> (UInt32?, BinaryFlags)
pub fn Binary::total_order(Self, Self) -> Bool
pub fn Binary::total_order_compare(Self, Self) -> Int32
pub fn Binary::total_order_mag(Self, Self) -> Bool
pub fn Binary::trunc(Self) -> Self
pub fn Binary::try_acos_ctx(Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
pub fn Binary::try_acosh_ctx(Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
pub fn Binary::try_acospi_ctx(Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
pub fn Binary::try_asin_ctx(Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
pub fn Binary::try_asinh_ctx(Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
pub fn Binary::try_asinpi_ctx(Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
pub fn Binary::try_atan2_ctx(Self, Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
pub fn Binary::try_atan2pi_ctx(Self, Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
pub fn Binary::try_atan_ctx(Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
pub fn Binary::try_atanh_ctx(Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
pub fn Binary::try_atanpi_ctx(Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
pub fn Binary::try_compound_ctx(Self, Int32, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
pub fn Binary::try_cos_ctx(Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
pub fn Binary::try_cosh_ctx(Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
pub fn Binary::try_cospi_ctx(Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
pub fn Binary::try_exp10_ctx(Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
pub fn Binary::try_exp10m1_ctx(Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
pub fn Binary::try_exp2_ctx(Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
pub fn Binary::try_exp2m1_ctx(Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
pub fn Binary::try_exp_ctx(Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
pub fn Binary::try_exp_directed_pair(Self, Int32) -> Result[(Self, Self), @arithmetic.ArithmeticError]
pub fn Binary::try_expm1_ctx(Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
pub fn Binary::try_hypot_ctx(Self, Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
pub fn Binary::try_ln_ctx(Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
pub fn Binary::try_ln_directed_pair(Self, Int32) -> Result[(Self, Self), @arithmetic.ArithmeticError]
pub fn Binary::try_log10_ctx(Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
pub fn Binary::try_log10p1_ctx(Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
pub fn Binary::try_log1p_ctx(Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
pub fn Binary::try_log2_ctx(Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
pub fn Binary::try_log2p1_ctx(Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
pub fn Binary::try_pow_ctx(Self, Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
pub fn Binary::try_powr_ctx(Self, Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
pub fn Binary::try_rootn_ctx(Self, Int32, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
pub fn Binary::try_rsqrt_ctx(Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
pub fn Binary::try_sin_ctx(Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
pub fn Binary::try_sinh_ctx(Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
pub fn Binary::try_sinpi_ctx(Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
pub fn Binary::try_tan_ctx(Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
pub fn Binary::try_tanh_ctx(Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
pub fn Binary::try_tanpi_ctx(Self, BinaryContext) -> Result[(Self, BinaryFlags), @arithmetic.ArithmeticError]
pub fn Binary::ulp(Self) -> Self
pub fn Binary::with_precision(Self, Int32, BinaryRoundingMode) -> Self
pub fn Binary::zero(precision? : Int32) -> Self
pub impl @arithmetic.AbsContextual for Binary
pub impl @arithmetic.AddContextual for Binary
pub impl @arithmetic.CompareChecked for Binary
pub impl @arithmetic.DivChecked for Binary
pub impl @arithmetic.DivContextual for Binary
pub impl @arithmetic.ExpContextual for Binary
pub impl @arithmetic.MulContextual for Binary
pub impl @arithmetic.PowIntChecked for Binary
pub impl @arithmetic.PowNatChecked for Binary
pub impl @arithmetic.SqrtChecked for Binary
pub impl @arithmetic.SqrtContextual for Binary
pub impl @arithmetic.SubContextual for Binary
pub impl @def.Floating for Binary
pub impl Add for Binary
pub impl Compare for Binary
pub impl Div for Binary
pub impl Eq for Binary
pub impl Mul for Binary
pub impl Neg for Binary
pub impl Show for Binary
pub impl Sub for Binary

#derive(Eq, @debug.Debug)
pub struct BinaryContext {
  // private fields
}
pub fn BinaryContext::binary128(rounding? : BinaryRoundingMode, tininess? : TininessDetection) -> Self
pub fn BinaryContext::binary16(rounding? : BinaryRoundingMode, tininess? : TininessDetection) -> Self
pub fn BinaryContext::binary32(rounding? : BinaryRoundingMode, tininess? : TininessDetection) -> Self
pub fn BinaryContext::binary64(rounding? : BinaryRoundingMode, tininess? : TininessDetection) -> Self
pub fn BinaryContext::e_max(Self) -> Int32
pub fn BinaryContext::e_min(Self) -> Int32
pub fn BinaryContext::equal(Self, Self) -> Bool
pub fn BinaryContext::from_arithmetic_context(@arithmetic.ArithmeticContext) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BinaryContext::new(precision? : Int32, e_max? : Int32, rounding? : BinaryRoundingMode, tininess? : TininessDetection) -> Self
pub fn BinaryContext::not_equal(Self, Self) -> Bool
pub fn BinaryContext::precision(Self) -> Int32
pub fn BinaryContext::refinement_limit(Self) -> Int32?
pub fn BinaryContext::rounding(Self) -> BinaryRoundingMode
pub fn BinaryContext::tininess(Self) -> TininessDetection
pub fn BinaryContext::to_repr(Self) -> @debug.Repr
pub fn BinaryContext::try_new(precision? : Int32, e_max? : Int32, rounding? : BinaryRoundingMode, tininess? : TininessDetection) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BinaryContext::with_e_max(Self, Int32) -> Self
pub fn BinaryContext::with_precision(Self, Int32) -> Self
pub fn BinaryContext::with_refinement_limit(Self, Int32?) -> Self
pub fn BinaryContext::with_rounding(Self, BinaryRoundingMode) -> Self
pub fn BinaryContext::with_tininess(Self, TininessDetection) -> Self

#derive(Eq)
pub struct BinaryFlags(FlagBits)
pub fn BinaryFlags::combine(Self, Self) -> Self
pub fn BinaryFlags::division_by_zero(Self) -> Bool
pub fn BinaryFlags::equal(Self, Self) -> Bool
pub fn BinaryFlags::inexact(Self) -> Bool
pub fn BinaryFlags::invalid_operation(Self) -> Bool
pub fn BinaryFlags::new() -> Self
pub fn BinaryFlags::not_computed(Self) -> Bool
pub fn BinaryFlags::not_equal(Self, Self) -> Bool
pub fn BinaryFlags::overflow(Self) -> Bool
pub fn BinaryFlags::to_repr(Self) -> @debug.Repr
pub fn BinaryFlags::underflow(Self) -> Bool
pub impl @debug.Debug for BinaryFlags

#derive(Eq)
pub struct BinaryInterchange {
  // private fields
}
pub fn BinaryInterchange::bits(Self) -> BinCoeff
pub fn BinaryInterchange::equal(Self, Self) -> Bool
pub fn BinaryInterchange::format(Self) -> BinaryInterchangeFormat
pub fn BinaryInterchange::from_binary(Binary, BinaryInterchangeFormat, rounding? : BinaryRoundingMode, tininess? : TininessDetection) -> (Self, BinaryFlags)
pub fn BinaryInterchange::from_bits(BinCoeff, BinaryInterchangeFormat) -> Self
pub fn BinaryInterchange::from_hex(String, BinaryInterchangeFormat) -> Self?
pub fn BinaryInterchange::not_equal(Self, Self) -> Bool
pub fn BinaryInterchange::to_binary(Self) -> Binary
pub fn BinaryInterchange::to_hex(Self) -> String

#derive(Eq, @debug.Debug)
pub(all) enum BinaryInterchangeFormat {
  Binary16
  Binary32
  Binary64
  Binary128
}
pub fn BinaryInterchangeFormat::bias(Self) -> Int32
pub fn BinaryInterchangeFormat::context(Self, rounding? : BinaryRoundingMode, tininess? : TininessDetection) -> BinaryContext
pub fn BinaryInterchangeFormat::e_max(Self) -> Int32
pub fn BinaryInterchangeFormat::e_min(Self) -> Int32
pub fn BinaryInterchangeFormat::equal(Self, Self) -> Bool
pub fn BinaryInterchangeFormat::exponent_field_width(Self) -> Int32
pub fn BinaryInterchangeFormat::not_equal(Self, Self) -> Bool
pub fn BinaryInterchangeFormat::precision(Self) -> Int32
pub fn BinaryInterchangeFormat::storage_width(Self) -> Int32
pub fn BinaryInterchangeFormat::to_repr(Self) -> @debug.Repr
pub fn BinaryInterchangeFormat::trailing_significand_field_width(Self) -> Int32

#derive(Eq, @debug.Debug)
pub(all) enum BinaryRoundingMode {
  RoundTiesToEven
  RoundTiesToAway
  RoundTowardZero
  RoundTowardPositive
  RoundTowardNegative
}
pub fn BinaryRoundingMode::equal(Self, Self) -> Bool
pub fn BinaryRoundingMode::from_arithmetic(@arithmetic.RoundingMode) -> Self?
pub fn BinaryRoundingMode::not_equal(Self, Self) -> Bool
pub fn BinaryRoundingMode::to_arithmetic(Self) -> @arithmetic.RoundingMode?
pub fn BinaryRoundingMode::to_repr(Self) -> @debug.Repr

#derive(Eq)
type FlagBits

#derive(Eq, @debug.Debug)
pub(all) enum TininessDetection {
  BeforeRounding
  AfterRounding
}
pub fn TininessDetection::equal(Self, Self) -> Bool
pub fn TininessDetection::not_equal(Self, Self) -> Bool
pub fn TininessDetection::to_repr(Self) -> @debug.Repr

// Type aliases

// Traits
```
<!-- generated-api-end -->
