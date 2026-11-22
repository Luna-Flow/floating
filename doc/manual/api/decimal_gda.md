# decimal_gda API

## Purpose

`decimal_gda` implements the General Decimal Arithmetic Specification 1.70
(GDA 1.70) by M. F. Cowlishaw. It has three parts:

- A `Decimal` is a sign, a decimal coefficient of any length and a decimal
  exponent.
- A `GdaContext` carries the precision, the rounding, the exponent limits,
  clamping, the switch between extended and subset arithmetic, the flags and
  the enabled traps.
- Every GDA operation is a pure function that returns a `GdaOutcome`: the
  defined result, the next context and the conditions the operation raised.

The [tutorial](../tutorial/decimal_gda.md) shows the package in use; the
[design page](../design/decimal_gda.md) derives the rules stated here.

The package does not depend on the IEEE 754 package `decimal`. It publishes the
GDA layer only (`Decimal`, `GdaContext`, the `Gda*` types and the functions
named after the GDA operations) and adapters to the `Luna-Flow/arithmetic` and
`Luna-Flow/luna-generic` traits. The engine the functions are built on, which
keeps no flags, is private to the package.

Throughout this page a finite value is written $(-1)^s \cdot c \cdot 10^{q}$,
with coefficient $c \ge 0$ and exponent $q$. Its *adjusted exponent* is
$\hat q = q + \operatorname{digits}(c) - 1$, the exponent of its leading digit.
For a context with precision $p$, $E_{\mathrm{tiny}} = E_{\min} - p + 1$ is the
smallest exponent a result may have; with clamping,
$E_{\mathrm{top}} = E_{\max} - p + 1$ is the largest.

## Importing

Add the package to your `moon.pkg`:

```moonbit nocheck
import {
  "Luna-Flow/floating/decimal_gda",
}
```

The examples on this page call the package through the alias
`@decimal_gda.`, and the trait adapters through `@lf_arith.` for
`Luna-Flow/arithmetic`. Several examples define a local helper
`d(s)`, which parses a literal with `Decimal::from_string` and keeps its
exponent.

## The `Decimal` value

### `Decimal`

`Decimal` is an immutable GDA number: a finite number or a special value (an
infinity, a quiet NaN or a signaling NaN).

```mbti
pub struct Decimal {
  // private fields
} derive(@debug.Debug)
```

A finite number keeps its exponent, so `2.50` and `2.5` are distinct members of
the same *cohort*: they compare equal numerically and differ in
`compare_total`, `same_quantum` and printing. Zero is signed. A NaN carries a
sign and a non-negative integer payload. A payload of 0 stands for a NaN without diagnostic information
and is printed as `NaN`; GDA 1.70, page 11 (Special values) describes the payload as a positive integer when a NaN
has one, and pages 18 and 19 give the string form as `NaN` with optional digits that have no leading zeros.

Every value stores a precision, the precision of the value (`precision()`).
It is the precision of the context or constructor that produced it. GDA
operations ignore the precision of the value and use the precision of the
context instead.

The coefficient is stored as a persistent decimal limb array, so a value can
be shared freely.

### `Decimal::zero`, `Decimal::negative_zero`, `Decimal::one`

Return $+0$, $-0$ and $1$, each with exponent 0.

```mbti
pub fn Decimal::zero(precision? : Int32) -> Self
pub fn Decimal::negative_zero(precision? : Int32) -> Self
pub fn Decimal::one(precision? : Int32) -> Self
```

`precision` (default 34) is the precision of the value: the number of digits
the coefficient may have, from 1 to 999,999,999 (the implementation limit on
the precision of a context). A precision outside that range aborts, and the
message names the function and the argument; no constructor replaces it by 1.
The same check applies to every constructor that takes a `precision`.

### `Decimal::inf`, `Decimal::nan`, `Decimal::quiet_nan`, `Decimal::signaling_nan`

Build the special values.

```mbti
pub fn Decimal::inf(negative? : Bool, precision? : Int32) -> Self
pub fn Decimal::nan(precision? : Int32) -> Self
pub fn Decimal::quiet_nan(payload? : @bigint.BigInt, negative? : Bool, precision? : Int32) -> Self
pub fn Decimal::signaling_nan(payload? : @bigint.BigInt, negative? : Bool, precision? : Int32) -> Self
```

| Call | Result |
| --- | --- |
| `inf()` | $+\infty$ |
| `inf(negative=true)` | $-\infty$ |
| `nan()` | a positive quiet NaN with payload 0, which stands for a NaN without diagnostic information |

A payload has at most `precision - 1` digits, because GDA 1.70, page 11
(Special values) says that a payload is no larger than the coefficient can
represent less one digit. A negative payload, or one that is too wide for the
`precision` given, aborts; at precision 1 only the payload 0 exists.

An arithmetic operation that consumes a signaling NaN raises `InvalidOperation`
and replaces it by the quiet NaN with the same sign and payload.

### `gda_value_e_max`, `gda_value_e_tiny`

`gda_value_e_max` and `gda_value_e_tiny` are the limits of the exponents a finite
`Decimal` can hold.

```mbti
pub let gda_value_e_max : Int32
pub let gda_value_e_tiny : Int32
```

