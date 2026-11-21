# decimal_gda API

## Purpose

`decimal_gda` implements the General Decimal Arithmetic Specification (GDA,
version 1.70) by M. F. Cowlishaw. Its `Decimal` is a sign, an arbitrary-length
decimal coefficient and a decimal exponent; its `GdaContext` carries the
precision, rounding mode, exponent limits, clamping, the extended/subset
switch, the sticky flags and the enabled traps; and every GDA operation is a
pure function that returns a `GdaOutcome` holding the defined result, the next
context and the conditions it raised. The [tutorial](../tutorial/decimal_gda.md)
shows the package in use; the [design page](../design/decimal_gda.md) derives
the rules stated here.

The package does not depend on the IEEE 754 package `decimal`. It publishes the
GDA layer only (`Decimal`, `GdaContext`, the `Gda*` types and the functions
named after the GDA operations) and adapters to the `Luna-Flow/arithmetic` and
`Luna-Flow/luna-generic` traits. The status-free engine the functions are built
on is private to the package.

Throughout, a finite value is written $(-1)^s \cdot c \cdot 10^{e}$ with
coefficient $c \ge 0$ and exponent $e$; its *adjusted exponent* is
$\hat e = e + \operatorname{digits}(c) - 1$, the exponent of its leading digit.
For a context with precision $p$, $E_{\mathrm{tiny}} = e_{\min} - p + 1$ is the
smallest exponent a result may have, and with clamping
$E_{\mathrm{top}} = e_{\max} - p + 1$ is the largest.

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

`Decimal` is an immutable GDA number: a finite value, an infinity, a quiet NaN
or a signaling NaN.

```mbti
pub struct Decimal {
  // private fields
} derive(@debug.Debug)
```

Finite values keep their exponent, so `2.50` and `2.5` are distinct members of
the same *cohort*: they compare equal numerically and differ in
`compare_total`, `same_quantum` and printing. Zero is signed. NaNs carry a sign
and a non-negative integer payload. Every value also stores a *precision
attribute* (`precision()`), the precision of the context or constructor that
produced it; GDA operations ignore it and use the context precision instead.
The coefficient is stored as a persistent decimal limb array, so a value can
be shared freely.

### `Decimal::zero`, `Decimal::negative_zero`, `Decimal::one`

These return $+0$, $-0$ and $1$, each with exponent 0.

```mbti
pub fn Decimal::zero(precision? : Int) -> Self
pub fn Decimal::negative_zero(precision? : Int) -> Self
pub fn Decimal::one(precision? : Int) -> Self
```

`precision` (default 34) is the stored precision attribute: the number of digits
the coefficient may have, from 1 to 999,999,999 (the limit a context has).
A precision outside that range aborts and names the function and the argument;
no constructor replaces it by 1. The same check applies to every constructor
that takes a `precision`.

### `Decimal::inf`, `Decimal::nan`, `Decimal::quiet_nan`, `Decimal::signaling_nan`

These build the special values.

```mbti
pub fn Decimal::inf(negative? : Bool, precision? : Int) -> Self
pub fn Decimal::nan(precision? : Int) -> Self
pub fn Decimal::quiet_nan(payload? : @bigint.BigInt, negative? : Bool, precision? : Int) -> Self
pub fn Decimal::signaling_nan(payload? : @bigint.BigInt, negative? : Bool, precision? : Int) -> Self
```

`inf(negative=true)` is $-\infty$ and `inf()` is $+\infty$. `nan()` is a
positive quiet NaN with payload 0. GDA 1.70 (page 11) says a payload is no
larger than the coefficient can represent less one digit, so a payload has at
most `precision - 1` digits: a negative payload, or one that is too wide for
the `precision` given, aborts (at precision 1 only the payload 0 exists). A
signaling NaN raises `InvalidOperation` when an arithmetic operation
consumes it and is replaced by the quiet NaN with the same sign and payload.

### `gda_value_e_max`, `gda_value_e_tiny`

These are the limits of the exponents a finite `Decimal` can hold.

```mbti
pub let gda_value_e_max : Int
pub let gda_value_e_tiny : Int
```

