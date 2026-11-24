# decimal API

## Purpose

The `Luna-Flow/floating/decimal` package in `floating` implements IEEE 754-2019
decimal floating-point arithmetic. A `Decimal` stores an arbitrary-precision value, its exponent $q$,
the sign of zero and any NaN payload. For a finite value, its quantum is
$10^q$, the unit in its last digit position (IEEE 754-2019 2.1). A
`DecimalContext` is an IEEE 754-2019 format with a precision, an exponent range
and one rounding-direction attribute. Each context operation returns the
rounded result and the `DecimalFlags` it raised. The package also encodes and
decodes the decimal32, decimal64 and decimal128 interchange formats in DPD and
BID, and evaluates elementary functions with certified rounding.

Use the [decimal tutorial](../tutorial/decimal.md) for common tasks. The
[decimal design](../design/decimal.md) explains the arithmetic model, encodings,
rounding and certification; [decimal conformance](../conformance/decimal.md)
records the finite evidence for the IEEE claim. The separate
[`decimal_gda`](decimal_gda.md) package provides General Decimal Arithmetic
status that accumulates across operations and trap handling.
[`decimal_checked`](decimal_checked.md) accumulates flags across a pipeline of
`Decimal` operations.

## Importing

Add the package to your `moon.pkg`:

```moonbit nocheck
import {
  "Luna-Flow/floating/decimal",
}
```

The examples refer to this package as `@decimal.`. Some also use `@def.` for
`Luna-Flow/floating/def` (the shared `RoundingMode` and `Sign`), `@lf_arith.`
for `Luna-Flow/arithmetic`, `@lf_alg.` for `Luna-Flow/luna-generic`, and
`@bigint.` for `moonbitlang/core/bigint`; import any of these packages used by
an example you copy. Most examples build values with the helper `d(s)`, defined as
`@decimal.Decimal::from_string(s).unwrap()`.

## Notation

For a finite value, $(-1)^s \cdot c \cdot 10^q$ denotes its value, where $s$
is its sign, $c$ its non-negative integer coefficient and $q$ its exponent.
The quantum is $10^q$, the unit in the last digit position (IEEE 754-2019
2.1). The context precision is $p$; its exponent limits
$e_{\min}$ and $e_{\max}$ bound the adjusted exponent
$\hat q = q + \operatorname{digits}(c) - 1$. The smallest exponent of a
subnormal is $E_{\text{tiny}} = e_{\min} - p + 1$.

## Values and representation

### `Decimal`

`Decimal` is an immutable decimal floating-point value.

```mbti
pub struct Decimal {
  // private fields
} derive(@debug.Debug)
```

A `Decimal` represents a finite value $(-1)^s c\,10^q$ (including $\pm 0$),
$\pm\infty$, or a quiet or signaling NaN with a sign and a non-negative integer
payload. Each value also carries the precision of the value: the precision of a
format a context could have, in `1..=999999999` (`decimal_precision_max`). The
plain operators and conversions without a context argument use it. The fields
are private; use the observers below. Values with the same mathematical value
but different exponents, such as `1.2` and `1.20`, are members of the same
*cohort*. Numeric comparison treats them as equal. Their different exponents are
observable through `quantum`, `same_quantum`, `total_order_compare`, formatting
and interchange encoding.