| Constant | Value | Limit on |
| --- | --- | --- |
| `gda_value_e_max` | $2^{31}-2 = 2{,}147{,}483{,}646$ | the adjusted exponent |
| `gda_value_e_tiny` | $-2^{31}+3 = -2{,}147{,}483{,}645$ | the exponent of the least digit; it is the $E_{\mathrm{tiny}}$ of the [working context of the plain operators](#decimaladd-decimalsub-decimalmul-decimaldiv-decimalneg), whatever the precision |

A finite value, a zero included (it has one digit), is stored only if
$q \ge$ `gda_value_e_tiny` and $\hat q \le$ `gda_value_e_max`, where $q$ is its
exponent, $c$ its coefficient and $\hat q = q + \operatorname{digits}(c) - 1$
its adjusted exponent.

The constructors `make`, `try_make` and `from_string` reject a value outside
the limits. The operations keep the values they produce inside, by rounding,
underflow or overflow, so every `Decimal` you can obtain satisfies the
condition. This is the invariant behind `x + 0 == x` and `x * 1 == x` for every
stored finite value (see
[the plain operators](#decimaladd-decimalsub-decimalmul-decimaldiv-decimalneg)).

A string outside the limits is read with a context when a rounded value is
wanted: [`to_number`](#to_number) rounds, overflows and underflows by the
context.

### `Decimal::make`, `Decimal::try_make`

`make(c, e, p)` returns $c \cdot 10^{q}$, where $q$ is `e`, as a value of `p`
digits of coefficient, the way the to-number conversion of GDA 1.70, page 21
(to-number) does.

```mbti
pub fn Decimal::make(@bigint.BigInt, Int32, Int32, mode? : GdaRoundingMode) -> Self
pub fn Decimal::try_make(@bigint.BigInt, Int32, Int32, mode? : GdaRoundingMode) -> Result[Self, @arithmetic.ArithmeticError]
```

The sign comes from the sign of `c`. The exponent is kept when `c` has at most
`p` digits. A longer coefficient is rounded once, in `mode` (default
`HalfEven`, one of the eight rounding algorithms of a context), to `p` digits,
and the rounded coefficient is not reduced.

| Call | Result |
| --- | --- |
| `make(1200, 0, 34)` | `1200` |
| `make(1200, -2, 34)` | `12.00` |
| `make(0, 5, 5)` | `0E+5` |
| `make(1000000, 0, 3)` | `1.00E+6` |

To remove trailing zeros use `Decimal::normalized` or `Decimal::trim`. No flags
are reported.

After the rounding, the value must be inside the implementation limit on the
exponents of a stored value
([`gda_value_e_max`, `gda_value_e_tiny`](#gda_value_e_max-gda_value_e_tiny)).
An exponent below `gda_value_e_tiny`, or an adjusted exponent above
`gda_value_e_max` (a carry of the rounding into the next power of ten
included), is never replaced by a zero or an infinity.

| Condition | `make` | `try_make` |
| --- | --- | --- |
| exponent or adjusted exponent outside the limits | aborts with a message that names both limits and the exponent | returns `Err` of the domain-error kind with the same message |
| precision outside `1..=999999999` | aborts | returns `Err` of the domain-error kind |

### Constructors from integers and binary values

Convert integers and binary values to decimal.

```mbti
pub fn Decimal::from_int(Int32, precision? : Int32) -> Self
pub fn Decimal::from_bigint(@bigint.BigInt, precision? : Int32) -> Self
pub fn Decimal::from_double(Double, precision? : Int32) -> Self
pub fn Decimal::from_float(Float, precision? : Int32) -> Self
pub fn Decimal::from_binary(@binary.Binary, precision~ : Int32, mode? : GdaRoundingMode) -> Self
```

| Argument | Result |
| --- | --- |
| an integer of at most `precision` digits | exponent 0 |
| an exact binary fraction | the exponent closest to 0 (trailing zeros are removed only down to exponent 0) |
| a longer or inexact value | rounded to exactly `precision` digits, half to even unless `mode` (for `from_binary`) says otherwise |

`precision` defaults to 34 digits; for `from_binary` it is required and
counts decimal digits, not the bits of the argument.

A binary floating-point number $m \cdot 2^{k}$ with $k < 0$ is first written
exactly as $m 5^{-k} \cdot 10^{k}$, so the conversion is exact whenever the
result fits in `precision` digits. For example, `from_double(0.1)` is the
exact binary64 value nearest to $0.1$, rounded half to even to 34 digits.

| Argument | Result |
| --- | --- |
| NaN | the quiet NaN (`from_double` keeps the sign) |
| an infinity | an infinity with the same sign |
| a zero | a zero with the same sign (`from_binary` returns $+0$) |

| Call | Result |
| --- | --- |
| `from_int(100)` | `100` (exponent 0) |
| `from_int(99999, precision=3)` | `1.00E+5` |
| `from_double(0.5)` | `0.5` |

### `Decimal::to_binary`

`to_binary` rounds the value to a `Binary` with `precision` significant bits.

```mbti
pub fn Decimal::to_binary(Self, precision~ : Int32, mode? : @binary.BinaryRoundingMode) -> @binary.Binary
```

`precision` is required and counts bits, from 1 to
`@binary.binary_precision_max` (outside that range the call aborts). `mode` is
a rounding-direction attribute of the radix of the result
(IEEE 754-2019 4.3.1 and 4.3.2) and defaults to `RoundTiesToEven`. Every rounding, ties-to-away
included, rounds the decimal once, from its value as an exact number, to `precision` bits, with no
intermediate rounding.

With `RoundTowardNegative` and `RoundTowardPositive` the two results enclose
the decimal value; the elementary functions build their certified input
intervals this way. Zeros map to $+0$, NaNs to the binary NaN.

### `Decimal::from_string`

`from_string` reads a GDA numeric string without a GDA context.

```mbti
pub fn Decimal::from_string(String, precision? : Int32) -> Result[Self, @arithmetic.ArithmeticError]
```

The accepted syntax is the GDA numeric-string grammar: an optional sign,
digits with an optional decimal point and an optional exponent `E±n`; or
`Infinity`, `Inf`, `NaN` or `sNaN` (case-insensitive) with an optional decimal
NaN payload.

The exponent is kept exactly, so `from_string("2.50")` has exponent $-2$. A
literal with more than `precision` (default 34) significant digits is rounded
half to even and its trailing zeros are removed.

| Input | Result |
| --- | --- |
| a malformed literal | `Err(parse_error)` |
| a precision outside `1..=999999999` | `Err` of the domain-error kind |
| a NaN whose payload is wider than `precision - 1` digits (GDA 1.70, page 11 (Special values)) | `Err(parse_error)` |
| a literal whose value (zero included) has an exponent below `gda_value_e_tiny` after the rounding, or an adjusted exponent above `gda_value_e_max` | `Err` of the domain-error kind that names both limits and the exponent |

No context exponent range applies, only the implementation limit on the
exponents of a stored value
([`gda_value_e_max`, `gda_value_e_tiny`](#gda_value_e_max-gda_value_e_tiny)).
A literal outside the limits is not a malformed literal, and it is not folded
into an infinity or a zero: `"1e3000000000"` and `"1e-3000000000"` are errors.
Use the package function [`to_number`](#to_number) when a rounded value is
wanted or when the exponent limits, flags or traps of a context must apply.

### `Decimal::to_string`, `Decimal::output`

Print the value in GDA scientific notation, with lowercase special values.

```mbti
pub fn Decimal::to_string(Self) -> String
pub fn Decimal::output(Self, &Logger) -> Unit
pub impl Show for Decimal
```

| Value | Printed as |
| --- | --- |
| a finite number with $q \le 0$ and $\hat q \ge -6$ | no exponent: `0.000123`, `7.50` |
| any other finite number | one digit, the remaining digits after a point, and `E±`$\hat q$: `1.23E+7`, `1E-7`, `0E+2` |
| an infinity | `inf` or `-inf` |
| a NaN | `nan`, `snan` or `-nan`, followed by the payload when it is not zero |

For the GDA spellings `Infinity`, `NaN` and `sNaN` use
[`Decimal::to_sci_string`](#decimalto_sci_string-decimalto_eng_string).

### `Decimal::to_sci_string`, `Decimal::to_eng_string`

Print a value with GDA to-scientific-string or to-engineering-string.
Neither conversion uses a context.

```mbti
pub fn Decimal::to_sci_string(Self) -> String
pub fn Decimal::to_eng_string(Self) -> String
```

Engineering notation uses an exponent that is a multiple of three (`123E+5`
prints as `12.3E+6`). Special values print as `Infinity`, `-Infinity`, `NaN`,
`sNaN` with payload. To convert a numeric string under a context first, call
[`to_number`](#to_number) and print its value.

## Observing a value

### `Decimal::classify`, `Decimal::signum`, `Decimal::precision`

Report the class, the numeric sign and the precision of a value.

```mbti
pub fn Decimal::classify(Self) -> @arithmetic.FpClass
pub fn Decimal::signum(Self) -> @def.Sign
pub fn Decimal::precision(Self) -> Int32
```

`classify` returns `Finite`, `Infinity` or `NaN`. `precision` returns the
precision of the value, defined in [`Decimal`](#decimal).

| Value | `signum` returns |
| --- | --- |
| a zero of either sign | `Zero` |
| a NaN | `Zero` |
| any other value | `Positive` or `Negative` |

To read the sign bit, use `is_signed`.

### `Decimal::coefficient`, `Decimal::exponent10`

Return the stored representation $(c, q)$ of a value.

```mbti
pub fn Decimal::coefficient(Self) -> @bigint.BigInt
pub fn Decimal::exponent10(Self) -> Int32
```

`coefficient` returns $c \ge 0$: the payload for a NaN and 0 for an
infinity. `exponent10` returns $q$, and 0 for a special value. GDA 1.70 has
no operation named `quantum`: its operations are `quantize` (GDA 1.70, page 36 (quantize))
and `same-quantum` (GDA 1.70, page 48 (same-quantum)).

### Class and sign predicates

Test the class and the sign of a value.

```mbti
pub fn Decimal::is_finite(Self) -> Bool
pub fn Decimal::is_infinite(Self) -> Bool
pub fn Decimal::is_nan(Self) -> Bool
pub fn Decimal::is_zero(Self) -> Bool
pub fn Decimal::is_signed(Self) -> Bool
pub fn Decimal::is_negative_zero(Self) -> Bool
```

`is_signed` reads the sign bit, so it is true for $-0$, $-\infty$ and negative
NaNs. `is_zero` is true for a finite zero of any exponent.

### `Decimal::is_qnan`, `Decimal::is_snan`

Test whether a value is a quiet NaN or a signaling NaN.

```mbti
pub fn Decimal::is_qnan(Self) -> Bool
pub fn Decimal::is_snan(Self) -> Bool
```

### `Decimal::is_canonical`

`is_canonical` always returns `true`, because every `Decimal` value is
canonical. Only an interchange encoding can be non-canonical: see
[`GdaInterchange::is_canonical`](#gdainterchangecanonical-gdainterchangeis_canonical).

```mbti
pub fn Decimal::is_canonical(Self) -> Bool
```

### `Decimal::nan_payload`

`nan_payload` returns the payload of a NaN, and 0 for any other value.

```mbti
pub fn Decimal::nan_payload(Self) -> @bigint.BigInt
```

The payload operations of IEEE 754-2019 9.7 (NaN payload operations:
`getPayload`, `setPayload`, `setPayloadSignaling`) are in
[`decimal`](decimal.md), not here.

## Sign, cohort and precision transformations

### Sign operations

Every operation here changes only the sign bit of a value. None of them rounds or signals, even for a
signaling NaN.

```mbti
pub fn Decimal::neg(Self) -> Self
pub fn Decimal::abs(Self) -> Self
pub fn Decimal::copy(Self) -> Self
pub fn Decimal::copy_abs(Self) -> Self
pub fn Decimal::copy_negate(Self) -> Self
pub fn Decimal::copy_sign(Self, Self) -> Self
```

| Operation | Result |
| --- | --- |
| `neg`, `copy_negate` | the value with its sign flipped |
| `abs`, `copy_abs` | the value with its sign cleared |
| `copy` | the value |
| `copy_sign(x, y)` | `x` with the sign bit of `y` |

`copy`, `copy_abs`, `copy_negate` and `copy_sign` are the GDA copy operations (GDA 1.70, pages 43 and 44 (Miscellaneous operations)); `neg` and `abs` act as `copy_negate` and `copy_abs`. The versions that round are the package functions
[`minus`, `plus`, `abs`](#apply-plus-minus-abs).

### `Decimal::normalized`, `Decimal::trim`, `Decimal::with_precision`

`normalized` and `trim` move a value within its cohort. `with_precision` rounds a value to a new
precision.

```mbti
pub fn Decimal::normalized(Self) -> Self
pub fn Decimal::trim(Self) -> Self
pub fn Decimal::with_precision(Self, Int32, GdaRoundingMode) -> Self
```

`normalized` rounds half to even to the precision of the value (see [`Decimal`](#decimal)) and
reduces the result, removing all trailing zeros: `7.50` becomes `7.5` and `1200` becomes `1.2E+3`.

`trim` removes only fractional trailing zeros and never makes the exponent positive: `7.50`
becomes `7.5` and `1200` stays `1200`. A zero becomes `0` with exponent 0.

`with_precision(p, mode)` rounds to `p` digits with the rounding algorithm `mode`, removes trailing
zeros and sets the precision of the value. A special value only gets the new precision.

None of the three reports flags.

A carry of the rounding at the top of the
[implementation limit on the exponents of a stored value](#gda_value_e_max-gda_value_e_tiny)
follows the Overflow rule (GDA 1.70, page 53 (Overflow)) with that limit as the largest adjusted exponent, so the result is never a finite
value above the limit. For example, `9999E+2147483643` rounded to 2 digits is `inf` in the rounding
algorithms that round away from zero or to nearest. In the algorithms that round toward zero it is
`9.9E+2147483646`, the largest finite value of that width.

### `Decimal::identical`

`identical` tests whether two values are the same datum.

```mbti
pub fn Decimal::identical(Self, Self) -> Bool
```

It is true for two values with the same class, sign, coefficient and exponent, the same precision and, for NaNs, the same payload and the same kind (quiet or signaling). It is
`compare_total` being 0 together with equal precision; GDA defines `compare_total`
without a precision.

`2.5` and `2.50` are equal by `==` and not identical. `0` and `-0` are equal and not identical. Two
NaNs with the same payload are identical, although `==` and `compare` treat every NaN alike.

The precision of the value is part of the relation because
[the plain operators](#decimaladd-decimalsub-decimalmul-decimaldiv-decimalneg) round to the larger
precision of their operands. `1` with precision 3 and `1` with precision 34 are equal and have
`compare_total` 0, but divided by `3` they give `0.333` and `0.3333333333333333333333333333333333`.
Two identical values give the same result in every function.

### `Decimal::same_quantum`

`same_quantum` tests whether two values have the same exponent.

```mbti
pub fn Decimal::same_quantum(Self, Self) -> Bool
```

| Operands | Result |
| --- | --- |
| two finite values | true when their exponents are equal |
| two infinities | true |
| two NaNs | true |
| any other pair | false |

## The GDA context

### `GdaContext`

`GdaContext` is the immutable GDA context. It holds an arithmetic policy, the flags of the
context and the enabled traps.

```mbti
pub struct GdaContext {
  // private fields
}
```

The policy is the precision $p \ge 1$, the rounding (a `GdaRoundingMode`),
$E_{\min} \le E_{\max}$, `clamp` and `extended`. The flags are a `GdaFlags` value that
operations only ever enlarge; the traps are a `GdaTrapSet`.

Neither the flags nor the traps influence the numerical result of an operation. They decide
the next context and whether the outcome is `Completed` or `Trapped`, as
[Trap selection](#trap-selection) states.

### `GdaContext::new`, `GdaContext::try_new`

Build a context with an empty set of flags. `new` aborts on an invalid parameter; `try_new`
takes the same parameters and returns a `Result`.

```mbti
pub fn GdaContext::new(precision? : Int32, rounding? : GdaRoundingMode, e_min? : Int32, e_max? : Int32, clamp? : Bool, extended? : Bool, traps? : GdaTrapSet) -> Self
pub fn GdaContext::try_new(precision? : Int32, rounding? : GdaRoundingMode, e_min? : Int32, e_max? : Int32, clamp? : Bool, extended? : Bool, traps? : GdaTrapSet) -> Result[Self, @arithmetic.ArithmeticError]
```

The defaults are:

| Parameter | Default |
| --- | --- |
| `precision` | `34` |
| `rounding` | `HalfEven` |
| `e_min` | `-999_999_999` |
| `e_max` | `999_999_999` |
| `clamp` | `false` |
| `extended` | `true` |
| `traps` | none |

The parameters must satisfy the rules below. `try_new` returns `Err(domain_error)` naming the
invalid parameter, and `new` aborts with the same message.

- `precision` is within `1..=999_999_999`, `e_max` within `0..=999_999_999` and `e_min`
  within `-999_999_999..=0`. These implementation limits are those of decNumber's
  `decContext.h`; they keep $E_{\mathrm{tiny}}$, $E_{\mathrm{top}}$ and exponent arithmetic
  within `Int`. GDA 1.70 itself fixes no limit.
- `e_min` is `-e_max`, `1 - e_max` (the IEEE 754 rule) or `-e_max - 1`. GDA 1.70, page 10
  (Abstract representation of numbers) requires the magnitudes of $E_{\min}$ and $E_{\max}$ to
  differ by at most one, so that the range of results is balanced. A range such as
  `e_min=-50, e_max=60` is rejected. The same passage requires `Elimit` to exceed five times
  the maximum coefficient length when there is one. The context has no maximum coefficient
  length, and 913 rows of the official decTest corpus run with an `e_max` below four times the
  precision, so the library does not enforce that requirement.

`clamp` and `extended` are not parameters of the context in the GDA text. They are decNumber
extensions that the library keeps, and the official decTest files use both.

- `clamp=true` is the fold-down of the Clamped condition (GDA 1.70, page 51 (Exceptional
  conditions)). It limits exponents to $E_{\max} - p + 1$, as the interchange formats do.
- `extended=false` selects the GDA subset arithmetic of Appendix A (GDA 1.70, page 55
  (Appendix A, The X3.274 subset); footnote 43: a parameter of the context "might" select it).
  In subset arithmetic, every operation that takes a context rounds an operand longer than $p$
  digits first (GDA 1.70, page 56 (Appendix A, The X3.274 subset)), which raises
  `LostDigits` when it is inexact; so `reduce(1234567891)` at precision 9 raises `LostDigits`
  and `next_toward(1234567891, 0)` is `1.23456788E+9`. The logical operations, the total orders and the
  classifications do not round their operands. Special values cannot be parsed, `divide` and `power` remove
  fractional trailing zeros, and `fma` is invalid.
  - The result of every operation that takes a context obeys three rules (GDA 1.70, page 55 (Appendix A, The X3.274
    subset)): a zero is $+0$ with exponent 0; a result below $E_{\min}$ (a subnormal result) is
    $+0$ with exponent 0 and the flags `Underflow`, `Subnormal`, `Inexact` and `Rounded` (and
    `Clamped`, where the operation raised it before, as `exp` does); and a
    result with a positive exponent has exponent 0 when it then has at most $p$ digits. So
    `reduce` of `1200` is `1200`, `scaleb(12, 2)` is `1200`, `remainder(1.4E+3, 5E+2)` is `400`,
    `round_to_integral_value(1.2E+3)` is `1200`, `sqrt(1E+2)` is `10`, `power(-0, 3)` is $+0$ and `next_toward(0, 1)` is
    $+0$ with `Underflow`.
  - The copy operations (`copy`, `copy_abs`, `copy_negate`, `copy_sign`) take no context and are
    outside the rules: `copy_negate(0)` is $-0$.
  - `quantize` and `rescale` keep the exponent of a zero and a positive exponent (`quantize` is the
    exception of page 55, `rescale` its former name): `quantize(-0, 1E+2)` is `0E+2`. `to_number`
    keeps a positive exponent, and reads a zero as $+0$ with exponent 0.
  - Appendix A does not name `reduce`, `rescale`, `scaleb`, `shift`, `rotate`, `remainder`,
    `remainder_near`, the two round-to-integral operations or `next_toward`; the rules apply to
    them as to every operation. decNumber 3.68 gives other results for some of them
    ([conformance](../conformance/decimal_gda.md#subset-arithmetic-and-operations-appendix-a-does-not-name)).

> [!NOTE]
> `exp`, `ln`, `log10` and `power` with a non-integer exponent accept only a context with
> $p \le 999\,999$, $E_{\max} \le 999\,999$ and $E_{\min} \ge -999\,999$; with the default
> exponent range they return a NaN and raise `InvalidContext`, as
> [the implementation limit of these operations](#implementation-limit-of-exp-ln-log10-and-power)
> states.

### Default contexts

Return the default contexts (GDA 1.70, page 16 (Default contexts)): `basic_default`, and the
extended default contexts `decimal32`, `decimal64` and `decimal128`.

```mbti
pub fn GdaContext::basic_default() -> Self
pub fn GdaContext::decimal32(rounding? : GdaRoundingMode) -> Self
pub fn GdaContext::decimal64(rounding? : GdaRoundingMode) -> Self
pub fn GdaContext::decimal128(rounding? : GdaRoundingMode) -> Self
```

| Context | $p$ | rounding | $E_{\min}$ | $E_{\max}$ | clamp | extended | traps |
| --- | ---: | --- | ---: | ---: | --- | --- | --- |
| `basic_default` | 9 | `HalfUp` | $-999\,999\,999$ | $999\,999\,999$ | no | no | DivisionByZero, InvalidOperation, Overflow, Underflow, Clamped |
| `decimal32` | 7 | `HalfEven` | $-95$ | $96$ | yes | yes | none |
| `decimal64` | 16 | `HalfEven` | $-383$ | $384$ | yes | yes | none |
| `decimal128` | 34 | `HalfEven` | $-6143$ | $6144$ | yes | yes | none |

`basic_default` is the basic default context of the specification: precision 9, round-half-up,
and every trap enabled except inexact, rounded and subnormal (GDA 1.70, page 16 (Default
contexts)). The library also leaves the lost-digits trap off, because Appendix A says that the Lost digits condition should be set to 0 in
default contexts (GDA 1.70, page 56 (Appendix A, The X3.274 subset)). It sets `extended=false` for this context (the X3.274 subset of Appendix A),
which the definition of the basic default context in GDA 1.70 does not set.

`decimal32`, `decimal64` and `decimal128` are the extended default contexts for the IEEE 754
formats: round-half-even and no traps. `rounding` replaces the rounding algorithm when given.

`GdaContext::new()` is not `basic_default()`: it has precision 34, half-even and no traps. The
values are created once and shared.

### `GdaContext::with_precision`, `GdaContext::with_rounding`, `GdaContext::with_exponent_range`

Return a copy of the context with one setting changed.

```mbti
pub fn GdaContext::with_precision(Self, Int32) -> Self
pub fn GdaContext::with_rounding(Self, GdaRoundingMode) -> Self
pub fn GdaContext::with_exponent_range(Self, e_min~ : Int32, e_max~ : Int32) -> Self
```

The result is checked like `new`: a precision or exponent range outside
[the rules of `new`](#gdacontextnew-gdacontexttry_new) aborts. The flags, the traps, `clamp`,
`extended` and the refinement limit are kept.

### Parameters of a context

Read the arithmetic policy of a context.

```mbti
pub fn GdaContext::precision(Self) -> Int32
pub fn GdaContext::rounding(Self) -> GdaRoundingMode
pub fn GdaContext::e_min(Self) -> Int32
pub fn GdaContext::e_max(Self) -> Int32
pub fn GdaContext::clamp(Self) -> Bool
pub fn GdaContext::extended(Self) -> Bool
pub fn GdaContext::radix(Self) -> Int32
```

`radix` always returns 10.

### `GdaContext::flags`, `GdaContext::traps`

Read the flags of the context and the enabled traps.

```mbti
pub fn GdaContext::flags(Self) -> GdaFlags
pub fn GdaContext::traps(Self) -> GdaTrapSet
```

### `GdaContext::refinement_limit`, `GdaContext::with_refinement_limit`

Read and set the number of refinement steps of the certified elementary functions `exp`, `ln`,
`log10` and `power`.

```mbti
pub fn GdaContext::refinement_limit(Self) -> Int32?
pub fn GdaContext::with_refinement_limit(Self, Int32?) -> Self
```

`exp`, `ln`, `log10` and `power` refine an enclosure of the result at most `Some(12)` times by
default. A rare argument close to a rounding boundary may need more: `with_refinement_limit(Some(24))`
allows 24 steps, and `None` removes the count, so that the working precision stops at a resource
bound. A limit below 1 is one step.

When the limit is reached, the plain functions return a NaN with `invalid_operation`, and
[`try_exp`, `try_ln`, `try_log10`, `try_power`](#try_exp-try_ln-try_log10-try_power) return `Err`.

### `GdaContext::trap`, `GdaContext::with_traps`, `GdaContext::clear_flags`, `GdaContext::reset`

Return a new context with changed traps or flags; the receiver is not modified.

```mbti
pub fn GdaContext::trap(Self, GdaSignal, enabled? : Bool) -> Self
pub fn GdaContext::with_traps(Self, GdaTrapSet) -> Self
pub fn GdaContext::clear_flags(Self) -> Self
pub fn GdaContext::reset(Self) -> Self
```

| Method | Effect |
| --- | --- |
| `trap(s)` | enables one trap, or disables it with `enabled=false` |
| `with_traps` | replaces the whole set |
| `clear_flags` | empties the flags and keeps the traps |
| `reset` | empties both |

### `GdaRoundingMode`

`GdaRoundingMode` is the type of the rounding of a context. Its eight values are the rounding
algorithms (GDA 1.70, pages 13 and 14 (Abstract representation of context)).

```mbti
pub(all) enum GdaRoundingMode {
  HalfEven
  HalfUp
  HalfDown
  Down
  Ceiling
  Floor
  Up
  ZeroFiveUp
}
```

When the exact result lies strictly between two representable neighbours, the algorithms
choose as follows.

| Rounding | Result |
| --- | --- |
| `Down` | the neighbour nearer zero |
| `Up` | the neighbour farther from zero |
| `Ceiling` | the larger neighbour |
| `Floor` | the smaller neighbour |
| `HalfEven` | the nearer neighbour; an exact tie goes to the one with an even last digit |
| `HalfUp` | the nearer neighbour; an exact tie goes away from zero |
| `HalfDown` | the nearer neighbour; an exact tie goes towards zero |
| `ZeroFiveUp` | rounds towards zero unless that leaves a last digit of 0 or 5, in which case it rounds away from zero |

The [design page](../design/decimal_gda.md#rounding-to-precision) gives each algorithm as a
formula.

## Signals, flags and traps

### `GdaSignal`

`GdaSignal` names the eight signals of GDA 1.70 and the Lost digits signal of its Appendix A. Each has a flag in the flags of
a context and a trap-enabler.

```mbti
pub(all) enum GdaSignal {
  Clamped
  DivisionByZero
  Inexact
  InvalidOperation
  LostDigits
  Overflow
  Rounded
  Subnormal
  Underflow
}
```

The specification has eight signals (GDA 1.70, page 15 (flags and
trap-enablers)): `Clamped`, `DivisionByZero`, `Inexact`, `InvalidOperation`,
`Overflow`, `Rounded`, `Subnormal` and `Underflow`. `LostDigits` is the ninth,
raised only in subset arithmetic (GDA 1.70, page 56 (Appendix A, The X3.274 subset)).

Four conditions that the specification says signal invalid-operation are not
signals: conversion syntax, division impossible, division undefined and invalid
context (GDA 1.70, pages 51 and 52 (Exceptional conditions)). They are
conditions of `GdaFlags`, and raising any of them raises the signal
`InvalidOperation`; [`GdaFlags::contains`](#gdaflagsnew-gdaflagscontains-gdaflagscombine)
states how.

### `GdaFlags`

`GdaFlags` is a set of conditions. It records both the conditions raised by one
operation and the flags of a context. It holds the thirteen conditions the
library raises, which are the twelve conditions of the Exceptional conditions section (GDA 1.70, pages 51 to 53) other than Insufficient storage, and Lost digits of Appendix A. Keeping the conditions apart is explained on the
[design page](../design/decimal_gda.md#keep-the-detailed-invalid-conditions).

```mbti
pub struct GdaFlags {
  // private fields
} derive(Eq)
```

The fields are private. Each of the 13 conditions is read with a method of the
same name, such as `raised().inexact()` or `flags().division_by_zero()`. The
only public constructor is `new`, so sets are built only with `new` and
`combine`. `GdaTrapSet` reads the same way, with one method for each of the
nine signals.

### `GdaFlags::new`, `GdaFlags::contains`, `GdaFlags::combine`

`new` is the empty set, `combine` the field-wise union, and `contains` the
membership test of a *signal*, with the GDA invalid-operation grouping. The
accessor methods read one *condition* each.

```mbti
pub fn GdaFlags::new() -> Self
pub fn GdaFlags::contains(Self, GdaSignal) -> Bool
pub fn GdaFlags::combine(Self, Self) -> Self
```

`combine` is associative, commutative and idempotent, with `new()` as identity.

`contains(s)` reads the field for `s`, except that `contains(InvalidOperation)`
is true when any of `invalid_operation`, `conversion_syntax`,
`division_impossible`, `division_undefined` or `invalid_context` is set. Use
`contains(InvalidOperation)` to ask whether the signal was raised.

The accessor `invalid_operation()` reads the plain Invalid operation condition
only, and the plain condition is not raised with every one of the four. A
division undefined or impossible raises it; a conversion syntax error or an
invalid context does not. This is as in decNumber, whose status word the
decTest rows describe.

### `GdaTrapSet`

`GdaTrapSet` is the set of enabled trap-enablers, one for each of the nine
signals.

```mbti
pub struct GdaTrapSet {
  // private fields
} derive(Eq)
```

### `GdaTrapSet::new`, `GdaTrapSet::with_signal`, `GdaTrapSet::contains`

Build and query trap sets.

```mbti
pub fn GdaTrapSet::new() -> Self
pub fn GdaTrapSet::with_signal(Self, GdaSignal, enabled? : Bool) -> Self
pub fn GdaTrapSet::contains(Self, GdaSignal) -> Bool
```

`new` enables no trap. `with_signal(s)` enables one trap, or disables it with
`enabled=false`. `contains(s)` reads the trap-enabler of `s`. The trap of
`InvalidOperation` fires for every condition that signals it, as
[Trap selection](#trap-selection) states.

### `GdaOutcome`

`GdaOutcome[T]` is the result of every GDA operation.

```mbti
pub enum GdaOutcome[T] {
  Completed(T, GdaContext, GdaFlags)
  Trapped(GdaSignal, T, GdaContext, GdaFlags)
}
```

Both variants carry the GDA-defined result, the next context and the
conditions raised by this operation. `Trapped` also names the trap that fired.

Outside the package a caller can `match` on the enum and use the accessors, but
only the GDA operations, `GdaOutcome::completed` and `GdaOutcome::absorb`
construct an outcome. `GdaOutcome::resume_defined` turns a trapped outcome into
its defined result.

### `GdaOutcome::value`, `GdaOutcome::next_context`, `GdaOutcome::raised`

Read the fields that both variants share, without a `match`.

```mbti
pub fn[T] GdaOutcome::value(Self[T]) -> T
pub fn[T] GdaOutcome::next_context(Self[T]) -> GdaContext
pub fn[T] GdaOutcome::raised(Self[T]) -> GdaFlags
```

`value` is the defined result, also for `Trapped`. `next_context` is the
context with the updated flags. `raised` is the conditions of this operation
only.

### `GdaOutcome::completed`, `GdaOutcome::absorb`

Build the outcomes a pipeline needs.

```mbti
pub fn[T] GdaOutcome::completed(T, GdaContext) -> Self[T]
pub fn[T, U] GdaOutcome::absorb(Self[T], Self[U]) -> Self[T]
```

`completed(v, c)` is the outcome of an operation that raised nothing: `v` and
`c` unchanged, empty `raised`.

`a.absorb(b)` keeps the value, the context (traps included) and the trap of
`a`. The conditions that `b` raised join `raised` and the flags of the next
context. In the flags, `invalid_operation` is set when one of the
[four detailed invalid conditions](#gdaflagsnew-gdaflagscontains-gdaflagscombine)
is among them. When `a` completed and `b` trapped, the result is `Trapped` with
the signal of `b`. The traps of `a` are not tested against the conditions of
`b`. [`GdaDecimalChecked`](decimal_gda_checked.md) uses `absorb` for the right
operand of a binary operation.

### `GdaOutcome::resume_defined`

Turns a `Trapped` outcome into a `Completed` one; it is the only way to do so.

```mbti
pub fn[T] GdaOutcome::resume_defined(Self[T]) -> Self[T]
```

`Completed` is returned unchanged. `Trapped(s, v, C, R)` becomes
`Completed(v, C, none)`, where `C` is the next context that the outcome carries (not the input
context of [Trap selection](#trap-selection)) and `none` is an empty `raised`; this is the GDA rule for continuing after a trap with the
defined result. `GdaDecimalChecked::resume_defined` calls it.

### Trap selection

A GDA function ends in the same three steps. Let $R$ be the conditions the
operation raised and $C$ the input context.

1. If $R$ is empty the outcome is `Completed(v, C, none)`: the same context
   comes back.
2. Otherwise the next context $C'$ is $C$ with flags
   $C.\mathrm{flags} \cup R$, where the `invalid_operation` flag is also set
   whenever $R$ contains one of the four detailed invalid conditions.
3. The trapped signal is the first $s$ in the order below with
   `raised.contains(s)` and `traps.contains(s)`: InvalidOperation,
   DivisionByZero, Overflow, Underflow, Subnormal, Inexact, Rounded, Clamped,
   LostDigits. If there is one the outcome is `Trapped(s, v, C', R)`,
   otherwise `Completed(v, C', R)`.

Because `contains(InvalidOperation)` covers the detailed invalid conditions,
the one `InvalidOperation` trap catches all of them, and the trapped signal is
`InvalidOperation` whichever condition raised it.

```moonbit
///|
test "GDA context, flags and traps" {
  let ctx = @decimal_gda.GdaContext::decimal64().trap(InvalidOperation)
  let zero = @decimal_gda.Decimal::zero()
  let out = @decimal_gda.divide(zero, zero, ctx) // 0/0
  inspect(out.value(), content="nan")
  inspect(out.raised().division_undefined(), content="true")
  inspect(out.raised().contains(InvalidOperation), content="true")
  match out {
    @decimal_gda.GdaOutcome::Trapped(signal, _, _, _) =>
      inspect(signal == InvalidOperation, content="true")
    @decimal_gda.GdaOutcome::Completed(_, _, _) => fail("expected a trap")
  }
  inspect(out.next_context().flags().invalid_operation(), content="true")
  inspect(ctx.flags() == @decimal_gda.GdaFlags::new(), content="true")
  inspect(ctx.reset().traps() == @decimal_gda.GdaTrapSet::new(), content="true")
}
```

## GDA operations

Every function in this section takes its operands (a string for `to_number`) and a
`GdaContext` and returns a `GdaOutcome` built by the [trap selection](#trap-selection) rule,
except the four `try_` functions, which return it in a `Result`. A signaling-NaN operand raises
`InvalidOperation` and yields the corresponding quiet NaN; a quiet NaN operand
propagates without raising anything (the first NaN operand wins). In subset
contexts (`extended=false`) finite operands longer than the precision are
rounded first (see [`GdaContext::new`](#gdacontextnew-gdacontexttry_new)).
Unless stated otherwise the result is the exact result, correctly rounded, and
when it is exact it has the *ideal exponent* listed for the operation.

### `to_number`

`to_number` converts a string to a `Decimal` by the GDA to-number conversion.

```mbti
pub fn to_number(String, GdaContext) -> GdaOutcome[Decimal]
```

The literal keeps its exponent unless it must be rounded to the precision or
clamped to the exponent range. Overflow and underflow are decided from the
exact exponent of the text, however large.

Malformed text gives a quiet NaN with `ConversionSyntax`. In subset contexts
infinities and NaNs are also a conversion-syntax error.

### `apply`, `plus`, `minus`, `abs`

Round one operand to the context: `plus` is $0 + x$, `minus` is $0 - x$, `abs`
is $|x|$, and `apply` is the plain conversion of a value to the context.

```mbti
pub fn apply(Decimal, GdaContext) -> GdaOutcome[Decimal]
pub fn plus(Decimal, GdaContext) -> GdaOutcome[Decimal]
pub fn minus(Decimal, GdaContext) -> GdaOutcome[Decimal]
pub fn abs(Decimal, GdaContext) -> GdaOutcome[Decimal]
```

The ideal exponent is that of the operand.

A zero result takes its sign from the GDA rule for a zero sum. `plus(-0)` and
`minus(0)` are $-0$ under `Floor` and $+0$ under every other rounding
algorithm, while `plus(0)`, `minus(-0)` and `abs` of either zero are $+0$. In a
subset context every zero result is $+0$.

In an extended context `apply` keeps the sign of a zero; it does not round subset operands first.

### `add`, `subtract`, `multiply`, `divide`, `fma`

Perform the basic arithmetic operations; `fma(a, b, c)` is $a \times b + c$
with a single rounding.

```mbti
pub fn add(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]
pub fn subtract(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]
pub fn multiply(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]
pub fn divide(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]
pub fn fma(Decimal, Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]
```

The ideal exponent of each operation, with $q_1$ and $q_2$ the exponents of the
first and second operand:

| Operation | Ideal exponent |
| --- | --- |
| `add`, `subtract` | $\min(q_1, q_2)$ |
| `multiply` | $q_1 + q_2$ |
| `divide` | $q_1 - q_2$ (an inexact quotient has a full $p$-digit coefficient) |
| `fma` | the `add` rule applied to the exact product and the addend |

An exact zero sum is $-0$ when both operands are negative, $+0$ when both are
positive, and otherwise $+0$, or $-0$ under `Floor`. For `subtract` the
operands are the first operand and the negated second; in a subset context a
second operand longer than $p$ digits is first rounded with its own sign and
then negated ([#761](https://github.com/Luna-Flow/floating/issues/761)), so
`subtract(0, 12)` at precision 1 under `Floor` is `-1E+1`. So `add(0, -0)` is `0`
under `HalfEven` and `-0` under `Floor`, while `add(0, 0)` is `0` under every
rounding algorithm.

The special cases:

| Operands | Result |
| --- | --- |
| $\infty - \infty$, $0 \times \infty$, $\infty / \infty$ | invalid |
| $x / 0$ | $\pm\infty$ with `DivisionByZero` |
| $0 / 0$ | NaN with `DivisionUndefined` |
| $x / \infty$ | a zero with exponent $E_{\mathrm{tiny}}$ and `Clamped` |

An invalid result raises `InvalidOperation`; the conditions that count as that
signal are listed under
[`GdaFlags::new`](#gdaflagsnew-gdaflagscontains-gdaflagscombine). `fma` is
invalid in a subset context.

A far smaller addend is absorbed as a sticky unit below every rounding
boundary of the sum, and a result is rounded to the subnormal grid only when
its exact result is below $10^{E_{\min}}$, so every one of these operations
rounds once. At precision 7, `add(1598618.5, 1E-20)` is `1598619`. In
decimal32, `multiply(3.000001E-45, 1.500001E-45)` is `4.500005E-90` and
`divide(1, 1.9999999999998E+101)` is `1E-101`.

### `divide_integer`, `remainder`, `remainder_near`

Divide to an integer quotient.

```mbti
pub fn divide_integer(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]
pub fn remainder(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]
pub fn remainder_near(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]
```

| Function | Returns | Ideal exponent |
| --- | --- | --- |
| `divide_integer` | $Q = \operatorname{trunc}(x / y)$ | 0 |
| `remainder` | $x - Q y$ (the sign of $x$) | $\min(q_x, q_y)$ |
| `remainder_near` | $x - n y$, where $n$ is $x / y$ rounded to the nearest integer, ties to even | $\min(q_x, q_y)$ |

When $Q$ (or $n$) needs more than $p$ digits the result is NaN with
`DivisionImpossible`. A zero divisor gives `DivisionByZero` (`divide_integer`
of a nonzero number) or `DivisionUndefined` ($0 / 0$). A zero divisor or an
infinite dividend makes both remainders invalid. A finite dividend with an
infinite divisor is its own remainder.

In an extended clamped context (see
[`GdaContext::new`](#gdacontextnew-gdacontexttry_new)), a zero quotient keeps
its exact sign and is folded to $E_{\max}-p+1$ when needed, raising `Clamped`
without raising `Rounded` or `Inexact`.

### `quantize`, `rescale`

Round a value to a prescribed exponent.

```mbti
pub fn quantize(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]
pub fn rescale(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]
```

`quantize(x, y)` returns the value of $x$ with the exponent $q_y$ of `y`,
rounded with the rounding of the context (raising `Rounded`, and `Inexact` when
digits are lost). `rescale(x, n)` does the same with exponent $n$, where $n$
must be an integer value.

The result is invalid when

- the target exponent lies outside $[E_{\mathrm{tiny}}, E_{\max}]$
  ($[E_{\min}, E_{\max}]$ in subset contexts),
- the result coefficient would need more than $p$ digits, or
- exactly one operand is infinite.

Two infinities give the infinity.

A subnormal result raises `Subnormal` (and `Inexact` and `Rounded` when digits
are lost) but never `Underflow`: in `decimal32`, `quantize(1.55E-100, 1E-101)`
is `1.6E-100` with `Subnormal`, `Inexact` and `Rounded`.

### `round_to_integral_exact`, `round_to_integral_value`

Round to an integer with the rounding of the context.

```mbti
pub fn round_to_integral_exact(Decimal, GdaContext) -> GdaOutcome[Decimal]
pub fn round_to_integral_value(Decimal, GdaContext) -> GdaOutcome[Decimal]
```

A value with exponent $\ge 0$ is already an integer and is returned
unchanged, even when it is longer than $p$ digits (a `clamp` context still
folds its exponent down).

A value with negative exponent is quantized to exponent 0 at a working
precision of $\max(p, \text{its digit count})$, as decNumber does, so the
integral part is never rounded to $p$ digits: at precision 3, `12345.6` gives
`12346`.

`round_to_integral_exact` raises `Inexact` and `Rounded` when digits are
dropped and `round_to_integral_value` never does. In a subset context the
operand is first rounded to $p$ digits, with `LostDigits`.

```moonbit
///|
test "round_to_integral keeps long integral parts" {
  let d = (s : String) => @decimal_gda.Decimal::from_string(s).unwrap()
  let p3 = @decimal_gda.GdaContext::new(precision=3)
  let exact = @decimal_gda.round_to_integral_exact(d("12345.6"), p3)
  inspect(exact.value(), content="12346")
  inspect(exact.raised().inexact(), content="true")
  let value = @decimal_gda.round_to_integral_value(d("12345.6"), p3)
  inspect(value.raised().inexact(), content="false")
  inspect(@decimal_gda.round_to_integral_exact(d("12345"), p3).value(), content="12345")
}
```

### Implementation limit of `exp`, `ln`, `log10` and `power`

`exp`, `ln`, `log10` and `power` with a non-integer exponent accept a context only if
$p \le 999\,999$, $E_{\max} \le 999\,999$ and $E_{\min} \ge -999\,999$. Beyond a limit they raise
`InvalidContext`; with the default exponent range they return NaN and raise `InvalidContext`.

| Limit | Applies to |
| --- | --- |
| $p \le 999\,999$, $E_{\max} \le 999\,999$, $-E_{\min} \le 999\,999$ | `exp`, `ln`, `log10`, and `power` with a non-integer exponent |
| a nonzero operand has at most 999,999 digits | `exp`, `ln`, `log10` |
| the adjusted exponent of a nonzero operand is at most 999,999 and at least $-1\,999\,997$ | `exp`, `ln`, `log10`, and `power` with a non-integer exponent (its base, and its exponent at the lower limit) |

This is an implementation limit. The operation text of GDA 1.70 states no such bound, and the
limit is permitted by its Invalid context condition, which applies when the precision "exceeds the
capability of the underlying concrete representation" (GDA 1.70, page 52 (Exceptional conditions)).
The value 999,999 is the `DEC_MAX_MATH` of decNumber. The [design
page](../design/decimal_gda.md#correctly-rounded-exp-ln-log10-and-non-integer-power) gives the
reason.

### `sqrt`, `exp`, `ln`, `log10`

Return the correctly rounded square root, exponential, natural logarithm and base-10 logarithm of
a value.

```mbti
pub fn sqrt(Decimal, GdaContext) -> GdaOutcome[Decimal]
pub fn exp(Decimal, GdaContext) -> GdaOutcome[Decimal]
pub fn ln(Decimal, GdaContext) -> GdaOutcome[Decimal]
pub fn log10(Decimal, GdaContext) -> GdaOutcome[Decimal]
```

They round the result with the half-even algorithm, whatever the rounding of the context. In a
subset context an operand longer than $p$ digits is first rounded with the rounding algorithm of
the context, not with the half-even one ([#762](https://github.com/Luna-Flow/floating/issues/762)):
`sqrt(0.999)` at precision 1 under `Down` is `0.9`. Every finite
result not listed as exact is inexact with $p$ digits.

| Function | Operand | Result |
| --- | --- | --- |
| `sqrt` | a perfect square | exact, with the ideal exponent $\lfloor q/2 \rfloor$, where $q$ is the exponent of the operand |
| `exp` | $0$ | $1$ |
| `ln` | $1$ | $0$ |
| `log10` | a power of ten $10^k$ | the integer $k$, rounded if $k$ has more than $p$ digits |

| Function | Operand | Result |
| --- | --- | --- |
| `sqrt`, `ln`, `log10` | a negative number | invalid |
| `ln`, `log10` | $0$ | $-\infty$; invalid in a subset context |
| `exp` | $-\infty$ | $0$ |
| all four | $+\infty$ | $+\infty$ |

An invalid result raises `InvalidOperation`; the conditions that count as that signal are
listed under [`GdaFlags::new`](#gdaflagsnew-gdaflagscontains-gdaflagscombine).

`exp`, `ln` and `log10` are subject to the
[implementation limit](#implementation-limit-of-exp-ln-log10-and-power). If the evaluation cannot
decide the rounding within the
[refinement limit](#gdacontextrefinement_limit-gdacontextwith_refinement_limit), the result is
NaN with `InvalidOperation`.

GDA 1.70 allows an inexact result of `exp`, `ln` and `log10` to be up to one unit in the last
place from the correctly rounded one (GDA 1.70, page 30 (exp); page 31 (ln, log10)). The library
returns the correctly rounded result, in a subset context as in the extended arithmetic (see the
[conformance page](../conformance/decimal_gda.md#deviations-of-the-corpus)).

### `power`

Return $x^y$ for `power(x, y)`.

```mbti
pub fn power(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]
```

For an integer $y$, the result is computed by binary powering with
$p + \operatorname{digits}(|y|) + 2$ working digits (one fewer in subset contexts) and then rounded
with the rounding of the context. An exact power that fits in $p$ digits is returned exactly, with
exponent $y \cdot q_x$.

For a non-integer $y$, $x$ must be positive (a negative base is invalid), and the result is
certified to be correctly rounded *with the rounding of the context*. The case $y = 0.5$ is
computed as a square root under the rounding of the context. The
[implementation limit](#implementation-limit-of-exp-ln-log10-and-power) applies to a non-integer
exponent. For a finite base, a non-integer exponent with a base whose adjusted exponent is above 999,999 or below
$-1\,999\,997$, or an exponent whose adjusted exponent is below $-1\,999\,997$, and an integer exponent with an
adjusted exponent above 999,999, give a NaN with
`InvalidOperation`, not `InvalidContext`.

The special cases follow GDA:

| Case | Result |
| --- | --- |
| $x^0$ | $1$; $0^0$ is invalid |
| a power of $\pm\infty$ or $\pm 0$ | takes its sign from the parity of an integer exponent |
| $1^y$, $y$ not an integer, or infinite | $1$ with `Inexact` and `Rounded` |
| subset context, $0^0$ | `1` |
| subset context, $0^{-n}$ | invalid, instead of $\infty$ |

GDA treats every non-integer power as inexact, even when the real number $x^y$ is representable:
`power(4, 1.5)` at precision 5 is `8.0000` with `Inexact` and `Rounded` in every rounding
algorithm. Such cases, an exponent $a/b$ in lowest terms with $x$ a perfect $b$-th power, are
decided before the refinement loop, because they lie on the boundary of a directed rounding cell
or on a midpoint, which the loop cannot certify.

GDA 1.70 allows an inexact `power` result to be up to one unit in the last place in error (GDA 1.70, page 35
(power)). The library always returns the correctly rounded result, so `Down`, `Floor` and
`ZeroFiveUp` give `8.0000` where libmpdec gives `7.9999`.

### `try_exp`, `try_ln`, `try_log10`, `try_power`

Return the outcome of `exp`, `ln`, `log10` or `power`, or `Err` when the library could not certify
the result.

```mbti
pub fn try_exp(Decimal, GdaContext) -> Result[GdaOutcome[Decimal], @arithmetic.ArithmeticError]
pub fn try_ln(Decimal, GdaContext) -> Result[GdaOutcome[Decimal], @arithmetic.ArithmeticError]
pub fn try_log10(Decimal, GdaContext) -> Result[GdaOutcome[Decimal], @arithmetic.ArithmeticError]
pub fn try_power(Decimal, Decimal, GdaContext) -> Result[GdaOutcome[Decimal], @arithmetic.ArithmeticError]
```

Every case the specification defines is an `Ok` outcome exactly as the plain function returns it.
These cases are domain errors, signaling NaNs, and a context beyond the supported exponent range,
which `exp` and its siblings report as `invalid_context` (the
[implementation limit](#implementation-limit-of-exp-ln-log10-and-power)). `Err` means that the
refinement limit or a resource bound stopped the computation; the plain function then returns a NaN
with `invalid_operation`.

### `reduce`

Round a value to the context and remove its trailing zeros.

```mbti
pub fn reduce(Decimal, GdaContext) -> GdaOutcome[Decimal]
```

A zero becomes $0$ with exponent 0, keeping its sign in extended contexts. In a clamped context
(the parameter `clamp`, see [`GdaContext::new`](#gdacontextnew-gdacontexttry_new)) the exponent is
not raised above $E_{\max} - p + 1$.

### `scaleb`, `logb`

`scaleb` scales a value by a power of ten, and `logb` returns its adjusted exponent.

```mbti
pub fn scaleb(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]
pub fn logb(Decimal, GdaContext) -> GdaOutcome[Decimal]
```

`scaleb(x, n)` returns $x \cdot 10^n$ by adding $n$ to the exponent. The operand $n$ must be an
integer with exponent 0 and $|n| \le 2(E_{\max} + p)$; otherwise the result is invalid. The result
then goes through the shared finalization:

| Case | Result | Example |
| --- | --- | --- |
| a coefficient longer than $p$ digits | rounded | |
| an overflow | $\pm\infty$ or the largest finite number, by the rounding algorithm | in decimal32 under `Down`, `scaleb(9E+96, 1)` is `9.999999E+96` |
| a zero result | clamped into the exponent range | `scaleb(0E+300, 400)` in decimal64 is `0E+369` |

`logb(x)` returns $\hat q$ as an integer. `logb(0)` is $-\infty$ with `DivisionByZero`, and
`logb(±∞)` is $+\infty$.

### `next_plus`, `next_minus`, `next_toward`

Return the representable number adjacent to a value.

```mbti
pub fn next_plus(Decimal, GdaContext) -> GdaOutcome[Decimal]
pub fn next_minus(Decimal, GdaContext) -> GdaOutcome[Decimal]
pub fn next_toward(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]
```

`next_plus` returns the smallest representable number greater than $x$ in the context, and
`next_minus` the largest smaller one. From a zero they step to $\pm 10^{E_{\mathrm{tiny}}}$, and
past the largest finite number they reach $\pm\infty$. Neither raises flags for finite results,
except in a subset context, where a step below the normal range gives $+0$ with `Underflow`,
`Subnormal`, `Inexact` and `Rounded` (a subnormal result is not permitted).

`next_toward(x, y)` steps from $x$ towards $y$, returning $x$ (with the sign of $y$ for zeros) when
they compare equal. When the step leaves the normal range, it raises `Overflow`, or `Underflow` and
`Subnormal`, together with `Inexact` and `Rounded`.

### `logical_and`, `logical_or`, `logical_xor`, `logical_invert`

Compute the digit-wise and, or, exclusive or and inversion of logical operands
(GDA 1.70, page 41 (Miscellaneous operations)). A logical operand is a non-negative integer with exponent 0 whose digits are all 0 or 1.

```mbti
pub fn logical_and(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]
pub fn logical_or(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]
pub fn logical_xor(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]
pub fn logical_invert(Decimal, GdaContext) -> GdaOutcome[Decimal]
```

Each operand is read as exactly $p$ digits: a shorter operand is padded with
leading zeros, and only the low $p$ digits of a longer one are used.
`logical_invert` inverts all $p$ digits. Any other operand makes the result
invalid (an [`InvalidOperation`](#gdaflagsnew-gdaflagscontains-gdaflagscombine)
condition).

### `shift`, `rotate`

Move the coefficient digits of $x$ by $n$ places within a window of $p$ digits
(GDA 1.70, page 49 (shift); page 47 (rotate)).

```mbti
pub fn shift(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]
pub fn rotate(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]
```

$n$ must be an integer with exponent 0 and $|n| \le p$, otherwise the result
is invalid. A positive $n$ moves digits to the left. `shift` drops the digits
that leave the window and fills with zeros; `rotate` moves them round to the
other end. The exponent and sign are unchanged, and an infinite $x$ is returned
unchanged.

### `compare`, `compare_signal`, `compare_total`, `compare_total_magnitude`

Compare two values by value or in the GDA total order (GDA 1.70, page 42 (compare-total)).

```mbti
pub fn compare(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]
pub fn compare_signal(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]
pub fn compare_total(Decimal, Decimal, GdaContext) -> GdaOutcome[Int32]
pub fn compare_total_magnitude(Decimal, Decimal, GdaContext) -> GdaOutcome[Int32]
```

| Function | Result | An operand is a NaN |
| --- | --- | --- |
| `compare` | the decimal $-1$, $0$ or $1$, by value ($-0 = +0$, $2.50 = 2.5$) | a quiet NaN; `InvalidOperation` only for a signaling NaN |
| `compare_signal` | the same as `compare` | a quiet NaN; `InvalidOperation` for any NaN |

`compare_total` returns $-1$, $0$ or $1$ in the GDA total order. The order is
by sign bit first. For positive values it is
$\text{finite} < \infty < \text{sNaN} < \text{NaN}$, with finite values
ordered by value and then by exponent (`2.50` < `2.5`) and NaNs by payload; for negative
values it is reversed. `compare_total_magnitude` applies the total
order to the absolute values. The total orders never raise flags in an
extended context.

A subset context (`extended=false`) first rounds the operands to the precision,
as it does for every operand (see [`GdaContext::new`](#gdacontextnew-gdacontexttry_new); GDA 1.70,
page 56 (Appendix A, The X3.274 subset)), which raises `Rounded` and `LostDigits`. The [`Decimal` methods of the same
names](#decimalcompare_total-decimalcompare_total_magnitude) compare the
operands as they are.

### `max`, `min`, `max_magnitude`, `min_magnitude`

Return the larger or smaller of two operands, by value or by magnitude (GDA 1.70,
page 32 (max)).

```mbti
pub fn max(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]
pub fn min(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]
pub fn max_magnitude(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]
pub fn min_magnitude(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]
```

| Operands | Result |
| --- | --- |
| one quiet NaN, the other operand not a NaN | the operand that is not a NaN |
| two quiet NaNs | the first |
| a signaling NaN | a quiet NaN, with `InvalidOperation` |
| values that compare equal, extended context | the operand the total order selects (so `max(2.5, 2.50)` is `2.5`) |
| values that compare equal, subset context | the first operand |

The selected operand is then rounded to the context as by `plus`, except that
in an extended context a zero keeps its sign: `max(-0, -0)` is `-0` for every
rounding algorithm, while `plus(-0)` is `0` unless the rounding is `Floor`.

### `class_name`, `is_normal`, `is_subnormal`

Classify a value under a context (GDA 1.70, page 42 (class); page 45 (is-normal);
page 46 (is-subnormal)). They never raise conditions, so they always return
`Completed` with the input context.

```mbti
pub fn class_name(Decimal, GdaContext) -> GdaOutcome[String]
pub fn is_normal(Decimal, GdaContext) -> GdaOutcome[Bool]
pub fn is_subnormal(Decimal, GdaContext) -> GdaOutcome[Bool]
```

They need the exponent limit $E_{\min}$ of the context, which is why they are
functions of the context. `same_quantum` uses no context and is a
[`Decimal` method](#decimalsame_quantum).

```moonbit
///|
test "GDA operation sampler" {
  let ctx = @decimal_gda.GdaContext::decimal64()
  let d = (s : String) => @decimal_gda.Decimal::from_string(s).unwrap()
  inspect(@decimal_gda.divide_integer(d("17"), d("5"), ctx).value(), content="3")
  inspect(@decimal_gda.remainder(d("-17"), d("5"), ctx).value(), content="-2")
  inspect(@decimal_gda.remainder_near(d("17"), d("5"), ctx).value(), content="2")
  inspect(@decimal_gda.fma(d("1.5"), d("2"), d("0.25"), ctx).value(), content="3.25")
  inspect(@decimal_gda.round_to_integral_exact(d("2.5"), ctx).value(), content="2")
  inspect(@decimal_gda.rescale(d("1.2345"), d("-2"), ctx).value(), content="1.23")
  inspect(@decimal_gda.reduce(d("120.00"), ctx).value(), content="1.2E+2")
  inspect(@decimal_gda.scaleb(d("1.5"), d("3"), ctx).value(), content="1.5E+3")
  inspect(@decimal_gda.logb(d("0.00123"), ctx).value(), content="-3")
  inspect(@decimal_gda.next_plus(d("1"), ctx).value(), content="1.000000000000001")
  inspect(@decimal_gda.logical_xor(d("1100"), d("1010"), ctx).value(), content="110")
  inspect(@decimal_gda.shift(d("12345"), d("2"), ctx).value(), content="1234500")
  inspect(@decimal_gda.rotate(d("12345"), d("-1"), @decimal_gda.GdaContext::new(precision=5)).value(), content="51234")
  inspect(@decimal_gda.power(d("2"), d("-3"), ctx).value(), content="0.125")
  inspect(@decimal_gda.max(d("2.5"), d("2.50"), ctx).value(), content="2.5")
  inspect(@decimal_gda.class_name(d("-0"), ctx).value(), content="-Zero")
  let wide = @decimal_gda.GdaContext::new() // exponent range ±999,999,999
  inspect(@decimal_gda.exp(d("1"), wide).raised().invalid_context(), content="true")
}
```

## Ordering and plain arithmetic on values

The methods and operators of this section take no context. They never signal and never
trap; use the GDA functions when flags matter.

### `Decimal::compare`, `Decimal::compare_checked`

`compare` returns the three-way numeric comparison of two values, total on all values;
`compare_checked` refuses NaNs.

```mbti
pub fn Decimal::compare(Self, Self) -> Int32
pub fn Decimal::compare_checked(Self, Self) -> Result[Int32, @arithmetic.ArithmeticError]
pub impl Compare for Decimal
pub impl @arithmetic.CompareChecked for Decimal
```

`compare` orders finite values and infinities numerically with $-0 = +0$ and
places every NaN equal to every other NaN and above every value that is not a NaN, so it is a
total preorder and sorting never aborts. `compare_checked` returns
`Err(unordered_comparison)` when either operand is a NaN.

### Comparison operators

Implement the operators of `Eq` and `Compare`.

```mbti
pub fn Decimal::equal(Self, Self) -> Bool
pub fn Decimal::not_equal(Self, Self) -> Bool
pub fn Decimal::op_lt(Self, Self) -> Bool
pub fn Decimal::op_le(Self, Self) -> Bool
pub fn Decimal::op_gt(Self, Self) -> Bool
pub fn Decimal::op_ge(Self, Self) -> Bool
pub impl Eq for Decimal
```

`==` compares as follows:

| Operands | `==` |
| --- | --- |
| finite values | numeric equality ($2.50 = 2.5$, $-0 = +0$) |
| infinities | equality of the signs |
| two NaNs | true |

`<`, `<=`, `>` and `>=` follow `compare`.

### `Decimal::compare_total`, `Decimal::compare_total_magnitude`

Return $-1$, $0$ or $1$ by the GDA total orders.

```mbti
pub fn Decimal::compare_total(Self, Self) -> Int32
pub fn Decimal::compare_total_magnitude(Self, Self) -> Int32
```

Each agrees with the package function of the same name,
[`compare_total`, `compare_total_magnitude`](#compare-compare_signal-compare_total-compare_total_magnitude),
except that the package function applies the rounding of operands of subset arithmetic
([`GdaContext::new`](#gdacontextnew-gdacontexttry_new)) and the method does not.

### `Decimal::clamp`, `Decimal::clamp_checked`

Limit a value to $[\min, \max]$ without rounding. The GDA operations `min` and
`max` are the free functions `min` and `max` of the package, which take a
`GdaContext` and return a `GdaOutcome`; there are no methods of those names.

```mbti
pub fn Decimal::clamp(Self, min~ : Self, max~ : Self) -> Self
pub fn Decimal::clamp_checked(Self, min~ : Self, max~ : Self) -> Result[Self, @arithmetic.ArithmeticError]
```

`clamp` returns `min` or `max` when the
value lies outside $[\min, \max]$ and the value otherwise (a NaN value is
returned unchanged). It aborts when a bound is NaN or `min > max`; there
`clamp_checked` returns `Err(domain_error)`.

### `Decimal::add`, `Decimal::sub`, `Decimal::mul`, `Decimal::div`, `Decimal::neg`

Implement `+`, `-`, `*`, `/` and unary `-` without a context.

```mbti
pub fn Decimal::add(Self, Self) -> Self
pub fn Decimal::sub(Self, Self) -> Self
pub fn Decimal::mul(Self, Self) -> Self
pub fn Decimal::div(Self, Self) -> Self
pub impl Add for Decimal
pub impl Sub for Decimal
pub impl Mul for Decimal
pub impl Div for Decimal
pub impl Neg for Decimal
```

`+`, `-`, `*` and `/` run the free functions `add`, `subtract`, `multiply` and
`divide` in a private working context and return their value. The working context has these
parameters:

| Parameter | Value |
| --- | --- |
| precision | $P$, the larger of the precisions of the two operands |
| rounding | half-even |
| arithmetic | extended |
| clamp | none |
| traps | none |
| exponent range | the one below |

The result is therefore a member of the cohort with the ideal exponent that GDA prescribes
(see [GDA operations](#gda-operations)):

| Operation | Exponent of the result | Example |
| --- | --- | --- |
| `+`, `-` | the smaller exponent of the operands | `1.10 + 3.50` is `4.60` |
| `*` | the sum of the exponents | |
| `/` | the difference of the exponents, with only the trailing zeros removed that an exact quotient allows | `1.5 / 0.5` is `3`, `1.50 / 0.5` is `3.0` |

A result of any of the four operations with more than $P$ digits is rounded to $P$ digits
(the product of `*` is then rounded, not exact).

`x + 0 == x` and `x * 1 == x` hold because equality compares values, not members of the
cohort, and, for every stored finite value, because the working exponent range below is the
[implementation limit on the exponents of a stored value](#gda_value_e_max-gda_value_e_tiny).

[`GdaContext::new`](#gdacontextnew-gdacontexttry_new) cannot build the working exponent
range. It limits $E_{\max}$ of a context to at most $999{,}999{,}999$ and $E_{\min}$ to at least $-999{,}999{,}999$ (GDA 1.70, page 10
(Abstract representation of numbers) allows a limit Elimit without giving a value), and the working range
fills the `Int` range: the largest adjusted exponent is $2^{31}-2 = 2{,}147{,}483{,}646$
and the smallest exponent is $E_{\mathrm{tiny}} = -2^{31}+3 = -2{,}147{,}483{,}645$
for every $P$, so $E_{\mathrm{tiny}}$ is always a valid `Int` exponent. A result above the range is a signed infinity
(`1E+1500000000 * 1E+1500000000` is `inf`); one below it is rounded with the half-even
rounding algorithm to $E_{\mathrm{tiny}}$, possibly to a signed zero.

Special values follow the default results of IEEE 754-2019 6.2 (operations with NaNs), 7.2
(invalid operation) and 7.3 (division by zero), without signals:

| Operands | Result |
| --- | --- |
| a NaN operand | a quiet NaN |
| $\infty - \infty$, $0 \times \infty$, $0/0$, $\infty/\infty$ | NaN |
| $x/0$, $x$ non-zero and not a NaN | a signed infinity |
| $x/\infty$ | a signed zero |

Use the free functions with a `GdaContext` when you need another precision, rounding, range
or the signals.

Unary `-` is
[`Decimal::neg`](#sign-operations): it flips the sign bit and uses no context. The
working context, the precision $P$, the cohort rules and the working range above apply to
`+`, `-`, `*` and `/` only.

### `Decimal::sqrt`

`sqrt` is the square root in the working context of the
[plain operators](#decimaladd-decimalsub-decimalmul-decimaldiv-decimalneg), at the precision
of the value.

```mbti
pub fn Decimal::sqrt(Self) -> Self
```

A negative operand gives NaN, as the free function [`sqrt`](#sqrt-exp-ln-log10) does. The
checked forms are `sqrt_checked` and `DivChecked::div_checked`. `Decimal::div_checked`
does not exist: use `1 / 0` for the infinity, or
`divide` with a trapping `GdaContext` for an error.

```moonbit
///|
test "context-free ordering and operators" {
  let d = (s : String) => @decimal_gda.Decimal::from_string(s).unwrap()
  inspect(d("2.50") == d("2.5"), content="true")
  inspect(d("2.50").compare_total(d("2.5")), content="-1")
  inspect(@decimal_gda.Decimal::nan() == @decimal_gda.Decimal::nan(), content="true")
  inspect(d("1").compare(@decimal_gda.Decimal::nan()), content="-1")
  inspect(d("1").compare_checked(@decimal_gda.Decimal::nan()) is Err(_), content="true")
  inspect(d("1.10") + d("2.20"), content="3.30")
  inspect(d("1.10") * d("2.20"), content="2.4200")
  inspect(d("1") / d("3"), content="0.3333333333333333333333333333333333")
  inspect(d("5").clamp(min=d("0"), max=d("3")), content="3")
}
```

## Interchange encodings

### `GdaInterchangeFormat`

`GdaInterchangeFormat` selects one of the three decimal interchange formats of IEEE 754: decimal32, decimal64 or decimal128.

```mbti
pub(all) enum GdaInterchangeFormat {
  Decimal32
  Decimal64
  Decimal128
} derive(Eq)
```

### `GdaInterchangeFormat::context`

`context` returns the extended default `GdaContext` of the format: precision 7, 16 or 34, half-even, clamped.

```mbti
pub fn GdaInterchangeFormat::context(Self) -> GdaContext
```

The contexts are the presets `GdaContext::decimal32()`, `decimal64()` and
`decimal128()`.

### `GdaInterchange`

`GdaInterchange` holds a decimal32, decimal64 or decimal128 bit pattern in the
densely packed decimal (DPD) encoding.

```mbti
pub struct GdaInterchange {
  // private fields
}
```

### `GdaInterchange::format`

`format` returns the format of the pattern.

```mbti
pub fn GdaInterchange::format(Self) -> GdaInterchangeFormat
```

### `GdaInterchange::from_decimal`, `GdaInterchange::to_decimal`

`from_decimal` encodes a `Decimal` in a format; `to_decimal` decodes a pattern.

```mbti
pub fn GdaInterchange::from_decimal(Decimal, GdaInterchangeFormat) -> (Self, GdaFlags)
pub fn GdaInterchange::to_decimal(Self) -> Decimal
```

`from_decimal` rounds the value to the format and encodes it; the returned
`GdaFlags` report the rounding, overflow, underflow and clamping. `to_decimal`
decodes exactly, keeping the exponent, and raises nothing; when the subnormal
condition is needed, test the result with
[`is_subnormal`](#class_name-is_normal-is_subnormal).

A NaN is encoded with its sign, its signaling bit and its payload. The payload of
a decimal32, decimal64 or decimal128 pattern has 6, 15 or 33 digits (the trailing
significand field, IEEE 754-2019 3.5.2). A payload that is wider keeps its low
digits and no flag is raised. IEEE 754-2019 6.2.3 asks that a conversion that
cannot preserve the payload return a quiet NaN carrying some language-defined
diagnostic information, and names no signal.

### `GdaInterchange::from_hex`, `GdaInterchange::to_hex`

`from_hex` parses a bit pattern from hexadecimal text; `to_hex` prints it.

```mbti
pub fn GdaInterchange::from_hex(String, GdaInterchangeFormat) -> Result[Self, @arithmetic.ArithmeticError]
pub fn GdaInterchange::to_hex(Self) -> String
```

The text is `#` (optional on input) followed by exactly 8, 16 or 32
hexadecimal digits; surrounding spaces are ignored. Any other input gives
`Err(parse_error)`. `to_hex` prints `#` and uppercase digits.

### `GdaInterchange::canonical`, `GdaInterchange::is_canonical`

`canonical` returns the canonical encoding of a pattern; `is_canonical` tests whether a pattern is canonical.

```mbti
pub fn GdaInterchange::canonical(Self) -> Self
pub fn GdaInterchange::is_canonical(Self) -> Bool
```

`canonical` decodes and re-encodes the pattern, which replaces non-canonical
declets and payloads with their canonical form. `is_canonical` is true when that
leaves the pattern unchanged.

### Sign operations on an encoding

Operate on the sign bit of an encoding without decoding it.

```mbti
pub fn GdaInterchange::copy(Self) -> Self
pub fn GdaInterchange::copy_abs(Self) -> Self
pub fn GdaInterchange::copy_negate(Self) -> Self
pub fn GdaInterchange::copy_sign(Self, Self) -> Self
```

`copy_sign` aborts when the two patterns have different formats.

```moonbit
///|
test "DPD interchange" {
  let d = (s : String) => @decimal_gda.Decimal::from_string(s).unwrap()
  let (bits, flags) = @decimal_gda.GdaInterchange::from_decimal(d("1.234567890"), Decimal32)
  inspect(bits.to_hex(), content="#25F4D2E8")
  inspect(bits.to_decimal(), content="1.234568")
  inspect(flags.inexact(), content="true")
  let back = @decimal_gda.GdaInterchange::from_hex("#A2300000000003D0", Decimal64).unwrap()
  inspect(back.to_decimal(), content="-7.50")
  inspect(bits.copy_negate().to_decimal(), content="-1.234568")
}
```

## Trait implementations

### Derived `Eq` of the enumerations and flag sets

`GdaRoundingMode`, `GdaSignal`, `GdaFlags`, `GdaTrapSet` and `GdaInterchangeFormat` have the derived `Eq` methods, which test two values for equality.

```mbti
pub fn GdaRoundingMode::equal(Self, Self) -> Bool
pub fn GdaRoundingMode::not_equal(Self, Self) -> Bool
pub fn GdaSignal::equal(Self, Self) -> Bool
pub fn GdaSignal::not_equal(Self, Self) -> Bool
pub fn GdaFlags::equal(Self, Self) -> Bool
pub fn GdaFlags::not_equal(Self, Self) -> Bool
pub fn GdaTrapSet::equal(Self, Self) -> Bool
pub fn GdaTrapSet::not_equal(Self, Self) -> Bool
pub fn GdaInterchangeFormat::equal(Self, Self) -> Bool
pub fn GdaInterchangeFormat::not_equal(Self, Self) -> Bool
```

They compare field by field (or variant by variant). `GdaContext` has no `Eq`. `Decimal`
has its own numeric `Eq`, documented under [Comparison operators](#comparison-operators).

### Contextual traits of `Luna-Flow/arithmetic`

`Decimal` implements the contextual traits of `Luna-Flow/arithmetic` on top of the
package's private engine: each operation runs under an `ArithmeticContext` and returns an
outcome or an error.

```mbti
pub fn Decimal::add_contextual(Self, Self, @arithmetic.ArithmeticContext) -> Result[@arithmetic.ArithmeticOutcome[Self], @arithmetic.ArithmeticError]
pub fn Decimal::sub_contextual(Self, Self, @arithmetic.ArithmeticContext) -> Result[@arithmetic.ArithmeticOutcome[Self], @arithmetic.ArithmeticError]
pub fn Decimal::mul_contextual(Self, Self, @arithmetic.ArithmeticContext) -> Result[@arithmetic.ArithmeticOutcome[Self], @arithmetic.ArithmeticError]
pub fn Decimal::div_contextual(Self, Self, @arithmetic.ArithmeticContext) -> Result[@arithmetic.ArithmeticOutcome[Self], @arithmetic.ArithmeticError]
pub fn Decimal::abs_contextual(Self, @arithmetic.ArithmeticContext) -> Result[@arithmetic.ArithmeticOutcome[Self], @arithmetic.ArithmeticError]
pub fn Decimal::sqrt_contextual(Self, @arithmetic.ArithmeticContext) -> Result[@arithmetic.ArithmeticOutcome[Self], @arithmetic.ArithmeticError]
pub fn Decimal::exp_contextual(Self, @arithmetic.ArithmeticContext) -> Result[@arithmetic.ArithmeticOutcome[Self], @arithmetic.ArithmeticError]
pub impl @arithmetic.AddContextual for Decimal
pub impl @arithmetic.SubContextual for Decimal
pub impl @arithmetic.MulContextual for Decimal
pub impl @arithmetic.DivContextual for Decimal
pub impl @arithmetic.AbsContextual for Decimal
pub impl @arithmetic.SqrtContextual for Decimal
pub impl @arithmetic.ExpContextual for Decimal
```

Each converts the arithmetic context to an engine context, runs the operation, and maps
the conditions the operation raises to the result:

| Condition raised | Result |
| --- | --- |
| `invalid_context` | `Err(unsupported)` |
| `division_by_zero` | `Err(division_by_zero)` |
| any other error flag | `Err(domain_error)` |
| none of these | `Ok` with the value and the diagnostics `inexact`, `rounded`, `overflow`, `underflow`, `subnormal` and `clamped` |

The rounding is one of the five rounding algorithms of `ArithmeticContext`.
`sqrt_contextual` and `exp_contextual` round with it, not half-even as the GDA functions do.

`exp_contextual` needs an `ArithmeticContext` that sets the exponent bounds. Like the package function `exp`, it is subject to the [implementation limit](#implementation-limit-of-exp-ln-log10-and-power):
precision, $E_{\max}$ and $-E_{\min}$ of at most $999\,999$. An `ArithmeticContext` without
`e_min` or `e_max` is not given bounds by default. It translates to the full range
$\pm 999\,999\,999$, which is an invalid context for `exp`.

The result for such a context is `Err(unsupported)`, whatever the operand (`-Infinity`
included). Its message starts with `invalid context:`, states the limit and names the bounds
the `ArithmeticContext` does not set. `ArithmeticContext::new(16)` therefore fails, while
`ArithmeticContext::new(16, e_min=-999_999, e_max=999_999)` and
`ArithmeticContext::decimal64()` work.

```moonbit
///|
test "exp_contextual needs exponent bounds" {
  let one = @decimal_gda.Decimal::one()
  let unbounded = @lf_arith.ArithmeticContext::new(16)
  let error = @lf_arith.ExpContextual::exp_contextual(one, unbounded).unwrap_err()
  inspect(error.is_unsupported(), content="true")
  inspect(
    error.message,
    content="invalid context: exp requires precision, e_max and -e_min of at most 999999; the ArithmeticContext sets no e_min and e_max",
  )
  let bounded = @lf_arith.ArithmeticContext::new(16, e_min=-999_999, e_max=999_999)
  inspect(
    @lf_arith.ExpContextual::exp_contextual(one, bounded).unwrap().value,
    content="2.718281828459045",
  )
}
```

### `NumericFormatContextual`

`Decimal` implements `NumericFormatContextual`, which describes the number format of
an `ArithmeticContext`. `zero_contextual` and `one_contextual` return `0` and `1`, each with the precision of the
context, and do not check the context.

```mbti
pub fn Decimal::zero_contextual(@arithmetic.ArithmeticContext) -> Self
pub fn Decimal::one_contextual(@arithmetic.ArithmeticContext) -> Self
pub fn Decimal::epsilon_contextual(@arithmetic.ArithmeticContext) -> Self
pub fn Decimal::min_normal_contextual(@arithmetic.ArithmeticContext) -> Self
pub fn Decimal::max_finite_contextual(@arithmetic.ArithmeticContext) -> Self
pub fn Decimal::classify_contextual(Self) -> @arithmetic.FpClass
pub impl @arithmetic.NumericFormatContextual for Decimal
```

With $p$ the precision of the context and $E_{\min}$, $E_{\max}$ its exponent limits:

| Method | Returns |
| --- | --- |
| `epsilon_contextual` | $\operatorname{next\_plus}(1) - 1 = 10^{1-p}$ |
| `min_normal_contextual` | $10^{E_{\min}}$ |
| `max_finite_contextual` | $(10^p - 1) \cdot 10^{E_{\max} - p + 1}$ |

If the `ArithmeticContext` is invalid, that is, if it cannot be converted to an engine context (for
example a precision above 999,999,999), these three methods return a zero with the precision of the
context limited to the range 1 through 999,999,999.

### Checked traits of `Luna-Flow/arithmetic`

`Decimal` implements the checked traits of `Luna-Flow/arithmetic`, which return
`Result` instead of flags.

```mbti
pub fn Decimal::parse_checked(String, @arithmetic.ArithmeticContext) -> Result[Self, @arithmetic.ArithmeticError]
pub fn Decimal::sqrt_checked(Self, @arithmetic.ArithmeticContext) -> Result[Self, @arithmetic.ArithmeticError]
pub fn Decimal::pow_int_checked(Self, Int32, @arithmetic.ArithmeticContext) -> Result[Self, @arithmetic.ArithmeticError]
pub fn Decimal::pow_nat_checked(Self, UInt32, @arithmetic.ArithmeticContext) -> Result[Self, @arithmetic.ArithmeticError]
pub impl @arithmetic.ParseChecked for Decimal
pub impl @arithmetic.SqrtChecked for Decimal
pub impl @arithmetic.PowIntChecked for Decimal
pub impl @arithmetic.PowNatChecked for Decimal
pub impl @arithmetic.DivChecked for Decimal
```

`parse_checked` converts the arithmetic context to an engine context and converts the
string under it: the precision, rounding, exponent bounds and clamp setting of the context
apply. If the context cannot be converted (a precision above 999,999,999, for example), it returns
`Err(domain_error)` for that conversion before it reads the string. It returns the converted value; conditions such as overflow are available from
[`to_number`](#to_number). Invalid syntax returns `Err(parse_error)`.

`sqrt_checked` returns `Err(domain_error)` for negative operands.

`pow_int_checked` and `pow_nat_checked` call the power operation with the integer exponent
converted exactly, with at least ten digits, which hold every accepted exponent. So at
precision 7 `(-1).pow_int_checked(12345679, ctx)` is `-1`. They return an error in these
cases:

| Case | Result |
| --- | --- |
| zero base, negative exponent | `Err(division_by_zero)` |
| `power` raises `invalid_context`: a positive exponent above 999,999,999 under a context without exponent bounds within $\pm 999\,999$ | `Err(unsupported)` with an `invalid context:` message |
| any other invalid result | `Err(domain_error)` |
| `pow_nat_checked` with an exponent above 999,999,999 | `Err(unsupported)` |

`DivChecked::div_checked` divides under the given context and returns
`Err(division_by_zero)` for a zero divisor and `Err(domain_error)` for an invalid division.

### `FromNat`, `FromInteger` and the `luna-generic` algebra traits

`Decimal` implements the `luna-generic` traits that let generic algebra code use it.

```mbti
pub impl @luna-generic.FromNat for Decimal
pub impl @luna-generic.FromInteger for Decimal
pub impl @luna-generic.Zero for Decimal
pub impl @luna-generic.One for Decimal
pub impl @luna-generic.AddMonoid for Decimal
pub impl @luna-generic.MulMonoid for Decimal
pub impl @luna-generic.AddGroup for Decimal
pub impl @luna-generic.Semiring for Decimal
pub impl @luna-generic.Ring for Decimal
```

`FromNat::from_natural` and `FromInteger::from_integer` are the canonical maps out of the
naturals and the integers. `Decimal` has no inherent method of those names: call the trait
method, or `Decimal::from_bigint(n).normalized()`, which is what they compute. They convert
with `Decimal::from_bigint` (34 digits) and reduce the result, so they are exact only for
integers of at most 34 significant digits. To convert another Luna-Flow integer type, pick
its representative with `Integral::normalize` first, or use `lift_to`.

`Zero::zero` and `One::one` are `Decimal::zero()` and `Decimal::one()`.

The ring structure uses the context-free operators. Because `+` rounds to the operand
precision, the ring laws hold exactly only while sums stay within that precision.

### `Decimal::to_repr` and the `@def.Floating`, `Show` and `Debug` implementations

`Decimal` implements the floating vocabulary of the `def` package, `Show` (see
[`Decimal::to_string`](#decimalto_string-decimaloutput)) and `Debug`.

```mbti
pub impl @def.Floating for Decimal
pub fn Decimal::to_repr(Self) -> @debug.Repr
```

The `Floating` methods are `classify`, `signum`, `precision`, `with_precision` and
`normalized`. The first three are documented under
[`Decimal::classify`](#decimalclassify-decimalsignum-decimalprecision), the last two under
[`Decimal::normalized`](#decimalnormalized-decimaltrim-decimalwith_precision). `to_repr` is the
structural `Debug` representation.

```moonbit
///|
test "trait adapters" {
  let d = (s : String) => @decimal_gda.Decimal::from_string(s).unwrap()
  let actx = @lf_arith.ArithmeticContext::new(4)
  let out = d("2").div_contextual(d("3"), actx).unwrap()
  inspect(out.value, content="0.6667")
  inspect(out.diagnostics.inexact, content="true")
  inspect(d("1").div_contextual(d("0"), actx) is Err(_), content="true")
  inspect(@decimal_gda.Decimal::epsilon_contextual(actx), content="0.001")
  inspect(d("1.5").pow_int_checked(3, actx).unwrap(), content="3.375")
  inspect(@decimal_gda.Decimal::from_bigint(1200N).normalized(), content="1.2E+3")
}
```

## Complete public interface

This snapshot is the generated `pkg.generated.mbti` of the package. It is the authority when prose and interface disagree.

<!-- generated-api-start -->
```mbti
// Generated using `moon info`, DON'T EDIT IT
package "Luna-Flow/floating/decimal_gda"

import {
  "Luna-Flow/arithmetic",
  "Luna-Flow/floating/binary",
  "Luna-Flow/floating/def",
  "Luna-Flow/luna-generic",
  "moonbitlang/core/bigint",
  "moonbitlang/core/debug",
}

// Values
pub fn abs(Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn add(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn apply(Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn class_name(Decimal, GdaContext) -> GdaOutcome[String]

pub fn compare(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn compare_signal(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn compare_total(Decimal, Decimal, GdaContext) -> GdaOutcome[Int32]

pub fn compare_total_magnitude(Decimal, Decimal, GdaContext) -> GdaOutcome[Int32]

pub fn divide(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn divide_integer(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn exp(Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn fma(Decimal, Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]

pub let gda_value_e_max : Int32

pub let gda_value_e_tiny : Int32

pub fn is_normal(Decimal, GdaContext) -> GdaOutcome[Bool]

pub fn is_subnormal(Decimal, GdaContext) -> GdaOutcome[Bool]

pub fn ln(Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn log10(Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn logb(Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn logical_and(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn logical_invert(Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn logical_or(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn logical_xor(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn max(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn max_magnitude(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn min(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn min_magnitude(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn minus(Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn multiply(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn next_minus(Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn next_plus(Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn next_toward(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn plus(Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn power(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn quantize(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn reduce(Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn remainder(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn remainder_near(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn rescale(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn rotate(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn round_to_integral_exact(Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn round_to_integral_value(Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn scaleb(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn shift(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn sqrt(Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn subtract(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn to_number(String, GdaContext) -> GdaOutcome[Decimal]

pub fn try_exp(Decimal, GdaContext) -> Result[GdaOutcome[Decimal], @arithmetic.ArithmeticError]

pub fn try_ln(Decimal, GdaContext) -> Result[GdaOutcome[Decimal], @arithmetic.ArithmeticError]

pub fn try_log10(Decimal, GdaContext) -> Result[GdaOutcome[Decimal], @arithmetic.ArithmeticError]

pub fn try_power(Decimal, Decimal, GdaContext) -> Result[GdaOutcome[Decimal], @arithmetic.ArithmeticError]

// Errors

// Types and methods
#derive(@debug.Debug)
pub struct Decimal {
  // private fields
}
pub fn Decimal::abs(Self) -> Self
pub fn Decimal::abs_contextual(Self, @arithmetic.ArithmeticContext) -> Result[@arithmetic.ArithmeticOutcome[Self], @arithmetic.ArithmeticError]
pub fn Decimal::add(Self, Self) -> Self
pub fn Decimal::add_contextual(Self, Self, @arithmetic.ArithmeticContext) -> Result[@arithmetic.ArithmeticOutcome[Self], @arithmetic.ArithmeticError]
pub fn Decimal::clamp(Self, min~ : Self, max~ : Self) -> Self
pub fn Decimal::clamp_checked(Self, min~ : Self, max~ : Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn Decimal::classify(Self) -> @arithmetic.FpClass
pub fn Decimal::classify_contextual(Self) -> @arithmetic.FpClass
pub fn Decimal::coefficient(Self) -> @bigint.BigInt
pub fn Decimal::compare(Self, Self) -> Int32
pub fn Decimal::compare_checked(Self, Self) -> Result[Int32, @arithmetic.ArithmeticError]
pub fn Decimal::compare_total(Self, Self) -> Int32
pub fn Decimal::compare_total_magnitude(Self, Self) -> Int32
pub fn Decimal::copy(Self) -> Self
pub fn Decimal::copy_abs(Self) -> Self
pub fn Decimal::copy_negate(Self) -> Self
pub fn Decimal::copy_sign(Self, Self) -> Self
pub fn Decimal::div(Self, Self) -> Self
pub fn Decimal::div_contextual(Self, Self, @arithmetic.ArithmeticContext) -> Result[@arithmetic.ArithmeticOutcome[Self], @arithmetic.ArithmeticError]
pub fn Decimal::epsilon_contextual(@arithmetic.ArithmeticContext) -> Self
pub fn Decimal::equal(Self, Self) -> Bool
pub fn Decimal::exp_contextual(Self, @arithmetic.ArithmeticContext) -> Result[@arithmetic.ArithmeticOutcome[Self], @arithmetic.ArithmeticError]
pub fn Decimal::exponent10(Self) -> Int32
pub fn Decimal::from_bigint(@bigint.BigInt, precision? : Int32) -> Self
pub fn Decimal::from_binary(@binary.Binary, precision~ : Int32, mode? : GdaRoundingMode) -> Self
pub fn Decimal::from_double(Double, precision? : Int32) -> Self
pub fn Decimal::from_float(Float, precision? : Int32) -> Self
pub fn Decimal::from_int(Int32, precision? : Int32) -> Self
pub fn Decimal::from_string(String, precision? : Int32) -> Result[Self, @arithmetic.ArithmeticError]
pub fn Decimal::identical(Self, Self) -> Bool
pub fn Decimal::inf(negative? : Bool, precision? : Int32) -> Self
pub fn Decimal::is_canonical(Self) -> Bool
pub fn Decimal::is_finite(Self) -> Bool
pub fn Decimal::is_infinite(Self) -> Bool
pub fn Decimal::is_nan(Self) -> Bool
pub fn Decimal::is_negative_zero(Self) -> Bool
pub fn Decimal::is_qnan(Self) -> Bool
pub fn Decimal::is_signed(Self) -> Bool
pub fn Decimal::is_snan(Self) -> Bool
pub fn Decimal::is_zero(Self) -> Bool
pub fn Decimal::make(@bigint.BigInt, Int32, Int32, mode? : GdaRoundingMode) -> Self
pub fn Decimal::max_finite_contextual(@arithmetic.ArithmeticContext) -> Self
pub fn Decimal::min_normal_contextual(@arithmetic.ArithmeticContext) -> Self
pub fn Decimal::mul(Self, Self) -> Self
pub fn Decimal::mul_contextual(Self, Self, @arithmetic.ArithmeticContext) -> Result[@arithmetic.ArithmeticOutcome[Self], @arithmetic.ArithmeticError]
pub fn Decimal::nan(precision? : Int32) -> Self
pub fn Decimal::nan_payload(Self) -> @bigint.BigInt
pub fn Decimal::neg(Self) -> Self
pub fn Decimal::negative_zero(precision? : Int32) -> Self
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
pub fn Decimal::pow_int_checked(Self, Int32, @arithmetic.ArithmeticContext) -> Result[Self, @arithmetic.ArithmeticError]
pub fn Decimal::pow_nat_checked(Self, UInt32, @arithmetic.ArithmeticContext) -> Result[Self, @arithmetic.ArithmeticError]
pub fn Decimal::precision(Self) -> Int32
pub fn Decimal::quiet_nan(payload? : @bigint.BigInt, negative? : Bool, precision? : Int32) -> Self
pub fn Decimal::same_quantum(Self, Self) -> Bool
pub fn Decimal::signaling_nan(payload? : @bigint.BigInt, negative? : Bool, precision? : Int32) -> Self
pub fn Decimal::signum(Self) -> @def.Sign
pub fn Decimal::sqrt(Self) -> Self
pub fn Decimal::sqrt_checked(Self, @arithmetic.ArithmeticContext) -> Result[Self, @arithmetic.ArithmeticError]
pub fn Decimal::sqrt_contextual(Self, @arithmetic.ArithmeticContext) -> Result[@arithmetic.ArithmeticOutcome[Self], @arithmetic.ArithmeticError]
pub fn Decimal::sub(Self, Self) -> Self
pub fn Decimal::sub_contextual(Self, Self, @arithmetic.ArithmeticContext) -> Result[@arithmetic.ArithmeticOutcome[Self], @arithmetic.ArithmeticError]
pub fn Decimal::to_binary(Self, precision~ : Int32, mode? : @binary.BinaryRoundingMode) -> @binary.Binary
pub fn Decimal::to_eng_string(Self) -> String
pub fn Decimal::to_repr(Self) -> @debug.Repr
pub fn Decimal::to_sci_string(Self) -> String
pub fn Decimal::to_string(Self) -> String
pub fn Decimal::trim(Self) -> Self
pub fn Decimal::try_make(@bigint.BigInt, Int32, Int32, mode? : GdaRoundingMode) -> Result[Self, @arithmetic.ArithmeticError]
pub fn Decimal::with_precision(Self, Int32, GdaRoundingMode) -> Self
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

pub struct GdaContext {
  // private fields
}
pub fn GdaContext::basic_default() -> Self
pub fn GdaContext::clamp(Self) -> Bool
pub fn GdaContext::clear_flags(Self) -> Self
pub fn GdaContext::decimal128(rounding? : GdaRoundingMode) -> Self
pub fn GdaContext::decimal32(rounding? : GdaRoundingMode) -> Self
pub fn GdaContext::decimal64(rounding? : GdaRoundingMode) -> Self
pub fn GdaContext::e_max(Self) -> Int32
pub fn GdaContext::e_min(Self) -> Int32
pub fn GdaContext::extended(Self) -> Bool
pub fn GdaContext::flags(Self) -> GdaFlags
pub fn GdaContext::new(precision? : Int32, rounding? : GdaRoundingMode, e_min? : Int32, e_max? : Int32, clamp? : Bool, extended? : Bool, traps? : GdaTrapSet) -> Self
pub fn GdaContext::precision(Self) -> Int32
pub fn GdaContext::radix(Self) -> Int32
pub fn GdaContext::refinement_limit(Self) -> Int32?
pub fn GdaContext::reset(Self) -> Self
pub fn GdaContext::rounding(Self) -> GdaRoundingMode
pub fn GdaContext::trap(Self, GdaSignal, enabled? : Bool) -> Self
pub fn GdaContext::traps(Self) -> GdaTrapSet
pub fn GdaContext::try_new(precision? : Int32, rounding? : GdaRoundingMode, e_min? : Int32, e_max? : Int32, clamp? : Bool, extended? : Bool, traps? : GdaTrapSet) -> Result[Self, @arithmetic.ArithmeticError]
pub fn GdaContext::with_exponent_range(Self, e_min~ : Int32, e_max~ : Int32) -> Self
pub fn GdaContext::with_precision(Self, Int32) -> Self
pub fn GdaContext::with_refinement_limit(Self, Int32?) -> Self
pub fn GdaContext::with_rounding(Self, GdaRoundingMode) -> Self
pub fn GdaContext::with_traps(Self, GdaTrapSet) -> Self

#derive(Eq)
pub struct GdaFlags {
  // private fields
}
pub fn GdaFlags::clamped(Self) -> Bool
pub fn GdaFlags::combine(Self, Self) -> Self
pub fn GdaFlags::contains(Self, GdaSignal) -> Bool
pub fn GdaFlags::conversion_syntax(Self) -> Bool
pub fn GdaFlags::division_by_zero(Self) -> Bool
pub fn GdaFlags::division_impossible(Self) -> Bool
pub fn GdaFlags::division_undefined(Self) -> Bool
pub fn GdaFlags::equal(Self, Self) -> Bool
pub fn GdaFlags::inexact(Self) -> Bool
pub fn GdaFlags::invalid_context(Self) -> Bool
pub fn GdaFlags::invalid_operation(Self) -> Bool
pub fn GdaFlags::lost_digits(Self) -> Bool
pub fn GdaFlags::new() -> Self
pub fn GdaFlags::not_equal(Self, Self) -> Bool
pub fn GdaFlags::overflow(Self) -> Bool
pub fn GdaFlags::rounded(Self) -> Bool
pub fn GdaFlags::subnormal(Self) -> Bool
pub fn GdaFlags::underflow(Self) -> Bool

pub struct GdaInterchange {
  // private fields
}
pub fn GdaInterchange::canonical(Self) -> Self
pub fn GdaInterchange::copy(Self) -> Self
pub fn GdaInterchange::copy_abs(Self) -> Self
pub fn GdaInterchange::copy_negate(Self) -> Self
pub fn GdaInterchange::copy_sign(Self, Self) -> Self
pub fn GdaInterchange::format(Self) -> GdaInterchangeFormat
pub fn GdaInterchange::from_decimal(Decimal, GdaInterchangeFormat) -> (Self, GdaFlags)
pub fn GdaInterchange::from_hex(String, GdaInterchangeFormat) -> Result[Self, @arithmetic.ArithmeticError]
pub fn GdaInterchange::is_canonical(Self) -> Bool
pub fn GdaInterchange::to_decimal(Self) -> Decimal
pub fn GdaInterchange::to_hex(Self) -> String

#derive(Eq)
pub(all) enum GdaInterchangeFormat {
  Decimal32
  Decimal64
  Decimal128
}
pub fn GdaInterchangeFormat::context(Self) -> GdaContext
pub fn GdaInterchangeFormat::equal(Self, Self) -> Bool
pub fn GdaInterchangeFormat::not_equal(Self, Self) -> Bool

pub enum GdaOutcome[T] {
  Completed(T, GdaContext, GdaFlags)
  Trapped(GdaSignal, T, GdaContext, GdaFlags)
}
pub fn[T, U] GdaOutcome::absorb(Self[T], Self[U]) -> Self[T]
pub fn[T] GdaOutcome::completed(T, GdaContext) -> Self[T]
pub fn[T] GdaOutcome::next_context(Self[T]) -> GdaContext
pub fn[T] GdaOutcome::raised(Self[T]) -> GdaFlags
pub fn[T] GdaOutcome::resume_defined(Self[T]) -> Self[T]
pub fn[T] GdaOutcome::value(Self[T]) -> T

#derive(Eq)
pub(all) enum GdaRoundingMode {
  HalfEven
  HalfUp
  HalfDown
  Down
  Ceiling
  Floor
  Up
  ZeroFiveUp
}
pub fn GdaRoundingMode::equal(Self, Self) -> Bool
pub fn GdaRoundingMode::not_equal(Self, Self) -> Bool

#derive(Eq)
pub(all) enum GdaSignal {
  Clamped
  DivisionByZero
  Inexact
  InvalidOperation
  LostDigits
  Overflow
  Rounded
  Subnormal
  Underflow
}
pub fn GdaSignal::equal(Self, Self) -> Bool
pub fn GdaSignal::not_equal(Self, Self) -> Bool

#derive(Eq)
pub struct GdaTrapSet {
  // private fields
}
pub fn GdaTrapSet::clamped(Self) -> Bool
pub fn GdaTrapSet::contains(Self, GdaSignal) -> Bool
pub fn GdaTrapSet::division_by_zero(Self) -> Bool
pub fn GdaTrapSet::equal(Self, Self) -> Bool
pub fn GdaTrapSet::inexact(Self) -> Bool
pub fn GdaTrapSet::invalid_operation(Self) -> Bool
pub fn GdaTrapSet::lost_digits(Self) -> Bool
pub fn GdaTrapSet::new() -> Self
pub fn GdaTrapSet::not_equal(Self, Self) -> Bool
pub fn GdaTrapSet::overflow(Self) -> Bool
pub fn GdaTrapSet::rounded(Self) -> Bool
pub fn GdaTrapSet::subnormal(Self) -> Bool
pub fn GdaTrapSet::underflow(Self) -> Bool
pub fn GdaTrapSet::with_signal(Self, GdaSignal, enabled? : Bool) -> Self

// Type aliases

// Traits
```
<!-- generated-api-end -->
