# decimal API

## Purpose

`Luna-Flow/floating/decimal` is the IEEE 754-2019 decimal floating-point
package of `floating`. A `Decimal` is an arbitrary-precision decimal value
that keeps its quantum (exponent), its sign of zero and its NaN payload; a
`DecimalContext` is an IEEE 754-2019 format (a precision and an exponent range)
with one rounding-direction attribute; every context operation returns the rounded value together with the
`DecimalFlags` it raised. The package also encodes and decodes the
decimal32/64/128 interchange formats in both DPD and BID, and evaluates
elementary functions with certified rounding.

The [decimal tutorial](../tutorial/decimal.md) walks through typical tasks and
the [decimal design](../design/decimal.md) explains the arithmetic model,
encodings, rounding and certification. The finite evidence for the IEEE claim
is recorded in [decimal conformance](../conformance/decimal.md). Sticky General
Decimal Arithmetic status and traps live in the separate
[`decimal_gda`](decimal_gda.md) package; [`decimal_checked`](decimal_checked.md)
accumulates the flags of a pipeline of `Decimal` operations.

> [!WARNING]
> Exact results of non-integral powers among the
> [elementary functions](#elementary-functions) do not yet meet the contracts
> described below. The note there links the GitHub issue that tracks them and
> the proposed fix.

## Importing

Add the package to your `moon.pkg`:

```moonbit nocheck
import {
  "Luna-Flow/floating/decimal",
}
```

The examples call the package through the alias `@decimal.`. Some of them also
use `@def.` for `Luna-Flow/floating/def` (the shared `RoundingMode` and `Sign`),
`@lf_arith.` for `Luna-Flow/arithmetic`, `@lf_alg.` for
`Luna-Flow/luna-generic` and `@bigint.` for `moonbitlang/core/bigint`; import
those packages too when you copy such an example. Most examples build values
with a local helper `d(s)`, which is `@decimal.Decimal::from_string(s).unwrap()`.

## Notation

Notation used below: a finite value is $(-1)^s \cdot c \cdot 10^{q}$ with sign
$s$, non-negative integer coefficient $c$ and exponent (quantum) $q$; $p$ is the
context precision, $e_{\max}$ and $e_{\min}$ the context exponent limits for the
*adjusted* exponent $q + \operatorname{digits}(c) - 1$, and
$E_{\text{tiny}} = e_{\min} - p + 1$ the smallest exponent of a subnormal.

## Values and representation

### `Decimal`

`Decimal` is an immutable decimal floating-point value.

```mbti
pub struct Decimal {
  // private fields
} derive(@debug.Debug)
```

A `Decimal` is one of: a finite value $(-1)^s c\,10^q$ (including $\pm 0$),
$\pm\infty$, or a quiet or signaling NaN with a sign and a non-negative integer
payload. Every value also carries a working `precision`, used by the plain
operators and by conversions that have no context argument. The fields are
private; use the observers below. Two values with the same mathematical value
but different exponents (for example `1.2` and `1.20`) are different members of
the same *cohort*: they compare equal numerically but are distinguished by
`quantum`, `same_quantum`, `total_order_compare`, formatting and interchange
encoding.

The derived `Debug` implementation is promoted as `Decimal::to_repr`; see
[Trait implementations](#trait-implementations).

### `Decimal::precision`, `coefficient`, `exponent10`, `quantum`

These observers return the stored representation of a value.

```mbti
pub fn Decimal::precision(Self) -> Int
pub fn Decimal::coefficient(Self) -> @bigint.BigInt
pub fn Decimal::exponent10(Self) -> Int
pub fn Decimal::quantum(Self) -> Int
```

`precision` is the working precision stored in the value: the precision of a format a context could have, `1..=999999999` (`decimal_precision_max`). Every constructor that returns a `Decimal` aborts on a precision outside that range, naming the function; the operations that return a `Result` return `Err`.
`coefficient` returns the non-negative coefficient $c$;
for a NaN they return the payload and for an infinity `0`. The sign is never
part of the coefficient: use `is_negative`. `exponent10` and `quantum` both
return the stored exponent $q$; for special values it is `0`.

```moonbit
///|
test "decimal representation observers" {
  let x = @decimal.Decimal::from_string("-12.300").unwrap()
  inspect(x.coefficient(), content="12300")
  inspect(x.quantum(), content="-3")
  inspect(x.is_negative(), content="true")
  inspect(x.precision(), content="34")
}
```

### `Decimal::sign`, `is_negative`

These observers report the sign of a value.

```mbti
pub fn Decimal::sign(Self) -> @def.Sign
pub fn Decimal::is_negative(Self) -> Bool
```

`sign` returns `@def.Sign::Zero` for both zeros and for every NaN, and
`Negative`/`Positive` otherwise. `is_negative` returns the stored sign bit, so it
is `true` for $-0$, for $-\infty$ and for a negative NaN.

### `Decimal::classify`, `class_of`

`classify` returns the coarse class of a value; `class_of` returns the ten-valued
class of IEEE 754-2019 clause 5.7.2 under a context.

```mbti
pub fn Decimal::classify(Self) -> @arithmetic.FpClass
pub fn Decimal::class_of(Self, DecimalContext) -> @def.IeeeClass
```

`classify` returns `Finite`, `Infinity` or `NaN`. `class_of` returns one of the
ten [`IeeeClass`](def.md#ieeeclass) values; the normal/subnormal split uses the
context's $e_{\min}$. It has no text form: `match` on the `IeeeClass` (the
former `class_name` strings were `"sNaN"`, `"NaN"`, `"+Zero"` and so on).

### `Decimal::is_finite`, `is_infinite`, `is_nan`, `is_zero`, `is_negative_zero`, `is_quiet_nan`, `is_signaling_nan`, `is_canonical`, `is_normal`, `is_subnormal`

These predicates test the class of a value.

```mbti
pub fn Decimal::is_finite(Self) -> Bool
pub fn Decimal::is_infinite(Self) -> Bool
pub fn Decimal::is_nan(Self) -> Bool
pub fn Decimal::is_zero(Self) -> Bool
pub fn Decimal::is_negative_zero(Self) -> Bool
pub fn Decimal::is_quiet_nan(Self) -> Bool
pub fn Decimal::is_signaling_nan(Self) -> Bool
pub fn Decimal::is_canonical(Self) -> Bool
pub fn Decimal::is_normal(Self, DecimalContext) -> Bool
pub fn Decimal::is_subnormal(Self, DecimalContext) -> Bool
```

`is_canonical` always returns `true`:
a `Decimal` has no non-canonical form; non-canonical *encodings* are a
property of [`DecimalInterchange`](#decimalinterchange-decimalinterchangeformat-encoding-to_hex). A value is normal
under a context when it is finite, non-zero and its adjusted exponent is at
least $e_{\min}$; it is subnormal when it is finite, non-zero and its adjusted
exponent is below $e_{\min}$. Zeros, infinities and NaNs are neither.

### `Decimal::nan_payload`, `get_payload`, `set_payload`, `set_payload_signaling`

These functions read and replace the payload of a NaN.

```mbti
pub fn Decimal::nan_payload(Self) -> @bigint.BigInt
pub fn Decimal::get_payload(Self) -> @bigint.BigInt
pub fn Decimal::set_payload(Self, @bigint.BigInt) -> Self
pub fn Decimal::set_payload_signaling(Self, @bigint.BigInt) -> Self
```

`nan_payload` returns the payload of a NaN and `0` for every other value.
`get_payload` is IEEE 754-2019 §9.7 getPayload: the payload of a NaN, and `-1`
for any other value. `set_payload` and `set_payload_signaling` are setPayload
and setPayloadSignaling: when the argument is a non-negative integer of at most
`precision - 1` digits (the receiver's `precision`, like the trailing
significand of an interchange NaN) the result is a quiet (respectively
signaling) NaN with that payload and the receiver's sign bit; otherwise it is
`+0` with exponent 0. The result does not depend on whether the receiver is a
NaN.

## Construction and conversion

### `decimal_value_e_max`, `decimal_value_e_tiny`

The limits of a stored finite value.

```mbti
pub let decimal_value_e_max : Int
pub let decimal_value_e_tiny : Int
```

A finite `Decimal` holds only a value with `exponent + digits - 1 <=
decimal_value_e_max` (the largest adjusted exponent, $2\,147\,483\,646$; a
zero has one digit) and `exponent >= decimal_value_e_tiny` (the smallest
exponent, $-2\,147\,483\,645$). They are the `e_max` and the `etiny` of the
private working context of the plain operators, the largest and smallest the
32-bit exponent field allows once `e_max`, `e_min` and `etiny = e_min - p + 1`
have to be representable in it, so that `x + 0 == x`, `x - 0 == x` and
`x * 1 == x` hold for every stored value. The exact constructors (`make`,
`try_make`, `parse`, `from_string`) refuse a value outside the range; the
constructors from integers, floats and binary floats cannot produce one; an
operation that rounds (the plain operators, `with_precision`) overflows to an
infinity or the largest finite value of the rounding direction, or underflows
to the smallest exponent, like a context result. These are not the limits of a
context (`decimal_implementation_e_max`, below): a context is narrower than
what can be stored, and a value outside every context range can still be
stored and is rounded when a context operation reads it.

### `Decimal::make`, `try_make`

`make` builds a finite value from a signed integer coefficient and an exponent,
rounding it to a precision; `try_make` is its `Result` form.

```mbti
pub fn Decimal::make(@bigint.BigInt, Int, Int, mode? : DecimalRoundingMode) -> Self
pub fn Decimal::try_make(@bigint.BigInt, Int, Int, mode? : DecimalRoundingMode) -> Result[Self, @arithmetic.ArithmeticError]
```

`Decimal::make(c, q, p, mode~)` represents $c \cdot 10^{q}$; the sign comes
from `c`. A coefficient of at most `p` digits keeps the exponent `q` (the cohort
member asked for is not reduced: `make(100, 0, 5)` is `100`, `make(0, 5, 5)` is
`0E+5`); a longer one is rounded to exactly `p` digits with `mode` (default
`RoundTiesToEven`) and not reduced (`make(1000000, 0, 3)` is `100E+4`). No
context exponent range applies, but the value must be within the [stored
range](#decimal_value_e_max-decimal_value_e_tiny), checked after the rounding: `make` aborts
naming the exponent and both limits, `try_make` returns the domain error (and an
error for a `p` outside `1..=999999999`).

### `Decimal::zero`, `negative_zero`, `one`, `inf`, `nan`, `quiet_nan`, `signaling_nan`

These constructors build the special and unit values.

```mbti
pub fn Decimal::zero(precision? : Int) -> Self
pub fn Decimal::negative_zero(precision? : Int) -> Self
pub fn Decimal::one(precision? : Int) -> Self
pub fn Decimal::inf(negative? : Bool, precision? : Int) -> Self
pub fn Decimal::nan(precision? : Int) -> Self
pub fn Decimal::quiet_nan(payload? : @bigint.BigInt, negative? : Bool, precision? : Int) -> Self
pub fn Decimal::signaling_nan(payload? : @bigint.BigInt, negative? : Bool, precision? : Int) -> Self
```

The default precision is 34. `zero`, `negative_zero` and `one` have exponent
`0`. `inf(negative=true)` is $-\infty$ and `inf()` is $+\infty$. `nan` is
a positive quiet NaN with payload 0; `quiet_nan` and `signaling_nan` default
to payload 0 and a positive sign. The payload is the trailing significand field
(IEEE 754-2019 3.5.2): a non-negative integer of at most `precision - 1` digits,
otherwise the constructor aborts; a conversion to a narrower format keeps the
low digits of the payload, construction never truncates. The precision must be
within `1..=999999999`.

### `Decimal::from_int`, `from_bigint`

These constructors convert an integer.

```mbti
pub fn Decimal::from_int(Int, precision? : Int) -> Self
pub fn Decimal::from_bigint(@bigint.BigInt, precision? : Int) -> Self
```

Both implement convertFromInt (IEEE 754-2019 §5.4.1, preferred exponent 0)
with the default precision 34: an integer of at most `precision` digits keeps
exponent 0, so `from_int(1000)` is `1000` and not the reduced `1E+3`; a longer
one is rounded half-even to exactly `precision` digits (§5.2), so
`from_int(99999, precision=3)` is `1.00E+5`. Zero is $+0$ with exponent 0.

### `Decimal::from_double`, `from_float`

These constructors convert a binary floating-point number.

```mbti
pub fn Decimal::from_double(Double, precision? : Int) -> Self
pub fn Decimal::from_float(Float, precision? : Int) -> Self
```

Every finite `Double` is a dyadic rational $m \cdot 2^{k}$ and therefore has a
finite decimal expansion $m \cdot 5^{-k} \cdot 10^{k}$ for $k<0$; the
conversion forms that exact expansion and, when it fits in `precision` digits
(default 34), returns it with the exponent closest to the preferred exponent 0
(`from_double(0.5)` is `0.5`, `from_double(100.0)` is `100`). Otherwise it is
rounded half-even to exactly `precision` digits, the least possible exponent
(IEEE 754-2019 §5.2): `from_double(0.1, precision=16)` is `0.1000000000000000`.
Signed zeros and infinities are preserved; every NaN
becomes a quiet NaN with payload 0 and the input's sign. `from_float` widens
to `Double` first, which is exact.

### `Decimal::from_bin_float`, `to_bin_float`

These functions convert between `Decimal` and the binary
[`BinFloat`](bin_float.md).

```mbti
pub fn Decimal::from_bin_float(@bin_float.BinFloat, precision~ : Int, mode? : DecimalRoundingMode) -> Self
pub fn Decimal::to_bin_float(Self, precision~ : Int, mode? : @bin_float.BinaryRoundingMode) -> @bin_float.BinFloat
```

`from_bin_float(x, precision~, mode~)` is exact whenever the decimal expansion of
`x` fits in `precision` decimal digits, with the exponent closest to 0 as for
`from_double`, and is otherwise rounded once to exactly `precision` digits in
`mode` (default `RoundTiesToEven`, the rounding type of the radix of the result).
The precision is required and counts digits; it was the number of bits of `x`
by default, a count of the wrong kind. A binary zero keeps its sign ($-0$
becomes $-0$, as IEEE 754-2019 §5.4.2 and §6.3 require), and a NaN becomes a
quiet NaN with payload 0. `to_bin_float(precision~, mode~)` rounds the exact
decimal value once to a `BinFloat` of `precision` bits with `mode`, one of the
five rounding-direction attributes of IEEE 754-2019 4.3.1 (default
`RoundTiesToEven`). The precision is required and counts bits, from 1 to
`@bin_float.binary_precision_max`; outside that range the call aborts (it was the
number of digits of the decimal by default). Most decimal fractions are not
dyadic, so this direction is usually inexact; converting with `RoundTowardNegative`
and `RoundTowardPositive` gives a binary enclosure of the decimal value. Zeros
keep their sign and NaN payloads are not kept. The same conversions are in
`decimal_gda`, with `GdaRoundingMode` for the decimal result.

### `Decimal::convert_format`, `from_bin_float_ctx`, `to_bin_float_ctx`

These functions are IEEE 754-2019 convertFormat (§5.4.2) with the flags, for
the conversions between decimal formats and between the radices.

```mbti
pub fn Decimal::convert_format(Self, DecimalInterchangeFormat) -> (Self, DecimalFlags)
pub fn Decimal::from_bin_float_ctx(@bin_float.BinFloat, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::to_bin_float_ctx(Self, @bin_float.BinaryContext) -> (@bin_float.BinFloat, @bin_float.BinaryFlags)
```

`convert_format(format)` converts to decimal32, decimal64 or decimal128: the
value is rounded once, to nearest even, to the precision and exponent range of
the format, with the flags of that rounding. The preferred exponent is the
quantum of the source ("For conversions between decimal formats, the preferred
exponent is Q(source)"): a conversion to a wider format is exact and keeps the
cohort member, a narrower one rounds, can overflow or underflow, and folds a
large exponent down.
`from_bin_float_ctx(x, ctx)` rounds the exact value of a binary float once
under the decimal context (precision, exponent range, direction) with the flags
of the rounding: an exact conversion has the preferred exponent 0 (the
exponent closest to 0 that holds the digits: `0.5` is `5E-1`, `96` is `96`), an
inexact one has `precision` digits ("the preferred exponent is the least
possible"). A value beyond the exponent range, or far below it, overflows or
underflows without its digits being formed. An in-range value is converted at
any binary exponent, correctly rounded, at a cost that does not grow with the
exponent; a binary exponent beyond $2^{22}$ is refused with NaN and
`invalid_operation`. `to_bin_float_ctx(ctx)` rounds the exact decimal value once
under a `BinaryContext` (binary16 to binary128, or any precision and range)
and returns the `BinaryFlags` (inexact, overflow, underflow); it is the
conversion of `BinFloat::from_string_ctx`, correctly rounded for any exponent.
A zero keeps its sign in every direction. A signaling NaN gives a quiet NaN
and the invalid operation exception; the sign of a NaN is kept, and so is its
payload when the destination holds it (§6.2.3): `p - 1` digits for the decimal
formats and `p - 2` bits for a binary format, otherwise the low digits or bits.
`from_bin_float` and `to_bin_float` are unchanged.

### The `FromNat` and `FromInteger` implementations

`Decimal` implements the `luna-generic` traits `FromNat` and `FromInteger`, the
canonical maps out of the naturals and the integers. There are no `Decimal::from_natural`
or `Decimal::from_integer` methods: call `Decimal::from_bigint(n)` (exponent 0,
the cohort of the integer) or the trait functions.

The trait functions return `from_bigint(n).normalized()` with precision 34, that
is, with the trailing zeros removed. To convert another Luna-Flow integer type,
pick its representative with `Integral::normalize` first, or use `lift_to`.

## Parsing and formatting

### `Decimal::from_string`

`from_string` converts decimal text to a `Decimal` while keeping its quantum.

```mbti
pub fn Decimal::from_string(String, precision? : Int) -> Result[Self, @arithmetic.ArithmeticError]
```

The accepted syntax is an optional sign, digits with an optional decimal
point, an optional exponent `E`/`e` with optional sign, or one of `Inf`,
`Infinity`, `NaN` and `sNaN` (any letter case) followed for NaNs by optional
decimal payload digits. Conversion rounds once, half-even, to `precision`
(default 34), while preserving the preferred exponent as far as the precision
and representation permit. For example, `"1.2300"` has coefficient 12300
and exponent $-4$; `"1.0001"` at precision 3 rounds to `1.00`, and the exact
`"1.000"` at precision 3 is `1.00` because its four coefficient digits do
not fit. `"10001"` at precision 3 rounds to `1.00E+4`. Invalid text returns
`Err(parse_error)`.

No context exponent range is applied; the limits are those of the
[stored range](#decimal_value_e_max-decimal_value_e_tiny): the exponent of the
value must be at least `decimal_value_e_tiny` ($-2\,147\,483\,645$) and its
adjusted exponent at most `decimal_value_e_max` ($2\,147\,483\,646$), checked
after the rounding to `precision` (a carry included) and for a zero as for any
finite value. A text whose value is outside them is refused, never replaced:
`from_string` returns the domain error, which names the
exponent and both limits (`"1e3000000000"`, `"12e2147483647"`, `"0e-2147483646"`
are refused; `"1249e-2147483646"` at precision 3 is `1.25E-2147483643`, its
exponent after the rounding being inside the range). Read the text with
[`from_string_ctx`](#decimalfrom_string_ctx) when a rounded value (an
infinity, a zero) and the `overflow` and `underflow` flags are wanted.

### `Decimal::from_string_ctx`

`from_string_ctx` converts text under a context and reports conversion flags.

```mbti
pub fn Decimal::from_string_ctx(String, DecimalContext) -> (Self, DecimalFlags)
```

The syntax is the one of `from_string`. The value is rounded to the context
precision (raising `inexact` when non-zero digits are
discarded), checked against the exponent range (overflow, underflow)
and folded down. A NaN payload with more digits than the
format allows (precision $-1$ digits) is a syntax error. Invalid text returns a
quiet NaN with `invalid_operation`.

```moonbit
///|
test "decimal from_string_ctx rounds and flags" {
  let ctx = @decimal.DecimalContext::decimal32()
  let (x, flags) = @decimal.Decimal::from_string_ctx("3.14159265", ctx)
  inspect(x, content="3.141593")
  inspect(flags.inexact(), content="true")
  let (bad, bad_flags) = @decimal.Decimal::from_string_ctx("1..2", ctx)
  inspect(bad.is_nan(), content="true")
  inspect(bad_flags.invalid_operation(), content="true")
}
```

### `Decimal::to_sci_string`, `to_eng_string`

These functions implement the General Decimal Arithmetic `to-scientific-string`
and `to-engineering-string` conversions of a value.

```mbti
pub fn Decimal::to_sci_string(Self) -> String
pub fn Decimal::to_eng_string(Self) -> String
```

Both format the value they are called on; to convert text under a context,
read it with `from_string_ctx` first, which also gives the flags of the
conversion (`Decimal::from_string_ctx("1000000000", ctx).0.to_sci_string()`).
Scientific form writes the coefficient with an exponent `E±n` whenever the
exponent is positive or the adjusted exponent is below $-6$, and plain digits
otherwise; engineering form uses an exponent that is a multiple of three.
Special values are written `Infinity`, `-Infinity`, `NaN`, `sNaN`, with a
payload such as `NaN7`.

Values without a context are formatted by `Decimal::to_string` (the `Show`
implementation), which uses the same scientific rule; see
[`Show` and `Debug`](#show-and-debug-decimalto_string-output-to_repr).

## Contexts

### `DecimalContext`

A `DecimalContext` is an immutable set of arithmetic parameters.

```mbti
pub struct DecimalContext {
  // private fields
} derive(Eq)
```

A context is the IEEE 754-2019 format of a precision $p$ and an exponent range
$[e_{\min}, e_{\max}]$ with $e_{\min} = 1 - e_{\max}$ (§3.3), and one
rounding-direction attribute (`rounding`, a `DecimalRoundingMode`). Every finite
result of a context operation is a member of the format: its exponent $q$
satisfies $e_{\min} \le q + p - 1 \le e_{\max}$, so $q \le e_{\max} - p + 1$
(large exponents are folded down, as the format requires), and tininess is
detected before rounding (§7.5). There is no option for any of this. No
operation reads ambient state: every context operation receives its context as
an argument.

### `decimal_implementation_e_max`, `decimal_implementation_e_min`, `decimal_precision_max`

The limits of the context parameters that `DecimalContext::try_new` accepts.

```mbti
pub let decimal_implementation_e_max : Int
pub let decimal_implementation_e_min : Int
pub let decimal_precision_max : Int
```

They are $999\,999\,999$, $-999\,999\,998$ ($1 - e_{\max}$, the smallest
$e_{\min}$ of a context) and $999\,999\,999$, the decNumber `decContext.h`
limits (`decimal_implementation_e_min` was $-999\,999\,999$ before 0.12).
`try_new` and `new` check `precision` and `e_max` against these constants
(`precision` in `1..=decimal_precision_max`, `e_max` in
`1..=decimal_implementation_e_max`), so the values cannot drift from the
validation. They bound the context only: the certified elementary functions
have their own, lower limit ($e_{\max} \le 999\,999$ and $p \le 999\,999$), which is
documented in [Elementary functions](#elementary-functions).

### `DecimalContext::new`, `try_new`

`new` builds the context of an IEEE 754-2019 decimal format from a precision and
an `e_max` and aborts on an invalid one; `try_new` takes the same parameters and
returns a `Result`.

```mbti
pub fn DecimalContext::new(precision? : Int, e_max? : Int, rounding? : DecimalRoundingMode) -> Self
pub fn DecimalContext::try_new(precision? : Int, e_max? : Int, rounding? : DecimalRoundingMode) -> Result[Self, @arithmetic.ArithmeticError]
```

| Parameter | Default | Meaning |
| --- | --- | --- |
| `precision` | 34 | coefficient digits $p$ |
| `e_max` | $\max(999\,999,\ 1000\,p)$ | the largest exponent $e_{\max}$; $e_{\min}$ is $1 - e_{\max}$ |
| `rounding` | `RoundTiesToEven` | rounding-direction attribute (IEEE 754-2019 §4.3) |

`precision` must be in `1..=999,999,999` and `e_max` in `1..=999,999,999`. The
default of `e_max` follows IEEE 754-2019 §3.7: an extendable format given by its
precision alone needs $e_{\max} \ge 1000\,p$ from 51 digits on, and 999,999 is
the widest range in which every operation of the package runs. `new()` is
therefore the format $(34,\ 999\,999)$, not decimal128: use `decimal128()` for
that. A precision above 999,999 has no default range (1000 $p$ exceeds the
limit): pass `e_max`. `try_new` returns `Err(domain_error)` naming the invalid
field; `new` aborts with a message that names it, like `BinaryContext::new`, so
use `try_new` for parameters that come from outside. NOTE 3 of §3.7 says that
$e_{\max}$ should be at least 2; the library accepts 1, the least value for which
$e_{\min} \le e_{\max}$ (§3.3).

There is one rounding parameter: finite results, infinities and every other
use of the context round by it, and `rounding()` reports exactly the mode that
is applied. The commercial rounding of GDA (`round-half-up`) is
`RoundTiesToAway`; the GDA modes `round-half-down`,
`round-up` and `round-05up` are not attributes of an IEEE 754-2019 decimal
format and exist only in [`decimal_gda`](decimal_gda.md). A context has no
`clamp`, `extended` or `tininess` setting and no unlimited precision (`exact()`
is gone): an IEEE format always has the exponent range of its quantum, the
subset arithmetic of the General Decimal Arithmetic appendix is not an IEEE
format, and exact results are obtained with a precision large enough for the
digits (a context of `digits(a) + digits(b)` digits and an `e_max` of at least
the exponent of the product makes `mul_ctx` exact).

> [!NOTE]
> The certified elementary functions accept contexts with $e_{\max} \le 999\,999$
> and $p \le 999\,999$. The default range of `DecimalContext::new` is the largest
> one inside that limit for $p \le 999$; a context with a larger range (explicit
> `e_max`, or $p \ge 1000$) makes them return NaN with `invalid_operation`.

### `DecimalContext::decimal32`, `decimal64`, `decimal128`

These constructors return the contexts of the IEEE 754-2019 interchange formats
(§3.6).

```mbti
pub fn DecimalContext::decimal32(rounding? : DecimalRoundingMode) -> Self
pub fn DecimalContext::decimal64(rounding? : DecimalRoundingMode) -> Self
pub fn DecimalContext::decimal128(rounding? : DecimalRoundingMode) -> Self
```

| Context | $p$ | $e_{\min}$ | $e_{\max}$ |
| --- | ---: | ---: | ---: |
| `decimal32` | 7 | $-95$ | 96 |
| `decimal64` | 16 | $-383$ | 384 |
| `decimal128` | 34 | $-6143$ | 6144 |

All three use `RoundTiesToEven` by default (pass `rounding~` for another
attribute).

### `DecimalContext::from_arithmetic_context`

`from_arithmetic_context` converts the shared Luna-Flow context.

```mbti
pub fn DecimalContext::from_arithmetic_context(@arithmetic.ArithmeticContext) -> Result[Self, @arithmetic.ArithmeticError]
```

Precision and rounding are copied; `clamp` is ignored (it is a property of every
IEEE format, and the `arithmetic` package's default is `false`). A given `e_max`
is used; a given `e_min` must equal `1 - e_max` or the conversion returns
`Err(domain_error)`; `e_min` alone gives `e_max = 1 - e_min`; neither gives the
default range of `new`. The conversion also returns `Err(domain_error)` for
`AwayFromZero` (no attribute of §4.3) and when the precision or `e_max` is out of
range. GDA 1.70 itself sets no fixed limits; these are the adopted decNumber
`decContext.h` limits.

### `DecimalContext::precision`, `rounding`, `e_min`, `e_max`

These accessors return the fields of a context.

```mbti
pub fn DecimalContext::precision(Self) -> Int
pub fn DecimalContext::rounding(Self) -> DecimalRoundingMode
pub fn DecimalContext::e_min(Self) -> Int
pub fn DecimalContext::e_max(Self) -> Int
```

`e_min` is always `1 - e_max`.

### `DecimalContext::refinement_limit`, `DecimalContext::with_refinement_limit`

Read and set the refinement limit of the certified elementary functions.

```mbti
pub fn DecimalContext::refinement_limit(Self) -> Int32?
pub fn DecimalContext::with_refinement_limit(Self, Int32?) -> Self
```

The certified elementary functions evaluate an enclosure at a growing working
precision until both ends round alike. The limit is the number of evaluations:
`Some(n)` allows `n` (a value below 1 counts as 1), the default is `Some(12)`,
and `None` removes the count limit. When the limit is reached without a
decision, `try_*_ctx` returns the `CertificationFailure` error with the
refinement count, as before, and the plain and `*_ctx` forms return NaN with
`invalid_operation`. With `None` the loop stops when the working precision
passes a cap, the larger of 8,000,000 bits and 256 times the first working
precision. The default changes no result. The field takes part in `==`: two
contexts that differ only in the limit are different.

```moonbit
///|
test "a refinement limit makes a hard-to-round result fail" {
  let context = @decimal.DecimalContext::new(precision=34, e_max=999_999)
  inspect(context.refinement_limit() == Some(12), content="true")
  // exp(5E-34) lies just above the midpoint 1 + 5E-34 at 34 digits.
  let x = @decimal.Decimal::from_string("5E-34", precision=34).unwrap()
  let short = context.with_refinement_limit(Some(1))
  inspect(x.try_exp_ctx(short) is Err(_), content="true")
  let unlimited = context.with_refinement_limit(None)
  inspect(x.try_exp_ctx(unlimited) is Ok(_), content="true")
}
```

### `DecimalContext::with_precision`, `with_e_max`, `with_rounding`

These functions derive a context.

```mbti
pub fn DecimalContext::with_precision(Self, Int) -> Self
pub fn DecimalContext::with_e_max(Self, Int) -> Self
pub fn DecimalContext::with_rounding(Self, DecimalRoundingMode) -> Self
```

`with_precision` replaces the precision and `with_e_max` the exponent range
(`e_min` follows); both abort outside the limits of `new`. `with_rounding`
replaces the rounding-direction attribute.

## Rounding modes

### `DecimalRoundingMode`

`DecimalRoundingMode` lists the five rounding-direction attributes of IEEE
754-2019 §4.3 that a decimal format has, in the spelling of `BinaryRoundingMode`.

```mbti
pub(all) enum DecimalRoundingMode {
  RoundTiesToEven
  RoundTiesToAway
  RoundTowardZero
  RoundTowardPositive
  RoundTowardNegative
}
```

Let $x>0$ lie strictly between two adjacent representable coefficients $c$
and $c+1$ (in units of the last place). `RoundTowardZero` returns $c$;
`RoundTowardPositive` and `RoundTowardNegative` round toward $+\infty$ and
$-\infty$ (so they depend on the sign); `RoundTiesToEven` and
`RoundTiesToAway` return the nearer of the two and break an exact tie toward
the even coefficient and away from zero respectively. The kernels also have
three working modes that no context can select (`HalfDown`, `Up` and
`ZeroFiveUp`: the double-rounding guard digit of division and the directed
bounds of the certified functions); they are internal.

### `DecimalRoundingMode::from_arithmetic`, `to_arithmetic`

These functions map between the attributes and the shared
`@arithmetic.RoundingMode`.

```mbti
pub fn DecimalRoundingMode::from_arithmetic(@arithmetic.RoundingMode) -> Self?
pub fn DecimalRoundingMode::to_arithmetic(Self) -> @arithmetic.RoundingMode?
```

| `@arithmetic.RoundingMode` | `DecimalRoundingMode` |
| --- | --- |
| `ToNearestEven` | `RoundTiesToEven` |
| `TowardZero` | `RoundTowardZero` |
| `TowardPositive` | `RoundTowardPositive` |
| `TowardNegative` | `RoundTowardNegative` |
| `AwayFromZero` | none (`from_arithmetic` returns `None`) |

`to_arithmetic` returns `None` for `RoundTiesToAway`, which the shared enum
does not have. `DecimalContext::from_arithmetic_context` and the `_contextual`
forms return `Err` for `AwayFromZero`.

Tininess is detected before rounding in every context (IEEE 754-2019 §7.5: "For
decimal formats, tininess is detected before rounding"): a non-zero result whose
exact magnitude is below $10^{e_{\min}}$ is tiny, whatever the delivered value. A
tiny result raises `underflow` when it is inexact. There is
no option for the binary-style after-rounding rule.

## Status flags

### `DecimalFlags`

`DecimalFlags` records the conditions raised by one operation.

```mbti
pub struct DecimalFlags {
  // private fields
} derive(Eq)
```

| Field | Raised when |
| --- | --- |
| `inexact` | the result differs from the exact result |
| `underflow` | the result is tiny and inexact |
| `overflow` | the rounded result's adjusted exponent exceeds $e_{\max}$ |
| `division_by_zero` | an exact infinite result from finite operands ($x/0$, $\ln 0$, $\log_2 0$, $\log_{10} 0$, $\operatorname{logb} 0$, $\operatorname{log1p}(-1)$, $\operatorname{log2p1}(-1)$, $\operatorname{log10p1}(-1)$, $\operatorname{rSqrt}(\pm 0)$, $\operatorname{compound}(-1, n<0)$, $\operatorname{powr}(\pm 0, y<0)$) |
| `invalid_operation` | no usefully definable result (signaling NaN, $\infty-\infty$, $0\times\infty$, $0/0$, bad quantize, text that is not a number, a context outside the range an elementary function supports) |
| `not_computed` | a result the library could not compute within a limit of the implementation (a context beyond the elementary kernels, an operand beyond their range, an exact sum with an exponent gap beyond the work bound, a certification that did not conclude): the value is a NaN, `invalid_operation` is not raised, and the `try_` form returns `Err` (certification failure kind) |

These are the five flags of IEEE 754-2019 7.2 to 7.6 and `not_computed`. The General Decimal Arithmetic flags `rounded`, `subnormal`, `clamped`, `lost_digits`, `conversion_syntax`, `division_impossible`, `division_undefined` and `invalid_context` are not part of `decimal`; `decimal_gda` keeps them.

The fields are private. Each flag is read with a method of the same name, such as `flags.inexact()` or `flags.division_by_zero()`; the flags never accumulate implicitly.

### `DecimalFlags::new`, `combine`, `has_error`

These functions create, merge and query flag sets.

```mbti
pub fn DecimalFlags::new() -> Self
pub fn DecimalFlags::combine(Self, Self) -> Self
pub fn DecimalFlags::has_error(Self) -> Bool
```

`new` has every flag clear. `combine` is the field-wise OR, so it is
associative, commutative and idempotent with `new()` as identity. `has_error` is

$$
\text{invalid\_operation} \lor \text{not\_computed} \lor \text{division\_by\_zero},
$$

the conditions for which IEEE 754-2019 delivers no usable number (7.2: invalid
operation is "no usefully definable result"). A failed `from_string_ctx`, which
raises `invalid_operation`, therefore counts as an error. `has_error` does not
include `overflow`, `underflow` or `inexact`: those deliver a usable result (IEEE 754-2019 7.4 to 7.6 define it, as 7.3 does for division by zero). `division_by_zero` is in the set only so that the checked forms of `Luna-Flow/arithmetic` can return `Err` for a division by zero.

```moonbit
///|
test "decimal flags accumulate by combine" {
  let ctx = @decimal.DecimalContext::decimal64()
  let one = @decimal.Decimal::one()
  let three = @decimal.Decimal::from_int(3)
  let (third, f1) = one.div_ctx(three, ctx)
  let (_, f2) = one.div_ctx(@decimal.Decimal::zero(), ctx)
  let all = f1.combine(f2)
  inspect(third, content="0.3333333333333333")
  inspect(all.inexact(), content="true")
  inspect(all.division_by_zero(), content="true")
  inspect(all.has_error(), content="true")
}
```

## Plain operations without a context

The operators and the functions in this group take no context and return no
flags. They are convenient for exact work and for generic code over the
Luna-Flow algebra traits; use the [context arithmetic](#context-arithmetic)
whenever rounding, the exponent range or flags matter.

### `Decimal::add`, `sub`, `mul`, `div`, `neg`

These functions are the arithmetic operators `+`, `-`, `*`, `/` and unary `-`.

```mbti
pub fn Decimal::add(Self, Self) -> Self
pub fn Decimal::sub(Self, Self) -> Self
pub fn Decimal::mul(Self, Self) -> Self
pub fn Decimal::div(Self, Self) -> Self
pub fn Decimal::neg(Self) -> Self
```

Each operator is the matching [context operation](#context-arithmetic) (`add_ctx`,
`sub_ctx`, `mul_ctx`, `div_ctx`, `sqrt_ctx`) in a private working context with the
flags dropped: the format of the larger precision $\max(p_a, p_b)$ of the
operand precision fields, round half even, the storage range of a value
(`decimal_value_e_max`, $2\,147\,483\,646$, and `decimal_value_e_tiny`,
$-2\,147\,483\,645$) and no fold-down. The result precision field is
$\max(p_a, p_b)$.

- An exact result takes the cohort member closest to the preferred exponent
  (IEEE 754-2019 5.4.1: $\min(q_a, q_b)$ for `add` and `sub`, $q_a+q_b$ for
  `mul`, $q_a-q_b$ for `div`): `1.20 + 3.40` is `4.60`, `6.0 / 2` is `3.0`,
  `1.25 * 2.50` is `3.1250`, `1.20 - 1.20` is `0.00`.
- An inexact result has exactly $p$ digits (the least exponent, 5.2) and is not
  reduced: `1 / 3` at seven digits is `0.3333333`, a product of two five-digit
  values is rounded to five digits. The product used to be returned exact, with
  up to $2p$ digits.
- `neg` flips the sign bit of every value, including zeros and NaNs.

Special values follow the context operations: a NaN operand gives a quiet NaN
with the payload of the first NaN; $\infty-\infty$, $0\times\infty$, $0/0$
and $\infty/\infty$ give a NaN; $x/0$ is an infinity with the sign of the
exact quotient (the sign of a zero counts: `1 / -0` is $-\infty$); the sign of
a zero product is the exclusive or of the signs; finite$/\infty$ is a signed
zero at the smallest exponent of the working context. A result beyond the
working range is an overflow of that context, an infinity, and a result below
it rounds half-even to the smallest exponent, possibly to a signed zero
(`1E+2147483646 * 1E+2147483646` is `inf`, `123E-2147483640 * 1E-10` is
`0E-2147483645`). `x + 0 == x`, `x - 0 == x` and `x * 1 == x` hold for every
finite value inside that range, at any exponent: the sum or product is the
value, at the cohort member closest to the preferred exponent that holds it in
$p$ digits.

```moonbit
///|
test "decimal plain operators" {
  let a = @decimal.Decimal::from_string("1.20").unwrap()
  let b = @decimal.Decimal::from_string("3.40").unwrap()
  inspect(a + b, content="4.60")
  inspect(a * b, content="4.0800")
  inspect(a - b, content="-2.20")
  inspect(-a, content="-1.20")
  inspect(@decimal.Decimal::one() / @decimal.Decimal::from_int(8), content="0.125")
}
```

### `Decimal::abs`, `neg`, `copy`, `copy_sign`

These functions change only the sign bit.

```mbti
pub fn Decimal::abs(Self) -> Self
pub fn Decimal::copy(Self) -> Self
pub fn Decimal::copy_sign(Self, Self) -> Self
```

They never round, never raise flags and keep exponent, payload and NaN kind.
`abs` clears the sign, `neg` flips it, `copy_sign`
copies the sign bit of the second operand and `copy` returns its argument.

### `Decimal::normalized`, `with_precision`

These functions change the cohort member or the precision field.

```mbti
pub fn Decimal::normalized(Self) -> Self
pub fn Decimal::with_precision(Self, Int, DecimalRoundingMode) -> Self
```

`normalized` returns the reduced member of the cohort (all trailing zeros
removed, zero with exponent 0), rounding half-even to the value's own
precision if the coefficient is longer. It is the only way to strip trailing zeros: IEEE 754-2019 has no operation for it, so `decimal` no longer has `reduce_ctx` or `trim` (`x.apply_ctx(ctx).0.normalized()` is the former `reduce_ctx`).
`with_precision(p, mode)` rounds a finite value to `p` digits with `mode`,
reduces it and stores `p` as the precision field; special values only get the
new precision field. All of them are flag-free.

### `Decimal::div_checked`, `sqrt`

`div_checked` divides, reporting domain errors as `Result`; `sqrt` takes the square root of the value under its own format.

```mbti
pub fn Decimal::div_checked(Self, Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn Decimal::sqrt(Self) -> Self
```

`div_checked(a, b)` is `div_ctx` under `DecimalContext::new(precision=max(p_a,
p_b))`; it returns `Err(division_by_zero)` for $x/0$ and `Err(domain_error)`
for an invalid division. `sqrt` is `sqrt_ctx` in the working context of the plain
operators (precision $p$) and returns NaN for a negative non-zero
operand (IEEE 754-2019 7.2; `sqrt_checked` reports it as `Err`). Both are
correctly rounded half-even.

## Context arithmetic

Every function in this group takes a `DecimalContext` and returns
`(result, flags)`. The result is the exact result rounded once to the context
precision with the context's decimal rounding mode, then checked against the
exponent range: overflow gives the rounding-mode-dependent result of the
[design page](../design/decimal.md#overflow), a result whose exact magnitude
is below $10^{e_{\min}}$ is rounded directly to the subnormal grid
$10^{E_{\text{tiny}}}$ (a normal result is rounded only to $p$ digits, even
when its exact exponent is below $E_{\text{tiny}}$), and large
exponents are folded down to $e_{\max}-p+1$. When the exact result fits, the exponent is the
*preferred exponent* of the operation, so cohorts carry information. NaN
operands propagate as a quiet NaN with the first NaN's sign and payload (the
payload is cut to its low $p-1$ digits, as in
`from_string_ctx` and the interchange encodings); any
signaling NaN operand raises `invalid_operation`.

Near the underflow threshold the single rounding matters. In decimal32, the
exact product `3.000001E-45 * 1.500001E-45` is $4.5000045000015\cdot
10^{-90}$, a normal number whose exact exponent is below $E_{\text{tiny}} =
-101$; it is rounded once to seven digits, `4.500005E-90`. The quotient
`1 / 1.9999999999998E+101` is $5.0000000000005\cdot 10^{-102}$, which is
subnormal; its guarded quotient is rounded once to the grid $10^{-101}$,
giving `1E-101` with `inexact` and `underflow`.

### `Decimal::add_ctx`, `sub_ctx`, `mul_ctx`, `div_ctx`

These functions are the correctly rounded arithmetic operations.

```mbti
pub fn Decimal::add_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::sub_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::mul_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::div_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
```

Preferred exponents: $\min(q_a,q_b)$ for addition and subtraction, $q_a+q_b$
for multiplication, $q_a-q_b$ for division. An exact quotient is returned in
the member closest to the preferred exponent; an inexact quotient has $p$
digits, except a subnormal one, which ends at $E_{\text{tiny}}$. A zero sum
is $+0$ except under `Floor` (where it is $-0$ if either operand is negative)
or when both operands are $-0$.

Special cases: $\infty-\infty$ and $0\times\infty$, $\infty/\infty$ give NaN
with `invalid_operation`; $0/0$ gives NaN with `invalid_operation`; $x/0$ for finite non-zero $x$ gives a signed infinity
with `division_by_zero`; finite$/\infty$ gives a signed zero with exponent
$E_{\text{tiny}}$.

When one operand of `add_ctx` or `sub_ctx` lies entirely below every
rounding boundary of the sum, the operation does not align it digit by
digit: it is replaced by a sticky unit of the same sign just below those
boundaries, and the sum is rounded once (see the
[design](../design/decimal.md#addition-with-a-far-smaller-addend)). With precision 7,
`1598617.000000000001 - 0.000000000002` is `1598616` under `Down`, and
`6.0000005E-73 + 1E-101` is `6.000001E-73` under `HalfEven`.

```moonbit
///|
test "decimal context results are rounded once" {
  let c32 = @decimal.DecimalContext::decimal32()
  let d = fn(s : String) { @decimal.Decimal::from_string(s).unwrap() }
  inspect(d("3.000001E-45").mul_ctx(d("1.500001E-45"), c32).0, content="4.500005E-90")
  let (q, flags) = d("1").div_ctx(d("1.9999999999998E+101"), c32)
  inspect(q, content="1E-101")
  inspect(flags.underflow(), content="true")
  let down = @decimal.DecimalContext::new(precision=7, rounding=@decimal.DecimalRoundingMode::RoundTowardZero)
  inspect(
    d("1598617.000000000001").add_ctx(d("-0.000000000002"), down).0,
    content="1598616",
  )
}
```

```moonbit
///|
test "decimal context arithmetic keeps preferred exponents" {
  let ctx = @decimal.DecimalContext::decimal64()
  let d = fn(s : String) { @decimal.Decimal::from_string(s).unwrap() }
  inspect(d("1.20").add_ctx(d("3.40"), ctx).0, content="4.60")
  inspect(d("1.25").mul_ctx(d("2.50"), ctx).0, content="3.1250")
  inspect(d("2.400").div_ctx(d("1.2"), ctx).0, content="2.00")
  let (q, flags) = d("2").div_ctx(d("3"), ctx)
  inspect(q, content="0.6666666666666667")
  inspect(flags.inexact(), content="true")
}
```

### `Decimal::fma_ctx`

`fma_ctx` computes $x \cdot y + z$ with a single rounding.

```mbti
pub fn Decimal::fma_ctx(Self, Self, Self, DecimalContext) -> (Self, DecimalFlags)
```

The product is formed exactly and added to `z` exactly; only the sum is
rounded. $0\times\infty + z$ is invalid for a number or infinite `z`; when
`z` is a quiet NaN the result is that NaN **without** `invalid_operation`
(IEEE 754-2019 §7.2 leaves this case to the implementation).
$\infty \cdot y + (-\infty)$ with opposite signs is invalid.

### `Decimal::sqrt_ctx`

`sqrt_ctx` returns the correctly rounded square root.

```mbti
pub fn Decimal::sqrt_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
```

The preferred exponent is $\lfloor q/2 \rfloor$. An exact root is returned in
the member closest to it (`sqrt(0.0400)` is `0.20`); an inexact root has $p$
digits and raises `inexact`. $\sqrt{-0} = -0$; a negative non-zero operand or $-\infty$ gives
NaN with `invalid_operation`; $\sqrt{+\infty}=+\infty$.

### `Decimal::abs_ctx`, `apply_ctx`

These functions round one operand to the context.

```mbti
pub fn Decimal::abs_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::apply_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
```

`apply_ctx` rounds a value to the context (precision, exponent range,
clamping) and quiets a NaN, keeping the sign of zero. It replaces the former
`plus_ctx` (and `minus_ctx` is `neg` followed by `apply_ctx`). `abs_ctx` is $|x|$ rounded to the context; signaling NaNs raise
`invalid_operation`.

### `Decimal::remainder_ctx`

This function computes the IEEE remainder.

```mbti
pub fn Decimal::remainder_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
```

`remainder_ctx(x, y)` is $x - y\cdot n$ where $n$ is
$x/y$ rounded to the nearest integer, ties to even (IEEE 754 *remainder*; the
GDA name of it is `remainder-near`, which `decimal_gda` keeps). The remainder is exact when it fits,
with preferred exponent $\min(q_x, q_y)$, and its sign is that of $x$ when it
is zero. $x \operatorname{rem} 0$ and $\infty \operatorname{rem} y$ are invalid
(so is $0 \operatorname{rem} 0$);
$x \operatorname{rem} \infty = x$.

```moonbit
///|
test "decimal remainders" {
  let ctx = @decimal.DecimalContext::decimal64()
  let d = fn(s : String) { @decimal.Decimal::from_string(s).unwrap() }
  inspect(d("10").remainder_ctx(d("6"), ctx).0, content="-2")
  inspect(d("-7.5").remainder_ctx(d("2"), ctx).0, content="0.5")
}
```

## Quantum and exponent operations

### `Decimal::quantize_ctx`

`quantize_ctx` rounds a value to the exponent of another value.

```mbti
pub fn Decimal::quantize_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
```

`x.quantize_ctx(y, ctx)` returns the value of `x` with exponent $q_y$, rounding
with the context's mode when digits are dropped (raising
`inexact` if they were non-zero). The result is NaN with `invalid_operation`
when the target exponent is outside $[E_{\text{tiny}}, e_{\max}]$, when the
resulting coefficient needs more than $p$ digits, when its adjusted exponent
exceeds $e_{\max}$, or when exactly one operand is infinite. Two infinities
give the infinity of `x`. The quantum never silently changes to another
value of the cohort range: if the result cannot have exponent $q_y$ the
operation fails. The one exception is the fold-down: a target exponent in
$(e_{\max}-p+1,\ e_{\max}]$ is accepted and the result is then folded down
to exponent $e_{\max}-p+1$, like every other result
(`1E+384` quantized to `1E+384` in decimal64 is `1.000000000000000E+384`).

```moonbit
///|
test "decimal quantize_ctx to cents" {
  let ctx = @decimal.DecimalContext::decimal64()
  let d = fn(s : String) { @decimal.Decimal::from_string(s).unwrap() }
  let (cents, flags) = d("12.3456").quantize_ctx(d("0.01"), ctx)
  inspect(cents, content="12.35")
  inspect(flags.inexact(), content="true")
  let small = @decimal.DecimalContext::new(precision=3, e_max=100)
  let (bad, bad_flags) = d("999.9").quantize_ctx(d("0.1"), small)
  inspect(bad.is_nan(), content="true")
  inspect(bad_flags.invalid_operation(), content="true")
}
```

### `Decimal::same_quantum`

`same_quantum` tests whether two values have the same exponent.

```mbti
pub fn Decimal::same_quantum(Self, Self) -> Bool
```

Two finite values have the same quantum when their exponents are equal; two
infinities, and two NaNs, always have the same quantum; any other pair does
not. It never raises flags.

### `Decimal::to_integral_exact_ctx`, `to_integral_value_ctx`

These functions round to an integer.

```mbti
pub fn Decimal::to_integral_exact_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::to_integral_value_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
```

A finite value with exponent $\ge 0$ is already an integer and is returned
unchanged, even when it is longer than $p$ digits (the fold-down of the
format still applies to its exponent). A value with negative exponent is quantized to
exponent 0 with the context's rounding mode, at a working precision of
$\max(p, \text{its digit count})$, so the integral part is never rounded to
$p$ digits: at precision 3, `12345.6` gives `12346`. `to_integral_exact_ctx`
reports `inexact` when non-zero digits are dropped; `to_integral_value_ctx`
returns the same value with `inexact` cleared. Infinities are
returned unchanged; NaNs are quieted.

IEEE 754 §5.9 defines roundToIntegral for an operand in the context's format
(at most $p$ digits), and for such an operand these are its results. An
operand longer than $p$ digits is not a value of the format, so §5.9 does not
cover it and the result is implementation-defined. The behaviour described
above for such operands (a longer integer unchanged, a longer fraction
quantized at $\max(p, \text{its digit count})$ digits) is the package's
chosen, GDA-style behaviour: General Decimal Arithmetic rounds to an integral
value at the operand's own precision.

### `Decimal::to_int_ctx`, `to_int64_ctx`, `to_uint_ctx`, `to_uint64_ctx`

These functions are IEEE 754-2019 convertToInteger (§5.4.1, §5.8): they round a
decimal to a fixed-width integer in the context's rounding direction.

```mbti
pub fn Decimal::to_int_ctx(Self, DecimalContext, exact? : Bool) -> (Int32?, DecimalFlags)
pub fn Decimal::to_int64_ctx(Self, DecimalContext, exact? : Bool) -> (Int64?, DecimalFlags)
pub fn Decimal::to_uint_ctx(Self, DecimalContext, exact? : Bool) -> (UInt32?, DecimalFlags)
pub fn Decimal::to_uint64_ctx(Self, DecimalContext, exact? : Bool) -> (UInt64?, DecimalFlags)
```

They have the shape of the `BinFloat` functions of the same names. The value
is rounded to an integer with the `rounding` of the context: ties to even,
toward zero, toward positive, toward negative and ties to away are the five
directions of §5.8. A NaN (quiet or signaling), an infinity and a value
outside the range of the integer type give `None` with `invalid_operation`;
the result of a negative value that rounds to zero is `0` (also for the
unsigned types), and any other negative value is out of range for them. With
`exact=true` (convertToIntegerExact) `inexact` is raised when rounding changed
the value; without it the flags of a valid conversion are empty. The context's
precision and exponent range play no part: an integer of any number of digits
that fits the type is converted exactly. The conversion never forms the power
of ten of the exponent: `1E+999999` is out of range and `1E-999999` rounds to
zero (or to one unit in an away direction) at once.

### `Decimal::scaleb_ctx`, `logb_ctx`

These functions scale by a power of ten and extract the adjusted exponent.

```mbti
pub fn Decimal::scaleb_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::logb_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
```

`x.scaleb_ctx(n, ctx)` returns $x \cdot 10^{n}$ by adding $n$ to the exponent;
$n$ must be a finite integer with exponent 0 and
$|n| \le 2(e_{\max}+p)$, otherwise the result is NaN with
`invalid_operation` (IEEE 754-2019 5.3.3 defines scaleB for integral counts only
and leaves a non-integral second operand, an infinity included, to the language;
the bound on $|n|$ is the GDA `scaleb` rule, where `BinFloat::scaleb_ctx` clamps a
larger count instead). The scaled value is then rounded once like every other
context result: a coefficient longer than $p$ digits is rounded to $p$ digits
(`12345678901234567890` scaled by 0 in decimal64 is
`1.234567890123457E+19` with `inexact`), a subnormal result is rounded to
$E_{\text{tiny}}$, overflow gives the rounding-mode-dependent result with
`overflow` and `inexact` (in decimal64 with `TowardZero`, `9E+384`
scaled by 1 is `9.999999999999999E+384`), and large exponents are folded
down. A zero keeps its sign and has its exponent clamped into the range:
`0` scaled by 700 in decimal64 is `0E+369`.

```moonbit
///|
test "decimal scaleb rounds like other context results" {
  let c64 = @decimal.DecimalContext::decimal64()
  let d = fn(s : String) { @decimal.Decimal::from_string(s).unwrap() }
  let toward_zero = c64.with_rounding(@decimal.DecimalRoundingMode::RoundTowardZero)
  inspect(d("9E+384").scaleb_ctx(d("1"), toward_zero).0, content="9.999999999999999E+384")
  inspect(d("9E+384").scaleb_ctx(d("1"), c64).0, content="inf")
  let (zero, flags) = d("0").scaleb_ctx(d("700"), c64)
  inspect(zero, content="0E+369")
  inspect(flags.inexact(), content="false")
  inspect(d("12345678901234567890").scaleb_ctx(d("0"), c64).0, content="1.234567890123457E+19")
}
```

`logb_ctx(x)` returns the adjusted exponent $\lfloor\log_{10}|x|\rfloor$ as an
integer `Decimal`; $\operatorname{logb}(\pm 0) = -\infty$ with
`division_by_zero` and $\operatorname{logb}(\pm\infty) = +\infty$.

## Adjacent values

### `Decimal::next_up_ctx`, `next_down_ctx`, `next_toward_ctx`

These functions return the neighbouring representable values.

```mbti
pub fn Decimal::next_up_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::next_down_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::next_toward_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
```

`next_up_ctx` is the smallest representable value greater than `x` in the
context and `next_down_ctx` the largest smaller one, including subnormals down to
$10^{E_{\text{tiny}}}$ and the largest finite value
$(10^{p}-1)\,10^{e_{\max}-p+1}$; `next_up_ctx(-∞)` is the most negative finite
value. They raise no flags for finite results. `next_toward_ctx(x, y)` moves `x`
one step toward `y`; when $x = y$ it returns `x` with the sign of `y` for
zeros. A step of `next_toward_ctx` that ends in an infinity raises `overflow`
and `inexact`; one that ends subnormal or zero raises `underflow`
and `inexact`.

```moonbit
///|
test "decimal neighbours of one" {
  let ctx = @decimal.DecimalContext::decimal64()
  let one = @decimal.Decimal::one()
  inspect(one.next_up_ctx(ctx).0, content="1.000000000000001")
  inspect(one.next_down_ctx(ctx).0, content="0.9999999999999999")
}
```

## Comparison and ordering

### `Decimal::compare`

`compare` is the numeric three-way comparison used by `Compare`, `==` and the
comparison operators.

```mbti
pub fn Decimal::compare(Self, Self) -> Int
```

`compare` returns $-1$, 0 or 1 by numeric value, with $-0 = +0$ and all
members of a cohort equal. NaN has no numeric order, so that `Compare` stays a
total preorder (sorting never aborts) every NaN compares equal to every other
NaN and greater than every non-NaN. `equal` (`==`) agrees with `compare`:
NaN `==` NaN is `true`. This is *not* IEEE equality; use
[`compare_checked`](#decimalcompare_checked), `compare_quiet` or the
predicates when NaN must be unordered. The operator methods are listed under
[trait implementations](#eq-and-compare-decimalequal-not_equal-op_lt-op_le-op_gt-op_ge).

```moonbit
///|
test "decimal numeric order is a total preorder" {
  let d = fn(s : String) { @decimal.Decimal::from_string(s).unwrap() }
  inspect(d("1.0") == d("1.00"), content="true")
  inspect(d("-0").compare(d("0")), content="0")
  inspect(@decimal.Decimal::nan().compare(d("1E+999")), content="1")
  let sorted = [d("2"), @decimal.Decimal::nan(), d("-1")]
  sorted.sort()
  inspect(sorted.map(fn(x) { x.to_string() }).join(" "), content="-1 2 nan")
}
```

### `Decimal::compare_checked`

`compare_checked` is the IEEE numeric comparison with NaN as an error.

```mbti
pub fn Decimal::compare_checked(Self, Self) -> Result[Int, @arithmetic.ArithmeticError]
```

It returns `Ok(compare(x, y))` when neither operand is a NaN and
`Err(unordered_comparison)` otherwise. It is the `CompareChecked`
implementation.

### `Decimal::compare_quiet`, `compare_signaling`

IEEE 754-2019 5.11 comparison as a four-valued relation with flags.

```mbti
pub fn Decimal::compare_quiet(Self, Self) -> (@def.PartialOrder, DecimalFlags)
pub fn Decimal::compare_signaling(Self, Self) -> (@def.PartialOrder, DecimalFlags)
```

The relation is `Less`, `Equal`, `Greater` or `Unordered` (some operand is a
NaN), with $-0 = +0$ and all members of a cohort equal. The quiet form raises
`invalid_operation` only for a signaling NaN; the signaling form raises it for
every unordered comparison. These are the functions of `BinFloat`; they replace
`compare_ctx` and `compare_signal_ctx`, which returned the `Decimal` $-1$, 0, 1
or a NaN, a General Decimal Arithmetic result and not an IEEE one.

### `Decimal::compare_quiet_equal` and the other comparison predicates

The predicates of IEEE 754-2019 Tables 5.1 and 5.2 that `BinFloat` has.

```mbti
pub fn Decimal::compare_quiet_equal(Self, Self) -> (Bool, DecimalFlags)
pub fn Decimal::compare_quiet_less(Self, Self) -> (Bool, DecimalFlags)
pub fn Decimal::compare_quiet_less_equal(Self, Self) -> (Bool, DecimalFlags)
pub fn Decimal::compare_quiet_unordered(Self, Self) -> (Bool, DecimalFlags)
pub fn Decimal::compare_signaling_equal(Self, Self) -> (Bool, DecimalFlags)
pub fn Decimal::compare_signaling_less(Self, Self) -> (Bool, DecimalFlags)
pub fn Decimal::compare_signaling_less_equal(Self, Self) -> (Bool, DecimalFlags)
```

Each is defined from `compare_quiet` or `compare_signaling` and returns its
flags; every predicate except `compare_quiet_unordered` is false on an
unordered pair.

### `Decimal::compare_quiet_not_equal` and the other comparison predicates of Tables 5.1 and 5.2

The fifteen predicates of IEEE 754-2019 5.11 not listed above.

```mbti
pub fn Decimal::compare_quiet_greater(Self, Self) -> (Bool, DecimalFlags)
pub fn Decimal::compare_quiet_greater_equal(Self, Self) -> (Bool, DecimalFlags)
pub fn Decimal::compare_quiet_greater_unordered(Self, Self) -> (Bool, DecimalFlags)
pub fn Decimal::compare_quiet_less_unordered(Self, Self) -> (Bool, DecimalFlags)
pub fn Decimal::compare_quiet_not_equal(Self, Self) -> (Bool, DecimalFlags)
pub fn Decimal::compare_quiet_not_greater(Self, Self) -> (Bool, DecimalFlags)
pub fn Decimal::compare_quiet_not_less(Self, Self) -> (Bool, DecimalFlags)
pub fn Decimal::compare_quiet_ordered(Self, Self) -> (Bool, DecimalFlags)
pub fn Decimal::compare_signaling_greater(Self, Self) -> (Bool, DecimalFlags)
pub fn Decimal::compare_signaling_greater_equal(Self, Self) -> (Bool, DecimalFlags)
pub fn Decimal::compare_signaling_greater_unordered(Self, Self) -> (Bool, DecimalFlags)
pub fn Decimal::compare_signaling_less_unordered(Self, Self) -> (Bool, DecimalFlags)
pub fn Decimal::compare_signaling_not_equal(Self, Self) -> (Bool, DecimalFlags)
pub fn Decimal::compare_signaling_not_greater(Self, Self) -> (Bool, DecimalFlags)
pub fn Decimal::compare_signaling_not_less(Self, Self) -> (Bool, DecimalFlags)
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
| 5.1 | `Decimal::compare_quiet_equal` (`compareQuietEqual`) | equal |
| 5.1 | `Decimal::compare_quiet_not_equal` (`compareQuietNotEqual`) | less, greater, unordered |
| 5.1 | `Decimal::compare_signaling_greater` (`compareSignalingGreater`) | greater |
| 5.1 | `Decimal::compare_signaling_not_greater` (`compareSignalingNotGreater`) | less, equal, unordered |
| 5.1 | `Decimal::compare_signaling_greater_equal` (`compareSignalingGreaterEqual`) | equal, greater |
| 5.1 | `Decimal::compare_signaling_less_unordered` (`compareSignalingLessUnordered`) | less, unordered |
| 5.1 | `Decimal::compare_signaling_less` (`compareSignalingLess`) | less |
| 5.1 | `Decimal::compare_signaling_not_less` (`compareSignalingNotLess`) | equal, greater, unordered |
| 5.1 | `Decimal::compare_signaling_less_equal` (`compareSignalingLessEqual`) | less, equal |
| 5.1 | `Decimal::compare_signaling_greater_unordered` (`compareSignalingGreaterUnordered`) | greater, unordered |
| 5.2 | `Decimal::compare_signaling_equal` (`compareSignalingEqual`) | equal |
| 5.2 | `Decimal::compare_signaling_not_equal` (`compareSignalingNotEqual`) | less, greater, unordered |
| 5.2 | `Decimal::compare_quiet_greater` (`compareQuietGreater`) | greater |
| 5.2 | `Decimal::compare_quiet_not_greater` (`compareQuietNotGreater`) | less, equal, unordered |
| 5.2 | `Decimal::compare_quiet_greater_equal` (`compareQuietGreaterEqual`) | equal, greater |
| 5.2 | `Decimal::compare_quiet_less_unordered` (`compareQuietLessUnordered`) | less, unordered |
| 5.2 | `Decimal::compare_quiet_less` (`compareQuietLess`) | less |
| 5.2 | `Decimal::compare_quiet_not_less` (`compareQuietNotLess`) | equal, greater, unordered |
| 5.2 | `Decimal::compare_quiet_less_equal` (`compareQuietLessEqual`) | less, equal |
| 5.2 | `Decimal::compare_quiet_greater_unordered` (`compareQuietGreaterUnordered`) | greater, unordered |
| 5.2 | `Decimal::compare_quiet_unordered` (`compareQuietUnordered`) | unordered |
| 5.2 | `Decimal::compare_quiet_ordered` (`compareQuietOrdered`) | less, equal, greater |


### `Decimal::total_order`, `total_order_mag`, `total_order_compare`

These functions implement the IEEE 754-2019 §5.10 `totalOrder` and
`totalOrderMag` predicates, and the same order as a three-way comparison.

```mbti
pub fn Decimal::total_order(Self, Self) -> Bool
pub fn Decimal::total_order_mag(Self, Self) -> Bool
pub fn Decimal::total_order_compare(Self, Self) -> Int
```

`total_order(x, y)` is `true` when `x` is ordered at or before `y`, and
`total_order_compare(x, y)` is `-1`, `0` or `1` for the same order. The order
covers every representation:

$$
-\text{NaN} < -\text{sNaN} < -\infty < \text{negative finite} < -0 < +0 <
\text{positive finite} < +\infty < +\text{sNaN} < +\text{NaN}.
$$

Equal finite values are ordered by exponent: for positive values the smaller
exponent comes first ($1.00 < 1.0$), for negative values the larger. NaNs of
the same sign and kind are ordered by payload (reversed for negative NaNs).
`total_order_compare` returns 0 only for identical representations.
`total_order_mag(x, y)` is `total_order` of the absolute values. None of them
takes a context, rounds or raises a flag.

### `Decimal::identical`

`identical` tests that two values are the same datum.

```mbti
pub fn Decimal::identical(Self, Self) -> Bool
```

`x.identical(y)` is true when the class, sign, signaling bit, coefficient (the
payload of a NaN), exponent and precision label are all equal. It is finer than
`==`, which compares values (`1.20 == 1.2`), and than `total_order_compare`,
which ignores the precision label: `1.20` and `1.2` are not identical, a zero and
its negative are not identical, and two NaNs that differ in payload are not
identical.

```moonbit
///|
test "decimal identical compares the representation" {
  let a = @decimal.Decimal::from_string("1.20").unwrap()
  inspect(a.identical(@decimal.Decimal::from_string("1.20").unwrap()), content="true")
  inspect(a.identical(@decimal.Decimal::from_string("1.2").unwrap()), content="false")
  inspect(a == @decimal.Decimal::from_string("1.2").unwrap(), content="true")
}
```

### `Decimal::min`, `max`, `clamp`, `clamp_checked`

These functions select by numeric order without a context.

```mbti
pub fn Decimal::min(Self, Self) -> Self
pub fn Decimal::max(Self, Self) -> Self
pub fn Decimal::clamp(Self, min~ : Self, max~ : Self) -> Self
pub fn Decimal::clamp_checked(Self, min~ : Self, max~ : Self) -> Result[Self, @arithmetic.ArithmeticError]
```

`min` and `max` return the other operand when exactly one is a quiet NaN, a
quiet NaN when both are NaNs or either is signaling, and the receiver on
ties. `clamp` returns `min` below the range, `max` above it, and the value
(including a NaN) otherwise; it aborts when a bound is NaN or `min > max`.
`clamp_checked` returns `Err(domain_error)` in those cases.

### `Decimal::minimum_ctx`, `maximum_ctx`, `minimum_number_ctx`, `maximum_number_ctx`, `minimum_magnitude_ctx`, `maximum_magnitude_ctx`, `minimum_magnitude_number_ctx`, `maximum_magnitude_number_ctx`

These eight functions are the IEEE 754-2019 §9.6 minimum and maximum
operations. The General Decimal Arithmetic `min`, `max`, `min-magnitude` and
`max-magnitude` are in `decimal_gda`.

```mbti
pub fn Decimal::minimum_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::maximum_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::minimum_number_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::maximum_number_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::minimum_magnitude_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::maximum_magnitude_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::minimum_magnitude_number_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::maximum_magnitude_number_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
```

`minimum_ctx` and `maximum_ctx` propagate NaN: any NaN operand gives a quiet
NaN. The `_number_` variants return the number when exactly one operand is a
NaN. In both, a signaling NaN raises `invalid_operation`. The magnitude
variants compare $|x|$ and $|y|$ and fall back to the signed order on equal
magnitudes. Ties are broken by `total_order_compare`, so $-0 < +0$. The selected value is rounded
to the context.

## Elementary functions

Every elementary function exists in two forms. `f_ctx(x, ctx)` returns
`(result, flags)`. `try_f_ctx(x, ctx)` returns the same pair in `Ok`, or
`Err` with an `ArithmeticError` whose `certification_failure_detail()` names
the operation, the target precision and the exhausted refinement budget when
the result could not be certified. When certification fails, `f_ctx` returns
NaN with `invalid_operation`.

Transcendental results are **certified**: the implementation evaluates a
guaranteed enclosure of $f(x)$ in [`ball_float`](ball_float.md) and accepts it
only when both endpoints round to the same `Decimal` with the same flags (see
the [design](../design/decimal.md#certified-elementary-functions)). Because
rounding is monotone, an accepted result is the rounding of $f(x)$ in every
`DecimalRoundingMode`. A list of exact cases (such as
$\log_{10} 1000 = 3$, $e^0 = 1$, $\sin 0 = 0$, $\operatorname{cospi}(1) = -1$,
$\operatorname{tanpi}(0.25) = 1$, $\operatorname{acos}(1) = 0$, $x^{0.5}$,
exact roots such as `rootn_ctx(0.008, 3)` $= 0.2$, exact norms such as
`hypot_ctx(0.3, 0.4)` $= 0.5$) is decided before the enclosure loop and
returned without `inexact`, and an exact binary result such as
`pow_ctx(4, 1.5)` $= 8$ is returned exactly by the enclosure itself. Integer
powers are not certified: [`pow_ctx`](#decimalpow_ctx-pown_ctx-rootn_ctx-hypot_ctx-try_pow_ctx-try_pown_ctx-try_rootn_ctx-try_hypot_ctx)
rounds them once from the exact power or from
refined directed bounds.

> [!NOTE]
> **Exact non-integral powers.** A power whose exact value is a representable
> decimal but not a binary fraction is decided in decimal before the loop, so
> in decimal64 `pow_ctx(0.0016, 0.25)` is `0.2`, `pow_ctx(32, 0.2)` is `2`
> and `pow_ctx(0.04, 1.5)` is `0.008`, all without `inexact` and in every
> rounding mode. The exponent is reduced to $p/q$ in lowest terms — a decimal
> exponent is $c \cdot 10^{-k}$, so $q$ keeps only the twos and fives the
> coefficient cannot cancel — and the power is exact exactly when $x$ itself
> is a perfect $q$-th power. The root is taken first and then raised to $p$,
> so the test never handles a number longer than the result. It finds every
> exact result of at most `precision + 1` digits, the only ones that sit on a
> rounding boundary; a longer exact value lies inside its rounding cell and the
> enclosure rounds it like any other.

These operations return NaN with `not_computed` (and the `try_` forms `Err`, of the certification-failure kind) when $p > 999\,999$,
$e_{\max} > 999\,999$ or $e_{\min} < -999\,999$, or when a finite operand has
more than 999,999 digits or an adjusted exponent beyond about $\pm 10^6$.
In such a context every operand is `not_computed`, the special ones (NaN,
infinities, zero) included, although IEEE 754-2019 defines those results (the
order of the checks is that of the implementation; lifting it is the subject of
#478). Only `pow_ctx` and `pown_ctx` handle their IEEE power cases before this
restricted-context check. For example, `pow_ctx(1, 1.1)` is exactly `1` even
in a restricted context, while `ln_ctx(1)` and `exp_ctx(-inf)` still return
`not_computed`. Integral powers in `decimal` support counts through
999,999,999 for positive exponents and -1,999,999,997 for negative exponents;
these are adopted decNumber implementation limits, not limits imposed by GDA
1.70. Integer powers above those counts use bounded square-and-multiply when
the exact exponent coefficient has at most 4,096 decimal digits. Larger
coefficients return NaN with `invalid_operation` before expansion. Thus
`pow_ctx(2, 1E+9)` is finite under `DecimalContext::new()`, while
`pow_ctx(2, 1E+9999999)` is rejected within the fixed work bound. The same
large input to `decimal_gda` still follows the GDA adapter's decNumber count
limit and returns `invalid_operation`; IEEE `decimal` and `decimal_gda`
therefore intentionally differ on this input. Non-integral powers such as
`pow_ctx(2, 1.5)` and `exp2_ctx(2)` remain subject to the elementary-function
context limits.

### `Decimal::exp_ctx`, `ln_ctx`, `log10_ctx`, `try_exp_ctx`, `try_ln_ctx`, `try_log10_ctx`

These functions are the General Decimal Arithmetic exponential and
logarithms.

```mbti
pub fn Decimal::exp_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::ln_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::log10_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::try_exp_ctx(Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::try_ln_ctx(Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::try_log10_ctx(Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
```

$e^{\pm 0} = 1$, $e^{+\infty}=+\infty$, $e^{-\infty} = +0$. $\ln$ and
$\log_{10}$ of $\pm 0$ are $-\infty$ with `division_by_zero`, as IEEE 754-2019 §9.2.1 requires and as `log2_ctx`, `log1p_ctx` and
`logb_ctx` do (General Decimal Arithmetic, which
[`decimal_gda`](decimal_gda.md) follows, raises no condition here); of
$+\infty$ are $+\infty$, of a negative value or $-\infty$ are NaN with
`invalid_operation`; $\ln 1 = 0$, and $\log_{10}$ of a power of ten is the
exact integer exponent. Arguments so large or small that $e^x$ certainly
overflows or underflows are decided without evaluation.

### `Decimal::pow_ctx`, `pown_ctx`, `rootn_ctx`, `hypot_ctx`, `try_pow_ctx`, `try_pown_ctx`, `try_rootn_ctx`, `try_hypot_ctx`

These functions compute powers, roots and the Euclidean norm.

```mbti
pub fn Decimal::pow_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::pown_ctx(Self, Int, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::rootn_ctx(Self, Int, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::hypot_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::try_pow_ctx(Self, Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::try_pown_ctx(Self, Int, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::try_rootn_ctx(Self, Int, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::try_hypot_ctx(Self, Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
```

`pow_ctx(x, y)` is the IEEE 754-2019 §9.2 power operation. A signaling NaN
operand is quieted and raises `invalid_operation`; this takes precedence over
the identities below. Otherwise $x^{\pm 0}=1$, including for zero, infinity,
and quiet NaN, and $\operatorname{pow}(+1,y)=1$ for every $y$ (including quiet
NaN). Also $\operatorname{pow}(-1,\pm\infty)=1$. An infinite exponent
classifies the magnitude of any other base: $|x|<1$ tends to zero for
$+\infty$ and infinity for $-\infty$, while $|x|>1$ does the reverse; the
sign of a negative base does not make these cases invalid.

For a zero base and a negative integer exponent, the result is the signed
infinity selected by the zero sign and exponent parity, with `division_by_zero`:
for example, $(-0)^{-1}=-\infty$ and $(-0)^{-2}=+\infty$. Positive integer powers
preserve the zero sign by parity: $(-0)^3=-0$ and $(-0)^2=+0$. Zero raised to a
negative non-integer exponent is positive infinity with `division_by_zero`.

Integer powers within the bounded count use binary square-and-multiply. An exact
power is returned when it fits in $p$ digits; otherwise the result is correctly
rounded. An integral
exponent outside the bounded count is still supported: the magnitude is
certified, and an odd power of a negative base swaps the directed rounding
modes before restoring its sign. For large integer exponents the zero and
infinity cases are decided from sign and parity without expanding the exponent:
for example, `pown_ctx(-0, Int::max_value())` is `-0`,
`pown_ctx(-0, Int::min_value())` is `+infinity` with `division_by_zero`, and
`pown_ctx(-infinity, Int::min_value())` is `+0`.

For other integral exponents, an exact power is returned when it fits in $p$
digits and otherwise the correctly rounded power (in
decimal32, `pow_ctx(3.339434, 3)` is `37.24077`; the exact cube is
$37.240765000\ldots$); $x^{0.5}$ is `sqrt_ctx`; positive non-integer powers
are certified and negative bases with a finite non-integer exponent are
invalid. These IEEE rules intentionally differ from
[`decimal_gda`](decimal_gda.md), which follows General Decimal Arithmetic
(including its `0^0` invalid result and the `powx2015` rounded `1.00` vector).
`pown_ctx(x, n)` converts the integer `n` exactly, so
$(-1)^{12345679}=-1$ at any precision. `rootn_ctx(x, n)` is
$x^{1/n}$ for integer $n \ne 0$; an even root of a negative value and $n=0$
are invalid, and $\operatorname{rootn}(\pm 0, n<0)$ is an infinity with
`division_by_zero`; an exactly representable root is returned exactly
(`rootn_ctx(0.008, 3)` is `0.2` with no flag). `hypot_ctx(x, y)` is
$\sqrt{x^2+y^2}$; it is $+\infty$ if either operand is infinite, even if the
other is a quiet NaN, and an exactly representable norm, or $|x|$ when $y$ is
zero, is returned exactly (`hypot_ctx(0.3, 0.4)` is `0.5`).

An integral exponent with more than 4,096 digits is never expanded: for a base
other than $\pm 1$, $\pm 0$ and $\pm\infty$ the magnitude $|y \ln |x||$ is far
beyond any context, so the result is the overflow or the underflow value of the
rounding direction (decided from the base being above or below 1 and the sign
of the exponent) and the sign follows the parity, not an `invalid_operation`. A
base with more than about 4,000 fractional digits, whose bound is not met, still
returns NaN with `invalid_operation`.

An exact result is delivered in the cohort member whose exponent is closest to
the preferred exponent of IEEE 754-2019 §9.2.2, $\lfloor y\,q_x \rfloor$ for
`pow_ctx(x, y)` and $\lfloor n\,q_x \rfloor$ for `pown_ctx(x, n)`, where
$q_x$ is the exponent of the stored `x` and the member must fit in $p$ digits:
in decimal64 `pown_ctx(1.00, 2)` is `1.0000`, `pown_ctx(-1.0, 3)` is `-1.000`,
`pown_ctx(-1E+5, 5)` is `-1E+25` (exact, no flags), `pow_ctx(1.00, 1.5)` is
`1.000` and `pow_ctx(4.00, 1.5)` is `8.000`; a negative exponent cannot reach
a preferred exponent above the value (`pown_ctx(1.00, -2)` is `1`). The
standard defines no preferred exponent when $y$ is infinite or a NaN, so
`pow_ctx(1.00, Infinity)` stays `1`. `decimal_gda` follows the repeated
multiplication exponent of General Decimal Arithmetic instead.

### `Decimal::exp2_ctx`, `exp10_ctx`, `expm1_ctx`, `log2_ctx`, `log1p_ctx`, `try_exp2_ctx`, `try_exp10_ctx`, `try_expm1_ctx`, `try_log2_ctx`, `try_log1p_ctx`

These functions are the IEEE 754-2019 §9.2 exponentials and logarithms in bases 2 and 10 and near zero. Each has the `f_ctx`/`try_f_ctx` shape described
at the start of this section.

```mbti
pub fn Decimal::exp2_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::exp10_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::expm1_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::log2_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::log1p_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::try_exp2_ctx(Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::try_exp10_ctx(Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::try_expm1_ctx(Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::try_log2_ctx(Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::try_log1p_ctx(Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
```

### `Decimal::exp2m1_ctx`, `exp10m1_ctx`, `log2p1_ctx`, `log10p1_ctx`, `try_exp2m1_ctx`, `try_exp10m1_ctx`, `try_log2p1_ctx`, `try_log10p1_ctx`

These functions are $2^x - 1$, $10^x - 1$, $\log_2(1 + x)$ and
$\log_{10}(1 + x)$ of IEEE 754-2019 §9.2, without the cancellation of
`exp2(x) - 1` or the rounding of `1 + x` near zero. Each has the
`f_ctx`/`try_f_ctx` shape described at the start of this section.

```mbti
pub fn Decimal::exp2m1_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::exp10m1_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::log2p1_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::log10p1_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::try_exp2m1_ctx(Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::try_exp10m1_ctx(Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::try_log2p1_ctx(Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::try_log10p1_ctx(Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
```

The special values are those of §9.2.1: $f(\pm 0) = \pm 0$ and
$f(+\infty) = +\infty$ for all four, $-\infty \mapsto -1$ for `exp2m1` and
`exp10m1`, and $-1 \mapsto -\infty$ with `division_by_zero` for `log2p1` and
`log10p1`, whose domain is $[-1, +\infty]$ ($x < -1$, including $-\infty$, is
invalid). The exact results are $2^n - 1$ and $10^n - 1$ for an integer $n$
and the integer $k$ when $1 + x = 2^k$ (resp. $10^k$); they take the
preferred exponent 0 of §9.2.2, so in decimal64 `exp2m1_ctx(4)` is `15`,
`exp2m1_ctx(-1)` is `-0.5`, `exp10m1_ctx(-2.0)` is `-0.99` and
`log2p1_ctx(-0.50)` is `-1`, all without flags. A context that cannot hold an
exact value rounds it with its flags: `log2p1_ctx(32767)` at precision 1 is
`2E+1` (a midpoint, `inexact`). $\operatorname{log2p1}(1) = 1$ exactly and
$\operatorname{log10p1}(1) = \log_{10} 2$; the rule $f(1) = +0$ of §9.2.1
belongs to `log`, `log2` and `log10` only. Results below the subnormal range
are rounded, never replaced, so they keep the sign of $x$
(`exp2m1_ctx(-1E-500)` is `-0E-398` in decimal64, `-1E-398` when rounding
toward $-\infty$), and the same restricted contexts as `exp_ctx` give
`not_computed`.

```moonbit
///|
test "decimal exp2m1 exp10m1 log2p1 log10p1" {
  let c64 = @decimal.DecimalContext::decimal64()
  let d = fn(s : String) { @decimal.Decimal::from_string(s).unwrap() }
  inspect(d("4").exp2m1_ctx(c64).0, content="15")
  inspect(d("-2.0").exp10m1_ctx(c64).0, content="-0.99")
  inspect(d("1E-10").exp2m1_ctx(c64).0, content="6.931471805839680E-11")
  inspect(d("-0.50").log2p1_ctx(c64).0, content="-1")
  let (pole, flags) = d("-1").log10p1_ctx(c64)
  inspect(pole, content="-inf")
  inspect(flags.division_by_zero(), content="true")
}
```

### `Decimal::rsqrt_ctx`, `compound_ctx`, `powr_ctx`, `try_rsqrt_ctx`, `try_compound_ctx`, `try_powr_ctx`

These functions are $1/\sqrt{x}$, $(1 + x)^n$ for an `Int32` $n$ and
$x^y = e^{y \ln x}$ of IEEE 754-2019 §9.2. Each has the `f_ctx`/`try_f_ctx`
shape described at the start of this section.

```mbti
pub fn Decimal::rsqrt_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::compound_ctx(Self, Int32, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::powr_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::try_rsqrt_ctx(Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::try_compound_ctx(Self, Int32, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::try_powr_ctx(Self, Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
```

`rsqrt_ctx` has domain $[0, +\infty]$: $x < 0$ (including $-\infty$) is
invalid, $\pm 0 \mapsto \pm\infty$ with `division_by_zero` and
$+\infty \mapsto +0$ (§9.2.1). It is exact when $x = 2^{2i}5^{2j}$; the
result then takes the preferred exponent $-\lfloor Q(x)/2 \rfloor$ of §9.2.2,
so in decimal64 `rsqrt_ctx(4.00)` is `0.5`, `rsqrt_ctx(1E+2)` is `0.1` and
`rsqrt_ctx(1E-400)` is `1E+200`.

`compound_ctx(x, n)` follows the list of §9.2.1: `compound(x, 0)` is 1 for
$x \ge -1$ and for a quiet NaN, $x < -1$ (also with $n = 0$) is invalid,
`compound(-1, n)` is $+\infty$ with `division_by_zero` for $n < 0$ and $+0$
for $n > 0$, `compound(±0, n)` is 1 and `compound(+∞, n)` is $+\infty$ or
$+0$. An exact result takes the preferred exponent
$\lfloor n \min(0, Q(x)) \rfloor$: `compound_ctx(0.10, 2)` is `1.2100` and
`compound_ctx(0.00, 3)` is `1.000000`. Every $n$ of `Int32` is accepted, also
the `Int32` minimum $-2^{31}$.

`powr_ctx(x, y)` is $e^{y \ln x}$, so its domain excludes $x < 0$ (invalid,
also when $y$ is a quiet NaN). It returns a quiet NaN for a NaN operand even
when $y = \pm 0$, is invalid for `powr(±0, ±0)`, `powr(+∞, ±0)` and
`powr(1, ±∞)`, and otherwise equals `pow_ctx` on $|x|$ (results, cohort and
flags): `powr_ctx(-0, 3)` is `0` where `pow_ctx` gives `-0`.

```moonbit
///|
test "decimal rsqrt compound powr" {
  let c64 = @decimal.DecimalContext::decimal64()
  let d = fn(s : String) { @decimal.Decimal::from_string(s).unwrap() }
  inspect(d("6.25").rsqrt_ctx(c64).0, content="0.4")
  inspect(d("2").rsqrt_ctx(c64).0, content="0.7071067811865475")
  inspect(d("0.05").compound_ctx(3, c64).0, content="1.157625")
  inspect(d("0.05").compound_ctx(-3, c64).0, content="0.8638375985314761")
  inspect(d("4").powr_ctx(d("0.5"), c64).0, content="2")
  let (invalid, flags) = d("-2").powr_ctx(d("2"), c64)
  inspect(invalid, content="nan")
  inspect(flags.invalid_operation(), content="true")
}
```

### `Decimal::sin_ctx`, `cos_ctx`, `tan_ctx`, `sinpi_ctx`, `cospi_ctx`, `tanpi_ctx`, `try_sin_ctx`, `try_cos_ctx`, `try_tan_ctx`, `try_sinpi_ctx`, `try_cospi_ctx`, `try_tanpi_ctx`

These functions are the trigonometric functions of $x$ and of $\pi x$. Each has the `f_ctx`/`try_f_ctx` shape described
at the start of this section.

```mbti
pub fn Decimal::sin_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::cos_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::tan_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::sinpi_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::cospi_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::tanpi_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::try_sin_ctx(Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::try_cos_ctx(Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::try_tan_ctx(Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::try_sinpi_ctx(Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::try_cospi_ctx(Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::try_tanpi_ctx(Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
```

### `Decimal::asin_ctx`, `acos_ctx`, `atan_ctx`, `atan2_ctx`, `try_asin_ctx`, `try_acos_ctx`, `try_atan_ctx`, `try_atan2_ctx`

These functions are the inverse trigonometric functions; `atan2(y, x)` is the angle of the point $(x, y)$. Each has the `f_ctx`/`try_f_ctx` shape described
at the start of this section.

```mbti
pub fn Decimal::asin_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::acos_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::atan_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::atan2_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::try_asin_ctx(Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::try_acos_ctx(Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::try_atan_ctx(Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::try_atan2_ctx(Self, Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
```

### `Decimal::asinpi_ctx`, `acospi_ctx`, `atanpi_ctx`, `atan2pi_ctx`, `try_asinpi_ctx`, `try_acospi_ctx`, `try_atanpi_ctx`, `try_atan2pi_ctx`

These functions are the inverse circular functions measured in
half-revolutions of IEEE 754-2019 §9.2: $\operatorname{asin}(x)/\pi$,
$\operatorname{acos}(x)/\pi$, $\operatorname{atan}(x)/\pi$ and
$\operatorname{atan2}(y, x)/\pi$, the last with the ordinate as the receiver
(`y.atan2pi_ctx(x, ctx)`) and a result in $[-1, 1]$. Each has the
`f_ctx`/`try_f_ctx` shape described at the start of this section.

```mbti
pub fn Decimal::asinpi_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::acospi_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::atanpi_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::atan2pi_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::try_asinpi_ctx(Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::try_acospi_ctx(Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::try_atanpi_ctx(Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::try_atan2pi_ctx(Self, Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
```

The exact results are those of §9.2.1, and by Niven's theorem the only ones:
$\operatorname{asinPi}(\pm 0) = \pm 0$, $\operatorname{asinPi}(\pm 1) = \pm\tfrac12$;
$\operatorname{acosPi}(1) = +0$, $\operatorname{acosPi}(-1) = 1$,
$\operatorname{acosPi}(\pm 0) = \tfrac12$; $\operatorname{atanPi}(\pm 0) = \pm 0$,
$\operatorname{atanPi}(\pm 1) = \pm\tfrac14$ and
$\operatorname{atanPi}(\pm\infty) = \pm\tfrac12$ with no exception; and the
eleven rows of $\operatorname{atan2Pi}$ for zero and infinite operands
($\pm 0$, $\pm 1$, $\pm\tfrac12$, $\pm\tfrac14$, $\pm\tfrac34$, the sign
bit of a zero abscissa choosing the half-plane), plus $\lvert y\rvert =
\lvert x\rvert$ for finite nonzero operands ($\pm\tfrac14$ for $x > 0$,
$\pm\tfrac34$ for $x < 0$). None of them signals an exception. They take the
preferred exponent 0 of §9.2.2, so $\tfrac12$ is `0.5`, $\tfrac14$ is
`0.25`, $\tfrac34$ is `0.75` and 1 is `1`, whatever the cohort of the operand;
a context too narrow for the constant (precision 1) rounds it, with `inexact`.
$\lvert x\rvert > 1$ (also $\pm\infty$) is invalid for `asinpi` and `acospi`.
Every other result is inexact ($\operatorname{asinPi}(\pm\tfrac12) = \pm\tfrac16$
and $\operatorname{acosPi}(\pm\tfrac12) = \tfrac13, \tfrac23$ are not
terminating decimals) and is correctly rounded, also next to the representable
values $\pm\tfrac12$ and $\pm 1$ that `atanpi` (large $\lvert x\rvert$),
`acospi` (tiny $\lvert x\rvert$) and `atan2pi` (extreme ratios) approach from
one side: there the rounding mode decides between the anchor and its
neighbour.

```moonbit
///|
test "decimal inverse circular functions in half-revolutions" {
  let c64 = @decimal.DecimalContext::decimal64()
  let d = fn(s : String) { @decimal.Decimal::from_string(s).unwrap() }
  inspect(d("1").atanpi_ctx(c64).0, content="0.25")
  inspect(d("-1").atan2pi_ctx(d("-1"), c64).0, content="-0.75")
  inspect(d("-0").atan2pi_ctx(d("-0"), c64).0, content="-1")
  inspect(d("0.5").asinpi_ctx(c64).0, content="0.1666666666666667")
  inspect(d("0.5").acospi_ctx(c64).0, content="0.3333333333333333")
  let (value, flags) = d("2").asinpi_ctx(c64)
  inspect(value, content="nan")
  inspect(flags.invalid_operation(), content="true")
}
```

### `Decimal::sinh_ctx`, `cosh_ctx`, `tanh_ctx`, `asinh_ctx`, `acosh_ctx`, `atanh_ctx`, `try_sinh_ctx`, `try_cosh_ctx`, `try_tanh_ctx`, `try_asinh_ctx`, `try_acosh_ctx`, `try_atanh_ctx`

These functions are the hyperbolic functions and their inverses. Each has the `f_ctx`/`try_f_ctx` shape described
at the start of this section.

```mbti
pub fn Decimal::sinh_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::cosh_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::tanh_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::asinh_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::acosh_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::atanh_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::try_sinh_ctx(Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::try_cosh_ctx(Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::try_tanh_ctx(Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::try_asinh_ctx(Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::try_acosh_ctx(Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::try_atanh_ctx(Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
```

Domain and special values of the functions in these four groups:

| Function | Invalid (`invalid_operation`) | Pole (`division_by_zero`) | Exact cases |
| --- | --- | --- | --- |
| `exp2`, `exp10` | none | none | integer argument (via `pow_ctx`), $\pm 0 \mapsto 1$, $-\infty \mapsto 0$, $+\infty \mapsto +\infty$ |
| `expm1` | none | none | $\pm0 \mapsto \pm0$, $-\infty\mapsto -1$, $+\infty \mapsto +\infty$ |
| `log2` | $x<0$, $-\infty$ | $\pm 0 \mapsto -\infty$ | $1 \mapsto 0$, exact binary powers ($0.125 \mapsto -3$), $+\infty \mapsto +\infty$ |
| `log1p` | $x<-1$, $-\infty$ | $-1 \mapsto -\infty$ | $\pm0 \mapsto \pm0$, $+\infty \mapsto +\infty$ |
| `exp2m1`, `exp10m1` | none | none | $\pm0 \mapsto \pm0$, $-\infty\mapsto -1$, $+\infty \mapsto +\infty$; integer $n$: $2^n - 1$, $10^n - 1$ |
| `log2p1`, `log10p1` | $x<-1$, $-\infty$ | $-1 \mapsto -\infty$ | $\pm0 \mapsto \pm0$, $+\infty \mapsto +\infty$; $1 + x = 2^k$ (resp. $10^k$) $\mapsto k$ |
| `rsqrt` | $x<0$, $-\infty$ | $\pm 0 \mapsto \pm\infty$ | $+\infty \mapsto +0$; $x = 2^{2i}5^{2j}$ |
| `compound(x, n)` | $x<-1$, $-\infty$ (any $n$) | $(-1, n<0) \mapsto +\infty$ | $(x, 0) \mapsto 1$, $(\pm 0, n) \mapsto 1$, $(-1, n>0) \mapsto +0$, $+\infty$ by the sign of $n$; exact powers |
| `powr(x, y)` | $x<0$, $(\pm0, \pm0)$, $(+\infty, \pm0)$, $(1, \pm\infty)$ | $(\pm 0, y<0) \mapsto +\infty$ | NaN for a NaN operand; otherwise as `power` on $\lvert x\rvert$ |
| `sin`, `cos`, `tan` | $\pm\infty$ | none | $\sin(\pm 0)=\pm 0$, $\tan(\pm 0)=\pm 0$, $\cos 0 = 1$ |
| `sinpi`, `cospi`, `tanpi` | $\pm\infty$ | `tanpi` at odd half-integers | integers, half-integers, `tanpi` at odd quarter-integers ($\pm 1$) |
| `asin`, `acos` | $\lvert x\rvert > 1$, $\pm\infty$ | none | $\operatorname{asin}(\pm0)=\pm0$, $\operatorname{acos}(1) = 0$ |
| `atan` | none | none | $\pm 0$; $\pm\infty \mapsto \pm\pi/2$ (certified) |
| `asinpi`, `acospi` | $\lvert x\rvert > 1$, $\pm\infty$ | none | $\operatorname{asinPi}(\pm0)=\pm0$, $\operatorname{asinPi}(\pm1)=\pm\tfrac12$, $\operatorname{acosPi}(1)=+0$, $\operatorname{acosPi}(-1)=1$, $\operatorname{acosPi}(\pm0)=\tfrac12$ |
| `atanpi` | none | none | $\pm 0$; $\pm 1 \mapsto \pm\tfrac14$; $\pm\infty \mapsto \pm\tfrac12$ (no exception) |
| `atan2pi(y, x)` | none | none | the eleven exact rows of §9.2.1 ($\pm0$, $\pm\tfrac12$, $\pm\tfrac14$, $\pm\tfrac34$, $\pm1$) and $\lvert y\rvert = \lvert x\rvert \mapsto \pm\tfrac14, \pm\tfrac34$ |
| `atan2(y, x)` | none | none | $\operatorname{atan2}(\pm 0, x) = \pm 0$ for $x = +0$ or $x > 0$, and $\operatorname{atan2}(y, +\infty) = \pm 0$ for finite $y$; any other zero or infinite operand gives $\pi$, $\pi/2$, $\pi/4$ or $3\pi/4$ with the sign of $y$ (certified) |
| `sinh`, `tanh`, `asinh` | none | none | $\pm0\mapsto\pm0$; $\sinh$, $\operatorname{asinh}$ keep $\pm\infty$; $\tanh(\pm\infty)=\pm 1$ |
| `cosh` | none | none | $\cosh(\pm 0) = 1$, $\cosh(\pm\infty)=+\infty$ |
| `acosh` | $x < 1$, $-\infty$ | none | $1 \mapsto 0$, $+\infty \mapsto +\infty$ |
| `atanh` | $\lvert x\rvert>1$, $\pm\infty$ | $\pm1 \mapsto \pm\infty$ | $\pm0 \mapsto \pm0$ |

These special values follow IEEE 754-2019 §9.2.1: in decimal64,
`atan2_ctx(-0, -1)` is `-3.141592653589793`, `atan2_ctx(+∞, -∞)` is
`2.356194490192345` and `atan2_ctx(-1, +∞)` is `-0`.

```moonbit
///|
test "decimal exact and special elementary results" {
  let c64 = @decimal.DecimalContext::decimal64()
  let d = fn(s : String) { @decimal.Decimal::from_string(s).unwrap() }
  let (norm, flags) = d("0.3").hypot_ctx(d("0.4"), c64)
  inspect(norm, content="0.5")
  inspect(flags.inexact(), content="false")
  inspect(d("0.008").rootn_ctx(3, c64).0, content="0.2")
  let c32 = @decimal.DecimalContext::decimal32()
  inspect(d("3.339434").pow_ctx(d("3"), c32).0, content="37.24077")
  let seven = @decimal.DecimalContext::new(precision=7)
  inspect(d("-1").pown_ctx(12345679, seven).0, content="-1")
  inspect(d("-0").atan2_ctx(d("-1"), c64).0, content="-3.141592653589793")
  inspect(d("Inf").atan2_ctx(d("-Inf"), c64).0, content="2.356194490192345")
  inspect(d("-1").atan2_ctx(d("Inf"), c64).0, content="-0")
  inspect(d("-Inf").cosh_ctx(c64).0, content="inf")
  inspect(d("Inf").log2_ctx(c64).0, content="inf")
}
```

```moonbit
///|
test "decimal certified elementary functions" {
  let ctx = @decimal.DecimalContext::decimal64()
  let d = fn(s : String) { @decimal.Decimal::from_string(s).unwrap() }
  inspect(d("1").exp_ctx(ctx).0, content="2.718281828459045")
  inspect(d("1000").log10_ctx(ctx).0, content="3")
  inspect(d("0.5").sinpi_ctx(ctx).0, content="1")
  let down = ctx.with_rounding(@decimal.DecimalRoundingMode::RoundTowardZero)
  inspect(d("2").ln_ctx(down).0, content="0.6931471805599453")
  // a context beyond the elementary kernels is not computed: `Err` in the `try_`
  // form, a NaN with `not_computed` (and not `invalid_operation`) in the plain form
  let beyond = @decimal.DecimalContext::new(e_max=999_999_999)
  match d("2").try_ln_ctx(beyond) {
    Ok(_) => fail("a context beyond the kernels must be an Err")
    Err(error) => inspect(error.is_certification_failure(), content="true")
  }
  let (value, flags) = d("2").ln_ctx(beyond)
  inspect(value.is_nan(), content="true")
  inspect(flags.not_computed(), content="true")
  inspect(flags.invalid_operation(), content="false")
  // a domain error is a value with invalid_operation
  let (nan, nan_flags) = d("-1").ln_ctx(ctx)
  inspect(nan.is_nan(), content="true")
  inspect(nan_flags.invalid_operation(), content="true")
}
```

## Interchange formats

### `DecimalInterchangeFormat`, `DecimalInterchangeFormat::context`

`DecimalInterchangeFormat` names an IEEE 754 decimal interchange format.

```mbti
pub(all) enum DecimalInterchangeFormat {
  Decimal32
  Decimal64
  Decimal128
}
pub fn DecimalInterchangeFormat::context(Self) -> DecimalContext
```

`context` returns `DecimalContext::decimal32()`, `decimal64()` or
`decimal128()`.

### `DecimalInterchangeEncoding`

`DecimalInterchangeEncoding` selects how the coefficient is stored in the
bits.

```mbti
pub(all) enum DecimalInterchangeEncoding {
  DPD
  BID
}
```

`DPD` stores three decimal digits per 10-bit declet (densely packed decimal);
`BID` stores the coefficient as a binary integer. Functions without an
encoding argument use `DPD`.

### `Decimal::to_interchange_hex`, `to_interchange_hex_with_encoding`

These functions encode a value as interchange bits written in hexadecimal.

```mbti
pub fn Decimal::to_interchange_hex(Self, DecimalInterchangeFormat) -> (String, DecimalFlags)
pub fn Decimal::to_interchange_hex_with_encoding(Self, DecimalInterchangeFormat, DecimalInterchangeEncoding) -> (String, DecimalFlags)
```

A finite value is first rounded with `apply_ctx` under the format context
(its flags are returned), then encoded with its exponent, so the cohort is
kept when it fits. The text is `#` followed by 8, 16 or 32 upper-case hex
digits. Infinities are encoded with a zero trailing field. A NaN keeps its
sign and kind, and its payload is stored as an integer, independent of the
value's precision field (IEEE 754-2019 §3.5.2): a payload below $10^{p-1}$ is
kept, and a longer one keeps its low $p-1$ digits, in DPD and BID alike.
`NaN7` encodes to decimal64 as `#7C00000000000007` in both encodings.

### `Decimal::from_interchange_hex`, `from_interchange_hex_with_encoding`

These functions decode interchange hex text.

```mbti
pub fn Decimal::from_interchange_hex(String, DecimalInterchangeFormat) -> Result[Self, @arithmetic.ArithmeticError]
pub fn Decimal::from_interchange_hex_with_encoding(String, DecimalInterchangeFormat, DecimalInterchangeEncoding) -> Result[Self, @arithmetic.ArithmeticError]
```

The text may have surrounding ASCII whitespace and a leading `#`; it must have
exactly the format's number of hex digits, in either case. Anything else is an
`Err` (a parse error) that says what was wrong: the number of digits wanted and
found (`"#A23003D"` for decimal32 has 7 of 8), or the first character that is
not a hexadecimal digit and its place among the digits. The length is checked
first. No bit pattern of the right length is refused: decoding is exact and keeps the exponent, the sign of zero, the NaN
kind and payload. Non-canonical encodings decode to the value IEEE 754
assigns them: a non-canonical DPD declet to its digits, a BID coefficient
$\ge 10^{p}$ to zero, an out-of-range BID NaN payload to 0; the unused
exponent bits of infinities and NaNs are ignored. The result has the format's
precision. `GdaInterchange::from_hex` of `decimal_gda` accepts the same texts
and refuses the same ones, but its message is one sentence for both faults.

```moonbit
///|
test "decimal64 interchange in both encodings" {
  let x = @decimal.Decimal::from_string("1.25").unwrap()
  let fmt = @decimal.DecimalInterchangeFormat::Decimal64
  let (dpd, _) = x.to_interchange_hex(fmt)
  let (bid, _) = x.to_interchange_hex_with_encoding(
    fmt,
    @decimal.DecimalInterchangeEncoding::BID,
  )
  inspect(dpd, content="#22300000000000A5")
  inspect(bid, content="#318000000000007D")
  let back = @decimal.Decimal::from_interchange_hex(dpd, fmt).unwrap()
  inspect(back, content="1.25")
  // a text of the wrong length is an error that says so
  match @decimal.Decimal::from_interchange_hex("#22300", fmt) {
    Ok(_) => fail("expected a parse error")
    Err(err) => assert_true(err.is_parse_error())
  }
}
```

### `DecimalInterchange`, `DecimalInterchange::format`, `encoding`, `to_hex`

`DecimalInterchange` holds the raw bits of one interchange value together
with its format and encoding.

```mbti
pub struct DecimalInterchange {
  // private fields
}
pub fn DecimalInterchange::format(Self) -> DecimalInterchangeFormat
pub fn DecimalInterchange::encoding(Self) -> DecimalInterchangeEncoding
pub fn DecimalInterchange::to_hex(Self) -> String
```

Use it when bits must be inspected or kept exactly, including non-canonical
encodings that a `Decimal` cannot represent. `format` and `encoding` return
the format and encoding the bits belong to; `to_hex` writes `#` and the
full-width upper-case hex digits.

### `DecimalInterchange::from_hex`, `from_hex_with_encoding`, `from_decimal`, `from_decimal_with_encoding`

These functions build an interchange value from text or from a `Decimal`.

```mbti
pub fn DecimalInterchange::from_hex(String, DecimalInterchangeFormat) -> Result[Self, @arithmetic.ArithmeticError]
pub fn DecimalInterchange::from_hex_with_encoding(String, DecimalInterchangeFormat, DecimalInterchangeEncoding) -> Result[Self, @arithmetic.ArithmeticError]
pub fn DecimalInterchange::from_decimal(Decimal, DecimalInterchangeFormat) -> (Self, DecimalFlags)
pub fn DecimalInterchange::from_decimal_with_encoding(Decimal, DecimalInterchangeFormat, DecimalInterchangeEncoding) -> (Self, DecimalFlags)
```

`from_hex` stores the bits unchanged (text rules and errors as in
`from_interchange_hex`). `from_decimal` encodes like `to_interchange_hex` and
returns the same flags. The forms without an encoding use `DPD`.

### `DecimalInterchange::to_decimal`, `to_decimal_ctx`

These functions decode the stored bits.

```mbti
pub fn DecimalInterchange::to_decimal(Self) -> Decimal
pub fn DecimalInterchange::to_decimal_ctx(Self) -> (Decimal, DecimalFlags)
```

Decoding is exact: `to_decimal_ctx` raises no flag.

### `DecimalInterchange::canonical`, `is_canonical`

These functions canonicalize the stored bits.

```mbti
pub fn DecimalInterchange::canonical(Self) -> Self
pub fn DecimalInterchange::is_canonical(Self) -> Bool
```

`canonical` decodes and re-encodes in the same format and encoding: every
non-canonical declet, out-of-range BID coefficient, and unused bit of an
infinity or NaN is replaced by its canonical form. It is idempotent.
`is_canonical` tests whether the bits are already canonical.

### `DecimalInterchange::copy`, `copy_abs`, `copy_negate`, `copy_sign`

These functions change only the sign bit of the stored bits.

```mbti
pub fn DecimalInterchange::copy(Self) -> Self
pub fn DecimalInterchange::copy_abs(Self) -> Self
pub fn DecimalInterchange::copy_negate(Self) -> Self
pub fn DecimalInterchange::copy_sign(Self, Self) -> Self
```

All other bits, canonical or not, are kept. `copy_sign` aborts unless both
operands have the same format and encoding.

## Trait implementations

### `Zero`, `One`, `Ring` and the operator traits

`Decimal` implements the Luna-Flow algebra traits through the plain
operators.

```mbti
pub impl @luna-generic.Zero for Decimal
pub impl @luna-generic.One for Decimal
pub impl @luna-generic.AddMonoid for Decimal
pub impl @luna-generic.MulMonoid for Decimal
pub impl @luna-generic.AddGroup for Decimal
pub impl @luna-generic.Semiring for Decimal
pub impl @luna-generic.Ring for Decimal
pub impl @luna-generic.FromNat for Decimal
pub impl @luna-generic.FromInteger for Decimal
pub impl Add for Decimal
pub impl Sub for Decimal
pub impl Mul for Decimal
pub impl Div for Decimal
pub impl Neg for Decimal
pub impl Eq for Decimal
pub impl Compare for Decimal
```

`Zero::zero()` and `One::one()` are `Decimal::zero()` and `Decimal::one()`.
The ring laws hold exactly for `+`, `-` and `*` as long as no sum is rounded
(sums whose exact coefficient fits the operand precision, and every
product, since `*` is exact); a rounded sum is only approximately associative.
`FromNat` and `FromInteger` are documented under
[construction](#the-fromnat-and-frominteger-implementations).

### `@def.Floating`

`Decimal` implements the `floating` scalar trait.

```mbti
pub impl @def.Floating for Decimal
```

The trait methods are `classify`, `sign`, `precision`, `with_precision` and
`normalized`, all documented above; `@def.is_finite(x)` and the other generic
predicates work through it.

### `Decimal::add_contextual`, `sub_contextual`, `mul_contextual`, `div_contextual`, `abs_contextual`, `sqrt_contextual`, `exp_contextual`, `zero_contextual`, `one_contextual`, `epsilon_contextual`, `min_normal_contextual`, `max_finite_contextual`, `classify_contextual`

These functions implement the contextual traits of
[`Luna-Flow/arithmetic`](https://lunaflow.cn/en/arithmetic/).

```mbti
pub fn Decimal::add_contextual(Self, Self, @arithmetic.ArithmeticContext) -> Result[@arithmetic.ArithmeticOutcome[Self], @arithmetic.ArithmeticError]
pub fn Decimal::sub_contextual(Self, Self, @arithmetic.ArithmeticContext) -> Result[@arithmetic.ArithmeticOutcome[Self], @arithmetic.ArithmeticError]
pub fn Decimal::mul_contextual(Self, Self, @arithmetic.ArithmeticContext) -> Result[@arithmetic.ArithmeticOutcome[Self], @arithmetic.ArithmeticError]
pub fn Decimal::div_contextual(Self, Self, @arithmetic.ArithmeticContext) -> Result[@arithmetic.ArithmeticOutcome[Self], @arithmetic.ArithmeticError]
pub fn Decimal::abs_contextual(Self, @arithmetic.ArithmeticContext) -> Result[@arithmetic.ArithmeticOutcome[Self], @arithmetic.ArithmeticError]
pub fn Decimal::sqrt_contextual(Self, @arithmetic.ArithmeticContext) -> Result[@arithmetic.ArithmeticOutcome[Self], @arithmetic.ArithmeticError]
pub fn Decimal::exp_contextual(Self, @arithmetic.ArithmeticContext) -> Result[@arithmetic.ArithmeticOutcome[Self], @arithmetic.ArithmeticError]
pub fn Decimal::zero_contextual(@arithmetic.ArithmeticContext) -> Self
pub fn Decimal::one_contextual(@arithmetic.ArithmeticContext) -> Self
pub fn Decimal::epsilon_contextual(@arithmetic.ArithmeticContext) -> Self
pub fn Decimal::min_normal_contextual(@arithmetic.ArithmeticContext) -> Self
pub fn Decimal::max_finite_contextual(@arithmetic.ArithmeticContext) -> Self
pub fn Decimal::classify_contextual(Self) -> @arithmetic.FpClass
pub impl @arithmetic.AddContextual for Decimal
pub impl @arithmetic.SubContextual for Decimal
pub impl @arithmetic.MulContextual for Decimal
pub impl @arithmetic.DivContextual for Decimal
pub impl @arithmetic.AbsContextual for Decimal
pub impl @arithmetic.SqrtContextual for Decimal
pub impl @arithmetic.ExpContextual for Decimal
pub impl @arithmetic.NumericFormatContextual for Decimal
```

Each `*_contextual` operation converts the context with
`DecimalContext::from_arithmetic_context`, runs the matching `*_ctx`
operation and returns `Err(division_by_zero)` when `division_by_zero` was
raised, `Err(domain_error)` when another `has_error` flag was raised, and
otherwise `Ok` with diagnostics `inexact`, `overflow` and
`underflow` copied from the flags. Because the
converted context has the default exponent range, which the certified functions
accept for precisions up to 999, `exp_contextual` works at the default range; an
explicit `e_max` above 999,999 fails with `certification_failure` (`not_computed`). A result with `invalid_operation` is a `domain_error`; one with `not_computed` is a `certification_failure`; the `try_` forms return `Err` only for the second kind.

`zero_contextual` and `one_contextual` have the context precision.
`epsilon_contextual` is $10^{1-p}$ (`next_up_ctx(1) - 1`).
`min_normal_contextual` is $10^{e_{\min}}$ (default $e_{\min} = -999\,999\,999$).
`max_finite_contextual` is $(10^{p}-1)\,10^{e_{\max}-p+1}$.
`classify_contextual` is `classify`.

### `Decimal::parse_checked`, `sqrt_checked`, `pow_nat_checked`, `pow_int_checked`

These functions implement the checked traits of `Luna-Flow/arithmetic`.

```mbti
pub fn Decimal::parse_checked(String, @arithmetic.ArithmeticContext) -> Result[Self, @arithmetic.ArithmeticError]
pub fn Decimal::sqrt_checked(Self, @arithmetic.ArithmeticContext) -> Result[Self, @arithmetic.ArithmeticError]
pub fn Decimal::pow_nat_checked(Self, UInt, @arithmetic.ArithmeticContext) -> Result[Self, @arithmetic.ArithmeticError]
pub fn Decimal::pow_int_checked(Self, Int, @arithmetic.ArithmeticContext) -> Result[Self, @arithmetic.ArithmeticError]
pub impl @arithmetic.ParseChecked for Decimal
pub impl @arithmetic.DivChecked for Decimal
pub impl @arithmetic.CompareChecked for Decimal
pub impl @arithmetic.SqrtChecked for Decimal
pub impl @arithmetic.PowNatChecked for Decimal
pub impl @arithmetic.PowIntChecked for Decimal
```

`parse_checked(s, ctx)` converts `ctx` to `DecimalContext` and uses
`Decimal::from_string_ctx`, so the context's precision, rounding direction,
exponent range applies. It returns the converted value; flags
such as overflow remain available from `from_string_ctx`. Invalid syntax
returns `Err(parse_error)`. `DivChecked::div_checked(x, y, ctx)` is `div_ctx`
under the converted context with `Err(division_by_zero)` and
`Err(domain_error)` as in [`div_checked`](#decimaldiv_checked-sqrt).
`sqrt_checked` is `sqrt_ctx` under the converted context and fails for
negative operands. `pow_nat_checked` and `pow_int_checked` call `pow_ctx`
with the integer exponent converted exactly (with at least ten digits, which
hold every accepted exponent), so at precision 7
`(-1).pow_int_checked(12345679, ctx)` is `-1`. They return `Ok(1)` for a zero
or quiet-NaN base with exponent zero, `Err(division_by_zero)` for a zero base with
a negative exponent, and `Err(domain_error)` for an
invalid result such as a signaling NaN operand. `pow_nat_checked` returns `Err(unsupported)` for exponents
above 999,999,999. `CompareChecked` is
[`compare_checked`](#decimalcompare_checked).

### `Eq` and `Compare`: `Decimal::equal`, `not_equal`, `op_lt`, `op_le`, `op_gt`, `op_ge`

These are the operator methods of `Eq` and `Compare`.

```mbti
pub fn Decimal::equal(Self, Self) -> Bool
pub fn Decimal::not_equal(Self, Self) -> Bool
pub fn Decimal::op_lt(Self, Self) -> Bool
pub fn Decimal::op_le(Self, Self) -> Bool
pub fn Decimal::op_gt(Self, Self) -> Bool
pub fn Decimal::op_ge(Self, Self) -> Bool
```

They are defined by [`compare`](#decimalcompare): `x == y` is
`compare(x, y) == 0`, `x < y` is `compare(x, y) < 0`, and so on. Cohort
members are equal (`1.0 == 1.00`), $-0 = +0$, every NaN equals every NaN and
is greater than every number. Use `total_order_compare` to tell representations
apart.

### Derived equality: `DecimalContext::equal`, `DecimalContext::not_equal`, `DecimalFlags::equal`, `DecimalFlags::not_equal`, `DecimalRoundingMode::equal`, `DecimalRoundingMode::not_equal`, `DecimalSignal::equal`, `DecimalSignal::not_equal`, `DecimalInterchangeFormat::equal`, `DecimalInterchangeFormat::not_equal`, `DecimalInterchangeEncoding::equal`, `DecimalInterchangeEncoding::not_equal`

These are the derived `Eq` methods of the context, flag and enum types.

```mbti
pub fn DecimalContext::equal(Self, Self) -> Bool
pub fn DecimalContext::not_equal(Self, Self) -> Bool
pub fn DecimalFlags::equal(Self, Self) -> Bool
pub fn DecimalFlags::not_equal(Self, Self) -> Bool
pub fn DecimalRoundingMode::equal(Self, Self) -> Bool
pub fn DecimalRoundingMode::not_equal(Self, Self) -> Bool
pub fn DecimalSignal::equal(Self, Self) -> Bool
pub fn DecimalSignal::not_equal(Self, Self) -> Bool
pub fn DecimalInterchangeFormat::equal(Self, Self) -> Bool
pub fn DecimalInterchangeFormat::not_equal(Self, Self) -> Bool
pub fn DecimalInterchangeEncoding::equal(Self, Self) -> Bool
pub fn DecimalInterchangeEncoding::not_equal(Self, Self) -> Bool
```

Contexts compare field by field (precision, rounding, exponent
limits, refinement limit); flag sets compare all thirteen fields.
`DecimalContext::from_arithmetic_context(ArithmeticContext::decimal64())` is
equal to `DecimalContext::decimal64()`.

### `Show` and `Debug`: `Decimal::to_string`, `output`, `to_repr`

`Decimal` implements `Show` and `Debug`.

```mbti
pub impl Show for Decimal
pub fn Decimal::to_string(Self) -> String
pub fn Decimal::output(Self, &Logger) -> Unit
pub fn Decimal::to_repr(Self) -> @debug.Repr
```

`to_string` formats a value in scientific notation without a context. Finite
values use the scientific-string rule of
[`to_sci_string`](#decimalto_sci_string-to_eng_string), so trailing zeros and
the exponent are visible: `1.20`, `1E+3`, `1.2E-7`. Special values are written
in lower case: `inf`, `-inf`, `nan`, `snan`, `-nan12`. `output` writes the same
text to a logger. `to_repr` is the derived structural representation used by
`debug_inspect` and `assert_eq`.

```moonbit
///|
test "decimal to_string" {
  let d = fn(s : String) { @decimal.Decimal::from_string(s).unwrap() }
  inspect(d("123E+2"), content="1.23E+4")
  inspect(d("0.0000001"), content="1E-7")
  inspect(d("-0.00"), content="-0.00")
  inspect(d("-sNaN7"), content="-snan7")
}
```

## Complete public interface

This snapshot is the generated `pkg.generated.mbti` of the package. It is the authority when prose and interface disagree.

<!-- generated-api-start -->
```mbti
// Generated using `moon info`, DON'T EDIT IT
package "Luna-Flow/floating/decimal"

import {
  "Luna-Flow/arithmetic",
  "Luna-Flow/floating/bin_float",
  "Luna-Flow/floating/def",
  "Luna-Flow/luna-generic",
  "moonbitlang/core/bigint",
  "moonbitlang/core/debug",
}

// Values
pub let decimal_implementation_e_max : Int32

pub let decimal_implementation_e_min : Int32

pub let decimal_precision_max : Int32

pub let decimal_value_e_max : Int32

pub let decimal_value_e_tiny : Int32

// Errors

// Types and methods
#derive(@debug.Debug)
pub struct Decimal {
  // private fields
}
pub fn Decimal::abs(Self) -> Self
pub fn Decimal::abs_contextual(Self, @arithmetic.ArithmeticContext) -> Result[@arithmetic.ArithmeticOutcome[Self], @arithmetic.ArithmeticError]
pub fn Decimal::abs_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::acos_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::acosh_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::acospi_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::add(Self, Self) -> Self
pub fn Decimal::add_contextual(Self, Self, @arithmetic.ArithmeticContext) -> Result[@arithmetic.ArithmeticOutcome[Self], @arithmetic.ArithmeticError]
pub fn Decimal::add_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::apply_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::asin_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::asinh_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::asinpi_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::atan2_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::atan2pi_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::atan_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::atanh_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::atanpi_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::clamp(Self, min~ : Self, max~ : Self) -> Self
pub fn Decimal::clamp_checked(Self, min~ : Self, max~ : Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn Decimal::class_of(Self, DecimalContext) -> @def.IeeeClass
pub fn Decimal::classify(Self) -> @arithmetic.FpClass
pub fn Decimal::classify_contextual(Self) -> @arithmetic.FpClass
pub fn Decimal::coefficient(Self) -> @bigint.BigInt
pub fn Decimal::compare(Self, Self) -> Int32
pub fn Decimal::compare_checked(Self, Self) -> Result[Int32, @arithmetic.ArithmeticError]
pub fn Decimal::compare_quiet(Self, Self) -> (@def.PartialOrder, DecimalFlags)
pub fn Decimal::compare_quiet_equal(Self, Self) -> (Bool, DecimalFlags)
pub fn Decimal::compare_quiet_greater(Self, Self) -> (Bool, DecimalFlags)
pub fn Decimal::compare_quiet_greater_equal(Self, Self) -> (Bool, DecimalFlags)
pub fn Decimal::compare_quiet_greater_unordered(Self, Self) -> (Bool, DecimalFlags)
pub fn Decimal::compare_quiet_less(Self, Self) -> (Bool, DecimalFlags)
pub fn Decimal::compare_quiet_less_equal(Self, Self) -> (Bool, DecimalFlags)
pub fn Decimal::compare_quiet_less_unordered(Self, Self) -> (Bool, DecimalFlags)
pub fn Decimal::compare_quiet_not_equal(Self, Self) -> (Bool, DecimalFlags)
pub fn Decimal::compare_quiet_not_greater(Self, Self) -> (Bool, DecimalFlags)
pub fn Decimal::compare_quiet_not_less(Self, Self) -> (Bool, DecimalFlags)
pub fn Decimal::compare_quiet_ordered(Self, Self) -> (Bool, DecimalFlags)
pub fn Decimal::compare_quiet_unordered(Self, Self) -> (Bool, DecimalFlags)
pub fn Decimal::compare_signaling(Self, Self) -> (@def.PartialOrder, DecimalFlags)
pub fn Decimal::compare_signaling_equal(Self, Self) -> (Bool, DecimalFlags)
pub fn Decimal::compare_signaling_greater(Self, Self) -> (Bool, DecimalFlags)
pub fn Decimal::compare_signaling_greater_equal(Self, Self) -> (Bool, DecimalFlags)
pub fn Decimal::compare_signaling_greater_unordered(Self, Self) -> (Bool, DecimalFlags)
pub fn Decimal::compare_signaling_less(Self, Self) -> (Bool, DecimalFlags)
pub fn Decimal::compare_signaling_less_equal(Self, Self) -> (Bool, DecimalFlags)
pub fn Decimal::compare_signaling_less_unordered(Self, Self) -> (Bool, DecimalFlags)
pub fn Decimal::compare_signaling_not_equal(Self, Self) -> (Bool, DecimalFlags)
pub fn Decimal::compare_signaling_not_greater(Self, Self) -> (Bool, DecimalFlags)
pub fn Decimal::compare_signaling_not_less(Self, Self) -> (Bool, DecimalFlags)
pub fn Decimal::compound_ctx(Self, Int32, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::convert_format(Self, DecimalInterchangeFormat) -> (Self, DecimalFlags)
pub fn Decimal::copy(Self) -> Self
pub fn Decimal::copy_sign(Self, Self) -> Self
pub fn Decimal::cos_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::cosh_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::cospi_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::div(Self, Self) -> Self
pub fn Decimal::div_checked(Self, Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn Decimal::div_contextual(Self, Self, @arithmetic.ArithmeticContext) -> Result[@arithmetic.ArithmeticOutcome[Self], @arithmetic.ArithmeticError]
pub fn Decimal::div_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::epsilon_contextual(@arithmetic.ArithmeticContext) -> Self
pub fn Decimal::equal(Self, Self) -> Bool
pub fn Decimal::exp10_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::exp10m1_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::exp2_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::exp2m1_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::exp_contextual(Self, @arithmetic.ArithmeticContext) -> Result[@arithmetic.ArithmeticOutcome[Self], @arithmetic.ArithmeticError]
pub fn Decimal::exp_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::expm1_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::exponent10(Self) -> Int32
pub fn Decimal::fma_ctx(Self, Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::from_bigint(@bigint.BigInt, precision? : Int32) -> Self
pub fn Decimal::from_bin_float(@bin_float.BinFloat, precision~ : Int32, mode? : DecimalRoundingMode) -> Self
pub fn Decimal::from_bin_float_ctx(@bin_float.BinFloat, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::from_double(Double, precision? : Int32) -> Self
pub fn Decimal::from_float(Float, precision? : Int32) -> Self
pub fn Decimal::from_int(Int32, precision? : Int32) -> Self
pub fn Decimal::from_interchange_hex(String, DecimalInterchangeFormat) -> Result[Self, @arithmetic.ArithmeticError]
pub fn Decimal::from_interchange_hex_with_encoding(String, DecimalInterchangeFormat, DecimalInterchangeEncoding) -> Result[Self, @arithmetic.ArithmeticError]
pub fn Decimal::from_string(String, precision? : Int32) -> Result[Self, @arithmetic.ArithmeticError]
pub fn Decimal::from_string_ctx(String, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::get_payload(Self) -> @bigint.BigInt
pub fn Decimal::hypot_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::identical(Self, Self) -> Bool
pub fn Decimal::inf(negative? : Bool, precision? : Int32) -> Self
pub fn Decimal::is_canonical(Self) -> Bool
pub fn Decimal::is_finite(Self) -> Bool
pub fn Decimal::is_infinite(Self) -> Bool
pub fn Decimal::is_nan(Self) -> Bool
pub fn Decimal::is_negative(Self) -> Bool
pub fn Decimal::is_negative_zero(Self) -> Bool
pub fn Decimal::is_normal(Self, DecimalContext) -> Bool
pub fn Decimal::is_quiet_nan(Self) -> Bool
pub fn Decimal::is_signaling_nan(Self) -> Bool
pub fn Decimal::is_subnormal(Self, DecimalContext) -> Bool
pub fn Decimal::is_zero(Self) -> Bool
pub fn Decimal::ln_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::log10_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::log10p1_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::log1p_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::log2_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::log2p1_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::logb_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::make(@bigint.BigInt, Int32, Int32, mode? : DecimalRoundingMode) -> Self
pub fn Decimal::max(Self, Self) -> Self
pub fn Decimal::max_finite_contextual(@arithmetic.ArithmeticContext) -> Self
pub fn Decimal::maximum_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::maximum_magnitude_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::maximum_magnitude_number_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::maximum_number_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::min(Self, Self) -> Self
pub fn Decimal::min_normal_contextual(@arithmetic.ArithmeticContext) -> Self
pub fn Decimal::minimum_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::minimum_magnitude_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::minimum_magnitude_number_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::minimum_number_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::mul(Self, Self) -> Self
pub fn Decimal::mul_contextual(Self, Self, @arithmetic.ArithmeticContext) -> Result[@arithmetic.ArithmeticOutcome[Self], @arithmetic.ArithmeticError]
pub fn Decimal::mul_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::nan(precision? : Int32) -> Self
pub fn Decimal::nan_payload(Self) -> @bigint.BigInt
pub fn Decimal::neg(Self) -> Self
pub fn Decimal::negative_zero(precision? : Int32) -> Self
pub fn Decimal::next_down_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::next_toward_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::next_up_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::normalized(Self) -> Self
pub fn Decimal::not_equal(Self, Self) -> Bool
pub fn Decimal::one(precision? : Int32) -> Self
pub fn Decimal::one_contextual(@arithmetic.ArithmeticContext) -> Self
pub fn Decimal::op_ge(Self, Self) -> Bool
pub fn Decimal::op_gt(Self, Self) -> Bool
pub fn Decimal::op_le(Self, Self) -> Bool
pub fn Decimal::op_lt(Self, Self) -> Bool
pub fn Decimal::output(Self, &Logger) -> Unit
pub fn Decimal::parse_checked(String, @arithmetic.ArithmeticContext) -> Result[Self, @arithmetic.ArithmeticError]
pub fn Decimal::pow_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::pow_int_checked(Self, Int32, @arithmetic.ArithmeticContext) -> Result[Self, @arithmetic.ArithmeticError]
pub fn Decimal::pow_nat_checked(Self, UInt32, @arithmetic.ArithmeticContext) -> Result[Self, @arithmetic.ArithmeticError]
pub fn Decimal::pown_ctx(Self, Int32, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::powr_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::precision(Self) -> Int32
pub fn Decimal::quantize_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::quantum(Self) -> Int32
pub fn Decimal::quiet_nan(payload? : @bigint.BigInt, negative? : Bool, precision? : Int32) -> Self
pub fn Decimal::remainder_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::rootn_ctx(Self, Int32, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::rsqrt_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::same_quantum(Self, Self) -> Bool
pub fn Decimal::scaleb_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::set_payload(Self, @bigint.BigInt) -> Self
pub fn Decimal::set_payload_signaling(Self, @bigint.BigInt) -> Self
pub fn Decimal::sign(Self) -> @def.Sign
pub fn Decimal::signaling_nan(payload? : @bigint.BigInt, negative? : Bool, precision? : Int32) -> Self
pub fn Decimal::sin_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::sinh_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::sinpi_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::sqrt(Self) -> Self
pub fn Decimal::sqrt_checked(Self, @arithmetic.ArithmeticContext) -> Result[Self, @arithmetic.ArithmeticError]
pub fn Decimal::sqrt_contextual(Self, @arithmetic.ArithmeticContext) -> Result[@arithmetic.ArithmeticOutcome[Self], @arithmetic.ArithmeticError]
pub fn Decimal::sqrt_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::sub(Self, Self) -> Self
pub fn Decimal::sub_contextual(Self, Self, @arithmetic.ArithmeticContext) -> Result[@arithmetic.ArithmeticOutcome[Self], @arithmetic.ArithmeticError]
pub fn Decimal::sub_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::tan_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::tanh_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::tanpi_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::to_bin_float(Self, precision~ : Int32, mode? : @bin_float.BinaryRoundingMode) -> @bin_float.BinFloat
pub fn Decimal::to_bin_float_ctx(Self, @bin_float.BinaryContext) -> (@bin_float.BinFloat, @bin_float.BinaryFlags)
pub fn Decimal::to_eng_string(Self) -> String
pub fn Decimal::to_int64_ctx(Self, DecimalContext, exact? : Bool) -> (Int64?, DecimalFlags)
pub fn Decimal::to_int_ctx(Self, DecimalContext, exact? : Bool) -> (Int32?, DecimalFlags)
pub fn Decimal::to_integral_exact_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::to_integral_value_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::to_interchange_hex(Self, DecimalInterchangeFormat) -> (String, DecimalFlags)
pub fn Decimal::to_interchange_hex_with_encoding(Self, DecimalInterchangeFormat, DecimalInterchangeEncoding) -> (String, DecimalFlags)
pub fn Decimal::to_repr(Self) -> @debug.Repr
pub fn Decimal::to_sci_string(Self) -> String
pub fn Decimal::to_string(Self) -> String
pub fn Decimal::to_uint64_ctx(Self, DecimalContext, exact? : Bool) -> (UInt64?, DecimalFlags)
pub fn Decimal::to_uint_ctx(Self, DecimalContext, exact? : Bool) -> (UInt32?, DecimalFlags)
pub fn Decimal::total_order(Self, Self) -> Bool
pub fn Decimal::total_order_compare(Self, Self) -> Int32
pub fn Decimal::total_order_mag(Self, Self) -> Bool
pub fn Decimal::try_acos_ctx(Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::try_acosh_ctx(Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::try_acospi_ctx(Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::try_asin_ctx(Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::try_asinh_ctx(Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::try_asinpi_ctx(Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::try_atan2_ctx(Self, Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::try_atan2pi_ctx(Self, Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::try_atan_ctx(Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::try_atanh_ctx(Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::try_atanpi_ctx(Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::try_compound_ctx(Self, Int32, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::try_cos_ctx(Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::try_cosh_ctx(Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::try_cospi_ctx(Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::try_exp10_ctx(Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::try_exp10m1_ctx(Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::try_exp2_ctx(Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::try_exp2m1_ctx(Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::try_exp_ctx(Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::try_expm1_ctx(Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::try_hypot_ctx(Self, Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::try_ln_ctx(Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::try_log10_ctx(Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::try_log10p1_ctx(Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::try_log1p_ctx(Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::try_log2_ctx(Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::try_log2p1_ctx(Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::try_make(@bigint.BigInt, Int32, Int32, mode? : DecimalRoundingMode) -> Result[Self, @arithmetic.ArithmeticError]
pub fn Decimal::try_pow_ctx(Self, Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::try_pown_ctx(Self, Int32, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::try_powr_ctx(Self, Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::try_rootn_ctx(Self, Int32, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::try_rsqrt_ctx(Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::try_sin_ctx(Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::try_sinh_ctx(Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::try_sinpi_ctx(Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::try_tan_ctx(Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::try_tanh_ctx(Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::try_tanpi_ctx(Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::with_precision(Self, Int32, DecimalRoundingMode) -> Self
pub fn Decimal::zero(precision? : Int32) -> Self
pub fn Decimal::zero_contextual(@arithmetic.ArithmeticContext) -> Self
pub impl @arithmetic.AbsContextual for Decimal
pub impl @arithmetic.AddContextual for Decimal
pub impl @arithmetic.CompareChecked for Decimal
pub impl @arithmetic.DivChecked for Decimal
pub impl @arithmetic.DivContextual for Decimal
pub impl @arithmetic.ExpContextual for Decimal
pub impl @arithmetic.MulContextual for Decimal
pub impl @arithmetic.NumericFormatContextual for Decimal
pub impl @arithmetic.ParseChecked for Decimal
pub impl @arithmetic.PowIntChecked for Decimal
pub impl @arithmetic.PowNatChecked for Decimal
pub impl @arithmetic.SqrtChecked for Decimal
pub impl @arithmetic.SqrtContextual for Decimal
pub impl @arithmetic.SubContextual for Decimal
pub impl @def.Floating for Decimal
pub impl @luna-generic.AddGroup for Decimal
pub impl @luna-generic.AddMonoid for Decimal
pub impl @luna-generic.FromInteger for Decimal
pub impl @luna-generic.FromNat for Decimal
pub impl @luna-generic.MulMonoid for Decimal
pub impl @luna-generic.One for Decimal
pub impl @luna-generic.Ring for Decimal
pub impl @luna-generic.Semiring for Decimal
pub impl @luna-generic.Zero for Decimal
pub impl Add for Decimal
pub impl Compare for Decimal
pub impl Div for Decimal
pub impl Eq for Decimal
pub impl Mul for Decimal
pub impl Neg for Decimal
pub impl Show for Decimal
pub impl Sub for Decimal

#derive(Eq)
pub struct DecimalContext {
  // private fields
}
pub fn DecimalContext::decimal128(rounding? : DecimalRoundingMode) -> Self
pub fn DecimalContext::decimal32(rounding? : DecimalRoundingMode) -> Self
pub fn DecimalContext::decimal64(rounding? : DecimalRoundingMode) -> Self
pub fn DecimalContext::e_max(Self) -> Int32
pub fn DecimalContext::e_min(Self) -> Int32
pub fn DecimalContext::equal(Self, Self) -> Bool
pub fn DecimalContext::from_arithmetic_context(@arithmetic.ArithmeticContext) -> Result[Self, @arithmetic.ArithmeticError]
pub fn DecimalContext::new(precision? : Int32, e_max? : Int32, rounding? : DecimalRoundingMode) -> Self
pub fn DecimalContext::not_equal(Self, Self) -> Bool
pub fn DecimalContext::precision(Self) -> Int32
pub fn DecimalContext::refinement_limit(Self) -> Int32?
pub fn DecimalContext::rounding(Self) -> DecimalRoundingMode
pub fn DecimalContext::try_new(precision? : Int32, e_max? : Int32, rounding? : DecimalRoundingMode) -> Result[Self, @arithmetic.ArithmeticError]
pub fn DecimalContext::with_e_max(Self, Int32) -> Self
pub fn DecimalContext::with_precision(Self, Int32) -> Self
pub fn DecimalContext::with_refinement_limit(Self, Int32?) -> Self
pub fn DecimalContext::with_rounding(Self, DecimalRoundingMode) -> Self

#derive(Eq)
pub struct DecimalFlags {
  // private fields
}
pub fn DecimalFlags::combine(Self, Self) -> Self
pub fn DecimalFlags::division_by_zero(Self) -> Bool
pub fn DecimalFlags::equal(Self, Self) -> Bool
pub fn DecimalFlags::has_error(Self) -> Bool
pub fn DecimalFlags::inexact(Self) -> Bool
pub fn DecimalFlags::invalid_operation(Self) -> Bool
pub fn DecimalFlags::new() -> Self
pub fn DecimalFlags::not_computed(Self) -> Bool
pub fn DecimalFlags::not_equal(Self, Self) -> Bool
pub fn DecimalFlags::overflow(Self) -> Bool
pub fn DecimalFlags::underflow(Self) -> Bool

pub struct DecimalInterchange {
  // private fields
}
pub fn DecimalInterchange::canonical(Self) -> Self
pub fn DecimalInterchange::copy(Self) -> Self
pub fn DecimalInterchange::copy_abs(Self) -> Self
pub fn DecimalInterchange::copy_negate(Self) -> Self
pub fn DecimalInterchange::copy_sign(Self, Self) -> Self
pub fn DecimalInterchange::encoding(Self) -> DecimalInterchangeEncoding
pub fn DecimalInterchange::format(Self) -> DecimalInterchangeFormat
pub fn DecimalInterchange::from_decimal(Decimal, DecimalInterchangeFormat) -> (Self, DecimalFlags)
pub fn DecimalInterchange::from_decimal_with_encoding(Decimal, DecimalInterchangeFormat, DecimalInterchangeEncoding) -> (Self, DecimalFlags)
pub fn DecimalInterchange::from_hex(String, DecimalInterchangeFormat) -> Result[Self, @arithmetic.ArithmeticError]
pub fn DecimalInterchange::from_hex_with_encoding(String, DecimalInterchangeFormat, DecimalInterchangeEncoding) -> Result[Self, @arithmetic.ArithmeticError]
pub fn DecimalInterchange::is_canonical(Self) -> Bool
pub fn DecimalInterchange::to_decimal(Self) -> Decimal
pub fn DecimalInterchange::to_decimal_ctx(Self) -> (Decimal, DecimalFlags)
pub fn DecimalInterchange::to_hex(Self) -> String

#derive(Eq)
pub(all) enum DecimalInterchangeEncoding {
  DPD
  BID
}
pub fn DecimalInterchangeEncoding::equal(Self, Self) -> Bool
pub fn DecimalInterchangeEncoding::not_equal(Self, Self) -> Bool

#derive(Eq)
pub(all) enum DecimalInterchangeFormat {
  Decimal32
  Decimal64
  Decimal128
}
pub fn DecimalInterchangeFormat::context(Self) -> DecimalContext
pub fn DecimalInterchangeFormat::equal(Self, Self) -> Bool
pub fn DecimalInterchangeFormat::not_equal(Self, Self) -> Bool

#derive(Eq)
pub(all) enum DecimalRoundingMode {
  RoundTiesToEven
  RoundTiesToAway
  RoundTowardZero
  RoundTowardPositive
  RoundTowardNegative
}
pub fn DecimalRoundingMode::equal(Self, Self) -> Bool
pub fn DecimalRoundingMode::from_arithmetic(@arithmetic.RoundingMode) -> Self?
pub fn DecimalRoundingMode::not_equal(Self, Self) -> Bool
pub fn DecimalRoundingMode::to_arithmetic(Self) -> @arithmetic.RoundingMode?

// Type aliases

// Traits
```
<!-- generated-api-end -->