`gda_value_e_max` is $2^{31}-2 = 2{,}147{,}483{,}646$, a limit on the
adjusted exponent. `gda_value_e_tiny` is $-2^{31}+3 = -2{,}147{,}483{,}645$,
a limit on the exponent of the least digit (the `Etiny` of the working context of
the plain operators, whatever the precision). A finite value, a zero included
(it has one digit), is stored only if
`e_tiny <= exponent` and `exponent + digits - 1 <= e_max`. The constructors
`make`, `try_make` and `from_string` reject what is outside; the operations keep
the values they produce inside, by rounding, underflow or overflow, so every
`Decimal` you can obtain satisfies the condition. This is the invariant behind
`x + 0 == x` and `x * 1 == x` for every stored finite value (see
[the plain operators](#decimaladd-decimalsub-decimalmul-decimaldiv-decimalneg)).
A text outside the limits is read with a context when a rounded value is wanted:
[`to_number`](#to_number) rounds, overflows and underflows by the context.

### `Decimal::make`, `Decimal::try_make`

`make(c, e, p)` returns $c \cdot 10^{e}$ as a value of `p` digits of coefficient,
the way the GDA to-number conversion does (page 21).

```mbti
pub fn Decimal::make(@bigint.BigInt, Int, Int, mode? : GdaRoundingMode) -> Self
pub fn Decimal::try_make(@bigint.BigInt, Int, Int, mode? : GdaRoundingMode) -> Result[Self, @arithmetic.ArithmeticError]
```

The sign comes from the sign of `c`. The exponent is kept when `c` has at most
`p` digits: `make(1200, 0, 34)` is `1200`, `make(1200, -2, 34)` is `12.00` and
`make(0, 5, 5)` is `0E+5`. A longer coefficient is rounded once, in `mode`
(default `HalfEven`, one of the eight modes of the context), to `p` digits, and
the rounded coefficient is not reduced: `make(1000000, 0, 3)` is `1.00E+6`. To
strip trailing zeros use `Decimal::normalized` or `Decimal::trim`. No flags are
reported.

The value must be inside the [stored range](#gda_value_e_max-gda_value_e_tiny)
after the rounding: an exponent below `gda_value_e_tiny`, or an adjusted
exponent above `gda_value_e_max` (a carry of the rounding into the next
power of ten included), is never replaced by a zero or an infinity. `make` then
aborts with a message that names both limits and the exponent, and `try_make`
returns `Err` of the domain-error kind with the same message. `try_make` also
returns that error for a precision outside `1..=999999999`, where `make` aborts.

### `Decimal::from_int`, `Decimal::from_bigint`, `Decimal::from_double`, `Decimal::from_float`, `Decimal::from_binary`

These convert binary values to decimal. An integer of at most `precision`
digits keeps exponent 0 and an exact binary fraction takes the exponent closest
to 0 (trailing zeros are removed only down to exponent 0); a longer or inexact
value is rounded to exactly `precision` digits, half to even unless `mode`
(for `from_binary`) says otherwise.

```mbti
pub fn Decimal::from_int(Int, precision? : Int) -> Self
pub fn Decimal::from_bigint(@bigint.BigInt, precision? : Int) -> Self
pub fn Decimal::from_double(Double, precision? : Int) -> Self
pub fn Decimal::from_float(Float, precision? : Int) -> Self
pub fn Decimal::from_binary(@binary.Binary, precision~ : Int, mode? : GdaRoundingMode) -> Self
```

`precision` defaults to 34 digits; for `from_binary` it is required and
counts decimal digits, not the bits of the argument. A binary float $m \cdot 2^{k}$ with $k < 0$ is first written exactly
as $m 5^{-k} \cdot 10^{k}$, so the conversion is exact whenever the result fits
in `precision` digits; for example `from_double(0.1)` is the exact binary64 value nearest to $0.1$
rounded half to even to 34 digits. NaNs become the quiet NaN
(sign kept by `from_double`), infinities keep their sign, zeros keep their
sign (`from_binary` returns $+0$). `from_int(100)` is `100` (exponent 0),
`from_int(99999, precision=3)` is `1.00E+5` and `from_double(0.5)` is `0.5`.

### `Decimal::to_binary`

`to_binary` rounds the value to a binary `Binary` with `precision`
significant bits.

```mbti
pub fn Decimal::to_binary(Self, precision~ : Int, mode? : @binary.BinaryRoundingMode) -> @binary.Binary
```

`precision` is required and counts bits, from 1 to
`@binary.binary_precision_max` (outside that range the call aborts). `mode` is a
rounding attribute of the radix of the result (IEEE 754-2019 4.3.1) and
defaults to `RoundTiesToEven`; ties-to-away rounds the exact value once, too. With
`RoundTowardNegative` and `RoundTowardPositive` the two results
enclose the decimal value; the elementary functions use exactly this to build
their certified input intervals. Zeros map to $+0$, NaNs to the binary NaN.

### `Decimal::from_string`

This reads a GDA numeric string without a GDA context.

```mbti
pub fn Decimal::from_string(String, precision? : Int) -> Result[Self, @arithmetic.ArithmeticError]
```

Accepted syntax is the GDA numeric-string grammar: an optional sign, digits
with an optional decimal point, an optional exponent `E±n`, or
`Infinity`/`Inf`/`NaN`/`sNaN` (case-insensitive) with an optional decimal NaN
payload. The exponent is kept exactly, so `from_string("2.50")` has exponent
$-2$. A literal with more than `precision` (default 34) significant digits is
rounded half to even and its trailing zeros are removed. A malformed literal
gives `Err(parse_error)`; so does a precision outside `1..=999999999` (`Err` of
the domain-error kind) and a NaN whose payload is wider than `precision - 1`
digits (page 11). No context exponent range applies, only the
[stored range](#gda_value_e_max-gda_value_e_tiny): a literal
whose value (zero included) has an exponent below `gda_value_e_tiny`
after the rounding, or an adjusted exponent above `gda_value_e_max`,
gives `Err` of the domain-error kind that names both limits and the exponent. It is
not a malformed literal, and it is no longer folded into an infinity or a zero
(`"1e3000000000"` and `"1e-3000000000"` are errors). Use the package function
[`to_number`](#to_number) when a rounded value is wanted or when the exponent
limits, flags or traps of a context must apply.

### `Decimal::to_string`, `Decimal::output`

These print the value in GDA scientific notation, with lowercase special
values.

```mbti
pub fn Decimal::to_string(Self) -> String
pub fn Decimal::output(Self, &Logger) -> Unit
pub impl Show for Decimal
```

A finite value with $e \le 0$ and $\hat e \ge -6$ prints without an exponent
(`0.000123`, `7.50`); otherwise it prints one digit, the remaining digits after
a point, and `E±`$\hat e$ (`1.23E+7`, `1E-7`, `0E+2`). Infinities print as
`inf`/`-inf`, NaNs as `nan`, `snan`, `-nan`, followed by the payload when it is
not zero. For the GDA spellings `Infinity`/`NaN`/`sNaN` use
[`Decimal::to_sci_string`](#decimalto_sci_string-decimalto_eng_string).

### `Decimal::to_sci_string`, `Decimal::to_eng_string`

These print a value with GDA to-scientific-string or to-engineering-string.
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

These report the class, the numeric sign and the stored precision attribute.

```mbti
pub fn Decimal::classify(Self) -> @arithmetic.FpClass
pub fn Decimal::signum(Self) -> @def.Sign
pub fn Decimal::precision(Self) -> Int
```

`classify` returns `Finite`, `Infinity` or `NaN`. `signum` returns `Zero` for
zeros of either sign and for NaNs, and `Positive`/`Negative` otherwise; use
`is_signed` to read the sign bit.

### `Decimal::coefficient`, `Decimal::exponent10`

These expose the stored representation $(c, e)$.

```mbti
pub fn Decimal::coefficient(Self) -> @bigint.BigInt
pub fn Decimal::exponent10(Self) -> Int
```

`coefficient` returns $c \ge 0$ (the payload for a NaN, 0
for an infinity). `exponent10` returns $e$ (0 for special values). GDA 1.70
has no operation named `quantum`: its operations are `quantize` and
`same-quantum`.

### `Decimal::is_finite`, `Decimal::is_infinite`, `Decimal::is_nan`, `Decimal::is_zero`, `Decimal::is_signed`, `Decimal::is_negative_zero`

These are the class and sign predicates.

```mbti
pub fn Decimal::is_finite(Self) -> Bool
pub fn Decimal::is_infinite(Self) -> Bool
pub fn Decimal::is_nan(Self) -> Bool
pub fn Decimal::is_zero(Self) -> Bool
pub fn Decimal::is_signed(Self) -> Bool
pub fn Decimal::is_negative_zero(Self) -> Bool
```

`is_signed` reads the sign bit, so it is
true for $-0$, $-\infty$ and negative NaNs. `is_zero` is true for finite zeros
of any exponent.

### `Decimal::is_qnan`, `Decimal::is_snan`

These distinguish quiet from signaling NaNs.

```mbti
pub fn Decimal::is_qnan(Self) -> Bool
pub fn Decimal::is_snan(Self) -> Bool
```

### `Decimal::is_canonical`

`is_canonical` always returns `true`: every `Decimal` value is canonical (only
interchange encodings can be non-canonical, see
[`GdaInterchange::is_canonical`](#gdainterchangecanonical-gdainterchangeis_canonical)).

```mbti
pub fn Decimal::is_canonical(Self) -> Bool
```

### `Decimal::nan_payload`

`nan_payload` reads a NaN payload.

```mbti
pub fn Decimal::nan_payload(Self) -> @bigint.BigInt
```

`nan_payload` returns the payload of a NaN and 0 for any other value. The
IEEE 754-2019 §9.7 payload operations (`getPayload`, `setPayload`,
`setPayloadSignaling`) are in [`decimal`](decimal.md), not here.

## Sign, cohort and precision transformations

### `Decimal::neg`, `Decimal::abs`, `Decimal::copy`, `Decimal::copy_abs`, `Decimal::copy_negate`, `Decimal::copy_sign`

These change only the sign bit; they never round and never signal, even for a
signaling NaN.

```mbti
pub fn Decimal::neg(Self) -> Self
pub fn Decimal::abs(Self) -> Self
pub fn Decimal::copy(Self) -> Self
pub fn Decimal::copy_abs(Self) -> Self
pub fn Decimal::copy_negate(Self) -> Self
pub fn Decimal::copy_sign(Self, Self) -> Self
```

`neg` and `copy_negate` flip the sign, `abs` and `copy_abs` clear it, `copy`
returns the value, and `copy_sign(x, y)` gives `x` the sign bit of `y`. These
are GDA *copy* operations; the rounding versions are the package functions
[`minus`, `plus`, `abs`](#apply-plus-minus-abs).

### `Decimal::normalized`, `Decimal::trim`, `Decimal::with_precision`

These move a value within its cohort or round it to a new precision attribute.

```mbti
pub fn Decimal::normalized(Self) -> Self
pub fn Decimal::trim(Self) -> Self
pub fn Decimal::with_precision(Self, Int, @arithmetic.RoundingMode) -> Self
```

`normalized` rounds half to even to the stored precision and removes all
trailing zeros (`7.50` becomes `7.5`, `1200` becomes `1.2E+3`). `trim` removes
only fractional trailing zeros and never makes the exponent positive (`7.50`
becomes `7.5`, `1200` stays `1200`); a zero becomes `0` with exponent 0.
`with_precision(p, mode)` rounds to `p` digits with `mode`, removes trailing
zeros and sets the precision attribute; special values only get the new
attribute. None of them report flags. A carry of the rounding at the top of the
[stored range](#gda_value_e_max-gda_value_e_tiny) follows the
GDA Overflow rule of the working range, so the result is never a finite value above
the limit: for example `9999E+2147483643` rounded to 2 digits is `inf` in the
modes that round away from zero or to nearest, and `9.9E+2147483646`, the
largest finite value of that width, in the modes toward zero.

### `Decimal::identical`

`identical` is the relation "the same datum".

```mbti
pub fn Decimal::identical(Self, Self) -> Bool
```

It is true for two values with the same class, sign, coefficient and exponent,
the same precision attribute and, for NaNs, the same payload and the same kind
(quiet or signaling). `2.5` and `2.50` are equal by `==` and not identical; `0`
and `-0` are equal and not identical; two NaNs with the same payload are
identical although `==` and `compare` treat every NaN alike. It is
`compare_total` being 0 together with equal precision attributes (GDA defines
`compare_total` without a precision). The attribute is part of it because the
plain operators round to the larger attribute of their operands: `1` with
attribute 3 and `1` with attribute 34 are equal and have `compare_total` 0, but
divided by `3` they give `0.333` and `0.3333333333333333333333333333333333`.
Two identical values give the same result in every function.

### `Decimal::same_quantum`

`same_quantum` tests whether two values have the same exponent.

```mbti
pub fn Decimal::same_quantum(Self, Self) -> Bool
```

It is true for two finite values with equal exponents, for two infinities and
for two NaNs, and false otherwise.

## The GDA context

### `GdaContext`

`GdaContext` is the immutable GDA context: arithmetic policy plus sticky flags
plus enabled traps.

```mbti
pub struct GdaContext {
  // private fields
}
```

The policy is precision $p \ge 1$, a `GdaRoundingMode`, $e_{\min} \le e_{\max}$,
`clamp` and `extended`. The flags are a `GdaFlags` value that operations only
ever enlarge; the traps are a `GdaTrapSet`. Neither flags nor traps influence
the numerical result of an operation: they only decide the next context and
whether the outcome is `Completed` or `Trapped`.

### `GdaContext::new`, `GdaContext::try_new`

`new` builds a context with an empty set of flags and aborts on an invalid
parameter; `try_new` takes the same parameters and returns a `Result`.

```mbti
pub fn GdaContext::new(precision? : Int, rounding? : GdaRoundingMode, e_min? : Int, e_max? : Int, clamp? : Bool, extended? : Bool, traps? : GdaTrapSet) -> Self
pub fn GdaContext::try_new(precision? : Int, rounding? : GdaRoundingMode, e_min? : Int, e_max? : Int, clamp? : Bool, extended? : Bool, traps? : GdaTrapSet) -> Result[Self, @arithmetic.ArithmeticError]
```

Defaults: `precision=34`, `rounding=HalfEven`, `e_min=-999_999_999`,
`e_max=999_999_999`, `clamp=false`, `extended=true`, no traps. The parameters
must satisfy these rules, and `try_new` returns `Err(domain_error)` naming the
invalid one while `new` aborts with the same message:

- precision within `1..=999_999_999`, `e_max` within `0..=999_999_999` and
  `e_min` within `-999_999_999..=0`. These adopted decNumber `decContext.h`
  limits keep Etiny/Etop and exponent arithmetic within `Int`; GDA 1.70
  itself fixes no limit.
- `e_min` is `-e_max`, `1 - e_max` (the IEEE 754 rule) or `-e_max - 1`. GDA 1.70
  (page 10) requires the magnitudes of Emin and Emax to differ by at most one,
  so that the range of results is balanced. A range such as `e_min=-50,
  e_max=60` is rejected. The text also requires `Elimit` to exceed five times
  the maximum coefficient length when there is one; the context has no maximum
  coefficient length, and 913 rows of the official decTest corpus run with
  an `e_max` below four times the precision, so that sentence is not enforced.

`clamp` and `extended` are not parameters of the context in the GDA text. They
are decNumber extensions that the library keeps: `clamp=true` is the
fold-down of the Clamped condition (page 51), which limits exponents to
$e_{\max} - p + 1$ as the interchange formats do, and `extended=false` selects
the GDA *subset* arithmetic of Appendix A (page 55, footnote 43: a parameter
of the context "might" select it): operands longer than $p$ digits are rounded
first (raising `LostDigits` when that is inexact), special values cannot be
parsed, zeros and some results are normalized, and `fma` is invalid. The
official decTest files use both (`clamp:` in 30,649 rows, `extended: 0` in all
16,162 rows of `dectest0`).

> [!NOTE]
> `exp`, `ln`, `log10` and `power` with a non-integer exponent require
> $p \le 999\,999$, $e_{\max} \le 999\,999$ and $e_{\min} \ge -999\,999$. This is a
> deliberate implementation limit, not a rule of the GDA operation text: it is
> decNumber's `DEC_MAX_MATH`, the official decTest suite requires it
> (`power.decTest` rows powx4001 to powx4005; the matching rows expx901 to
> expx906, lnx901 to lnx906 and logx901 to logx906 of `exp.decTest`,
> `ln.decTest` and `log10.decTest`, in a section that decTest labels
> decNumber's restricted range for the mathematical functions), and GDA 1.70
> permits it through its Invalid context condition (the precision "exceeds the
> capability of the underlying concrete representation"). With the default
> exponent range they return NaN and raise `InvalidContext`.

### `GdaContext::basic_default`, `GdaContext::decimal32`, `GdaContext::decimal64`, `GdaContext::decimal128`

These return the default contexts of GDA 1.70 (page 16).

```mbti
pub fn GdaContext::basic_default() -> Self
pub fn GdaContext::decimal32(mode? : GdaRoundingMode) -> Self
pub fn GdaContext::decimal64(mode? : GdaRoundingMode) -> Self
pub fn GdaContext::decimal128(mode? : GdaRoundingMode) -> Self
```

| Context | $p$ | rounding | $e_{\min}$ | $e_{\max}$ | clamp | extended | traps |
| --- | ---: | --- | ---: | ---: | --- | --- | --- |
| `basic_default` | 9 | `HalfUp` | $-999\,999\,999$ | $999\,999\,999$ | no | no | DivisionByZero, InvalidOperation, Overflow, Underflow, Clamped |
| `decimal32` | 7 | `HalfEven` | $-95$ | $96$ | yes | yes | none |
| `decimal64` | 16 | `HalfEven` | $-383$ | $384$ | yes | yes | none |
| `decimal128` | 34 | `HalfEven` | $-6143$ | $6144$ | yes | yes | none |

`basic_default` is what the specification calls the *basic default context*:
precision 9, round-half-up, and every trap enabled except inexact, rounded and
subnormal (GDA 1.70 page 16); the library also leaves the lost-digits trap off, because
Appendix A sets it to 0 in default contexts. The library also sets `extended=false` for it (the X3.274 subset of
Appendix A); the text of the context does not set that parameter. `decimal32`, `decimal64` and `decimal128` are the
*extended default contexts* for the IEEE 754 formats: round-half-even, no traps;
`rounding` replaces the mode when given. `GdaContext::new()` is not
`basic_default()`: it has precision 34, half-even and no traps. The values are
created once and shared.

### `GdaContext::with_precision`, `GdaContext::with_rounding`, `GdaContext::with_exponent_range`

These return a copy with one setting changed.

```mbti
pub fn GdaContext::with_precision(Self, Int) -> Self
pub fn GdaContext::with_rounding(Self, GdaRoundingMode) -> Self
pub fn GdaContext::with_exponent_range(Self, e_min~ : Int, e_max~ : Int) -> Self
```

The result is checked like `new`: a precision or exponent range outside the
rules above aborts. The sticky flags, the traps, `clamp`, `extended` and the
refinement limit are kept.

### `GdaContext::precision`, `GdaContext::rounding`, `GdaContext::e_min`, `GdaContext::e_max`, `GdaContext::clamp`, `GdaContext::extended`, `GdaContext::radix`

These read the arithmetic policy.

```mbti
pub fn GdaContext::precision(Self) -> Int
pub fn GdaContext::rounding(Self) -> GdaRoundingMode
pub fn GdaContext::e_min(Self) -> Int
pub fn GdaContext::e_max(Self) -> Int
pub fn GdaContext::clamp(Self) -> Bool
pub fn GdaContext::extended(Self) -> Bool
pub fn GdaContext::radix(Self) -> Int
```

`radix` always returns 10.

### `GdaContext::flags`, `GdaContext::traps`

These read the sticky flags and the enabled traps.

```mbti
pub fn GdaContext::flags(Self) -> GdaFlags
pub fn GdaContext::traps(Self) -> GdaTrapSet
```

### `GdaContext::refinement_limit`, `GdaContext::with_refinement_limit`

These read and set the number of refinement steps of the certified elementary
functions.

```mbti
pub fn GdaContext::refinement_limit(Self) -> Int?
pub fn GdaContext::with_refinement_limit(Self, Int?) -> Self
```

`exp`, `ln`, `log10` and `power` refine an enclosure of the result at most
`Some(12)` times by default. A rare argument close to a rounding boundary may
need more: `with_refinement_limit(Some(24))` allows 24 steps and `None` removes
the count (the working precision then stops at a resource bound). A limit below
1 is one step. When the limit is reached, the plain functions return a NaN with
`invalid_operation` and [`try_exp`, `try_ln`, `try_log10`, `try_power`](#try_exp-try_ln-try_log10-try_power)
return `Err`.

### `GdaContext::trap`, `GdaContext::with_traps`, `GdaContext::clear_flags`, `GdaContext::reset`

These return a new context with changed traps or flags; the receiver is not
modified.

```mbti
pub fn GdaContext::trap(Self, GdaSignal, enabled? : Bool) -> Self
pub fn GdaContext::with_traps(Self, GdaTrapSet) -> Self
pub fn GdaContext::clear_flags(Self) -> Self
pub fn GdaContext::reset(Self) -> Self
```

`trap(s)` enables (or with `enabled=false` disables) one trap; `with_traps`
replaces the whole set. `clear_flags` empties the flags and keeps the traps;
`reset` empties both.

### `GdaRoundingMode`

`GdaRoundingMode` lists the eight GDA rounding modes.

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

When the exact result lies strictly between two representable neighbours,
`Down` takes the one nearer zero, `Up` the one farther from zero, `Ceiling` the
larger, `Floor` the smaller; `HalfEven`, `HalfUp` and `HalfDown` take the
nearer one and break an exact tie towards an even last digit, away from zero,
or towards zero respectively; `ZeroFiveUp` rounds towards zero unless that
leaves a last digit of 0 or 5, in which case it rounds away from zero. The
[design page](../design/decimal_gda.md#rounding-to-precision) gives each mode as
a formula.

## Signals, flags and traps

### `GdaSignal`

`GdaSignal` names the nine signals of GDA 1.70. Each has a flag in the context
flags and a trap-enabler.

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

The eight signals of the specification (page 15) are `Clamped`,
`DivisionByZero`, `Inexact`, `InvalidOperation`, `Overflow`, `Rounded`,
`Subnormal` and `Underflow`; `LostDigits` is the ninth, raised only in subset
arithmetic (Appendix A). The conditions of pages 51 and 52 that the text says
signal invalid-operation (conversion syntax, division impossible, division
undefined and invalid context) are not signals: they are conditions of
`GdaFlags`, and raising any of them raises the signal `InvalidOperation`.

### `GdaFlags`

`GdaFlags` is a set of conditions (the thirteen conditions the library raises,
the fourteen of the specification without Insufficient storage), used both for
the conditions raised by one operation and for the sticky flags of a context.
The decTest files name conditions, so the flags keep them apart.

```mbti
pub struct GdaFlags {
  // private fields
} derive(Eq)
```

The fields are private. Each of the 13 conditions is read with a method of the
same name, such as `raised().inexact()` or `status().division_by_zero()`; there
is no public constructor besides `new`, so sets are built only with `new` and
`combine`. `GdaTrapSet` reads the same way, one method for each of the nine signals.

### `GdaFlags::new`, `GdaFlags::contains`, `GdaFlags::combine`

`new` is the empty set, `combine` the field-wise union and `contains` the
membership test of a *signal*, with the GDA invalid-operation grouping. The
accessor methods read one *condition* each.

```mbti
pub fn GdaFlags::new() -> Self
pub fn GdaFlags::contains(Self, GdaSignal) -> Bool
pub fn GdaFlags::combine(Self, Self) -> Self
```

`combine` is associative, commutative and idempotent with `new()` as identity.
`contains(s)` reads the field for `s`, except that `contains(InvalidOperation)`
is true when any of `invalid_operation`, `conversion_syntax`,
`division_impossible`, `division_undefined` or `invalid_context` is set. The
accessor `invalid_operation()` reads the plain Invalid operation condition
only, and the plain condition is not raised with every one of the four: a
division undefined or impossible raises it, a conversion syntax error or an
invalid context does not, as in decNumber, whose status word the decTest rows
describe. Use `contains(InvalidOperation)` to ask whether the signal was
raised.

### `GdaTrapSet`

`GdaTrapSet` is the set of enabled trap-enablers, one for each of the nine
signals.

```mbti
pub struct GdaTrapSet {
  // private fields
} derive(Eq)
```

### `GdaTrapSet::new`, `GdaTrapSet::with_signal`, `GdaTrapSet::contains`

These build and query trap sets.

```mbti
pub fn GdaTrapSet::new() -> Self
pub fn GdaTrapSet::with_signal(Self, GdaSignal, enabled? : Bool) -> Self
pub fn GdaTrapSet::contains(Self, GdaSignal) -> Bool
```

`new` enables no trap. `with_signal(s)` enables one trap (or disables it with
`enabled=false`); `contains(s)` reads the trap-enabler of `s`. The trap of
`InvalidOperation` fires for every condition that signals it.

### `GdaOutcome`

`GdaOutcome[T]` is the result of every GDA operation.

```mbti
pub enum GdaOutcome[T] {
  Completed(T, GdaContext, GdaFlags)
  Trapped(GdaSignal, T, GdaContext, GdaFlags)
}
```

Both variants carry the GDA-defined result, the next context and the
conditions raised by this operation; `Trapped` also names the trap that fired.

The enum is read-only outside the package: a caller can `match` on it and use
the accessors, but only the GDA operations, `GdaOutcome::completed` and
`GdaOutcome::absorb` construct an outcome. To turn a
trapped outcome into its defined result, use `GdaOutcome::resume_defined`.

### `GdaOutcome::value`, `GdaOutcome::next_context`, `GdaOutcome::raised`

These read the fields that both variants share, without a `match`.

```mbti
pub fn[T] GdaOutcome::value(Self[T]) -> T
pub fn[T] GdaOutcome::next_context(Self[T]) -> GdaContext
pub fn[T] GdaOutcome::raised(Self[T]) -> GdaFlags
```

`value` is the defined result also for `Trapped`, `next_context` the context
with the updated flags, and `raised` the conditions of this operation only.

### `GdaOutcome::completed`, `GdaOutcome::absorb`

These build the outcomes a pipeline needs.

```mbti
pub fn[T] GdaOutcome::completed(T, GdaContext) -> Self[T]
pub fn[T, U] GdaOutcome::absorb(Self[T], Self[U]) -> Self[T]
```

`completed(v, c)` is the outcome of an operation that raised nothing: `v` and `c`
unchanged, empty `raised`. `a.absorb(b)` keeps the value, the context (traps
included) and the trap of `a`; the conditions that `b` raised join `raised` and the
sticky flags of the next context (with `invalid_operation` set when one of the
four detailed invalid conditions is among them); when `a` completed and `b`
trapped, the result is `Trapped` with the signal of `b`. The traps of `a` are not
tested against the conditions of `b`. [`GdaDecimalChecked`](decimal_gda_checked.md)
uses it for the right operand of a binary operation.

### `GdaOutcome::resume_defined`

This is the only way to build a `Completed` outcome from a `Trapped` one.

```mbti
pub fn[T] GdaOutcome::resume_defined(Self[T]) -> Self[T]
```

`Completed` is returned unchanged; `Trapped(s, v, C, R)` becomes
`Completed(v, C, none)`, the GDA rule for continuing after a trap with the
defined result. `GdaDecimalChecked::resume_defined` calls it.

### Trap selection

Every GDA function finishes the same way. Let $R$ be the conditions the
operation raised and $C$ the input context.

1. If $R$ is empty the outcome is `Completed(v, C, none)`: the very same
   context comes back.
2. Otherwise the next context is $C$ with flags
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

Every function in this section takes its operands and a `GdaContext`, rounds
to that context, and returns a `GdaOutcome` built by the
[trap selection](#trap-selection) rule. A signaling-NaN operand raises
`InvalidOperation` and yields the corresponding quiet NaN; a quiet NaN operand
propagates without raising anything (the first NaN operand wins). In subset
contexts (`extended=false`) finite operands longer than the precision are
rounded first. Unless stated otherwise the result is the exact mathematical
result rounded once, with the *ideal exponent* listed for the operation when
the result is exact.

### `to_number`

`to_number` is the GDA to-number conversion of a string.

```mbti
pub fn to_number(String, GdaContext) -> GdaOutcome[Decimal]
```

The literal keeps its exponent unless it must be rounded to the precision or
clamped to the exponent range; overflow and underflow are decided from the
exact exponent of the text, however large. Malformed text gives a quiet NaN with
`ConversionSyntax`. In subset contexts infinities and NaNs are also a
conversion-syntax error.

### `apply`, `plus`, `minus`, `abs`

These round one operand to the context: `plus` is $0 + x$, `minus` is
$0 - x$, `abs` is $|x|$, and `apply` is the plain conversion of a value to the
context.

```mbti
pub fn apply(Decimal, GdaContext) -> GdaOutcome[Decimal]
pub fn plus(Decimal, GdaContext) -> GdaOutcome[Decimal]
pub fn minus(Decimal, GdaContext) -> GdaOutcome[Decimal]
pub fn abs(Decimal, GdaContext) -> GdaOutcome[Decimal]
```

Ideal exponent: that of the operand. A zero result takes its sign from the
GDA rule for a zero sum: `plus(x)` is $0 + x$ and `minus(x)` is $0 - x$, so
`plus(-0)` and `minus(0)` are $-0$ under `Floor` and $+0$ in every other mode,
while `plus(0)`, `minus(-0)` and `abs` of either zero are $+0$ (in a subset
context every zero result is $+0$). `apply` keeps
the sign of a zero and does not round subset operands first.

### `add`, `subtract`, `multiply`, `divide`, `fma`

These are the basic arithmetic operations; `fma(a, b, c)` is $a \times b + c$
with a single rounding.

```mbti
pub fn add(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]
pub fn subtract(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]
pub fn multiply(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]
pub fn divide(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]
pub fn fma(Decimal, Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]
```

Ideal exponents: $\min(e_1, e_2)$ for `add` and `subtract`; $e_1 + e_2$ for
`multiply`; $e_1 - e_2$ for `divide` (an inexact quotient has a full
$p$-digit coefficient); for `fma`, the `add` rule applied to the exact product
and the addend. An exact zero sum is $-0$ when both operands (for `subtract`,
the first operand and the negated second) are negative, $+0$ when both are
positive, and otherwise $+0$, or $-0$ under `Floor`; so `add(0, -0)` is `0`
in `HalfEven` and `-0` in `Floor`, while `add(0, 0)` is `0` in every mode. Special cases: $\infty - \infty$,
$0 \times \infty$ and $\infty / \infty$ are invalid; $x / 0$ is $\pm\infty$
with `DivisionByZero`; $0 / 0$ is NaN with `DivisionUndefined`;
$x / \infty$ is a zero with exponent $E_{\mathrm{tiny}}$ and `Clamped`. `fma`
is invalid in a subset context.

A far smaller addend is absorbed as a sticky unit below every rounding
boundary of the sum, and a result is rounded to the subnormal grid only when
its exact value is below $10^{e_{\min}}$, so every one of these operations
rounds once: at precision 7, `add(1598618.5, 1E-20)` is `1598619`, and in
decimal32 `multiply(3.000001E-45, 1.500001E-45)` is `4.500005E-90` and
`divide(1, 1.9999999999998E+101)` is `1E-101`.

### `divide_integer`, `remainder`, `remainder_near`

These divide to an integer quotient.

```mbti
pub fn divide_integer(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]
pub fn remainder(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]
pub fn remainder_near(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]
```

`divide_integer` returns $q = \operatorname{trunc}(x / y)$ with preferred exponent 0;
`remainder` returns $x - q y$ (the sign of $x$); `remainder_near` returns
$x - n y$ where $n$ is $x / y$ rounded to the nearest integer, ties to even.
The remainder has ideal exponent $\min(e_x, e_y)$. When $q$ (or $n$) needs
more than $p$ digits the result is NaN with `DivisionImpossible`. A zero
divisor gives `DivisionByZero` (`divide_integer` of a nonzero number) or
`DivisionUndefined` ($0 / 0$); a zero divisor or an infinite dividend makes
both remainders invalid; a finite dividend with an infinite divisor is its
own remainder. In an extended clamped context, a zero quotient keeps its exact
sign and is folded to $e_{\max}-p+1$ when needed, raising `Clamped` without
raising `Rounded` or `Inexact`.

### `quantize`, `rescale`

These round a value to a prescribed exponent.

```mbti
pub fn quantize(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]
pub fn rescale(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]
```

`quantize(x, q)` returns the value of $x$ with exponent $e_q$, rounded with the
context mode (raising `Rounded`, and `Inexact` when digits are lost).
`rescale(x, n)` does the same with exponent $n$, where $n$ must be an integer
value. The result is invalid when the target exponent lies outside
$[E_{\mathrm{tiny}}, e_{\max}]$ ($[e_{\min}, e_{\max}]$ in subset contexts),
when the result coefficient would need more than $p$ digits, or when exactly
one operand is infinite. Two infinities give the infinity. A subnormal result
raises `Subnormal` (and `Inexact` and `Rounded` when digits are lost) but never
`Underflow`: in `decimal32`, `quantize(1.55E-100, 1E-101)` is `1.6E-100` with
`Subnormal`, `Inexact` and `Rounded`.

### `round_to_integral_exact`, `round_to_integral_value`

These round to an integer with the context rounding mode.

```mbti
pub fn round_to_integral_exact(Decimal, GdaContext) -> GdaOutcome[Decimal]
pub fn round_to_integral_value(Decimal, GdaContext) -> GdaOutcome[Decimal]
```

A value with exponent $\ge 0$ is already an integer and is returned
unchanged, even when it is longer than $p$ digits (a `clamp` context still
folds its exponent down). A value with negative
exponent is quantized to exponent 0 at a working precision of
$\max(p, \text{its digit count})$, as decNumber does, so the integral part is
never rounded to $p$ digits: at precision 3, `12345.6` gives `12346`.
`round_to_integral_exact` raises `Inexact` and `Rounded` when digits are dropped and
`round_to_integral_value` never does. In a subset context the operand is first
rounded to $p$ digits, with `LostDigits`, like every other operand.

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

### `sqrt`, `exp`, `ln`, `log10`

These are the correctly rounded square root, exponential, natural logarithm
and base-10 logarithm.

```mbti
pub fn sqrt(Decimal, GdaContext) -> GdaOutcome[Decimal]
pub fn exp(Decimal, GdaContext) -> GdaOutcome[Decimal]
pub fn ln(Decimal, GdaContext) -> GdaOutcome[Decimal]
pub fn log10(Decimal, GdaContext) -> GdaOutcome[Decimal]
```

They always round half to even, whatever the context rounding mode. Exact
results: `sqrt` of a perfect square has the ideal exponent $\lfloor e/2
\rfloor$; `exp(0) = 1`; `ln(1) = 0`; `log10` of a power of ten $10^k$ is the
integer $k$ (rounded if $k$ has more than $p$ digits). Every other finite
result is inexact with $p$ digits. Domain: the square root and logarithms of a
negative number are invalid, $\ln 0 = \log_{10} 0 = -\infty$ (invalid in a
subset context), $\exp(-\infty) = 0$, and $+\infty$ maps to $+\infty$ for
all four. `exp`, `ln` and `log10` raise `InvalidContext` unless $p$,
$e_{\max}$ and $-e_{\min}$ are at most 999,999, and also for a nonzero operand
with more than 999,999 digits or an adjusted exponent above 999,999 or below
$-1\,999\,997$. If the certified
evaluation cannot decide the rounding within its refinement budget the result
is NaN with `InvalidOperation`. In a subset context, `ln` reproduces the
result of the classic reference algorithm, which can exceed the correctly
rounded result by one unit in the last place.

### `power`

`power(x, y)` is $x^y$.

```mbti
pub fn power(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]
```

For an integer $y$ the result is computed by binary powering with
$p + \operatorname{digits}(|y|) + 2$ working digits (one fewer in subset
contexts) and then rounded with the context mode; an exact power that fits in
$p$ digits is returned exactly with exponent $y \cdot e_x$. For a non-integer
$y$, $x$ must be positive (a negative base is invalid) and the result is
certified to be correctly rounded *with the context rounding mode*;
$y = 0.5$ is computed as a square root under the context rounding mode. The
same context limits as for `exp` apply to non-integer exponents. Special
cases follow GDA: $x^0 = 1$ (and $0^0$ is invalid), powers of $\pm\infty$ and
$\pm 0$ take their sign from the parity of an integer exponent, and $1^y = 1$.
In a subset context $0^0$ is `1` and $0^{-n}$ is invalid instead of
$\infty$.

GDA treats every non-integer power as inexact, even when its exact value is
representable: `power(4, 1.5)` at precision 5 is `8.0000` with `Inexact` and
`Rounded` in every rounding mode. Such exact values (an exponent $a/q$ in
lowest terms with $x$ a perfect $q$-th power) are decided before the
certified loop, because they lie on the boundary of a directed rounding cell
or on a midpoint, which the loop cannot certify. The specification allows an
inexact power to be up to one unit in the last place in error; this package
always returns the correctly rounded value, so `Down`, `Floor` and
`ZeroFiveUp` give `8.0000` where libmpdec gives `7.9999`.

### `try_exp`, `try_ln`, `try_log10`, `try_power`

These are `exp`, `ln`, `log10` and `power` with a second channel for "the
library could not certify this result".

```mbti
pub fn try_exp(Decimal, GdaContext) -> Result[GdaOutcome[Decimal], @arithmetic.ArithmeticError]
pub fn try_ln(Decimal, GdaContext) -> Result[GdaOutcome[Decimal], @arithmetic.ArithmeticError]
pub fn try_log10(Decimal, GdaContext) -> Result[GdaOutcome[Decimal], @arithmetic.ArithmeticError]
pub fn try_power(Decimal, Decimal, GdaContext) -> Result[GdaOutcome[Decimal], @arithmetic.ArithmeticError]
```

Every case the specification defines (domain errors, signaling NaNs,
a context beyond the supported exponent range, which `exp` and its siblings
report as `invalid_context`) is an `Ok` outcome exactly as the plain function
returns it. `Err` means the refinement limit or a resource bound stopped the
computation, where the plain function returns a NaN with `invalid_operation`.

### `reduce`

`reduce` rounds to the context and removes trailing zeros.

```mbti
pub fn reduce(Decimal, GdaContext) -> GdaOutcome[Decimal]
```

A zero becomes $0$ with exponent 0 (keeping its sign in extended contexts). In
a clamped context the exponent is not raised above $e_{\max} - p + 1$.

### `scaleb`, `logb`

These scale by a power of ten and extract the adjusted exponent.

```mbti
pub fn scaleb(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]
pub fn logb(Decimal, GdaContext) -> GdaOutcome[Decimal]
```

`scaleb(x, n)` returns $x \cdot 10^n$ by adding $n$ to the exponent; $n$ must
be an integer with exponent 0 and $|n| \le 2(e_{\max} + p)$, otherwise the
result is invalid. The result then goes through the shared finalization: a
coefficient longer than $p$ digits is rounded, an overflow gives $\pm\infty$
or the largest finite number by rounding direction (in decimal32 under `Down`,
`scaleb(9E+96, 1)` is `9.999999E+96`), and a zero result is clamped into the
exponent range (`scaleb(0E+300, 400)` in decimal64 is `0E+369`). `logb(x)` returns $\hat e$ as
an integer; `logb(0)` is $-\infty$ with `DivisionByZero` and `logb(±∞)` is
$+\infty$.

### `next_plus`, `next_minus`, `next_toward`

These step to the adjacent representable value.

```mbti
pub fn next_plus(Decimal, GdaContext) -> GdaOutcome[Decimal]
pub fn next_minus(Decimal, GdaContext) -> GdaOutcome[Decimal]
pub fn next_toward(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]
```

`next_plus` returns the smallest representable number greater than $x$ in the
context and `next_minus` the largest smaller one; from a zero they step to
$\pm 10^{E_{\mathrm{tiny}}}$, and past the largest finite number they reach
$\pm\infty$. Neither raises flags for finite results. `next_toward(x, y)`
steps from $x$ towards $y$ (returning $x$, with the sign of $y$ for zeros, when
they compare equal) and raises `Overflow`, or `Underflow` and `Subnormal`,
together with `Inexact` and `Rounded`, when the step leaves the normal range.

### `logical_and`, `logical_or`, `logical_xor`, `logical_invert`

These are digit-wise logical operations on *logical operands*: non-negative
integers with exponent 0 whose digits are all 0 or 1.

```mbti
pub fn logical_and(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]
pub fn logical_or(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]
pub fn logical_xor(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]
pub fn logical_invert(Decimal, GdaContext) -> GdaOutcome[Decimal]
```

Each operand is read as exactly $p$ digits: shorter operands are padded with
leading zeros and only the low $p$ digits of longer ones are used.
`logical_invert` inverts all $p$ digits. Any other operand makes the result
invalid.

### `shift`, `rotate`

These move the coefficient digits of $x$ by $n$ places within a window of $p$
digits.

```mbti
pub fn shift(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]
pub fn rotate(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]
```

$n$ must be an integer with exponent 0 and $|n| \le p$, otherwise the result
is invalid. A positive $n$ moves digits to the left. `shift` drops the digits
that leave the window and fills with zeros; `rotate` moves them round to the
other end. The exponent and sign are unchanged; an infinite $x$ is returned
unchanged.

### `compare`, `compare_signal`, `compare_total`, `compare_total_magnitude`

These compare two values.

```mbti
pub fn compare(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]
pub fn compare_signal(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]
pub fn compare_total(Decimal, Decimal, GdaContext) -> GdaOutcome[Int]
pub fn compare_total_magnitude(Decimal, Decimal, GdaContext) -> GdaOutcome[Int]
```

`compare` returns the decimal $-1$, $0$ or $1$ by numeric value ($-0 = +0$,
$2.50 = 2.5$), or a quiet NaN when an operand is a NaN (raising
`InvalidOperation` only for a signaling NaN). `compare_signal` is the same but
raises `InvalidOperation` for any NaN. `compare_total` returns $-1$, $0$ or $1$
in the GDA total order: by sign bit first, then, for positive values,
$\text{finite} < \infty < \text{sNaN} < \text{NaN}$, finite values by numeric
value and then by exponent (`2.50` < `2.5`), NaNs by payload; the order is
reversed for negative values. `compare_total_magnitude` applies the total
order to the absolute values. The total orders never raise flags in an
extended context. In a subset context (`extended=false`) the operands are first
rounded to the precision like every other operand (Appendix A), which raises
`Rounded` and `LostDigits`; the [`Decimal` methods of the same
names](#decimalcompare_total-decimalcompare_total_magnitude) compare the
numbers as they are.

### `max`, `min`, `max_magnitude`, `min_magnitude`

These are the GDA max and min operations, on values or on magnitudes.

```mbti
pub fn max(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]
pub fn min(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]
pub fn max_magnitude(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]
pub fn min_magnitude(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]
```

A single quiet NaN is ignored in favour of the number; two quiet NaNs give
the first; a signaling NaN gives a quiet NaN with `InvalidOperation`. Values
that compare equal are separated by the total order (so `max(2.5, 2.50)` is
`2.5`); in a subset context the first operand is chosen instead. The selected
operand is then rounded to the context as by `plus`, except that in an
extended context a zero keeps its sign (`max(-0, -0)` is `-0` in every
mode, while `plus(-0)` is `0` unless the rounding is `Floor`).

### `class_name`, `is_normal`, `is_subnormal`

These classify values under a context; they never raise conditions, so they
always return `Completed` with the input context.

```mbti
pub fn class_name(Decimal, GdaContext) -> GdaOutcome[String]
pub fn is_normal(Decimal, GdaContext) -> GdaOutcome[Bool]
pub fn is_subnormal(Decimal, GdaContext) -> GdaOutcome[Bool]
```

They need the exponent limits of the context (`Emin`), which is why they are
functions of the context; `same_quantum` uses no context and is a
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

These methods and operators take no context. They never signal and never
trap; use the GDA functions when flags matter.

### `Decimal::compare`, `Decimal::compare_checked`

`compare` is a three-way numeric comparison that is total on all values;
`compare_checked` refuses NaNs.

```mbti
pub fn Decimal::compare(Self, Self) -> Int
pub fn Decimal::compare_checked(Self, Self) -> Result[Int, @arithmetic.ArithmeticError]
pub impl Compare for Decimal
pub impl @arithmetic.CompareChecked for Decimal
```

`compare` orders finite values and infinities numerically with $-0 = +0$ and
places every NaN equal to every other NaN and above every number, so it is a
total preorder and sorting never aborts. `compare_checked` returns
`Err(unordered_comparison)` when either operand is a NaN.

### `Decimal::equal`, `Decimal::not_equal`, `Decimal::op_lt`, `Decimal::op_le`, `Decimal::op_gt`, `Decimal::op_ge`

These are the `Eq` and `Compare` operator methods.

```mbti
pub fn Decimal::equal(Self, Self) -> Bool
pub fn Decimal::not_equal(Self, Self) -> Bool
pub fn Decimal::op_lt(Self, Self) -> Bool
pub fn Decimal::op_le(Self, Self) -> Bool
pub fn Decimal::op_gt(Self, Self) -> Bool
pub fn Decimal::op_ge(Self, Self) -> Bool
pub impl Eq for Decimal
```

`==` is numeric equality on finite values ($2.50 = 2.5$, $-0 = +0$),
sign equality on infinities, and true for any two NaNs. `<`, `<=`, `>`, `>=`
follow `compare`.

### `Decimal::compare_total`, `Decimal::compare_total_magnitude`

These are the GDA total orders as plain methods, returning $-1$, $0$ or $1$.

```mbti
pub fn Decimal::compare_total(Self, Self) -> Int
pub fn Decimal::compare_total_magnitude(Self, Self) -> Int
```

They agree with the package functions
[`compare_total`, `compare_total_magnitude`](#compare-compare_signal-compare_total-compare_total_magnitude)
(without subset operand rounding).

### `Decimal::clamp`, `Decimal::clamp_checked`

These select between values without rounding. The GDA operations `min` and
`max` are the free functions `min` and `max` of the package, which take a
`GdaContext` and return a `GdaOutcome`; there are no methods of those names.

```mbti
pub fn Decimal::clamp(Self, min~ : Self, max~ : Self) -> Self
pub fn Decimal::clamp_checked(Self, min~ : Self, max~ : Self) -> Result[Self, @arithmetic.ArithmeticError]
```

`clamp` returns `min` or `max` when the
value lies outside $[\min, \max]$ and the value otherwise (a NaN value is
returned unchanged); it aborts when a bound is NaN or `min > max`, where
`clamp_checked` returns `Err(domain_error)`.

### `Decimal::add`, `Decimal::sub`, `Decimal::mul`, `Decimal::div`, `Decimal::neg`

These implement `+`, `-`, `*`, `/` and unary `-` without a context.

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
`divide` in a private working context and return their value: precision $P$, the larger precision attribute of
the operands, half-even rounding, the extended rules, no clamp and no traps.
The result is therefore a member of the cohort GDA prescribes: `+` and `-`
keep the smaller exponent (`1.10 + 3.50` is `4.60`), `*` adds the exponents,
`/` starts from the difference of the exponents and removes only the trailing
zeros that exact quotients allow (`1.5 / 0.5` is `3`, `1.50 / 0.5` is `3.0`),
and a result of any of the four operations with more than $P$ digits is rounded to
$P$ digits (`*` is no longer exact). `x + 0 == x` and `x * 1 == x` hold because equality compares values, not members
of the cohort, and for every stored finite value, because the working range
below is the [stored range](#gda_value_e_max-gda_value_e_tiny).

The working exponent range cannot be built with
[`GdaContext::new`](#gdacontextnew-gdacontexttry_new), because that function
limits the exponent range of a context to $\pm 999{,}999{,}999$ (limits adopted
from decNumber; GDA 1.70 page 9 allows a limit Elimit without giving a value)
and this one fills the `Int` range: the largest adjusted exponent is $2^{31}-2 = 2{,}147{,}483{,}646$
and the smallest exponent is $\text{Etiny} = -2^{31}+3 = -2{,}147{,}483{,}645$
for every $P$ (so `Etiny` is always a valid `Int` exponent). A result above the range is a signed infinity
(`1E+1500000000 * 1E+1500000000` is `inf`); one below it is rounded half to
even to `Etiny`, possibly to a signed zero. Special values follow IEEE rules
without signals: NaN operands give a quiet NaN, $\infty - \infty$,
$0 \times \infty$, $0/0$ and $\infty/\infty$ give NaN, $x/0$ gives a signed
infinity and $x/\infty$ gives a signed zero. Use the free functions with a
`GdaContext` when you need another precision, rounding, range or the signals.
Unary `-` is
[`Decimal::neg`](#decimalneg-decimalabs-decimalcopy-decimalcopy_abs-decimalcopy_negate-decimalcopy_sign):
it flips the sign bit and uses no context, so the context, the precision $P$, the
cohort rules and the working range above apply to `+`, `-`, `*` and `/` only.

### `Decimal::sqrt`

`sqrt` is the square root in the same working context as the operators, with
the value's own precision attribute.

```mbti
pub fn Decimal::sqrt(Self) -> Self
```

A negative operand gives NaN, as the free function [`sqrt`](#sqrt-exp-ln-log10) does. The
checked forms are `sqrt_checked` and `DivChecked::div_checked`; the
`Decimal::div_checked` method is removed (use `1 / 0` for the infinity, or
`divide` with a trapping `GdaContext` for an error).

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

`GdaInterchangeFormat` names the three IEEE 754 decimal interchange formats.

```mbti
pub(all) enum GdaInterchangeFormat {
  Decimal32
  Decimal64
  Decimal128
} derive(Eq)
```

### `GdaInterchangeFormat::context`

`context` returns the extended default `GdaContext` of the format.

```mbti
pub fn GdaInterchangeFormat::context(Self) -> GdaContext
```

The presets are `GdaContext::decimal32()`, `decimal64()` and
`decimal128()`: precision 7, 16 or 34, half-even, clamped.

### `GdaInterchange`

`GdaInterchange` is a decimal32, decimal64 or decimal128 bit pattern in the
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

These encode and decode values.

```mbti
pub fn GdaInterchange::from_decimal(Decimal, GdaInterchangeFormat) -> (Self, GdaFlags)
pub fn GdaInterchange::to_decimal(Self) -> Decimal
```

`from_decimal` rounds the value to the format (reporting the rounding,
overflow, underflow and clamping flags) and encodes it. `to_decimal` decodes
exactly, keeping the exponent and raising nothing; test the result with
[`is_subnormal`](#class_name-is_normal-is_subnormal) when the flag is needed.

A NaN is encoded with its sign, its signaling bit and its payload. The payload of
a decimal32, decimal64 or decimal128 pattern has 6, 15 or 33 digits (the trailing
significand field, IEEE 754-2019 3.5.2). A payload that is wider keeps its low
digits and no flag is raised: IEEE 754-2019 6.2.3 asks that a conversion that
cannot preserve the payload return a quiet NaN carrying some language-defined
diagnostic information, and names no signal. The decTest interchange rows have
no payload wider than their format.

### `GdaInterchange::from_hex`, `GdaInterchange::to_hex`

These convert between a bit pattern and its hexadecimal text.

```mbti
pub fn GdaInterchange::from_hex(String, GdaInterchangeFormat) -> Result[Self, @arithmetic.ArithmeticError]
pub fn GdaInterchange::to_hex(Self) -> String
```

The text is `#` (optional on input) followed by exactly 8, 16 or 32
hexadecimal digits; surrounding spaces are ignored and any other input gives
`Err(parse_error)`. `to_hex` prints `#` and uppercase digits.

### `GdaInterchange::canonical`, `GdaInterchange::is_canonical`

These canonicalize an encoding.

```mbti
pub fn GdaInterchange::canonical(Self) -> Self
pub fn GdaInterchange::is_canonical(Self) -> Bool
```

`canonical` decodes and re-encodes the pattern, which replaces non-canonical
declets and payloads with their canonical form; `is_canonical` tests whether
that changes the pattern.

### `GdaInterchange::copy`, `GdaInterchange::copy_abs`, `GdaInterchange::copy_negate`, `GdaInterchange::copy_sign`

These operate on the sign bit of the encoding without decoding it.

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

### `GdaRoundingMode::equal`, `GdaRoundingMode::not_equal`, `GdaSignal::equal`, `GdaSignal::not_equal`, `GdaFlags::equal`, `GdaFlags::not_equal`, `GdaTrapSet::equal`, `GdaTrapSet::not_equal`, `GdaInterchangeFormat::equal`, `GdaInterchangeFormat::not_equal`

These are the derived `Eq` methods of the enums and flag sets.

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

They compare field by field (or variant by variant); `GdaContext` has no `Eq`. `Decimal`
has its own numeric `Eq`, documented under
[`Decimal::equal`](#decimalequal-decimalnot_equal-decimalop_lt-decimalop_le-decimalop_gt-decimalop_ge).

### `Decimal::add_contextual`, `Decimal::sub_contextual`, `Decimal::mul_contextual`, `Decimal::div_contextual`, `Decimal::abs_contextual`, `Decimal::sqrt_contextual`, `Decimal::exp_contextual`

These implement the `Luna-Flow/arithmetic` contextual traits on top of the
package's private engine.

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

Each converts the arithmetic context to an engine context, runs the
operation, and returns `Err(unsupported)` when the operation
raises `invalid_context`, `Err(division_by_zero)` when `division_by_zero` is
raised, `Err(domain_error)` for any other error flag, and otherwise `Ok` with
the value and diagnostics `inexact`, `rounded`, `overflow`, `underflow`,
`subnormal` and `clamped`. The rounding is one of the five
`ArithmeticContext` modes, and `sqrt_contextual` and `exp_contextual` round
with it (not half-even as the GDA functions do).

`exp_contextual` requires the caller to set the exponent bounds. Like the GDA
`exp`, it is defined only for precision, $e_{\max}$ and $-e_{\min}$ of at most
$999\,999$, and an `ArithmeticContext` without `e_min` or `e_max` is not
given bounds by default: it translates to the full range
$\pm 999\,999\,999$, which is an invalid context for `exp`. The result is
`Err(unsupported)` whose message starts with `invalid context:`, states the
limit and names the bounds the `ArithmeticContext` does not set, whatever the
operand (as `exp(-Infinity)` is `Invalid_context` in the decTest row
`expx901`). `ArithmeticContext::new(16)` therefore fails, while
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

### `Decimal::zero_contextual`, `Decimal::one_contextual`, `Decimal::epsilon_contextual`, `Decimal::min_normal_contextual`, `Decimal::max_finite_contextual`, `Decimal::classify_contextual`

These implement `NumericFormatContextual`: they describe the number format of
an `ArithmeticContext`.

```mbti
pub fn Decimal::zero_contextual(@arithmetic.ArithmeticContext) -> Self
pub fn Decimal::one_contextual(@arithmetic.ArithmeticContext) -> Self
pub fn Decimal::epsilon_contextual(@arithmetic.ArithmeticContext) -> Self
pub fn Decimal::min_normal_contextual(@arithmetic.ArithmeticContext) -> Self
pub fn Decimal::max_finite_contextual(@arithmetic.ArithmeticContext) -> Self
pub fn Decimal::classify_contextual(Self) -> @arithmetic.FpClass
pub impl @arithmetic.NumericFormatContextual for Decimal
```

`epsilon_contextual` is $\operatorname{next\_plus}(1) - 1 = 10^{1-p}$,
`min_normal_contextual` is $10^{e_{\min}}$ and `max_finite_contextual` is
$(10^p - 1) \cdot 10^{e_{\max} - p + 1}$.

### `Decimal::parse_checked`, `Decimal::sqrt_checked`, `Decimal::pow_int_checked`, `Decimal::pow_nat_checked`

These implement the checked traits of `Luna-Flow/arithmetic`: they return
`Result` instead of flags.

```mbti
pub fn Decimal::parse_checked(String, @arithmetic.ArithmeticContext) -> Result[Self, @arithmetic.ArithmeticError]
pub fn Decimal::sqrt_checked(Self, @arithmetic.ArithmeticContext) -> Result[Self, @arithmetic.ArithmeticError]
pub fn Decimal::pow_int_checked(Self, Int, @arithmetic.ArithmeticContext) -> Result[Self, @arithmetic.ArithmeticError]
pub fn Decimal::pow_nat_checked(Self, UInt, @arithmetic.ArithmeticContext) -> Result[Self, @arithmetic.ArithmeticError]
pub impl @arithmetic.ParseChecked for Decimal
pub impl @arithmetic.SqrtChecked for Decimal
pub impl @arithmetic.PowIntChecked for Decimal
pub impl @arithmetic.PowNatChecked for Decimal
pub impl @arithmetic.DivChecked for Decimal
```

`parse_checked` converts the arithmetic context to an engine context and
converts the string under it; the context's precision, rounding direction,
exponent bounds and clamp setting apply. It returns the converted value;
conditions such as overflow are available from [`to_number`](#to_number). Invalid
syntax returns `Err(parse_error)`. `sqrt_checked`
returns `Err(domain_error)` for negative operands. `pow_int_checked` and
`pow_nat_checked` call the power operation with the integer exponent converted
exactly (with at least ten digits, which hold every accepted exponent), so at
precision 7 `(-1).pow_int_checked(12345679, ctx)` is `-1`; they return
`Err(division_by_zero)` for a zero base with a negative exponent,
`Err(unsupported)` with an `invalid context:` message when `power` raises
`invalid_context` (a positive exponent above 999,999,999 under a context
without exponent bounds within $\pm 999\,999$, as in the decTest rows
`powx1183` and `powx1184`), `Err(domain_error)` for other invalid results,
and `pow_nat_checked` returns `Err(unsupported)` for exponents above
999,999,999. `DivChecked::div_checked`
divides under the given context and returns `Err(division_by_zero)` for a zero
divisor and `Err(domain_error)` for an invalid division.

### `FromNat`, `FromInteger` and the `luna-generic` algebra traits

These let generic algebra code use `Decimal`.

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

`FromNat::from_natural` and `FromInteger::from_integer` are the canonical maps out of the naturals
and the integers; `Decimal` has no inherent method of those names, call the trait method, or `Decimal::from_bigint(n).normalized()`, which is what they compute. They convert with `Decimal::from_bigint` (34 digits, trailing
zeros removed), so they are exact only for integers of at most 34 significant
digits. To convert another Luna-Flow integer type, pick its representative with
`Integral::normalize` first, or use `lift_to`. `Zero::zero` and
`One::one` are `Decimal::zero()` and `Decimal::one()`. The ring structure uses
the context-free operators; because `+` rounds to the operand precision, the
ring laws hold exactly only while sums stay within that precision.

### `Decimal::to_repr` and the `@def.Floating`, `Show` and `Debug` implementations

`Decimal` implements the floating vocabulary of the `def` package, `Show` (see
[`Decimal::to_string`](#decimalto_string-decimaloutput)) and `Debug`.

```mbti
pub impl @def.Floating for Decimal
pub fn Decimal::to_repr(Self) -> @debug.Repr
```

The `Floating` methods are `classify`, `signum`, `precision`,
`with_precision` and `normalized`, documented above. `to_repr` is the
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