The derived `Debug` implementation is promoted as `Decimal::to_repr`; see
[Trait implementations](#trait-implementations).

### `Decimal::precision`, `coefficient`, `exponent10`, `quantum`

Return parts of the stored representation of a value.

```mbti
pub fn Decimal::precision(Self) -> Int32
pub fn Decimal::coefficient(Self) -> @bigint.BigInt
pub fn Decimal::exponent10(Self) -> Int32
```

`precision` returns the precision of the value. A constructor returning a
`Decimal` aborts on a precision outside `1..=999999999` and names the function;
an operation returning `Result` returns `Err`.

`coefficient` returns the non-negative coefficient $c$, the payload for a NaN,
or `0` for an infinity. The sign is not part of the coefficient; read it with
`is_sign_minus`. `exponent10` returns the stored exponent $q$, or `0` for a
special value. IEEE 754-2019's `quantum` operation is `quantum_ctx` below; it is
not an accessor.

```moonbit
///|
test "decimal representation observers" {
  let x = @decimal.Decimal::from_string("-12.300").unwrap()
  inspect(x.coefficient(), content="12300")
  inspect(x.exponent10(), content="-3")
  inspect(x.is_sign_minus(), content="true")
  inspect(x.precision(), content="34")
}
```

### `Decimal::signum`, `is_sign_minus`

`signum` reports the sign classification; `is_sign_minus` reports the stored
sign bit.

```mbti
pub fn Decimal::signum(Self) -> @def.Sign
pub fn Decimal::is_sign_minus(Self) -> Bool
```

`signum` returns `@def.Sign::Zero` for both zeros and every NaN, and
`Negative` or `Positive` otherwise. `is_sign_minus` returns `true` for $-0$,
$-\infty$ and a negative NaN.

### `Decimal::classify`, `class_of`

`classify` returns the coarse class of a value. `class_of` returns one of the
ten classes defined by IEEE 754-2019 5.7.2, using a context.

```mbti
pub fn Decimal::classify(Self) -> @arithmetic.FpClass
pub fn Decimal::class_of(Self, DecimalContext) -> @def.IeeeClass
```

`classify` returns `Finite`, `Infinity` or `NaN`. `class_of` returns one of the
ten [`IeeeClass`](def.md#ieeeclass) values. The context's $e_{\min}$ determines
whether a finite nonzero value is normal or subnormal. `IeeeClass` has no text
form; use `match` on its value.

### `Decimal::is_finite`, `is_infinite`, `is_nan`, `is_zero`, `is_negative_zero`, `is_quiet_nan`, `is_signaling_nan`, `is_canonical`, `is_normal`, `is_subnormal`

Test a value's class with these predicates.

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

`is_canonical` returns `true` for every value. A `Decimal` has no
non-canonical form; non-canonical *encodings* belong to
[`DecimalInterchange`](#decimalinterchange-decimalinterchangeformat-encoding-to_hex).

Under a context, a finite nonzero value is normal when its adjusted exponent is
at least $e_{\min}$, and subnormal when its adjusted exponent is below
$e_{\min}$. Zeros, infinities and NaNs are neither.

### `Decimal::nan_payload`, `get_payload`, `set_payload`, `set_payload_signaling`

Read or replace a NaN's payload with these functions.

```mbti
pub fn Decimal::nan_payload(Self) -> @bigint.BigInt
pub fn Decimal::get_payload(Self) -> @bigint.BigInt
pub fn Decimal::set_payload(Self, @bigint.BigInt) -> Self
pub fn Decimal::set_payload_signaling(Self, @bigint.BigInt) -> Self
```

`nan_payload` returns the payload for a NaN and `0` for any other value.
`get_payload` implements getPayload of IEEE 754-2019 9.7: it returns the NaN
payload, or `-1` for a non-NaN.

`set_payload` and `set_payload_signaling` implement setPayload and
setPayloadSignaling of IEEE 754-2019 9.7. If the argument is a non-negative
integer with at most `precision - 1` digits, the result is a quiet or signaling
NaN, respectively, with that payload and the receiver's sign bit. This limit
uses the receiver's `precision`, like the trailing significand of an
interchange NaN. Otherwise the result is `+0` with exponent 0. The receiver
need not be a NaN.

## Construction and conversion

### `decimal_value_e_max`, `decimal_value_e_tiny`

These constants give the implementation limits on the exponents of stored finite
values.

```mbti
pub let decimal_value_e_max : Int
pub let decimal_value_e_tiny : Int
```

A finite `Decimal` can have an exponent no smaller than
`decimal_value_e_tiny` ($-2\,147\,483\,645$), and an adjusted exponent no larger
than `decimal_value_e_max` ($2\,147\,483\,646$). Its adjusted exponent is
$q + \operatorname{digits}(c) - 1$. A zero has one digit in this calculation.

These are the `e_max` and `etiny` of the private working context used by the
plain operators. They are the largest and smallest values allowed by the
32-bit exponent field once `e_max`, `e_min` and `etiny = e_min - p + 1` must
also be representable. This range lets `x + 0 == x`, `x - 0 == x` and
`x * 1 == x` hold for every stored value.

Exact constructors (`make`, `try_make`, `parse`, `from_string`) refuse values
outside these implementation limits. Constructors from integers and
floating-point inputs cannot produce such a value. Operations that round (the
plain operators and `with_precision`) overflow to infinity or the largest finite
value in the rounding direction, or underflow to the smallest exponent, as a
context result does.

These are not context limits. Context limits are narrower, so a value outside
every context range can still be stored and is rounded when a context operation
reads it. The context limits are
[`decimal_context_e_max_limit`](#decimal_context_e_max_limit-decimal_context_e_min_limit-decimal_precision_max)
and its related parameters.

### `Decimal::make`, `try_make`

`make` builds a finite value from a signed integer coefficient and an exponent,
rounding it to a precision. `try_make` returns the same result through
`Result`.

```mbti
pub fn Decimal::make(@bigint.BigInt, Int, Int, mode? : DecimalRoundingMode) -> Self
pub fn Decimal::try_make(@bigint.BigInt, Int, Int, mode? : DecimalRoundingMode) -> Result[Self, @arithmetic.ArithmeticError]
```

`Decimal::make(c, q, p, mode~)` represents $c \cdot 10^q$, with the sign taken
from `c`.

| Coefficient length | Result |
| --- | --- |
| At most $p$ digits | Keeps exponent $q$ and is not reduced: `make(100, 0, 5)` is `100`; `make(0, 5, 5)` is `0E+5`. |
| More than $p$ digits | Rounds to exactly $p$ digits with `mode` (default `RoundTiesToEven`) and is not reduced: `make(1000000, 0, 3)` is `100E+4`. |

No context exponent range applies. After rounding, the value must satisfy the
[implementation limits on stored values](#decimal_value_e_max-decimal_value_e_tiny). `make` aborts with a
message naming the exponent and both limits; `try_make` returns a domain error.
Both also reject $p$ outside `1..=999999999`.

### `Decimal::zero`, `negative_zero`, `one`, `inf`, `nan`, `quiet_nan`, `signaling_nan`

Construct zeros, one, infinities and NaNs.

```mbti
pub fn Decimal::zero(precision? : Int) -> Self
pub fn Decimal::negative_zero(precision? : Int) -> Self
pub fn Decimal::one(precision? : Int) -> Self
pub fn Decimal::inf(negative? : Bool, precision? : Int) -> Self
pub fn Decimal::nan(precision? : Int) -> Self
pub fn Decimal::quiet_nan(payload? : @bigint.BigInt, negative? : Bool, precision? : Int) -> Self
pub fn Decimal::signaling_nan(payload? : @bigint.BigInt, negative? : Bool, precision? : Int) -> Self
```

The default precision is 34. `zero`, `negative_zero` and `one` use exponent
`0`. `inf(negative=true)` returns $-\infty$; `inf()` returns $+\infty$.
`nan` returns a positive quiet NaN with payload 0. `quiet_nan` and
`signaling_nan` default to payload 0 and a positive sign.

The payload is the trailing significand field (IEEE 754-2019 3.5.2). It must
be a non-negative integer with at most `precision - 1` digits; otherwise the
constructor aborts. Construction does not truncate a payload, while conversion
to a narrower format keeps its low digits. The precision must be within
`1..=999999999`.

### `Decimal::from_int`, `from_bigint`

Convert an integer to a `Decimal`.

```mbti
pub fn Decimal::from_int(Int, precision? : Int) -> Self
pub fn Decimal::from_bigint(@bigint.BigInt, precision? : Int) -> Self
```

Both implement convertFromInt (IEEE 754-2019 5.4.1) with preferred exponent 0
and default precision 34. An integer with at most `precision` digits keeps
exponent 0: `from_int(1000)` returns `1000`, not the reduced `1E+3`. A longer
integer is rounded half-even to exactly `precision` digits (IEEE 754-2019 5.2),
so `from_int(99999, precision=3)` returns `1.00E+5`. Zero is $+0$ with
exponent 0.

### `Decimal::from_double`, `from_float`

Convert a binary floating-point value to a `Decimal`.

```mbti
pub fn Decimal::from_double(Double, precision? : Int) -> Self
pub fn Decimal::from_float(Float, precision? : Int) -> Self
```

A finite `Double` is a dyadic rational $m \cdot 2^{k}$ and therefore has a
finite decimal expansion $m \cdot 5^{-k} \cdot 10^{k}$ for $k<0$. The
conversion forms that exact expansion. If it fits in `precision` digits
(default 34), the result uses the exponent closest to preferred exponent 0:
`from_double(0.5)` returns `0.5`, and `from_double(100.0)` returns `100`.
Otherwise, the result is rounded half-even to exactly `precision` digits, using
the least possible exponent (IEEE 754-2019 5.2). For example,
`from_double(0.1, precision=16)` returns `0.1000000000000000`.

Signed zeros and infinities are preserved. Every NaN becomes a quiet NaN with
payload 0 and the input's sign. `from_float` first widens to `Double`; that
conversion is exact.

### `Decimal::from_binary`, `to_binary`

Convert between `Decimal` and the binary
[`Binary`](binary.md).

```mbti
pub fn Decimal::from_binary(@binary.Binary, precision~ : Int, mode? : DecimalRoundingMode) -> Self
pub fn Decimal::to_binary(Self, precision~ : Int, mode? : @binary.BinaryRoundingMode) -> @binary.Binary
```

`from_binary(x, precision~, mode~)` is exact whenever the decimal expansion of
`x` fits in `precision` decimal digits, with the exponent closest to 0 as for
`from_double`, and is otherwise rounded once to exactly `precision` digits in
`mode` (default `RoundTiesToEven`, the rounding type of the radix of the result).
The precision is required and counts digits; it was the number of bits of `x`
by default, a count of the wrong kind.

A binary zero keeps its sign, so $-0$ converts to $-0$ (IEEE 754-2019 5.4.2
and 6.3). A NaN becomes a quiet NaN with payload 0.

`to_binary(precision~, mode~)` rounds the exact decimal value once to a
`Binary` of `precision` bits with `mode`, one of the five rounding-direction
attributes of IEEE 754-2019 4.3.1 (default `RoundTiesToEven`). The precision is
required and counts bits, from 1 to `@binary.binary_precision_max`; outside
that range the call aborts (it was the number of digits of the decimal by
default). Most decimal fractions are not dyadic, so
this conversion is usually inexact. Using `RoundTowardNegative` and
`RoundTowardPositive` gives a binary enclosure of the decimal value. Zeros keep
their sign; NaN payloads are not kept. The same conversions are available in
`decimal_gda`, with `GdaRoundingMode` for a decimal result.

### `Decimal::convert_format`, `from_binary_ctx`, `to_binary_ctx`

Convert a `Decimal` between decimal formats or between decimal and binary
formats; each operation returns flags. They implement convertFormat,
IEEE 754-2019 5.4.2.

```mbti
pub fn Decimal::convert_format(Self, DecimalInterchangeFormat) -> (Self, DecimalFlags)
pub fn Decimal::from_binary_ctx(@binary.Binary, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::to_binary_ctx(Self, @binary.BinaryContext) -> (@binary.Binary, @binary.BinaryFlags)
```

`convert_format(format)` converts to decimal32, decimal64 or decimal128. It
rounds the value once to the format's precision and exponent range, to nearest
even, and returns the flags from that rounding. The preferred exponent is the
quantum of the source: for conversions between decimal formats, IEEE 754-2019
5.4.2 specifies $Q(\mathrm{source})$. Conversion to a wider format is exact
and keeps the cohort member. Conversion to a narrower format rounds and can
overflow or underflow; a large exponent is folded down.

`from_binary_ctx(x, ctx)` rounds the exact value of a binary float once under
the decimal context (precision, exponent range, direction) with the flags of
the rounding. For an exact conversion, the preferred exponent is 0, the
exponent closest to 0 that holds the digits: `0.5` is `5E-1`, and `96` is `96`.
An inexact conversion has
`precision` digits because the preferred exponent is the least possible. A
value beyond the exponent range, or far below it, overflows or underflows
without its digits being formed. An in-range value is correctly rounded at any
binary exponent, at a cost that does not grow with the exponent. A binary
exponent beyond $2^{22}$ is refused with NaN and `invalid_operation`.

`to_binary_ctx(ctx)` rounds the exact decimal value once under a
`BinaryContext`. The destination may be binary16 through binary128, or a
format with any precision and range. It returns `BinaryFlags` for `inexact`,
`overflow` and `underflow`. This is the conversion of
`Binary::from_string_ctx`, correctly rounded for any exponent.

A zero keeps its sign in every rounding direction. A signaling NaN becomes a
quiet NaN and raises the invalid operation exception. A NaN keeps its sign and
its payload when the destination holds it, IEEE 754-2019 6.2.3: `p - 1`
digits for decimal formats and `p - 2` bits for a binary format. Otherwise the
conversion keeps the low digits or bits. `from_binary` and `to_binary` are
unchanged.

### The `FromNat` and `FromInteger` implementations

`Decimal` implements the `luna-generic` traits `FromNat` and `FromInteger`, the
canonical maps from naturals and integers. To construct a `Decimal` directly,
call `Decimal::from_bigint(n)`; it uses exponent 0, the cohort of the integer.
The trait functions are the other entry points. There are no
`Decimal::from_natural` or `Decimal::from_integer` methods.

The trait functions return `from_bigint(n).normalized()` with precision 34,
which removes trailing zeros. To convert another Luna-Flow integer type, first
choose its representative with `Integral::normalize`, or use `lift_to`.

## Parsing and formatting

### `Decimal::from_string`

`from_string` converts decimal text to a `Decimal` and keeps its exponent.

```mbti
pub fn Decimal::from_string(String, precision? : Int) -> Result[Self, @arithmetic.ArithmeticError]
```

The accepted syntax is an optional sign, digits with an optional decimal
point, an optional exponent `E` or `e` with optional sign, or one of `Inf`,
`Infinity`, `NaN` and `sNaN` (any letter case) followed for NaNs by optional
decimal payload digits. Conversion rounds once, half-even, to `precision`
(default 34), preserving the preferred exponent as far as precision and the
representation permit. For example, `"1.2300"` has coefficient 12300 and
exponent $-4$; `"1.0001"` at precision 3 rounds to `1.00`; the exact
`"1.000"` at precision 3 is also `1.00` because its four coefficient digits
do not fit. `"10001"` at precision 3 rounds to `1.00E+4`. Invalid text returns
`Err(parse_error)`.

No context exponent range applies. The [implementation limits on a stored
value's exponents](#decimal_value_e_max-decimal_value_e_tiny) set the minimum
exponent to `decimal_value_e_tiny` ($-2\,147\,483\,645$) and the maximum
adjusted exponent to `decimal_value_e_max` ($2\,147\,483\,646$).
These limits are checked after rounding to `precision`, including a carry, and
apply to zero as to any finite value. Text whose value is outside the limits
is refused rather than replaced. `from_string` returns the domain error, which
names the exponent and both limits: `"1e3000000000"`, `"12e2147483647"` and
`"0e-2147483646"` are refused. At precision 3, `"1249e-2147483646"` becomes
`1.25E-2147483643`; its exponent after rounding is inside the range. Read the
text with [`from_string_ctx`](#decimalfrom_string_ctx) when you need a rounded
value (infinity or zero) and the `overflow` and `underflow` flags.

### `Decimal::from_string_ctx`

`from_string_ctx` converts text under a context and returns its conversion flags.

```mbti
pub fn Decimal::from_string_ctx(String, DecimalContext) -> (Self, DecimalFlags)
```

`from_string_ctx` accepts the syntax of `from_string`. It rounds the value to
the context precision and raises `inexact` when it discards non-zero digits.
It checks the exponent range for overflow and underflow and folds down large
exponents. A NaN payload longer than the format allows (precision $-1$ digits)
is a syntax error. Invalid text returns a quiet NaN with `invalid_operation`.

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

Format a value using the General Decimal Arithmetic `to-scientific-string`
or `to-engineering-string` conversion.

```mbti
pub fn Decimal::to_sci_string(Self) -> String
pub fn Decimal::to_eng_string(Self) -> String
```

Both format the value they receive. To format text after converting it under a
context, first call `from_string_ctx`; this also returns the conversion flags.
For example, `Decimal::from_string_ctx("1000000000", ctx).0.to_sci_string()`
formats the converted result.

| Format | Rule |
| --- | --- |
| Scientific | Writes the coefficient with an exponent `E±n` when the exponent is positive or the adjusted exponent is below $-6$; otherwise writes plain digits. |
| Engineering | Uses an exponent that is a multiple of three. |
| Special values | Writes `Infinity`, `-Infinity`, `NaN` or `sNaN`, with a payload such as `NaN7`. |

`Decimal::to_string` formats a value without a context using the same scientific
rule. It is the `Show` implementation; see
[`Show` and `Debug`](#show-and-debug-decimalto_string-output-to_repr).

## Contexts

### `DecimalContext`

`DecimalContext` stores the arithmetic parameters used by context operations.

```mbti
pub struct DecimalContext {
  // private fields
} derive(Eq)
```

An IEEE 754-2019 decimal format has precision $p$, maximum adjusted exponent
$e_{\max}$ and minimum adjusted exponent $e_{\min}=1-e_{\max}$ (3.3). A
`DecimalContext` selects one such format and one rounding-direction attribute,
`rounding`, whose value is a `DecimalRoundingMode`.

For a finite result with exponent $q$, the format requires
$e_{\min} \le q + p - 1 \le e_{\max}$. Therefore $q \le e_{\max}-p+1$;
larger exponents are folded down. IEEE 754-2019 7.5 requires decimal formats to
detect tininess before rounding. The context has no option for these format
rules. Each context operation receives its context as an argument and reads no
ambient state.

### `decimal_context_e_max_limit`, `decimal_context_e_min_limit`, `decimal_precision_max`

These constants bound the context parameters accepted by
`DecimalContext::try_new`.

```mbti
pub let decimal_context_e_max_limit : Int
pub let decimal_context_e_min_limit : Int
pub let decimal_precision_max : Int
```

| Constant | Value | Meaning |
| --- | ---: | --- |
| `decimal_context_e_max_limit` | $999{,}999{,}999$ | Largest accepted `e_max`. |
| `decimal_context_e_min_limit` | $-999{,}999{,}998$ | $1-e_{\max}$, the smallest `e_min` of a context. |
| `decimal_precision_max` | $999{,}999{,}999$ | Largest accepted precision. |

These are the decNumber `decContext.h` limits.

`try_new` and `new` check `precision` against `1..=decimal_precision_max` and
`e_max` against `1..=decimal_context_e_max_limit`; the constants used for the
checks are also the public limits. These values bound contexts only. The
certified elementary functions have a lower implementation limit:
$e_{\max} \le 999{,}999$ and $p \le 999{,}999$. See
[Elementary functions](#elementary-functions).

### `DecimalContext::new`, `try_new`

Construct an IEEE 754-2019 decimal-format context from a precision and `e_max`.
`new` aborts for invalid parameters; `try_new` returns a `Result`.

```mbti
pub fn DecimalContext::new(precision? : Int, e_max? : Int, rounding? : DecimalRoundingMode) -> Self
pub fn DecimalContext::try_new(precision? : Int, e_max? : Int, rounding? : DecimalRoundingMode) -> Result[Self, @arithmetic.ArithmeticError]
```

| Parameter | Default | Meaning |
| --- | --- | --- |
| `precision` | 34 | coefficient digits $p$ |
| `e_max` | $\max(999{,}999, 1000p)$ | The maximum adjusted exponent $e_{\max}$; $e_{\min}=1-e_{\max}$. |
| `rounding` | `RoundTiesToEven` | The rounding-direction attribute (IEEE 754-2019 4.3). |

`precision` and `e_max` must each be in `1..=999,999,999`. IEEE 754-2019 3.7
requires a language that supports an extendable format specified by precision
alone to define $e_{\max}$ as at least $1000p$ when decimal precision is at
least 51 digits. The library sets its default `e_max` to
$\max(999{,}999,1000p)$; 999,999 is the widest range in which every package
operation runs.

`new()` therefore creates format $(34,999{,}999)$, not decimal128; use
`decimal128()` for that format. A precision above 999,999 has no default range
because $1000p$ exceeds the limit; pass `e_max`. `try_new` returns
`Err(domain_error)` naming the invalid field. `new` aborts with a message that
names it, as `BinaryContext::new` does. Use `try_new` for parameters from
outside the program.

IEEE 754-2019 3.7 NOTE 3 recommends $e_{\max}\ge2$. The library accepts 1, the
least value for which $e_{\min}\le e_{\max}$ under 3.3.

The context's `rounding` attribute applies to finite results, infinities and
every other use of the context; `rounding()` reports exactly the rounding
direction applied. The
commercial GDA rounding algorithm `round-half-up` corresponds to
`RoundTiesToAway`. GDA's `round-half-down`, `round-up` and `round-05up` are not
attributes of an IEEE 754-2019 decimal format and exist only in
[`decimal_gda`](decimal_gda.md).

A context has no `clamp`, `extended` or `tininess` setting and no unlimited
precision option. An IEEE format always has the exponent range associated with
its quantum; subset arithmetic from the General Decimal Arithmetic appendix is
not an IEEE format. To obtain exact results, choose a precision large enough
for the digits. For example, a context with `digits(a) + digits(b)` digits and
an `e_max` at least the exponent of the product makes `mul_ctx` exact.

> [!NOTE]
> Certified elementary functions accept contexts with $e_{\max}\le999{,}999$
> and $p\le999{,}999$. For $p\le999$, `DecimalContext::new` defaults to the
> largest range inside that limit. A larger range, from explicit `e_max` or
> $p\ge1000$, makes them return NaN with `invalid_operation`.

### `DecimalContext::decimal32`, `decimal64`, `decimal128`

Construct the contexts for the IEEE 754-2019 interchange formats (IEEE 754-2019 3.6).

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

The conversion copies precision and rounding. It ignores `clamp`, which every
IEEE format has and whose default in `arithmetic` is `false`. A supplied
`e_max` is used. A supplied `e_min` must equal $1-e_{\max}$; otherwise the
conversion returns `Err(domain_error)`. If only `e_min` is supplied,
`e_max = 1 - e_min`; if neither is supplied, the default range of `new` is
used. The conversion also returns `Err(domain_error)` for `AwayFromZero`, which
is not an attribute of IEEE 754-2019 4.3, or for precision and `e_max` values
outside their accepted ranges. GDA 1.70 sets no fixed limits; these limits are
adopted from decNumber `decContext.h`.

### `DecimalContext::precision`, `rounding`, `e_min`, `e_max`

Read the precision, rounding direction and exponent limits of a context.

```mbti
pub fn DecimalContext::precision(Self) -> Int
pub fn DecimalContext::rounding(Self) -> DecimalRoundingMode
pub fn DecimalContext::e_min(Self) -> Int
pub fn DecimalContext::e_max(Self) -> Int
```

The context's `e_min` is always $1-e_{\max}$.

### `DecimalContext::refinement_limit`, `DecimalContext::with_refinement_limit`

Read or set the refinement limit for certified elementary functions.

```mbti
pub fn DecimalContext::refinement_limit(Self) -> Int32?
pub fn DecimalContext::with_refinement_limit(Self, Int32?) -> Self
```

The elementary functions evaluate an enclosure at increasing working
precision until both ends round to the same result. The limit counts
evaluations: `Some(n)` allows `n` evaluations (a value below 1 counts as 1),
`Some(12)` is the default, and `None` removes this count limit. If the function
does not decide a result within the limit, `try_*_ctx` returns the
`CertificationFailure` error with the refinement count; the plain and `*_ctx`
forms return NaN with `invalid_operation`. With `None`, evaluation stops when
the working precision exceeds the larger of 8,000,000 bits and 256 times the
initial working precision. The default changes no result. This field takes
part in `==`, so contexts that differ only in this limit are unequal.

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

### `DecimalContext::elementary_precision_limit`, `DecimalContext::with_elementary_precision_limit`

Read or set the precision limit of the elementary functions and the `pow`
family.

```mbti
pub fn DecimalContext::elementary_precision_limit(Self) -> Int32?
pub fn DecimalContext::with_elementary_precision_limit(Self, Int32?) -> Self
```

For an ordinary operand, `Some(n)` causes the `pow` family and elementary
functions to return `not_computed` when the context precision exceeds `n` digits.
The `try_` forms return `Err`. The default is `Some(999_999)` digits, and
`None` removes this implementation limit. Above the default limit, the library
does not bound running time or memory and makes no guarantee; this range is not
covered by the conformance gates. Results returned by these operations still
come from the same certified kernels and are correctly rounded. The measured
times for `pow(2, 0.5)` are 0.6 s at 100,000 digits, 14.7 s at 1,000,000 digits,
and more than 300 s at 10,000,000 digits (release build, loaded machine).

When the certified kernel cannot represent the working precision (above
80,807,093 digits), functions that use it return the context-limit error,
regardless of this limit. The square-root route of `pow` (exponent 0.5,
`sqrt_ctx`) and the exact routes are not refused there. The cases listed in
IEEE 754-2019 9.2.1 return values regardless of the precision limit. This field
participates in `==`; `with_precision`, `with_e_max` and `with_rounding` preserve
it.

```moonbit
///|
test "the precision limit of the elementary functions" {
  let context = @decimal.DecimalContext::new(precision=101)
  inspect(context.elementary_precision_limit() == Some(999_999), content="true")
  let low = context.with_elementary_precision_limit(Some(100))
  let two = @decimal.Decimal::from_int(2)
  inspect(two.try_pow_ctx(@decimal.Decimal::from_int(3), low) is Err(_), content="true")
  let open = low.with_elementary_precision_limit(None)
  inspect(two.pow_ctx(@decimal.Decimal::from_int(3), open).0.to_string(), content="8")
}
```

### `DecimalContext::with_precision`, `with_e_max`, `with_rounding`

Derive a context by replacing its precision, exponent range or rounding direction.

```mbti
pub fn DecimalContext::with_precision(Self, Int) -> Self
pub fn DecimalContext::with_e_max(Self, Int) -> Self
pub fn DecimalContext::with_rounding(Self, DecimalRoundingMode) -> Self
```

`with_precision` replaces the precision, and `with_e_max` replaces the
exponent range; in the latter, `e_min` follows from `e_max`. Either method
aborts when its argument is outside the limits accepted by `new`.
`with_rounding` replaces the context's rounding direction.

## Rounding modes

### `DecimalRoundingMode`

`DecimalRoundingMode` lists the five IEEE 754-2019 4.3 rounding-direction
attributes for decimal formats, using the spellings of `BinaryRoundingMode`.

```mbti
pub(all) enum DecimalRoundingMode {
  RoundTiesToEven
  RoundTiesToAway
  RoundTowardZero
  RoundTowardPositive
  RoundTowardNegative
}
```

Let $x>0$ lie strictly between adjacent representable coefficients $c$ and
$c+1$, measured in units in the last place. `RoundTowardZero` returns $c$.
`RoundTowardPositive` and `RoundTowardNegative` round toward $+\infty$ and
$-\infty$, respectively, so their results depend on the sign. The nearest
rounding directions, `RoundTiesToEven` and `RoundTiesToAway`, return the nearer
coefficient; at an exact tie they choose the even coefficient and the one farther
from zero, respectively. The kernels also use three rounding algorithms that a
context cannot select: `HalfDown`, `Up` and `ZeroFiveUp`. Division uses `ZeroFiveUp` for
its double-rounding guard digit, and certified functions use directed bounds.

### `DecimalRoundingMode::from_arithmetic`, `to_arithmetic`

Map between `DecimalRoundingMode` and the shared `@arithmetic.RoundingMode`.

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
does not contain. `DecimalContext::from_arithmetic_context` and the
`_contextual` forms return `Err` for `AwayFromZero`.

Every context detects tininess before rounding (IEEE 754-2019 7.5). A non-zero
exact result whose magnitude is below $10^{e_{\min}}$ is tiny, regardless of the
delivered value. An inexact tiny result raises `underflow`. Contexts have no
option for the binary after-rounding rule.

## Status flags

### `DecimalFlags`

`DecimalFlags` records the conditions raised by one operation.

```mbti
pub struct DecimalFlags {
  // private fields
} derive(Eq)
```

| Flag | Set when |
| --- | --- |
| `inexact` | the result differs from the exact result |
| `underflow` | the result is tiny and inexact |
| `overflow` | the rounded result's adjusted exponent exceeds $e_{\max}$ |
| `division_by_zero` | finite operands produce an exact infinite result ($x/0$, $\ln 0$, $\log_2 0$, $\log_{10} 0$, $\operatorname{logb} 0$, $\operatorname{log1p}(-1)$, $\operatorname{log2p1}(-1)$, $\operatorname{log10p1}(-1)$, $\operatorname{rSqrt}(\pm 0)$, $\operatorname{compound}(-1, n<0)$, $\operatorname{powr}(\pm 0, y<0)$) |
| `invalid_operation` | the result is not usefully definable (signaling NaN, $\infty-\infty$, $0\times\infty$, $0/0$, bad quantize, text that is not a number, a context outside the range an elementary function supports) |
| `not_computed` | the library cannot compute a result within an implementation limit (a context beyond the elementary kernels, an operand beyond their range, an exact sum with an exponent gap beyond the work bound, or an undecided certification): the value is a NaN, `invalid_operation` is not raised, and the `try_` form returns `Err` of the certification-failure kind |

IEEE 754-2019 7.2 to 7.6 defines the five IEEE flags; `not_computed` is an additional library
flag. The General Decimal Arithmetic flags `rounded`, `subnormal`, `clamped`, `lost_digits`,
`conversion_syntax`, `division_impossible`, `division_undefined` and `invalid_context` belong to
`decimal_gda`, not `decimal`.

The fields are private. Read each flag with a method of the same name, such as `flags.inexact()`
or `flags.division_by_zero()`. Flags do not accumulate implicitly.

### `DecimalFlags::new`, `combine`, `has_error`

Create an empty flag set, combine two sets, or test whether a set contains an error condition.

```mbti
pub fn DecimalFlags::new() -> Self
pub fn DecimalFlags::combine(Self, Self) -> Self
pub fn DecimalFlags::has_error(Self) -> Bool
```

`new` clears every flag. `combine` takes the field-wise OR; it is associative, commutative and
idempotent, and `new()` is its identity. `has_error` tests

$$
\text{invalid\_operation} \lor \text{not\_computed} \lor \text{division\_by\_zero}.
$$

This is the set of conditions for which IEEE 754-2019 delivers no usable number: 7.2 defines
invalid operation as having no usefully definable result. A failed `from_string_ctx` raises
`invalid_operation`, so `has_error` returns true. `has_error` excludes `overflow`, `underflow` and
`inexact`: those deliver a usable result (IEEE 754-2019 7.4 to 7.6 define it, as 7.3 does for
division by zero). `division_by_zero` is in the set only so that the checked forms of `Luna-Flow/arithmetic`
can return `Err` for division by zero.

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

The operators and functions in this group take no context and return no flags. Use them for exact
work or generic code over the Luna-Flow algebra traits. Use [context arithmetic](#context-arithmetic)
when rounding, the exponent range or flags matter.
### `Decimal::add`, `sub`, `mul`, `div`, `neg`

Implement the arithmetic operators `+`, `-`, `*`, `/` and unary `-`.

```mbti
pub fn Decimal::add(Self, Self) -> Self
pub fn Decimal::sub(Self, Self) -> Self
pub fn Decimal::mul(Self, Self) -> Self
pub fn Decimal::div(Self, Self) -> Self
pub fn Decimal::neg(Self) -> Self
```

Each operator runs the matching [context operation](#context-arithmetic)
(`add_ctx`, `sub_ctx`, `mul_ctx` or `div_ctx`) in a private context and drops
the flags. That context uses the larger precision of the operands,
$\max(p_a,p_b)$, round-half-even, the stored-value range
(`decimal_value_e_max` = $2\,147\,483\,646$,
`decimal_value_e_tiny` = $-2\,147\,483\,645$), and no fold-down. The result
has precision $\max(p_a,p_b)$. For checked division, call the trait method
`DivChecked::div_checked(a, b, ctx)` (see
[`parse_checked` and the checked traits](#decimalparse_checked-sqrt_checked-pow_nat_checked-pow_int_checked));
`Decimal::div_checked` is not an inherent method.

- An exact result uses the cohort member closest to the preferred exponent
  (IEEE 754-2019 5.4.1): $\min(q_a,q_b)$ for `add` and `sub`, $q_a+q_b$ for
  `mul`, and $q_a-q_b$ for `div`. Thus `1.20 + 3.40` is `4.60`, `6.0 / 2`
  is `3.0`, `1.25 * 2.50` is `3.1250`, and `1.20 - 1.20` is `0.00`.
- An inexact result has exactly $p$ digits at the least exponent, IEEE
  754-2019 5.2, and is not reduced. At seven digits, `1 / 3` is `0.3333333`;
  a product of two five-digit values is rounded to five digits.
- For every value, `neg` flips the sign bit; this includes zeros and NaNs.

Special values follow the context operations:

| Case | Result |
| --- | --- |
| A NaN operand | A quiet NaN with the payload of the first NaN |
| $\infty-\infty$, $0\times\infty$, $0/0$ or $\infty/\infty$ | NaN |
| $x/0$ | Infinity with the sign of the exact quotient; the sign of zero counts, so `1 / -0` is $-\infty$ |
| Zero product | Sign is the exclusive or of the operand signs |
| Finite value divided by infinity | Signed zero at the smallest exponent of the private context |
| Result above the private range | Overflow result of that context, which is infinity |
| Result below the private range | Round half-even to the smallest exponent, possibly producing signed zero |

For example, `1E+2147483646 * 1E+2147483646` is `inf`, and
`123E-2147483640 * 1E-10` is `0E-2147483645`. For every finite value inside
the private range, `x + 0 == x`, `x - 0 == x` and `x * 1 == x` hold at any
exponent. The sum or product uses the cohort member closest to the preferred
exponent that holds the value in $p$ digits.

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

Change only the sign bit of a value.

```mbti
pub fn Decimal::abs(Self) -> Self
pub fn Decimal::copy(Self) -> Self
pub fn Decimal::copy_sign(Self, Self) -> Self
```

Clear, copy or replace a sign bit without rounding or raising flags.

They preserve the exponent, payload and NaN kind. `abs` clears the
sign, `neg` flips it, `copy_sign` copies the second operand's sign bit, and
`copy` returns the input value.

### `Decimal::normalized`, `with_precision`

`normalized` changes the cohort member; `with_precision` sets the precision of
the value.

```mbti
pub fn Decimal::normalized(Self) -> Self
pub fn Decimal::with_precision(Self, Int, DecimalRoundingMode) -> Self
```

`normalized` returns the reduced member of the cohort: it removes all trailing
zeros and gives zero exponent 0. If the coefficient has more digits than the
precision of the value, it first rounds half-even to that precision. It is the
only operation in this package that strips trailing zeros; IEEE 754-2019 defines
no such operation. To apply a context before reducing, call
`x.apply_ctx(ctx).0.normalized()`.

`with_precision(p, mode)` rounds a finite value to $p$ digits with `mode`,
reduces it and sets its precision to $p$. It changes only the precision of a
special value. Neither function raises flags.

### `Decimal::sqrt`

Compute the square root of the value under its own format.

```mbti
pub fn Decimal::sqrt(Self) -> Self
```

`sqrt` runs `sqrt_ctx` in the plain operators' private context, with precision
$p$. A negative non-zero operand returns NaN; IEEE 754-2019 7.2. The
[`sqrt_checked` entry](#decimalparse_checked-sqrt_checked-pow_nat_checked-pow_int_checked)
returns `Err` for this case. Both forms are correctly rounded half-even.

## Context arithmetic

Each function in this group takes a `DecimalContext` and returns
`(result, flags)`. It rounds the exact result once to the context precision in the
context's rounding direction, then applies the exponent range. Overflow gives
the result for that rounding direction; see [overflow](../design/decimal.md#overflow).
A result whose exact magnitude is below $10^{e_{\min}}$ is rounded directly to
the subnormal grid $10^{E_{\text{tiny}}}$. A normal result is rounded only to $p$
digits even when its exact exponent is below $E_{\text{tiny}}$. Large
exponents are folded down to $e_{\max}-p+1$.

When the exact result fits, the operation uses its *preferred exponent*, so
cohort information is preserved. NaN operands propagate as a quiet NaN with
the sign and payload of the first NaN; the payload is cut to its low $p-1$
digits, as in `from_string_ctx` and the interchange encodings. A signaling NaN
operand raises `invalid_operation`.

Near the underflow threshold, the single rounding determines the result. In
decimal32, the exact product `3.000001E-45 * 1.500001E-45` is
$4.5000045000015\cdot 10^{-90}$. It is a normal number even though its exact
exponent is below $E_{\text{tiny}}=-101$, and rounds once to seven digits as
`4.500005E-90`. The quotient `1 / 1.9999999999998E+101` is
$5.0000000000005\cdot 10^{-102}$, which is subnormal. Its guarded quotient
rounds once to the grid $10^{-101}$, giving `1E-101` with `inexact` and
`underflow`.

### `Decimal::add_ctx`, `sub_ctx`, `mul_ctx`, `div_ctx`

Add, subtract, multiply and divide return correctly rounded results.

```mbti
pub fn Decimal::add_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::sub_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::mul_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::div_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
```

The preferred exponents are $\min(q_a,q_b)$ for addition and subtraction,
$q_a+q_b$ for multiplication, and $q_a-q_b$ for division. An exact quotient
uses the cohort member closest to its preferred exponent. An inexact quotient
has $p$ digits, except a subnormal quotient, whose exponent is
$E_{\text{tiny}}$. A zero sum is $+0$ except under `Floor`, when it is $-0$
if either operand is negative, or when both operands are $-0$.

| Operands | Result and flag |
| --- | --- |
| $\infty-\infty$ | NaN with `invalid_operation` |
| $0\times\infty$ | NaN with `invalid_operation` |
| $\infty/\infty$ | NaN with `invalid_operation` |
| $0/0$ | NaN with `invalid_operation` |
| finite non-zero $x/0$ | Signed infinity with `division_by_zero` |
| finite$/\infty$ | Signed zero with exponent $E_{\text{tiny}}$ |

When an operand of `add_ctx` or `sub_ctx` lies below every rounding boundary
of the sum, the operation does not align it digit by digit. It replaces that
operand with a sticky unit of the same sign just below those boundaries, then
rounds the sum once. See [addition with a far smaller addend](../design/decimal.md#addition-with-a-far-smaller-addend).
At precision 7, `1598617.000000000001 - 0.000000000002` is `1598616` under
`Down`, while `6.0000005E-73 + 1E-101` is `6.000001E-73` under `HalfEven`.

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

`fma_ctx` computes $x \cdot y + z$ with one rounding.

```mbti
pub fn Decimal::fma_ctx(Self, Self, Self, DecimalContext) -> (Self, DecimalFlags)
```

The product and its sum with `z` are formed exactly; only the sum is rounded.
For $0\times\infty+z$, the result is invalid when `z` is a number or infinity.
When `z` is a quiet NaN, the result is that NaN without `invalid_operation`
(IEEE 754-2019 7.2 leaves whether to signal invalid operation
implementation-defined). The expression $\infty \cdot y + (-\infty)$ with
opposite signs is invalid.

### `Decimal::sqrt_ctx`

`sqrt_ctx` returns the correctly rounded square root of its operand.

```mbti
pub fn Decimal::sqrt_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
```

The preferred exponent is $\lfloor q/2 \rfloor$. An exact root uses the cohort
member closest to it; for example, `sqrt(0.0400)` is `0.20`. An inexact root
has $p$ digits and raises `inexact`. The result preserves $\sqrt{-0}=-0$ and
$\sqrt{+\infty}=+\infty$. A negative non-zero operand or $-\infty$ gives NaN
with `invalid_operation`.

### `Decimal::abs_ctx`, `apply_ctx`

Round a value to the context or return its absolute value rounded to the context.

```mbti
pub fn Decimal::abs_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::apply_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
```

`apply_ctx` rounds a value to the precision and exponent range of the context. An exponent above
$E_{\mathrm{top}}=e_{\max}-p+1$ is folded down. It quiets a NaN and keeps the sign of zero.
`abs_ctx` returns $|x|$ rounded to the context; a signaling NaN raises `invalid_operation`.

### `Decimal::remainder_ctx`

Compute the IEEE remainder of a value and a divisor.

```mbti
pub fn Decimal::remainder_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
```

`remainder_ctx(x, y)` returns $x-y\cdot n$, where $n$ is $x/y$ rounded to the nearest integer,
with ties to even. IEEE 754-2019 5.3.1 calls this operation *remainder*; GDA calls it
*remainder-near*, which `decimal_gda` keeps. The result is exact when it fits and has preferred
exponent $\min(q_x,q_y)$. A zero result has the sign of $x$.

| Operands | Result |
| --- | --- |
| $x$ and zero, including zero and zero | invalid operation |
| infinity and $y$ | invalid operation |
| $x$ and infinity | $x$ |

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

### `Decimal::quantum_ctx`

Return the quantum of a value.

```mbti
pub fn Decimal::quantum_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
```

For a finite $x$, `quantum_ctx` returns $(0,q,1)$, or $10^q$, where $q$ is the exponent of $x$;
this includes zeros. Thus `quantum_ctx(1.2300)` is `0.0001`. The exact result has preferred
exponent $Q(x)$.

| Input | Result and flags |
| --- | --- |
| Infinity, either sign | $+\infty$, no exception |
| Quiet NaN | propagated with its payload, no flag |
| Signaling NaN | quiet NaN with its payload; raises `invalid_operation` (6.2) |

The stored exponent is `exponent10`. IEEE 754-2019 5.3.2 says *should* for `quantum` and
*shall* for `quantize`. Only a signaling NaN can raise a flag, but the operation takes a context
and returns flags, like `logb_ctx` and `next_up_ctx` (`doc/manual/conventions.md`); there is no
plain `quantum`.

### `Decimal::quantize_ctx`

Round a value to the exponent of another value.

```mbti
pub fn Decimal::quantize_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
```

`x.quantize_ctx(y, ctx)` returns $x$ with exponent $q_y$, using the context's rounding direction
when digits are dropped. It raises `inexact` if any dropped digit is nonzero.
IEEE 754-2019 5.3.2 specifies `quantize` and its preferred exponent $Q(y)$.

The result is NaN with `invalid_operation` in these cases:

| Condition | Result |
| --- | --- |
| The target exponent is outside $[E_{\text{tiny}},e_{\max}]$ | NaN with `invalid_operation` |
| The resulting coefficient needs more than $p$ digits | NaN with `invalid_operation` |
| The adjusted exponent exceeds $e_{\max}$ | NaN with `invalid_operation` |
| Exactly one operand is infinite | NaN with `invalid_operation` |

Two infinities give the infinity of $x$. The quantum does not silently change to another value
of the cohort range: if the result cannot have exponent $q_y$, the operation fails. A target
exponent in $(E_{\mathrm{top}},e_{\max}]$ is accepted as the fold-down exception; the result
then has exponent $E_{\mathrm{top}}$, like every other result. For example, quantizing `1E+384`
to `1E+384` in decimal64 gives `1.000000000000000E+384`.

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

Test whether two values have the same exponent.

```mbti
pub fn Decimal::same_quantum(Self, Self) -> Bool
```

IEEE 754-2019 5.7.3 defines `sameQuantum`: two finite values have the same quantum when their
exponents are equal. Two infinities and two NaNs always have the same quantum; every other pair
does not. The operation never raises flags.
### `Decimal::to_integral_exact_ctx`, `to_integral_value_ctx`

Round a value to an integer.

```mbti
pub fn Decimal::to_integral_exact_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::to_integral_value_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
```

A finite value with exponent $q \ge 0$ is already integral and the functions
return it unchanged, even when it has more than $p$ digits; the format's
fold-down of its exponent still applies. For a value with $q < 0$, they
quantize to exponent 0 using the context's rounding direction and an internal
precision of $\max(p, \text{the digit count of the value})$. Thus the integral
part is not rounded to $p$ digits: at precision 3, `12345.6` gives `12346`.
`to_integral_exact_ctx` raises `inexact` when it discards non-zero digits;
`to_integral_value_ctx` returns the same value with `inexact` cleared.
Infinities are unchanged, and NaNs are quieted.

IEEE 754-2019 5.9 defines roundToIntegral for an operand in the context's
format, which has at most $p$ digits; for such operands, these functions return
the specified results. An operand with more than $p$ digits is not a value of
the format, so 5.9 does not cover it and its result is implementation-defined.
For such operands, this package leaves a longer integer unchanged and
quantizes a fraction using $\max(p, \text{the digit count of the value})$ digits.
This is the package's chosen GDA-style behavior: General Decimal Arithmetic
rounds to an integral value at the precision of the operand.

### `Decimal::to_int_ctx`, `to_int64_ctx`, `to_uint_ctx`, `to_uint64_ctx`

Convert a decimal to a fixed-width integer, rounding in the context's rounding
direction as specified by IEEE 754-2019 5.4.1 and 5.8.

```mbti
pub fn Decimal::to_int_ctx(Self, DecimalContext, exact? : Bool) -> (Int32?, DecimalFlags)
pub fn Decimal::to_int64_ctx(Self, DecimalContext, exact? : Bool) -> (Int64?, DecimalFlags)
pub fn Decimal::to_uint_ctx(Self, DecimalContext, exact? : Bool) -> (UInt32?, DecimalFlags)
pub fn Decimal::to_uint64_ctx(Self, DecimalContext, exact? : Bool) -> (UInt64?, DecimalFlags)
```

These functions follow the interface of the `Binary` conversions with the same
names. They round using the context's rounding direction: ties to even, toward
zero, toward positive, toward negative or ties away, the five directions
specified by IEEE 754-2019 5.8. A quiet or signaling NaN, an infinity, or a
value outside the integer type's range produces `None` and raises
`invalid_operation`. A negative value that rounds to zero produces `0`, also
for an unsigned result; any other negative value is out of range for an
unsigned type. With `exact=true` (`convertToIntegerExact`), a changed value
raises `inexact`; without it, a valid conversion has no flags. Context
precision and exponent range do not affect conversion: any integer that fits
the target type converts exactly, regardless of its digit count. The
conversion does not form $10^q$: `1E+999999` is out of range and `1E-999999`
rounds to zero, or to one unit in a direction away from zero.

### `Decimal::scaleb_ctx`, `logb_ctx`

Scale a value by a power of ten or return its adjusted exponent.

```mbti
pub fn Decimal::scaleb_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::logb_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
```

`x.scaleb_ctx(n, ctx)` adds $n$ to the exponent of $x$ and returns
$x \cdot 10^n$. IEEE 754-2019 5.3.3 defines scaleB for integral counts only;
the language defines behavior for a non-integral second operand, including an
infinity. This package also requires $n$ to be finite and integral, with
exponent 0, and $|n| \le 2(e_{\max}+p)$; otherwise it returns NaN and raises
`invalid_operation`. The count bound follows the GDA `scaleb` rule, while
`Binary::scaleb_ctx` clamps a larger count.

The scaled value is rounded once as a context result. A coefficient longer
than $p$ digits is rounded to $p$ digits: scaling
`12345678901234567890` by 0 in decimal64 gives `1.234567890123457E+19` with
`inexact`. A subnormal result is rounded to $E_{\text{tiny}}$. Overflow
produces the result selected by the context's rounding direction and raises
`overflow` and `inexact`; with decimal64 and `TowardZero`, scaling `9E+384` by
1 gives `9.999999999999999E+384`. Large exponents are folded down. A zero keeps
its sign and its exponent is clamped to the range: scaling `0` by 700 in
decimal64 gives `0E+369`.

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
integer `Decimal`. For $\pm0$ it returns $-\infty$ with `division_by_zero`,
and for $\pm\infty$ it returns $+\infty$.

## Adjacent values

### `Decimal::next_up_ctx`, `next_down_ctx`

Return the neighboring representable values in a context.

```mbti
pub fn Decimal::next_up_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::next_down_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
```

`next_up_ctx` returns the least value in the context greater than `x`;
`next_down_ctx` returns the greatest value less than `x`. The range includes
subnormals down to $10^{E_{\text{tiny}}}$ and the largest finite value
$(10^{p}-1)\,10^{e_{\max}-p+1}$. For example, `next_up_ctx(-∞)` returns the
most negative finite value. Finite results raise no flags. IEEE 754-2019 5.3.1
defines nextUp and nextDown only: the next-toward operation of GDA 1.70 is
`next_toward` of `decimal_gda`, and this package has no `next_toward_ctx`.

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

Compare two values numerically with `compare`. `Compare`, `==` and the
comparison operators use this ordering.

```mbti
pub fn Decimal::compare(Self, Self) -> Int
```

`compare` returns $-1$, 0 or 1 by numeric value. It treats $-0$ and $+0$ as
equal and treats every member of a cohort as equal. NaN has no numeric order, so
`Compare` stays a total preorder (sorting never aborts): every NaN compares equal
to every other NaN and greater than every non-NaN. `equal` (`==`) follows the
same rule, including `NaN == NaN` as `true`. This is *not* IEEE equality; use
[`compare_checked`](#decimalcompare_checked), `compare_quiet` or the
predicates; these leave NaN unordered. The operator methods are listed under
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

Use `compare_checked` for IEEE numeric comparison that returns an error for NaN.

```mbti
pub fn Decimal::compare_checked(Self, Self) -> Result[Int, @arithmetic.ArithmeticError]
```

When neither operand is NaN, it returns `Ok(compare(x, y))`. Otherwise it
returns `Err(unordered_comparison)`. It implements `CompareChecked`.

### `Decimal::compare_quiet`, `compare_signaling`

Compare values using the four-valued IEEE 754-2019 5.11 relation and return
the associated flags.

```mbti
pub fn Decimal::compare_quiet(Self, Self) -> (@def.PartialOrder, DecimalFlags)
pub fn Decimal::compare_signaling(Self, Self) -> (@def.PartialOrder, DecimalFlags)
```

The relation is `Less`, `Equal`, `Greater` or `Unordered` when an operand is
NaN. Both forms treat $-0$ and $+0$ as equal and equate all members of a cohort.
The quiet form raises `invalid_operation` only for a signaling NaN; the
signaling form raises it for every unordered comparison. These functions match
the corresponding `Binary` functions. The removed `compare_ctx` and
`compare_signal_ctx` returned the GDA-style `Decimal` result $-1$, 0, 1 or NaN.

### `Decimal::compare_quiet_equal` and the other comparison predicates

The predicates of IEEE 754-2019 Tables 5.1 and 5.2 that `Binary` has.

```mbti
pub fn Decimal::compare_quiet_equal(Self, Self) -> (Bool, DecimalFlags)
pub fn Decimal::compare_quiet_less(Self, Self) -> (Bool, DecimalFlags)
pub fn Decimal::compare_quiet_less_equal(Self, Self) -> (Bool, DecimalFlags)
pub fn Decimal::compare_quiet_unordered(Self, Self) -> (Bool, DecimalFlags)
pub fn Decimal::compare_signaling_equal(Self, Self) -> (Bool, DecimalFlags)
pub fn Decimal::compare_signaling_less(Self, Self) -> (Bool, DecimalFlags)
pub fn Decimal::compare_signaling_less_equal(Self, Self) -> (Bool, DecimalFlags)
```

Each predicate applies its corresponding quiet or signaling comparison and
returns its flags. On an unordered pair, only `compare_quiet_unordered` returns
true; the other predicates return false.

### `Decimal::compare_quiet_not_equal` and the other comparison predicates of Tables 5.1 and 5.2

These fifteen predicates complete the comparison predicates of IEEE 754-2019 5.11.

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

IEEE 754-2019 5.11 lists 22 comparison predicates: 10 in Table 5.1, including
the predicates associated with the common mathematical symbols, and 12 in
Table 5.2. Together with the seven predicates in the preceding entry, all 22
have a function here. Each function returns a Boolean and the flags raised by
`compare_quiet` or `compare_signaling`; a quiet predicate raises
`invalid_operation` only for a signaling NaN, while a signaling predicate raises
it for every NaN operand. Each function's doc comment names its table row. Its
name starts with `compare_`, followed by `quiet` or `signaling` and the table's
predicate name in snake case. Predicates paired as negations in a table return
opposite Boolean values and the same flags.

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

`total_order` and `total_order_mag` implement the IEEE 754-2019 5.10 predicates
`totalOrder` and `totalOrderMag`; `total_order_compare` gives the same order as
a three-way comparison.

```mbti
pub fn Decimal::total_order(Self, Self) -> Bool
pub fn Decimal::total_order_mag(Self, Self) -> Bool
pub fn Decimal::total_order_compare(Self, Self) -> Int
```

`total_order(x, y)` is true when `x` is ordered at or before `y`.
`total_order_compare(x, y)` returns `-1`, `0` or `1` for that order. It covers
every representation:

$$
-\text{NaN} < -\text{sNaN} < -\infty < \text{negative finite} < -0 < +0 <
\text{positive finite} < +\infty < +\text{sNaN} < +\text{NaN}.
$$

For equal finite values, the exponent orders the representations. Positive
values with the smaller exponent come first ($1.00 < 1.0$); for negative values,
those with the larger exponent come first. NaNs with the same sign and kind are
ordered by payload, in reverse order for negative NaNs. `total_order_compare`
returns 0 only for identical representations. `total_order_mag(x, y)` applies
`total_order` to the absolute values. These functions take no context, perform
no rounding and raise no flags.

### `Decimal::identical`

Test whether two values are the same datum with `identical`.

```mbti
pub fn Decimal::identical(Self, Self) -> Bool
```

`x.identical(y)` is true when the class, sign, signaling bit, coefficient (the
payload for a NaN), exponent and precision label are all equal. Unlike `==`, it
distinguishes values with equal numerical value but different cohort members
(`1.20` and `1.2`). Unlike `total_order_compare`, it also compares the precision
label. A zero and its negative are not identical, nor are NaNs with different
payloads.

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

Select values by numeric order without a context.

```mbti
pub fn Decimal::min(Self, Self) -> Self
pub fn Decimal::max(Self, Self) -> Self
pub fn Decimal::clamp(Self, min~ : Self, max~ : Self) -> Self
pub fn Decimal::clamp_checked(Self, min~ : Self, max~ : Self) -> Result[Self, @arithmetic.ArithmeticError]
```

`min` and `max` select the other operand when exactly one is a quiet NaN. They
return a quiet NaN when both operands are NaNs or either operand is signaling,
and return the receiver when the values tie.

`clamp` returns `min` below the range, `max` above it, and the value, including
a NaN, otherwise. It aborts when a bound is NaN or `min > max`.
`clamp_checked` returns `Err(domain_error)` for those inputs.

### `Decimal::minimum_ctx`, `maximum_ctx`, `minimum_number_ctx`, `maximum_number_ctx`, `minimum_magnitude_ctx`, `maximum_magnitude_ctx`, `minimum_magnitude_number_ctx`, `maximum_magnitude_number_ctx`

Compute the IEEE 754-2019 9.6 minimum and maximum operations. The General
Decimal Arithmetic `min`, `max`, `min-magnitude` and `max-magnitude` are in
`decimal_gda`.

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

`minimum_ctx` and `maximum_ctx` return a quiet NaN when either operand is a NaN.
The `_number_` variants return the number when exactly one operand is a NaN. All
four raise `invalid_operation` when either operand is signaling.

The magnitude variants compare $|x|$ and $|y|$. When the magnitudes are equal,
they use the signed order. Ties are resolved by `total_order_compare`, so
$-0 < +0$. The selected value is rounded to the context.

## Elementary functions

Each elementary function has two forms. `f_ctx(x, ctx)` returns `(result,
flags)`. `try_f_ctx(x, ctx)` returns the same pair in `Ok`, or returns `Err` with
an `ArithmeticError` when it cannot certify the result. The error's
`certification_failure_detail()` names the operation, target precision and
exhausted refinement limit. On certification failure, `f_ctx` returns NaN with
`not_computed`; `try_f_ctx` returns `Err` of the certification-failure kind.

Transcendental results are **certified**. The implementation evaluates a
guaranteed enclosure of $f(x)$ in [`interval`](interval.md) and accepts it only
when both bounds round to the same `Decimal` with the same flags. The
[design page](../design/decimal.md#certified-elementary-functions) describes
the method. Since rounding is monotone, an accepted result is the rounding of
$f(x)$ in every `DecimalRoundingMode`.

The implementation decides exact cases before the enclosure loop. For example,
$\log_{10} 1000 = 3$, $e^0 = 1$, $\sin 0 = 0$, $\operatorname{cospi}(1) = -1$,
$\operatorname{tanpi}(0.25) = 1$, $\operatorname{acos}(1) = 0$, $x^{0.5}$,
exact roots such as `rootn_ctx(0.008, 3)` $= 0.2$, and exact norms such as
`hypot_ctx(0.3, 0.4)` $= 0.5$ return without `inexact`. An exact binary result
such as `pow_ctx(4, 1.5)` $= 8$ is returned exactly by the enclosure itself.
Integer powers are not certified. [`pow_ctx`](#decimalpow_ctx-pown_ctx-rootn_ctx-hypot_ctx-try_pow_ctx-try_pown_ctx-try_rootn_ctx-try_hypot_ctx)
rounds them once from the exact power or from refined directed bounds.

> [!NOTE]
> **Exact non-integral powers.** A power whose exact result is representable
> decimal but not a binary fraction is decided in decimal before the loop, so
> in decimal64 `pow_ctx(0.0016, 0.25)` is `0.2`, `pow_ctx(32, 0.2)` is `2`
> and `pow_ctx(0.04, 1.5)` is `0.008`, all without `inexact` and in every
> rounding direction. The exponent is reduced to $p/q$ in lowest terms — a decimal
> exponent is $c \cdot 10^{-k}$, so $q$ keeps only the twos and fives the
> coefficient cannot cancel — and the power is exact exactly when $x$ itself
> is a perfect $q$-th power. The root is taken first and then raised to $p$,
> so the test never handles a number longer than the result. It finds every
> exact result of at most `precision + 1` digits, the only ones that sit on a
> rounding boundary; a longer exact result lies inside its rounding cell and the
> enclosure rounds it like any other.

These operations return NaN with `not_computed`; the `try_` forms return `Err`
of the certification-failure kind when $p > 999\,999$, $e_{\max} > 999\,999$,
$e_{\min} < -999\,999$, or a finite operand has more than 999,999 digits or an
adjusted exponent beyond about $\pm 10^6$.

In such a context, cases listed in IEEE 754-2019 9.2.1 or Table 9.1 return
values; other cases return `not_computed`. The listed cases are a NaN
operand; an infinite or zero operand; the exact points
(`ln_ctx(1)`, `log2_ctx(1)`, `log10_ctx(1)`, `acos_ctx(1)`, `acospi_ctx(1)`,
`acosh_ctx(1)` are `0`, `atanpi_ctx(+inf)` is `0.5`, `sinpi_ctx(n)` for an
integer `n`, `cospi_ctx(n + 0.5)`, `tanpi_ctx` at integers and half-integers);
domain errors (`invalid_operation`) and poles (`division_by_zero`); `compound`,
`rootn` and `rsqrt` for the operands the clause lists; and the constants of
`atan2`, `atan2pi` and `atan(+-inf)`. The context limit is tested after these
cases and before the first computation. Exact results of ordinary operands not
listed by the clause still return `not_computed`:
`hypot_ctx(3, 4)`, `rsqrt_ctx(4)`, `log10_ctx(1E+5)`, `atanpi_ctx(1)`,
`acospi_ctx(0)`, `sinpi_ctx(0.5)`, `cospi_ctx(1)`, `exp2_ctx(3)`, `rootn_ctx(8, 3)`.
Accepting every context for ordinary operands is the subject of
[#478](https://github.com/Luna-Flow/floating/issues/478). `decimal_gda` keeps
the other order, which the decTest corpus requires.

The constants of `atan(+-inf)` and multiples of pi in `atan2` are computed at
the context precision. At 1,000,000 digits that takes about 100 seconds each.
From 80,807,094 digits, the result is `not_computed` at once because
`decimal_certified_work_refusal` refuses a first working precision above
`binary_precision_max`, 268,435,456 bits (`binary/context.mbt:43`); the first
working precision is 3.321929 bits per digit plus 31 guard bits. The largest
precision served is 80,807,093 digits. Integral powers in `decimal` support counts through
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

Compute the General Decimal Arithmetic exponential and logarithms.

```mbti
pub fn Decimal::exp_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::ln_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::log10_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::try_exp_ctx(Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::try_ln_ctx(Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::try_log10_ctx(Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
```

$e^x$ returns $1$ for $x=\pm 0$, $+\infty$ for $x=+\infty$, and $+0$ for
$x=-\infty$. IEEE 754-2019 9.2.1 requires $\ln(\pm 0)$ and
$\log_{10}(\pm 0)$ to return $-\infty$ with `division_by_zero`; `log2_ctx`,
`log1p_ctx` and `logb_ctx` do the same. General Decimal Arithmetic, followed
by [`decimal_gda`](decimal_gda.md), raises no condition for these inputs.

Both logarithms return $+\infty$ for $+\infty$. They return NaN with
`invalid_operation` for a negative value or $-\infty$. In addition,
$\ln 1=0$, and $\log_{10}$ of a power of ten returns its exact integer
exponent. The implementation decides arguments that certainly make $e^x$
overflow or underflow without evaluating the exponential.

### `Decimal::pow_ctx`, `pown_ctx`, `rootn_ctx`, `hypot_ctx`, `try_pow_ctx`, `try_pown_ctx`, `try_rootn_ctx`, `try_hypot_ctx`

Compute powers, roots and the Euclidean norm.

The `pow` family (`pow_ctx`, `pown_ctx`, `powr_ctx` and their `try_` forms)
has an implementation limit on context precision. By default, the limit is
999,999 decimal digits, the precision component of
`DecimalContext::elementary_precision_limit`. Setting it to `None` or a
larger value removes this limit without a guarantee. Above the default limit,
the functions return the context-limit error immediately (`not_computed` in
the plain form) for an ordinary operand. They do not compute even the
exponent `0.5`, which would otherwise be a square root at that precision.

The cost is the reason for the limit: `pow(2, 0.5)` takes about 0.6 s at 100,000 digits,
14.7 s at 1,000,000 digits and more than 300 s at 10,000,000 digits. The
special cases for `pow` listed in IEEE 754-2019 9.2.1 still return values at
every context precision. `pown_ctx` applies `pow_ctx` to an integral
exponent and shares the same limit, including for an exact integral power.
`rootn_ctx` and `compound_ctx` were already under it. `sqrt_ctx` has no such
limit because it is a basic operation (IEEE 754-2019 5.4.1).

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

`pow_ctx(x, y)` implements the power operation of IEEE 754-2019 9.2. A
signaling NaN operand is quieted and raises `invalid_operation` before the
identities below apply. Otherwise, $x^{\pm 0}=1$, including when $x$ is zero,
infinite or a quiet NaN. Also, $\operatorname{pow}(+1,y)=1$ for every $y$,
including a quiet NaN, and $\operatorname{pow}(-1,\pm\infty)=1$.

For any other base and an infinite exponent, the magnitude of the base
determines the result: $|x|<1$ tends to zero for exponent $+\infty$ and
infinity for exponent $-\infty$; $|x|>1$ gives the reverse. A negative base
does not make these cases invalid.

For a zero base and negative integer exponent, the result is a signed infinity
selected by the zero sign and exponent parity, with `division_by_zero`:
$(-0)^{-1}=-\infty$ and $(-0)^{-2}=+\infty$. Positive integer powers
preserve the zero sign according to parity: $(-0)^3=-0$ and $(-0)^2=+0$.
Zero raised to a negative non-integer exponent returns positive infinity with
`division_by_zero`.

For integer powers within the bounded count, the implementation uses binary
square-and-multiply. It returns an exact power when it fits in $p$ digits and
otherwise returns the correctly rounded result. It also supports integral
exponents outside the bounded count by certifying the magnitude. For an odd
power of a negative base, it swaps the directed rounding directions before
restoring the sign.

For large integer exponents, the implementation decides zero and infinity
cases from the sign and parity without expanding the exponent. For example,
`pown_ctx(-0, Int::max_value())` returns `-0`,
`pown_ctx(-0, Int::min_value())` returns `+infinity` with `division_by_zero`,
and `pown_ctx(-infinity, Int::min_value())` returns `+0`.

For other integral exponents, the result is exact when the power fits in $p$
digits and correctly rounded otherwise. In decimal32,
`pow_ctx(3.339434, 3)` returns `37.24077`; the exact cube is
$37.240765000\ldots$. The operation treats $x^{0.5}$ as `sqrt_ctx`. It
certifies positive non-integer powers and treats a negative base with a finite
non-integer exponent as invalid. These IEEE rules intentionally differ from
[`decimal_gda`](decimal_gda.md), which follows General Decimal Arithmetic,
including its invalid result for $0^0$ and the `powx2015` vector rounded to
`1.00`.

`pown_ctx(x, n)` converts the integer $n$ exactly, so
$(-1)^{12345679}=-1$ at any precision. `rootn_ctx(x, n)` returns
$x^{1/n}$ for integer $n\ne 0$. An even root of a negative value and $n=0$
are invalid. For $n<0$, `rootn_ctx` returns infinity for $\pm 0$ with
`division_by_zero`. It returns an exactly representable root exactly; for
example, `rootn_ctx(0.008, 3)` returns `0.2` with no flag.

`hypot_ctx(x, y)` returns $\sqrt{x^2+y^2}$. It returns $+\infty$ if either
operand is infinite, even when the other is a quiet NaN. An exactly
representable norm is returned exactly; when $y$ is zero, it returns $|x|$.
For example, `hypot_ctx(0.3, 0.4)` returns `0.5`.

The implementation never expands an integral exponent with more than 4,096
digits. For a base other than $\pm 1$, $\pm 0$ or $\pm\infty$, the magnitude
$|y\ln|x||$ is far beyond any context. The result is therefore the overflow
or underflow value selected by the rounding direction; the base's relation to
1 and the exponent's sign determine which. The result sign follows parity.
This case does not raise `invalid_operation`.

A base with more than about 4,000 fractional digits still returns NaN with
`invalid_operation` when it does not meet that bound.

For an exact result, `pow_ctx` and `pown_ctx` select the cohort member whose
exponent is closest to the preferred exponent in IEEE 754-2019 9.2.2. For
`pow_ctx(x, y)`, the preferred exponent is $\lfloor y\,q_x\rfloor$; for
`pown_ctx(x, n)`, it is $\lfloor n\,q_x\rfloor$. Here $q_x$ is the exponent
stored in $x$, and the cohort member must fit in $p$ digits. In decimal64,
`pown_ctx(1.00, 2)` returns `1.0000`, `pown_ctx(-1.0, 3)` returns `-1.000`,
and `pown_ctx(-1E+5, 5)` returns `-1E+25` exactly with no flags. The results
of `pow_ctx(1.00, 1.5)` and `pow_ctx(4.00, 1.5)` are `1.000` and `8.000`.
A negative exponent cannot reach a preferred exponent above the value, so
`pown_ctx(1.00, -2)` returns `1`.

IEEE 754-2019 defines no preferred exponent when $y$ is infinite or a NaN;
`pow_ctx(1.00, Infinity)` therefore remains `1`. `decimal_gda` instead follows
the exponent from repeated multiplication in General Decimal Arithmetic.

### `Decimal::exp2_ctx`, `exp10_ctx`, `expm1_ctx`, `log2_ctx`, `log1p_ctx`, `try_exp2_ctx`, `try_exp10_ctx`, `try_expm1_ctx`, `try_log2_ctx`, `try_log1p_ctx`

Evaluate the base-2 and base-10 exponentials and logarithms of IEEE 754-2019 9.2,
including their forms near zero. Each function has the `f_ctx` and `try_f_ctx`
shape described at the start of this section.

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

Compute $2^x - 1$, $10^x - 1$, $\log_2(1 + x)$ and $\log_{10}(1 + x)$ as
specified by IEEE 754-2019 9.2. These forms avoid the cancellation in
`exp2(x) - 1` and the rounding of `1 + x` near zero. Each function has the
`f_ctx` and `try_f_ctx` shape described at the start of this section.

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

IEEE 754-2019 9.2.1 specifies the special values. For all four functions,
$f(\pm 0) = \pm 0$ and $f(+\infty) = +\infty$. For `exp2m1` and `exp10m1`,
$f(-\infty)=-1$. For `log2p1` and `log10p1`, $f(-1)=-\infty$ with
`division_by_zero`; their domain is $[-1, +\infty]$, so $x < -1$, including
$-\infty$, is invalid.

The exact results are $2^n - 1$ and $10^n - 1$ for integer $n$, and the integer
$k$ when $1 + x = 2^k$ or $1 + x = 10^k$. Under IEEE 754-2019 9.2.2, these
results have preferred exponent 0. Thus, in decimal64, `exp2m1_ctx(4)` returns
`15`, `exp2m1_ctx(-1)` returns `-0.5`, `exp10m1_ctx(-2.0)` returns `-0.99`,
and `log2p1_ctx(-0.50)` returns `-1`, all without flags.

A context that cannot hold an exact result rounds it and returns its flags. For
example, `log2p1_ctx(32767)` at precision 1 returns `2E+1`, a midpoint, with
`inexact`. The identity $\operatorname{log2p1}(1)=1$ is exact, while
$\operatorname{log10p1}(1)=\log_{10}2$. The rule $f(1)=+0$ of IEEE 754-2019 9.2.1
applies only to `log`, `log2` and `log10`.

Results below the subnormal range are rounded, never replaced, so they keep
the sign of $x$: `exp2m1_ctx(-1E-500)` returns `-0E-398` in decimal64 and
`-1E-398` when rounding toward $-\infty$. The same restricted contexts as
`exp_ctx` return `not_computed`.

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

Compute the reciprocal square root, compound and real-power operations of IEEE 754-2019 9.2.
`rsqrt_ctx` returns $1/\sqrt{x}$, `compound_ctx` returns $(1 + x)^n$ for an `Int32` $n$, and
`powr_ctx` returns $x^y = e^{y \ln x}$. Each operation has the `f_ctx`/`try_f_ctx` shape
described at the start of this section.

```mbti
pub fn Decimal::rsqrt_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::compound_ctx(Self, Int32, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::powr_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::try_rsqrt_ctx(Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::try_compound_ctx(Self, Int32, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::try_powr_ctx(Self, Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
```

`rsqrt_ctx` accepts $x$ in $[0, +\infty]$. A negative input, including $-\infty$, is
invalid; $\pm 0$ returns $\pm\infty$ with `division_by_zero`, and $+\infty$ returns
$+0$ (IEEE 754-2019 9.2.1). When $x = 2^{2i}5^{2j}$, the result is exact and has the
preferred exponent $-\lfloor Q(x)/2 \rfloor$ (IEEE 754-2019 9.2.2). In decimal64,
`rsqrt_ctx(4.00)` returns `0.5`, `rsqrt_ctx(1E+2)` returns `0.1`, and
`rsqrt_ctx(1E-400)` returns `1E+200`.

`compound_ctx(x, n)` follows these special cases from IEEE 754-2019 9.2.1:

| Input | Result |
| --- | --- |
| `compound(x, 0)` for $x \ge -1$ or a quiet NaN | 1 |
| `compound(x, n)` for $x < -1$, including when $n = 0$ | invalid |
| `compound(-1, n)` for $n < 0$ | $+\infty$ with `division_by_zero` |
| `compound(-1, n)` for $n > 0$ | $+0$ |
| `compound(±0, n)` | 1 |
| `compound(+∞, n)` for $n > 0$ | $+\infty$ |
| `compound(+∞, n)` for $n < 0$ | $+0$ |

An exact result has preferred exponent $\lfloor n \min(0, Q(x)) \rfloor$
(IEEE 754-2019 9.2.2). `compound_ctx(0.10, 2)` returns `1.2100`, and
`compound_ctx(0.00, 3)` returns `1.000000`. Every `Int32` value of $n$ is accepted,
including the `Int32` minimum $-2^{31}$.

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

Compute the trigonometric functions of $x$ and $\pi x$. Each has the
`f_ctx`/`try_f_ctx` shape described at the start of this section.

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

Compute the inverse trigonometric functions. `atan2(y, x)` returns the angle of the point
$(x, y)$. Each has the `f_ctx`/`try_f_ctx` shape described at the start of this section.

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

Compute the inverse circular functions measured in half-revolutions:
$\operatorname{asin}(x)/\pi$,
$\operatorname{acos}(x)/\pi$, $\operatorname{atan}(x)/\pi$ and
$\operatorname{atan2}(y, x)/\pi$. The ordinate is the receiver of `atan2pi_ctx`,
as in `y.atan2pi_ctx(x, ctx)`, and its result is in $[-1, 1]$ (IEEE 754-2019
9.2). Each operation has the `f_ctx` and `try_f_ctx` shapes described at the start
of this section.

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

IEEE 754-2019 9.2.1 gives these exact special cases; by Niven's theorem, they
are the only exact results:

| Operation | Input | Exact result |
| --- | --- | --- |
| $\operatorname{asinPi}$ | $\pm 0$ | $\pm 0$ |
| $\operatorname{asinPi}$ | $\pm 1$ | $\pm\tfrac12$ |
| $\operatorname{acosPi}$ | $1$ | $+0$ |
| $\operatorname{acosPi}$ | $-1$ | $1$ |
| $\operatorname{acosPi}$ | $\pm 0$ | $\tfrac12$ |
| $\operatorname{atanPi}$ | $\pm 0$ | $\pm 0$ |
| $\operatorname{atanPi}$ | $\pm 1$ | $\pm\tfrac14$ |
| $\operatorname{atanPi}$ | $\pm\infty$ | $\pm\tfrac12$ |
| $\operatorname{atan2Pi}$ | zero and infinite operands | the eleven results $\pm 0$, $\pm 1$, $\pm\tfrac12$, $\pm\tfrac14$ and $\pm\tfrac34$; the sign bit of a zero abscissa chooses the half-plane |
| $\operatorname{atan2Pi}$ | finite nonzero operands with $|y|=|x|$ | $\pm\tfrac14$ for $x > 0$; $\pm\tfrac34$ for $x < 0$ |

None of these results signals an exception. The functions use preferred exponent 0
(IEEE 754-2019 9.2.2): $\tfrac12$, $\tfrac14$, $\tfrac34$ and 1 are returned
as `0.5`, `0.25`, `0.75` and `1`, whatever the cohort of the operand. A context
with precision 1 is too narrow for the constant, so it rounds the result and
raises `inexact`.

For $|x| > 1$, including $\pm\infty$, the result is invalid for `asinpi` and
`acospi`.

Every other result is inexact and correctly rounded. For example,
$\operatorname{asinPi}(\pm\tfrac12)=\pm\tfrac16$ and
$\operatorname{acosPi}(\pm\tfrac12)=\tfrac13,\tfrac23$ are not terminating
decimals. For large $|x|$, `atanpi` approaches the representable values
$\pm\tfrac12$ and $\pm 1$ from one side; for tiny $|x|$, `acospi` does so; and
for extreme ratios, `atan2pi` does so. At those values, the rounding direction
decides between the anchor and its neighbour.

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

Domain and special values of the functions in the seven groups above, from `exp2` to `atanh`:

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
pub fn DecimalInterchange::abs(Self) -> Self
pub fn DecimalInterchange::neg(Self) -> Self
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
The ring laws hold exactly for `+`, `-` and `*` as long as no result is rounded
(a sum or a product whose exact coefficient fits the larger operand precision);
a rounded result is only approximately associative.
`FromNat` and `FromInteger` are documented under
[construction](#the-fromnat-and-frominteger-implementations).

### `@def.Floating`

`Decimal` implements the `floating` scalar trait.

```mbti
pub impl @def.Floating for Decimal
```

The trait methods are `classify`, `signum`, `precision`, `with_precision` and
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
`min_normal_contextual` is $10^{e_{\min}}$ of the converted context; its default $e_{\min}$ is $1 - e_{\max}$, that is $-999\,998$ for the default range of `new` (precision 34).
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
under the converted context; it returns `Err(division_by_zero)` for the
division-by-zero flag and `Err(domain_error)` for the invalid-operation flag.
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
limits, refinement limit); flag sets compare all six fields.
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
  "Luna-Flow/floating/binary",
  "Luna-Flow/floating/def",
  "Luna-Flow/luna-generic",
  "moonbitlang/core/bigint",
  "moonbitlang/core/debug",
}

// Values
pub let decimal_context_e_max_limit : Int32

pub let decimal_context_e_min_limit : Int32

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
pub fn Decimal::from_binary(@binary.Binary, precision~ : Int32, mode? : DecimalRoundingMode) -> Self
pub fn Decimal::from_binary_ctx(@binary.Binary, DecimalContext) -> (Self, DecimalFlags)
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
pub fn Decimal::is_negative_zero(Self) -> Bool
pub fn Decimal::is_normal(Self, DecimalContext) -> Bool
pub fn Decimal::is_quiet_nan(Self) -> Bool
pub fn Decimal::is_sign_minus(Self) -> Bool
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
pub fn Decimal::max_finite_contextual(@arithmetic.ArithmeticContext) -> Self
pub fn Decimal::max_num(Self, Self) -> Self
pub fn Decimal::maximum_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::maximum_magnitude_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::maximum_magnitude_number_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::maximum_number_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::min_normal_contextual(@arithmetic.ArithmeticContext) -> Self
pub fn Decimal::min_num(Self, Self) -> Self
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
pub fn Decimal::quantum_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::quiet_nan(payload? : @bigint.BigInt, negative? : Bool, precision? : Int32) -> Self
pub fn Decimal::remainder_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::rootn_ctx(Self, Int32, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::rsqrt_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::same_quantum(Self, Self) -> Bool
pub fn Decimal::scaleb_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::set_payload(Self, @bigint.BigInt) -> Self
pub fn Decimal::set_payload_signaling(Self, @bigint.BigInt) -> Self
pub fn Decimal::signaling_nan(payload? : @bigint.BigInt, negative? : Bool, precision? : Int32) -> Self
pub fn Decimal::signum(Self) -> @def.Sign
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
pub fn Decimal::to_binary(Self, precision~ : Int32, mode? : @binary.BinaryRoundingMode) -> @binary.Binary
pub fn Decimal::to_binary_ctx(Self, @binary.BinaryContext) -> (@binary.Binary, @binary.BinaryFlags)
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
pub fn DecimalContext::elementary_precision_limit(Self) -> Int32?
pub fn DecimalContext::equal(Self, Self) -> Bool
pub fn DecimalContext::from_arithmetic_context(@arithmetic.ArithmeticContext) -> Result[Self, @arithmetic.ArithmeticError]
pub fn DecimalContext::new(precision? : Int32, e_max? : Int32, rounding? : DecimalRoundingMode) -> Self
pub fn DecimalContext::not_equal(Self, Self) -> Bool
pub fn DecimalContext::precision(Self) -> Int32
pub fn DecimalContext::refinement_limit(Self) -> Int32?
pub fn DecimalContext::rounding(Self) -> DecimalRoundingMode
pub fn DecimalContext::try_new(precision? : Int32, e_max? : Int32, rounding? : DecimalRoundingMode) -> Result[Self, @arithmetic.ArithmeticError]
pub fn DecimalContext::with_e_max(Self, Int32) -> Self
pub fn DecimalContext::with_elementary_precision_limit(Self, Int32?) -> Self
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
pub fn DecimalInterchange::abs(Self) -> Self
pub fn DecimalInterchange::canonical(Self) -> Self
pub fn DecimalInterchange::copy(Self) -> Self
pub fn DecimalInterchange::copy_sign(Self, Self) -> Self
pub fn DecimalInterchange::encoding(Self) -> DecimalInterchangeEncoding
pub fn DecimalInterchange::format(Self) -> DecimalInterchangeFormat
pub fn DecimalInterchange::from_decimal(Decimal, DecimalInterchangeFormat) -> (Self, DecimalFlags)
pub fn DecimalInterchange::from_decimal_with_encoding(Decimal, DecimalInterchangeFormat, DecimalInterchangeEncoding) -> (Self, DecimalFlags)
pub fn DecimalInterchange::from_hex(String, DecimalInterchangeFormat) -> Result[Self, @arithmetic.ArithmeticError]
pub fn DecimalInterchange::from_hex_with_encoding(String, DecimalInterchangeFormat, DecimalInterchangeEncoding) -> Result[Self, @arithmetic.ArithmeticError]
pub fn DecimalInterchange::is_canonical(Self) -> Bool
pub fn DecimalInterchange::neg(Self) -> Self
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
