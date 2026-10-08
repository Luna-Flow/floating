# decimal_gda API

`decimal_gda` implements the General Decimal Arithmetic Specification (GDA,
version 1.70) by M. F. Cowlishaw. Its `Decimal` is a sign, an arbitrary-length
decimal coefficient and a decimal exponent; its `GdaContext` carries the
precision, rounding mode, exponent limits, clamping, the extended/subset
switch, the sticky status and the enabled traps; and every GDA operation is a
pure function that returns a `GdaOutcome` holding the defined result, the next
context and the conditions it raised. The [tutorial](../tutorial/decimal_gda.md)
shows the package in use; the [design page](../design/decimal_gda.md) derives
the rules stated here.

The package does not depend on the IEEE 754 package `decimal`. Besides the GDA
surface it publishes a lower, status-free layer — `DecimalContext`,
`DecimalFlags` and the `Decimal::*_ctx` methods — on which the GDA functions
are built, plus adapters to the `Luna-Flow/arithmetic` and
`Luna-Flow/luna-generic` traits.

Throughout, a finite value is written $(-1)^s \cdot c \cdot 10^{e}$ with
coefficient $c \ge 0$ and exponent $e$; its *adjusted exponent* is
$\hat e = e + \operatorname{digits}(c) - 1$, the exponent of its leading digit.
For a context with precision $p$, $E_{\mathrm{tiny}} = e_{\min} - p + 1$ is the
smallest exponent a result may have.

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

`precision` (default 34, clamped to at least 1) is only the stored precision
attribute.

### `Decimal::inf`, `Decimal::nan`, `Decimal::quiet_nan`, `Decimal::signaling_nan`

These build the special values.

```mbti
pub fn Decimal::inf(@def.Sign, precision? : Int) -> Self
pub fn Decimal::nan(precision? : Int) -> Self
pub fn Decimal::quiet_nan(payload? : @bigint.BigInt, negative? : Bool, precision? : Int) -> Self
pub fn Decimal::signaling_nan(payload? : @bigint.BigInt, negative? : Bool, precision? : Int) -> Self
```

`inf(Negative)` is $-\infty$; any other `Sign` gives $+\infty$. `nan()` is a
positive quiet NaN with payload 0. The payload is stored as its absolute
value. A signaling NaN raises `InvalidOperation` when an arithmetic operation
consumes it and is replaced by the quiet NaN with the same sign and payload.

### `Decimal::make`

`make(c, e, p)` returns $c \cdot 10^{e}$ rounded to `p` significant digits and
with trailing zeros removed.

```mbti
pub fn Decimal::make(@bigint.BigInt, Int, Int, mode? : @arithmetic.RoundingMode) -> Self
```

The sign comes from the sign of `c`. Rounding uses `mode` (default
`ToNearestEven`). Because trailing zeros are removed, `make(1200, 0, 34)` is
`1.2E+3`; build from a string when the quantum matters. No flags are reported.

### `Decimal::from_int`, `Decimal::from_bigint`, `Decimal::from_double`, `Decimal::from_float`, `Decimal::from_bin_float`

These convert binary values to decimal, round half to even to `precision`
digits and remove trailing zeros.

```mbti
pub fn Decimal::from_int(Int, precision? : Int) -> Self
pub fn Decimal::from_bigint(@bigint.BigInt, precision? : Int) -> Self
pub fn Decimal::from_double(Double, precision? : Int) -> Self
pub fn Decimal::from_float(Float, precision? : Int) -> Self
pub fn Decimal::from_bin_float(@bin_float.BinFloat, precision? : Int) -> Self
```

`precision` defaults to 34 (for `from_bin_float`, to the precision of the
argument). A binary float $m \cdot 2^{k}$ with $k < 0$ is first written exactly
as $m 5^{-k} \cdot 10^{k}$, so the conversion is exact whenever the result fits
in `precision` digits; for example `from_double(0.1)` is the 34-digit
rounding of the binary64 value nearest to $0.1$. NaNs become the quiet NaN
(sign kept by `from_double`), infinities keep their sign, zeros keep their
sign (`from_bin_float` returns $+0$). `from_int(100)` is `1E+2`.

### `Decimal::to_bin_float`

`to_bin_float` rounds the value to a binary `BinFloat` with `precision`
significant bits.

```mbti
pub fn Decimal::to_bin_float(Self, precision? : Int, mode? : @arithmetic.RoundingMode) -> @bin_float.BinFloat
```

`precision` defaults to the stored precision attribute and `mode` to
`ToNearestEven`. With `TowardNegative` and `TowardPositive` the two results
enclose the decimal value; the elementary functions use exactly this to build
their certified input intervals. Zeros map to $+0$, NaNs to the binary NaN.

### `Decimal::parse`, `Decimal::from_string`

These read a GDA numeric string without a GDA context.

```mbti
pub fn Decimal::parse(String, precision? : Int) -> Result[Self, @arithmetic.ArithmeticError]
pub fn Decimal::from_string(String, precision? : Int) -> Self?
```

Accepted syntax is the GDA numeric-string grammar: an optional sign, digits
with an optional decimal point, an optional exponent `E±n`, or
`Infinity`/`Inf`/`NaN`/`sNaN` (case-insensitive) with an optional decimal NaN
payload. The exponent is kept exactly, so `from_string("2.50")` has exponent
$-2$. A literal with more than `precision` (default 34) significant digits is
rounded half to even and its trailing zeros are removed. A malformed literal
gives `Err(parse_error)` or `None`. Use the package function
[`parse`](#parse) when the exponent limits, flags, status or traps of a context
must apply.

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

These convert a numeric *string* under a `DecimalContext` and print it with
GDA to-scientific-string or to-engineering-string.

```mbti
pub fn Decimal::to_sci_string(String, DecimalContext) -> (String, DecimalFlags)
pub fn Decimal::to_eng_string(String, DecimalContext) -> (String, DecimalFlags)
```

The string is converted exactly as by
[`Decimal::from_string_ctx`](#decimalfrom_string_ctx) (rounding to the context,
with the conversion flags returned), then formatted. Engineering notation uses
an exponent that is a multiple of three (`123E+5` prints as `12.3E+6`). Special
values print as `Infinity`, `-Infinity`, `NaN`, `sNaN` with payload.

### `Decimal::from_string_ctx`

`from_string_ctx` is the GDA *to-number* conversion under a status-free
context.

```mbti
pub fn Decimal::from_string_ctx(String, DecimalContext) -> (Self, DecimalFlags)
```

The literal is rounded to the context precision, checked against the exponent
range (overflow, subnormal, underflow, clamping) and returned with its flags.
Malformed input returns a quiet NaN with `conversion_syntax`. In a
non-extended context, infinities and NaNs are themselves a conversion-syntax
error, and zeros lose their sign and exponent.

```moonbit
///|
test "Decimal construction and printing" {
  inspect(@decimal_gda.Decimal::from_string("2.50").unwrap(), content="2.50")
  inspect(@decimal_gda.Decimal::from_int(100), content="1E+2")
  inspect(@decimal_gda.Decimal::make(12345N, -2, 3), content="123")
  inspect(@decimal_gda.Decimal::from_double(0.5), content="0.5")
  inspect(@decimal_gda.Decimal::signaling_nan(payload=7N), content="snan7")
  inspect(@decimal_gda.Decimal::from_string("1.2.3") is None, content="true")
  let ctx = @decimal_gda.DecimalContext::new(precision=3)
  let (v, flags) = @decimal_gda.Decimal::from_string_ctx("1.2345", ctx)
  inspect(v, content="1.23")
  inspect(flags.inexact, content="true")
  let (sci, _) = @decimal_gda.Decimal::to_sci_string("-sNaN12", ctx)
  inspect(sci, content="-sNaN12")
}
```

## Observing a value

### `Decimal::classify`, `Decimal::sign`, `Decimal::precision`

These report the class, the numeric sign and the stored precision attribute.

```mbti
pub fn Decimal::classify(Self) -> @arithmetic.FpClass
pub fn Decimal::sign(Self) -> @def.Sign
pub fn Decimal::precision(Self) -> Int
```

`classify` returns `Finite`, `Infinity` or `NaN`. `sign` returns `Zero` for
zeros of either sign and for NaNs, and `Positive`/`Negative` otherwise; use
`is_negative` to read the sign bit.

### `Decimal::coefficient`, `Decimal::magnitude`, `Decimal::exponent10`, `Decimal::quantum`

These expose the stored representation $(c, e)$.

```mbti
pub fn Decimal::coefficient(Self) -> @bigint.BigInt
pub fn Decimal::magnitude(Self) -> @bigint.BigInt
pub fn Decimal::exponent10(Self) -> Int
pub fn Decimal::quantum(Self) -> Int
```

`coefficient` and `magnitude` both return $c \ge 0$ (the payload for a NaN, 0
for an infinity). `exponent10` and `quantum` both return $e$ (0 for special
values).

### `Decimal::is_finite`, `Decimal::is_infinite`, `Decimal::is_nan`, `Decimal::is_zero`, `Decimal::is_negative`, `Decimal::is_signed`, `Decimal::is_negative_zero`

These are the class and sign predicates.

```mbti
pub fn Decimal::is_finite(Self) -> Bool
pub fn Decimal::is_infinite(Self) -> Bool
pub fn Decimal::is_nan(Self) -> Bool
pub fn Decimal::is_zero(Self) -> Bool
pub fn Decimal::is_negative(Self) -> Bool
pub fn Decimal::is_signed(Self) -> Bool
pub fn Decimal::is_negative_zero(Self) -> Bool
```

`is_negative` and `is_signed` are the same: they read the sign bit, so they are
true for $-0$, $-\infty$ and negative NaNs. `is_zero` is true for finite zeros
of any exponent.

### `Decimal::is_quiet_nan`, `Decimal::is_qnan`, `Decimal::is_signaling_nan`, `Decimal::is_snan`

These distinguish quiet from signaling NaNs; each pair are aliases.

```mbti
pub fn Decimal::is_quiet_nan(Self) -> Bool
pub fn Decimal::is_qnan(Self) -> Bool
pub fn Decimal::is_signaling_nan(Self) -> Bool
pub fn Decimal::is_snan(Self) -> Bool
```

### `Decimal::is_canonical`

`is_canonical` always returns `true`: every `Decimal` value is canonical (only
interchange encodings can be non-canonical, see
[`GdaInterchange::is_canonical`](#gdainterchangecanonical-gdainterchangeis_canonical)).

```mbti
pub fn Decimal::is_canonical(Self) -> Bool
```

### `Decimal::nan_payload`, `Decimal::get_payload`, `Decimal::set_payload`, `Decimal::set_payload_signaling`

These read and replace a NaN payload.

```mbti
pub fn Decimal::nan_payload(Self) -> @bigint.BigInt
pub fn Decimal::get_payload(Self) -> @bigint.BigInt
pub fn Decimal::set_payload(Self, @bigint.BigInt) -> Self
pub fn Decimal::set_payload_signaling(Self, @bigint.BigInt) -> Self
```

`nan_payload` and `get_payload` return the payload of a NaN and 0 for any
other value. `set_payload` turns a NaN into a quiet NaN with the given payload
and the same sign; `set_payload_signaling` makes it signaling. Both return
non-NaN values unchanged.

### `Decimal::is_normal`, `Decimal::is_subnormal`, `Decimal::class_name`

These classify a value against the exponent range of a `DecimalContext`.

```mbti
pub fn Decimal::is_normal(Self, DecimalContext) -> Bool
pub fn Decimal::is_subnormal(Self, DecimalContext) -> Bool
pub fn Decimal::class_name(Self, DecimalContext) -> String
```

A nonzero finite value is normal when $\hat e \ge e_{\min}$ and subnormal when
$\hat e < e_{\min}$; zeros, infinities and NaNs are neither. `class_name`
returns the GDA class string: `sNaN`, `NaN`, `-Infinity`, `+Infinity`,
`-Zero`, `+Zero`, `-Subnormal`, `+Subnormal`, `-Normal` or `+Normal`. The GDA
forms taking a `GdaContext` are the package functions
[`class_name`, `is_normal`, `is_subnormal`](#class_name-is_normal-is_subnormal-same_quantum).

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
attribute. None of them report flags.

### `Decimal::same_quantum`

`same_quantum` tests whether two values have the same exponent.

```mbti
pub fn Decimal::same_quantum(Self, Self) -> Bool
```

It is true for two finite values with equal exponents, for two infinities and
for two NaNs, and false otherwise.

## The GDA context

### `GdaContext`

`GdaContext` is the immutable GDA context: arithmetic policy plus sticky status
plus enabled traps.

```mbti
pub struct GdaContext {
  // private fields
}
```

The policy is precision $p \ge 1$, a `GdaRoundingMode`, $e_{\min} \le e_{\max}$,
`clamp` and `extended`. The status is a `GdaFlags` value that operations only
ever enlarge; the traps are a `GdaTrapSet`. Neither status nor traps influence
the numerical result of an operation: they only decide the next context and
whether the outcome is `Completed` or `Trapped`.

### `GdaContext::new`, `GdaContext::try_new`

These build a context with an empty status.

```mbti
pub fn GdaContext::new(precision? : Int, rounding? : GdaRoundingMode, e_min? : Int, e_max? : Int, clamp? : Bool, extended? : Bool, traps? : GdaTrapSet) -> Self
pub fn GdaContext::try_new(precision? : Int, rounding? : GdaRoundingMode, e_min? : Int, e_max? : Int, clamp? : Bool, extended? : Bool, traps? : GdaTrapSet) -> Result[Self, @arithmetic.ArithmeticError]
```

Defaults: `precision=34`, `rounding=HalfEven`, `e_min=-999_999_999`,
`e_max=999_999_999`, `clamp=false`, `extended=true`, no traps. `new` aborts
when `precision <= 0` or `e_min > e_max`; `try_new` returns
`Err(domain_error)` instead. `clamp=true` limits exponents to
$e_{\max} - p + 1$ as the interchange formats do. `extended=false` selects GDA
*subset* arithmetic: operands longer than $p$ digits are rounded first
(raising `LostDigits` when that is inexact), special values cannot be parsed,
zeros and some results are normalized, and `fma` is invalid.

> [!NOTE]
> `exp`, `ln`, `log10` and `power` with a non-integer exponent require
> $p \le 999\,999$, $e_{\max} \le 999\,999$ and $e_{\min} \ge -999\,999$, as the
> GDA specification does for its mathematical functions. With the default
> exponent range they return NaN and raise `InvalidContext`.

### `GdaContext::basic`, `GdaContext::default`, `GdaContext::decimal32`, `GdaContext::decimal64`, `GdaContext::decimal128`

These return the standard contexts.

```mbti
pub fn GdaContext::basic() -> Self
pub fn GdaContext::default() -> Self
pub fn GdaContext::decimal32() -> Self
pub fn GdaContext::decimal64() -> Self
pub fn GdaContext::decimal128() -> Self
```

| Context | $p$ | rounding | $e_{\min}$ | $e_{\max}$ | clamp | extended | traps |
| --- | ---: | --- | ---: | ---: | --- | --- | --- |
| `basic`, `default` | 9 | `HalfUp` | $-999\,999\,999$ | $999\,999\,999$ | no | no | DivisionByZero, InvalidOperation, Overflow, Underflow, Clamped |
| `decimal32` | 7 | `HalfEven` | $-95$ | $96$ | yes | yes | none |
| `decimal64` | 16 | `HalfEven` | $-383$ | $384$ | yes | yes | none |
| `decimal128` | 34 | `HalfEven` | $-6143$ | $6144$ | yes | yes | none |

`basic` is the GDA basic default context; `default` is the same value. The
values are created once and shared.

### `context`, `decimal32_context`, `decimal64_context`, `decimal128_context`

These package functions are shorthands for `GdaContext::new` (without a trap
argument) and the three interchange presets.

```mbti
pub fn context(precision? : Int, rounding? : GdaRoundingMode, e_min? : Int, e_max? : Int, clamp? : Bool, extended? : Bool) -> GdaContext
pub fn decimal32_context() -> GdaContext
pub fn decimal64_context() -> GdaContext
pub fn decimal128_context() -> GdaContext
```

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

### `GdaContext::status`, `GdaContext::traps`

These read the sticky status and the enabled traps.

```mbti
pub fn GdaContext::status(Self) -> GdaFlags
pub fn GdaContext::traps(Self) -> GdaTrapSet
```

### `GdaContext::trap`, `GdaContext::with_traps`, `GdaContext::clear_status`, `GdaContext::reset`

These return a new context with changed traps or status; the receiver is not
modified.

```mbti
pub fn GdaContext::trap(Self, GdaSignal, enabled? : Bool) -> Self
pub fn GdaContext::with_traps(Self, GdaTrapSet) -> Self
pub fn GdaContext::clear_status(Self) -> Self
pub fn GdaContext::reset(Self) -> Self
```

`trap(s)` enables (or with `enabled=false` disables) one trap; `with_traps`
replaces the whole set. `clear_status` empties the status and keeps the traps;
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
pub fn GdaRoundingMode::equal(Self, Self) -> Bool
pub fn GdaRoundingMode::not_equal(Self, Self) -> Bool
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

`GdaSignal` names the thirteen GDA conditions.

```mbti
pub(all) enum GdaSignal {
  ConversionSyntax
  DivisionByZero
  DivisionImpossible
  DivisionUndefined
  InvalidContext
  InvalidOperation
  Overflow
  Underflow
  Subnormal
  Inexact
  Rounded
  Clamped
  LostDigits
}
pub fn GdaSignal::equal(Self, Self) -> Bool
pub fn GdaSignal::not_equal(Self, Self) -> Bool
```

The GDA signals are `Clamped`, `DivisionByZero`, `Inexact`,
`InvalidOperation`, `Overflow`, `Rounded`, `Subnormal` and `Underflow`.
`ConversionSyntax`, `DivisionImpossible`, `DivisionUndefined` and
`InvalidContext` are conditions that the specification reports through the
`InvalidOperation` signal; the package keeps them as separate flags and traps
so you can tell them apart. `LostDigits` is raised only in subset arithmetic.

### `GdaFlags`

`GdaFlags` is a set of conditions, used both for the conditions raised by one
operation and for the sticky status of a context.

```mbti
pub struct GdaFlags {
  conversion_syntax : Bool
  division_by_zero : Bool
  division_impossible : Bool
  division_undefined : Bool
  invalid_context : Bool
  invalid_operation : Bool
  overflow : Bool
  underflow : Bool
  subnormal : Bool
  inexact : Bool
  rounded : Bool
  clamped : Bool
  lost_digits : Bool
} derive(Eq)
pub fn GdaFlags::none() -> Self
pub fn GdaFlags::contains(Self, GdaSignal) -> Bool
pub fn GdaFlags::combine(Self, Self) -> Self
pub fn GdaFlags::equal(Self, Self) -> Bool
pub fn GdaFlags::not_equal(Self, Self) -> Bool
```

The fields are read-only; build sets with `none` and `combine` (field-wise
union). `contains(s)` reads the field for `s`, except that
`contains(InvalidOperation)` is true when any of `invalid_operation`,
`conversion_syntax`, `division_impossible`, `division_undefined` or
`invalid_context` is set.

### `GdaTrapSet`

`GdaTrapSet` is the set of enabled traps.

```mbti
pub struct GdaTrapSet {
  conversion_syntax : Bool
  division_by_zero : Bool
  division_impossible : Bool
  division_undefined : Bool
  invalid_context : Bool
  invalid_operation : Bool
  overflow : Bool
  underflow : Bool
  subnormal : Bool
  inexact : Bool
  rounded : Bool
  clamped : Bool
  lost_digits : Bool
} derive(Eq)
pub fn GdaTrapSet::none() -> Self
pub fn GdaTrapSet::with_signal(Self, GdaSignal, enabled? : Bool) -> Self
pub fn GdaTrapSet::contains(Self, GdaSignal) -> Bool
pub fn GdaTrapSet::equal(Self, Self) -> Bool
pub fn GdaTrapSet::not_equal(Self, Self) -> Bool
```

`with_signal(s)` enables one trap (or disables it with `enabled=false`);
`contains(s)` reads exactly the field for `s`.

### `GdaOutcome`

`GdaOutcome[T]` is the result of every GDA operation.

```mbti
pub(all) enum GdaOutcome[T] {
  Completed(T, GdaContext, GdaFlags)
  Trapped(GdaSignal, T, GdaContext, GdaFlags)
}
pub fn[T] GdaOutcome::value(Self[T]) -> T
pub fn[T] GdaOutcome::next_context(Self[T]) -> GdaContext
pub fn[T] GdaOutcome::raised(Self[T]) -> GdaFlags
```

Both variants carry the GDA-defined result, the next context and the
conditions raised by this operation; `Trapped` also names the trap that fired.
`value`, `next_context` and `raised` read the common fields without matching.

### Trap selection

Every GDA function finishes the same way. Let $R$ be the conditions the
operation raised and $C$ the input context.

1. If $R$ is empty the outcome is `Completed(v, C, none)`: the very same
   context comes back.
2. Otherwise the next context is $C$ with status
   $C.\mathrm{status} \cup R$, where the `invalid_operation` flag is also set
   whenever $R$ contains one of the four detailed invalid conditions.
3. The trapped signal is the first $s$ in the order below with
   `raised.contains(s)` and `traps.contains(s)`: InvalidOperation,
   DivisionByZero, DivisionUndefined, DivisionImpossible, InvalidContext,
   ConversionSyntax, Overflow, Underflow, Subnormal, Inexact, Rounded,
   Clamped, LostDigits. If there is one the outcome is `Trapped(s, v, C', R)`,
   otherwise `Completed(v, C', R)`.

Because `contains(InvalidOperation)` covers the detailed invalid conditions,
an `InvalidOperation` trap catches all of them, and it wins over a trap on the
detailed condition itself.

```moonbit
///|
test "GDA context, status and traps" {
  let ctx = @decimal_gda.GdaContext::decimal64()
    .trap(DivisionUndefined)
    .trap(InvalidOperation)
  let zero = @decimal_gda.Decimal::zero()
  let out = @decimal_gda.divide(zero, zero, ctx) // 0/0
  inspect(out.value(), content="nan")
  inspect(out.raised().division_undefined, content="true")
  inspect(out.raised().contains(InvalidOperation), content="true")
  match out {
    @decimal_gda.GdaOutcome::Trapped(signal, _, _, _) =>
      inspect(signal == InvalidOperation, content="true")
    @decimal_gda.GdaOutcome::Completed(_, _, _) => fail("expected a trap")
  }
  inspect(out.next_context().status().invalid_operation, content="true")
  inspect(ctx.status() == @decimal_gda.GdaFlags::none(), content="true")
  inspect(ctx.reset().traps() == @decimal_gda.GdaTrapSet::none(), content="true")
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

### `parse`

`parse` is the GDA to-number conversion of a string.

```mbti
pub fn parse(String, GdaContext) -> GdaOutcome[Decimal]
```

The literal keeps its exponent unless it must be rounded to the precision or
clamped to the exponent range. Malformed text gives a quiet NaN with
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

Ideal exponent: that of the operand. `plus`, `minus` and `abs` return a zero
result as $+0$; `apply` keeps the sign of a zero and does not round subset
operands first.

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
and the addend. An exact zero sum is $+0$, or $-0$ when both operands are
negative or the mode is `Floor`. Special cases: $\infty - \infty$,
$0 \times \infty$ and $\infty / \infty$ are invalid; $x / 0$ is $\pm\infty$
with `DivisionByZero`; $0 / 0$ is NaN with `DivisionUndefined`;
$x / \infty$ is a zero with exponent $E_{\mathrm{tiny}}$ and `Clamped`. `fma`
is invalid in a subset context.

> [!WARNING]
> On the current branch `divide` can misround in the half modes when the
> quotient has a non-terminating expansion whose discarded part lies within a
> very small distance of one half unit: at precision 1, `divide(1, 2222)`
> returns `0.0004` where GDA requires `0.0005`. See the
> [design page](../design/decimal_gda.md#division) for the cause.

### `divide_integer`, `remainder`, `remainder_near`

These divide to an integer quotient.

```mbti
pub fn divide_integer(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]
pub fn remainder(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]
pub fn remainder_near(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]
```

`divide_integer` returns $q = \operatorname{trunc}(x / y)$ with exponent 0;
`remainder` returns $x - q y$ (the sign of $x$); `remainder_near` returns
$x - n y$ where $n$ is $x / y$ rounded to the nearest integer, ties to even.
The remainder has ideal exponent $\min(e_x, e_y)$. When $q$ (or $n$) needs
more than $p$ digits the result is NaN with `DivisionImpossible`. A zero
divisor gives `DivisionByZero` (`divide_integer` of a nonzero number) or
`DivisionUndefined` ($0 / 0$); a zero divisor or an infinite dividend makes
both remainders invalid; a finite dividend with an infinite divisor is its
own remainder.

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
one operand is infinite. Two infinities give the infinity. A quantized result
never raises `Underflow`.

### `to_integral_exact`, `to_integral_value`

These round to an integer with the context rounding mode.

```mbti
pub fn to_integral_exact(Decimal, GdaContext) -> GdaOutcome[Decimal]
pub fn to_integral_value(Decimal, GdaContext) -> GdaOutcome[Decimal]
```

A value with negative exponent is quantized to exponent 0; `to_integral_exact`
raises `Inexact` and `Rounded` when digits are dropped and
`to_integral_value` never does. A value with exponent $\ge 0$ is passed
through `apply`, so it is rounded to the context precision if it is longer
than $p$ digits.[^integral]

[^integral]: The GDA reference implementation returns such operands unchanged;
    for example, at precision 3 it maps `12345` to `12345`, while this package
    returns `1.23E+4` with `Inexact`. The pinned test suite has no such row.

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
integer $k$. Every other finite result is inexact with $p$ digits. Domain:
the square root and logarithms of a negative number are invalid,
$\ln 0 = \log_{10} 0 = -\infty$, $\exp(-\infty) = 0$, and $+\infty$ maps to
$+\infty$ for all four. `exp`, `ln` and `log10` raise `InvalidContext` unless
$p$, $e_{\max}$ and $-e_{\min}$ are at most 999,999. If the certified
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
result is invalid. The result is then checked for overflow, subnormality and
clamping. `logb(x)` returns $\hat e$ as an integer; `logb(0)` is $-\infty$
with `DivisionByZero` and `logb(±∞)` is $+\infty$.

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
order to the absolute values. The total orders never raise flags.

### `max`, `min`, `max_mag`, `min_mag`

These are the GDA max and min operations, on values or on magnitudes.

```mbti
pub fn max(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]
pub fn min(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]
pub fn max_mag(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]
pub fn min_mag(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]
```

A single quiet NaN is ignored in favour of the number; two quiet NaNs give
the first; a signaling NaN gives a quiet NaN with `InvalidOperation`. Values
that compare equal are separated by the total order (so `max(2.5, 2.50)` is
`2.5`). The selected operand is then rounded to the context as by `plus`.

### `class_name`, `is_normal`, `is_subnormal`, `same_quantum`

These classify values under a context; they never raise conditions, so they
always return `Completed` with the input context.

```mbti
pub fn class_name(Decimal, GdaContext) -> GdaOutcome[String]
pub fn is_normal(Decimal, GdaContext) -> GdaOutcome[Bool]
pub fn is_subnormal(Decimal, GdaContext) -> GdaOutcome[Bool]
pub fn same_quantum(Decimal, Decimal, GdaContext) -> GdaOutcome[Bool]
```

They wrap [`Decimal::class_name`](#decimalis_normal-decimalis_subnormal-decimalclass_name),
`Decimal::is_normal`, `Decimal::is_subnormal` and
[`Decimal::same_quantum`](#decimalsame_quantum).

```moonbit
///|
test "GDA operation sampler" {
  let ctx = @decimal_gda.GdaContext::decimal64()
  let d = (s : String) => @decimal_gda.Decimal::from_string(s).unwrap()
  inspect(@decimal_gda.divide_integer(d("17"), d("5"), ctx).value(), content="3")
  inspect(@decimal_gda.remainder(d("-17"), d("5"), ctx).value(), content="-2")
  inspect(@decimal_gda.remainder_near(d("17"), d("5"), ctx).value(), content="2")
  inspect(@decimal_gda.fma(d("1.5"), d("2"), d("0.25"), ctx).value(), content="3.25")
  inspect(@decimal_gda.to_integral_exact(d("2.5"), ctx).value(), content="2")
  inspect(@decimal_gda.rescale(d("1.2345"), d("-2"), ctx).value(), content="1.23")
  inspect(@decimal_gda.reduce(d("120.00"), ctx).value(), content="1.2E+2")
  inspect(@decimal_gda.scaleb(d("1.5"), d("3"), ctx).value(), content="1.5E+3")
  inspect(@decimal_gda.logb(d("0.00123"), ctx).value(), content="-3")
  inspect(@decimal_gda.next_plus(d("1"), ctx).value(), content="1.000000000000001")
  inspect(@decimal_gda.logical_xor(d("1100"), d("1010"), ctx).value(), content="110")
  inspect(@decimal_gda.shift(d("12345"), d("2"), ctx).value(), content="1234500")
  inspect(@decimal_gda.rotate(d("12345"), d("-1"), @decimal_gda.context(precision=5)).value(), content="51234")
  inspect(@decimal_gda.power(d("2"), d("-3"), ctx).value(), content="0.125")
  inspect(@decimal_gda.max(d("2.5"), d("2.50"), ctx).value(), content="2.5")
  inspect(@decimal_gda.class_name(d("-0"), ctx).value(), content="-Zero")
  let wide = @decimal_gda.context() // exponent range ±999,999,999
  inspect(@decimal_gda.exp(d("1"), wide).raised().invalid_context, content="true")
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

### `Decimal::min`, `Decimal::max`, `Decimal::clamp`, `Decimal::clamp_checked`

These select between values without rounding.

```mbti
pub fn Decimal::min(Self, Self) -> Self
pub fn Decimal::max(Self, Self) -> Self
pub fn Decimal::clamp(Self, min~ : Self, max~ : Self) -> Self
pub fn Decimal::clamp_checked(Self, min~ : Self, max~ : Self) -> Result[Self, @arithmetic.ArithmeticError]
```

`min` and `max` return the other operand when one is a quiet NaN, the first
NaN (quieted) when a signaling NaN is involved or both are NaN, and the
receiver when the two compare equal. `clamp` returns `min` or `max` when the
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

Let $P$ be the larger precision attribute of the operands. `+`, `-` and `/`
round half to even to $P$ digits and then remove trailing zeros; `*` returns
the exact product (it is never rounded) with attribute $P$. Special values
follow IEEE rules without signals: NaN operands give a quiet NaN,
$\infty - \infty$, $0 \times \infty$, $0/0$ and $\infty/\infty$ give NaN,
$x/0$ gives a signed infinity and $x/\infty$ gives $+0$. `neg` is
[`Decimal::neg`](#decimalneg-decimalabs-decimalcopy-decimalcopy_abs-decimalcopy_negate-decimalcopy_sign).

### `Decimal::div_checked`, `Decimal::sqrt`

These are checked conveniences that use a default context of the larger
operand precision.

```mbti
pub fn Decimal::div_checked(Self, Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn Decimal::sqrt(Self) -> Result[Self, @arithmetic.ArithmeticError]
```

`div_checked` divides with `DecimalContext::new(precision=P)` and returns
`Err(division_by_zero)` for a zero divisor and `Err(domain_error)` for an
invalid division. `sqrt` takes the square root at the value's own precision
attribute and returns `Err(domain_error)` for negative operands.

```moonbit
///|
test "context-free ordering and operators" {
  let d = (s : String) => @decimal_gda.Decimal::from_string(s).unwrap()
  inspect(d("2.50") == d("2.5"), content="true")
  inspect(d("2.50").compare_total(d("2.5")), content="-1")
  inspect(@decimal_gda.Decimal::nan() == @decimal_gda.Decimal::nan(), content="true")
  inspect(d("1").compare(@decimal_gda.Decimal::nan()), content="-1")
  inspect(d("1").compare_checked(@decimal_gda.Decimal::nan()) is Err(_), content="true")
  inspect(d("1.10") + d("2.20"), content="3.3")
  inspect(d("1.10") * d("2.20"), content="2.4200")
  inspect(d("1") / d("3"), content="0.3333333333333333333333333333333333")
  inspect(d("5").clamp(min=d("0"), max=d("3")), content="3")
}
```

## The status-free context layer

The GDA functions are thin wrappers over the methods below: each converts the
`GdaContext` policy to a `DecimalContext`, calls one method, and feeds the
returned `DecimalFlags` to [trap selection](#trap-selection). You can call the
layer directly when you want per-operation flags without sticky status, or the
IEEE-style extras it adds (IEEE 754-2019 `minimum`/`maximum`, a choice of
tininess detection). The [`decimal`](decimal.md) package, not this layer, is
the supported IEEE 754 implementation.

### `DecimalContext`

`DecimalContext` is a status-free context: precision, two views of the
rounding mode, exponent range, clamp, extended and tininess detection.

```mbti
pub struct DecimalContext {
  // private fields
} derive(Eq)
pub fn DecimalContext::new(precision? : Int, rounding? : @arithmetic.RoundingMode, decimal_rounding? : DecimalRoundingMode, e_min? : Int, e_max? : Int, clamp? : Bool, extended? : Bool, tininess? : DecimalTininessDetection) -> Self
pub fn DecimalContext::try_new(precision? : Int, rounding? : @arithmetic.RoundingMode, decimal_rounding? : DecimalRoundingMode, e_min? : Int, e_max? : Int, clamp? : Bool, extended? : Bool, tininess? : DecimalTininessDetection) -> Result[Self, @arithmetic.ArithmeticError]
pub fn DecimalContext::exact() -> Self
pub fn DecimalContext::decimal32() -> Self
pub fn DecimalContext::decimal64() -> Self
pub fn DecimalContext::decimal128() -> Self
pub fn DecimalContext::from_arithmetic_context(@arithmetic.ArithmeticContext) -> Self
pub fn DecimalContext::precision(Self) -> Int
pub fn DecimalContext::rounding(Self) -> @arithmetic.RoundingMode
pub fn DecimalContext::decimal_rounding(Self) -> DecimalRoundingMode
pub fn DecimalContext::with_rounding(Self, @arithmetic.RoundingMode) -> Self
pub fn DecimalContext::e_min(Self) -> Int
pub fn DecimalContext::e_max(Self) -> Int
pub fn DecimalContext::clamp(Self) -> Bool
pub fn DecimalContext::extended(Self) -> Bool
pub fn DecimalContext::tininess(Self) -> DecimalTininessDetection
pub fn DecimalContext::with_tininess(Self, DecimalTininessDetection) -> Self
pub fn DecimalContext::equal(Self, Self) -> Bool
pub fn DecimalContext::not_equal(Self, Self) -> Bool
```

Defaults are those of `GdaContext::new` with `rounding=ToNearestEven` and
`tininess=BeforeRounding`. The rounding actually used is `decimal_rounding`,
which defaults to the translation of `rounding`
(`DecimalRoundingMode::from_arithmetic`); pass `decimal_rounding` to select
`HalfUp`, `HalfDown` or `ZeroFiveUp`. `with_rounding` sets both views. `new`
aborts and `try_new` returns `Err(domain_error)` for `precision <= 0` or
`e_min > e_max`. `exact()` is the unbounded-precision context (precision 0):
results are never rounded. `decimal32`/`64`/`128` match the `GdaContext`
presets. `from_arithmetic_context` copies precision, rounding, the optional
exponent bounds (default $\pm 999\,999\,999$) and clamp. The GDA functions
always use `BeforeRounding` tininess.

### `DecimalRoundingMode`

`DecimalRoundingMode` is the same eight-mode set as `GdaRoundingMode`, for the
status-free layer.

```mbti
pub(all) enum DecimalRoundingMode {
  HalfEven
  HalfUp
  HalfDown
  Down
  Ceiling
  Floor
  Up
  ZeroFiveUp
} derive(Eq)
pub fn DecimalRoundingMode::from_arithmetic(@arithmetic.RoundingMode) -> Self
pub fn DecimalRoundingMode::to_arithmetic(Self) -> @arithmetic.RoundingMode?
pub fn DecimalRoundingMode::equal(Self, Self) -> Bool
pub fn DecimalRoundingMode::not_equal(Self, Self) -> Bool
```

`from_arithmetic` maps `ToNearestEven`, `TowardZero`, `TowardPositive`,
`TowardNegative`, `AwayFromZero` to `HalfEven`, `Down`, `Ceiling`, `Floor`,
`Up`; `to_arithmetic` is its inverse and returns `None` for `HalfUp`,
`HalfDown` and `ZeroFiveUp`.

### `DecimalTininessDetection`

`DecimalTininessDetection` chooses when a result counts as tiny for
`Underflow` and `Subnormal`.

```mbti
pub(all) enum DecimalTininessDetection {
  BeforeRounding
  AfterRounding
} derive(Eq)
pub fn DecimalTininessDetection::equal(Self, Self) -> Bool
pub fn DecimalTininessDetection::not_equal(Self, Self) -> Bool
```

`BeforeRounding` tests the adjusted exponent of the exact result against
$e_{\min}$; `AfterRounding` tests the result rounded to $E_{\mathrm{tiny}}$.

### `DecimalSignal`, `DecimalFlags`

These are the per-operation condition names and flag set of the status-free
layer.

```mbti
pub(all) enum DecimalSignal {
  ConversionSyntax
  DivisionByZero
  DivisionImpossible
  DivisionUndefined
  InvalidContext
  InvalidOperation
  Overflow
  Underflow
  Subnormal
  Inexact
  Rounded
  Clamped
  LostDigits
} derive(Eq)
pub fn DecimalSignal::equal(Self, Self) -> Bool
pub fn DecimalSignal::not_equal(Self, Self) -> Bool

pub struct DecimalFlags {
  inexact : Bool
  rounded : Bool
  lost_digits : Bool
  invalid_operation : Bool
  division_by_zero : Bool
  overflow : Bool
  underflow : Bool
  subnormal : Bool
  clamped : Bool
  conversion_syntax : Bool
  division_impossible : Bool
  division_undefined : Bool
  invalid_context : Bool
} derive(Eq)
pub fn DecimalFlags::new() -> Self
pub fn DecimalFlags::combine(Self, Self) -> Self
pub fn DecimalFlags::contains(Self, DecimalSignal) -> Bool
pub fn DecimalFlags::has_error(Self) -> Bool
pub fn DecimalFlags::equal(Self, Self) -> Bool
pub fn DecimalFlags::not_equal(Self, Self) -> Bool
```

`new` is the empty set and `combine` the union. Unlike `GdaFlags`,
`DecimalFlags::contains(InvalidOperation)` reads only the
`invalid_operation` field (the layer sets it together with
`division_undefined` and `division_impossible`, but not with
`conversion_syntax` or `invalid_context`). `has_error` is true when any of
`invalid_operation`, `division_by_zero`, `division_undefined`,
`division_impossible` or `invalid_context` is set.

### Context methods of `Decimal`

Each method below is the status-free form of the GDA function of the same
name; it rounds with the given `DecimalContext` and returns
`(result, DecimalFlags)`.

```mbti
pub fn Decimal::apply_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::plus_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::minus_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::abs_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::add_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::sub_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::mul_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::div_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::fma_ctx(Self, Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::divide_integer(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::remainder(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::remainder_near(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::quantize(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::rescale(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::to_integral_exact(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::to_integral_value(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::reduce_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::scaleb_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::logb_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::next_plus(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::next_minus(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::next_toward(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::logical_and(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::logical_or(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::logical_xor(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::logical_invert(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::shift_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::rotate_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::compare_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::compare_signal_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::compare_total_ctx(Self, Self, DecimalContext) -> (Int, DecimalFlags)
pub fn Decimal::compare_total_magnitude_ctx(Self, Self, DecimalContext) -> (Int, DecimalFlags)
pub fn Decimal::min_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::max_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::min_mag_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::max_mag_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
```

The results and flags are exactly those the GDA function reports in its
outcome. (The GDA functions `parse`, `add`, `subtract`, `multiply` and `fma`
first try a fast path for small exact integer operands; it is taken only when
it produces the same value with no flags.)

### `Decimal::sqrt_ctx`, `Decimal::exp_ctx`, `Decimal::ln_ctx`, `Decimal::log10_ctx`, `Decimal::power_ctx`

These are the status-free elementary functions.

```mbti
pub fn Decimal::sqrt_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::exp_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::ln_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::log10_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::power_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
```

Unlike the GDA functions `sqrt`, `exp`, `ln` and `log10`, these methods round
with the context's own rounding mode (the GDA functions pass them a half-even
copy of the context). A certification failure gives NaN with
`invalid_operation`.

### `Decimal::try_exp_ctx`, `Decimal::try_ln_ctx`, `Decimal::try_log10_ctx`, `Decimal::try_power_ctx`

These are the same functions with certification failures reported as errors.

```mbti
pub fn Decimal::try_exp_ctx(Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::try_ln_ctx(Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::try_log10_ctx(Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::try_power_ctx(Self, Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
```

When the refinement budget (twelve precision increases) is exhausted without
certifying the rounding, they return `Err(certification_failure(...))` with
the operation name, target precision, final working precision and refinement
count. Domain errors are still reported as NaN plus flags inside `Ok`.

### `Decimal::normalize_ctx`, `Decimal::remainder_ctx`

These are aliases kept for the IEEE vocabulary.

```mbti
pub fn Decimal::normalize_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::remainder_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
```

`normalize_ctx` is `reduce_ctx`; `remainder_ctx` is the IEEE remainder, which
is `remainder_near`.

### `Decimal::minimum_ctx`, `Decimal::maximum_ctx` and their number and magnitude variants

These are the IEEE 754-2019 `minimum`, `maximum`, `minimumNumber`,
`maximumNumber`, `minimumMagnitude`, `maximumMagnitude`,
`minimumMagnitudeNumber` and `maximumMagnitudeNumber` operations.

```mbti
pub fn Decimal::minimum_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::maximum_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::minimum_number_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::maximum_number_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::minimum_magnitude_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::maximum_magnitude_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::minimum_number_magnitude_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::maximum_number_magnitude_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::minimum_mag_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::maximum_mag_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::minimum_number_mag_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::maximum_number_mag_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
```

The plain variants return a quiet NaN when either operand is a NaN; the
`number` variants return the number when exactly one operand is a NaN. A
signaling NaN raises `invalid_operation` in both. Equal values are separated by
the total order. The `*_mag_ctx` names are aliases of the `*_magnitude_ctx`
ones. These are not GDA operations and have no `GdaContext` form.

```moonbit
///|
test "status-free layer" {
  let d = (s : String) => @decimal_gda.Decimal::from_string(s).unwrap()
  let ctx = @decimal_gda.DecimalContext::new(precision=5, decimal_rounding=HalfUp)
  let (q, flags) = d("2").div_ctx(d("3"), ctx)
  inspect(q, content="0.66667")
  inspect(flags.inexact, content="true")
  inspect(flags.contains(Rounded), content="true")
  let floor = @decimal_gda.DecimalContext::new(
    precision=3,
    rounding=TowardNegative,
    e_min=-999_999,
    e_max=999_999,
  )
  inspect(d("1").exp_ctx(floor).0, content="2.71") // context rounding
  let nan = @decimal_gda.Decimal::nan()
  inspect(d("1").maximum_ctx(nan, ctx).0, content="nan")
  inspect(d("1").maximum_number_ctx(nan, ctx).0, content="1")
  let (_, zero_div) = d("0").div_ctx(d("0"), ctx)
  inspect(zero_div.has_error(), content="true")
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
pub fn GdaInterchangeFormat::context(Self) -> DecimalContext
pub fn GdaInterchangeFormat::equal(Self, Self) -> Bool
pub fn GdaInterchangeFormat::not_equal(Self, Self) -> Bool
```

`context` returns the matching `DecimalContext` preset (precision 7, 16 or
34, clamped).

### `GdaInterchange`

`GdaInterchange` is a decimal32, decimal64 or decimal128 bit pattern in the
densely packed decimal (DPD) encoding.

```mbti
pub struct GdaInterchange {
  // private fields
}
pub fn GdaInterchange::format(Self) -> GdaInterchangeFormat
```

`format` returns the format of the pattern.

### `GdaInterchange::from_decimal`, `GdaInterchange::to_decimal`, `GdaInterchange::to_decimal_ctx`

These encode and decode values.

```mbti
pub fn GdaInterchange::from_decimal(Decimal, GdaInterchangeFormat) -> (Self, DecimalFlags)
pub fn GdaInterchange::to_decimal(Self) -> Decimal
pub fn GdaInterchange::to_decimal_ctx(Self) -> (Decimal, DecimalFlags)
```

`from_decimal` rounds the value to the format (reporting the rounding,
overflow, underflow and clamping flags) and encodes it. `to_decimal` decodes
exactly, keeping the exponent; `to_decimal_ctx` also reports `subnormal` for
a subnormal value.

### `GdaInterchange::from_hex`, `GdaInterchange::to_hex`

These convert between a bit pattern and its hexadecimal text.

```mbti
pub fn GdaInterchange::from_hex(String, GdaInterchangeFormat) -> Self?
pub fn GdaInterchange::to_hex(Self) -> String
```

The text is `#` (optional on input) followed by exactly 8, 16 or 32
hexadecimal digits; surrounding spaces are ignored and any other input gives
`None`. `to_hex` prints `#` and uppercase digits.

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

### `Decimal::from_interchange_hex`, `Decimal::to_interchange_hex`

These are the same conversions directly between `Decimal` and hexadecimal
text.

```mbti
pub fn Decimal::from_interchange_hex(String, GdaInterchangeFormat) -> Self?
pub fn Decimal::to_interchange_hex(Self, GdaInterchangeFormat) -> (String, DecimalFlags)
```

```moonbit
///|
test "DPD interchange" {
  let d = (s : String) => @decimal_gda.Decimal::from_string(s).unwrap()
  let (bits, flags) = @decimal_gda.GdaInterchange::from_decimal(d("1.234567890"), Decimal32)
  inspect(bits.to_hex(), content="#25F4D2E8")
  inspect(bits.to_decimal(), content="1.234568")
  inspect(flags.inexact, content="true")
  let back = @decimal_gda.Decimal::from_interchange_hex("#A2300000000003D0", Decimal64).unwrap()
  inspect(back, content="-7.50")
  inspect(bits.copy_negate().to_decimal(), content="-1.234568")
}
```

## Trait implementations

### `Luna-Flow/arithmetic` contextual traits

These adapt the status-free layer to `ArithmeticContext`.

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

Each converts the context with `DecimalContext::from_arithmetic_context`,
calls the `_ctx` method, and returns `Err(division_by_zero)` when
`division_by_zero` is raised, `Err(domain_error)` for any other error flag,
and otherwise `Ok` with the value and diagnostics `inexact`, `rounded`,
`overflow`, `underflow`, `subnormal` and `clamped`.

### `NumericFormatContextual`

These describe the number format of an `ArithmeticContext`.

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

### Checked traits

These return `Result` instead of flags.

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

`parse_checked` is `Decimal::parse` at the context precision. `sqrt_checked`
returns `Err(domain_error)` for negative operands. `pow_int_checked` and
`pow_nat_checked` call `power_ctx` with an integer exponent; they return
`Err(division_by_zero)` for a zero base with a negative exponent,
`Err(domain_error)` for invalid results, and `pow_nat_checked` returns
`Err(unsupported)` for exponents above 999,999,999. `DivChecked::div_checked`
divides under the given context with the same errors as
[`Decimal::div_checked`](#decimaldiv_checked-decimalsqrt).

### `luna-generic` algebra traits

These let generic algebra code use `Decimal`.

```mbti
pub fn[S : @luna-generic.Nat] Decimal::from_nat(S) -> Self
pub fn[S : @luna-generic.Integral] Decimal::from_integral(S) -> Self
pub impl @luna-generic.NatHomomorphism for Decimal
pub impl @luna-generic.IntegralHomomorphism for Decimal
pub impl @luna-generic.Zero for Decimal
pub impl @luna-generic.One for Decimal
pub impl @luna-generic.AddMonoid for Decimal
pub impl @luna-generic.MulMonoid for Decimal
pub impl @luna-generic.AddGroup for Decimal
pub impl @luna-generic.Semiring for Decimal
pub impl @luna-generic.Ring for Decimal
```

`from_nat` and `from_integral` convert through `BigInt` with
`Decimal::from_bigint` (34 digits, trailing zeros removed), so they are exact
only for integers of at most 34 significant digits. `Zero::zero` and
`One::one` are `Decimal::zero()` and `Decimal::one()`. The ring structure uses
the context-free operators; because `+` rounds to the operand precision, the
ring laws hold exactly only while sums stay within that precision.

### `@def.Floating`, `Show`, `Debug`

`Decimal` implements the floating vocabulary of the `def` package, `Show` (see
[`Decimal::to_string`](#decimalto_string-decimaloutput)) and `Debug`.

```mbti
pub impl @def.Floating for Decimal
pub fn Decimal::to_repr(Self) -> @debug.Repr
```

The `Floating` methods are `classify`, `sign`, `precision`,
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
  inspect(@decimal_gda.Decimal::from_integral(1200), content="1.2E+3")
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
  "Luna-Flow/floating/bin_float",
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

pub fn compare_total(Decimal, Decimal, GdaContext) -> GdaOutcome[Int]

pub fn compare_total_magnitude(Decimal, Decimal, GdaContext) -> GdaOutcome[Int]

pub fn context(precision? : Int, rounding? : GdaRoundingMode, e_min? : Int, e_max? : Int, clamp? : Bool, extended? : Bool) -> GdaContext

pub fn decimal128_context() -> GdaContext

pub fn decimal32_context() -> GdaContext

pub fn decimal64_context() -> GdaContext

pub fn divide(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn divide_integer(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn exp(Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn fma(Decimal, Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]

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

pub fn max_mag(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn min(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn min_mag(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn minus(Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn multiply(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn next_minus(Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn next_plus(Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn next_toward(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn parse(String, GdaContext) -> GdaOutcome[Decimal]

pub fn plus(Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn power(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn quantize(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn reduce(Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn remainder(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn remainder_near(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn rescale(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn rotate(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn same_quantum(Decimal, Decimal, GdaContext) -> GdaOutcome[Bool]

pub fn scaleb(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn shift(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn sqrt(Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn subtract(Decimal, Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn to_integral_exact(Decimal, GdaContext) -> GdaOutcome[Decimal]

pub fn to_integral_value(Decimal, GdaContext) -> GdaOutcome[Decimal]

// Errors

// Types and methods
pub struct Decimal {
  // private fields
} derive(@debug.Debug)
pub fn Decimal::abs(Self) -> Self
pub fn Decimal::abs_contextual(Self, @arithmetic.ArithmeticContext) -> Result[@arithmetic.ArithmeticOutcome[Self], @arithmetic.ArithmeticError]
pub fn Decimal::abs_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::add(Self, Self) -> Self
pub fn Decimal::add_contextual(Self, Self, @arithmetic.ArithmeticContext) -> Result[@arithmetic.ArithmeticOutcome[Self], @arithmetic.ArithmeticError]
pub fn Decimal::add_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::apply_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::clamp(Self, min~ : Self, max~ : Self) -> Self
pub fn Decimal::clamp_checked(Self, min~ : Self, max~ : Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn Decimal::class_name(Self, DecimalContext) -> String
pub fn Decimal::classify(Self) -> @arithmetic.FpClass
pub fn Decimal::classify_contextual(Self) -> @arithmetic.FpClass
pub fn Decimal::coefficient(Self) -> @bigint.BigInt
pub fn Decimal::compare(Self, Self) -> Int
pub fn Decimal::compare_checked(Self, Self) -> Result[Int, @arithmetic.ArithmeticError]
pub fn Decimal::compare_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::compare_signal_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::compare_total(Self, Self) -> Int
pub fn Decimal::compare_total_ctx(Self, Self, DecimalContext) -> (Int, DecimalFlags)
pub fn Decimal::compare_total_magnitude(Self, Self) -> Int
pub fn Decimal::compare_total_magnitude_ctx(Self, Self, DecimalContext) -> (Int, DecimalFlags)
pub fn Decimal::copy(Self) -> Self
pub fn Decimal::copy_abs(Self) -> Self
pub fn Decimal::copy_negate(Self) -> Self
pub fn Decimal::copy_sign(Self, Self) -> Self
pub fn Decimal::div(Self, Self) -> Self
pub fn Decimal::div_checked(Self, Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn Decimal::div_contextual(Self, Self, @arithmetic.ArithmeticContext) -> Result[@arithmetic.ArithmeticOutcome[Self], @arithmetic.ArithmeticError]
pub fn Decimal::div_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::divide_integer(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::epsilon_contextual(@arithmetic.ArithmeticContext) -> Self
pub fn Decimal::equal(Self, Self) -> Bool
pub fn Decimal::exp_contextual(Self, @arithmetic.ArithmeticContext) -> Result[@arithmetic.ArithmeticOutcome[Self], @arithmetic.ArithmeticError]
pub fn Decimal::exp_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::exponent10(Self) -> Int
pub fn Decimal::fma_ctx(Self, Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::from_bigint(@bigint.BigInt, precision? : Int) -> Self
pub fn Decimal::from_bin_float(@bin_float.BinFloat, precision? : Int) -> Self
pub fn Decimal::from_double(Double, precision? : Int) -> Self
pub fn Decimal::from_float(Float, precision? : Int) -> Self
pub fn Decimal::from_int(Int, precision? : Int) -> Self
pub fn[S : @luna-generic.Integral] Decimal::from_integral(S) -> Self
pub fn Decimal::from_interchange_hex(String, GdaInterchangeFormat) -> Self?
pub fn[S : @luna-generic.Nat] Decimal::from_nat(S) -> Self
pub fn Decimal::from_string(String, precision? : Int) -> Self?
pub fn Decimal::from_string_ctx(String, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::get_payload(Self) -> @bigint.BigInt
pub fn Decimal::inf(@def.Sign, precision? : Int) -> Self
pub fn Decimal::is_canonical(Self) -> Bool
pub fn Decimal::is_finite(Self) -> Bool
pub fn Decimal::is_infinite(Self) -> Bool
pub fn Decimal::is_nan(Self) -> Bool
pub fn Decimal::is_negative(Self) -> Bool
pub fn Decimal::is_negative_zero(Self) -> Bool
pub fn Decimal::is_normal(Self, DecimalContext) -> Bool
pub fn Decimal::is_qnan(Self) -> Bool
pub fn Decimal::is_quiet_nan(Self) -> Bool
pub fn Decimal::is_signaling_nan(Self) -> Bool
pub fn Decimal::is_signed(Self) -> Bool
pub fn Decimal::is_snan(Self) -> Bool
pub fn Decimal::is_subnormal(Self, DecimalContext) -> Bool
pub fn Decimal::is_zero(Self) -> Bool
pub fn Decimal::ln_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::log10_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::logb_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::logical_and(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::logical_invert(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::logical_or(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::logical_xor(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::magnitude(Self) -> @bigint.BigInt
pub fn Decimal::make(@bigint.BigInt, Int, Int, mode? : @arithmetic.RoundingMode) -> Self
pub fn Decimal::max(Self, Self) -> Self
pub fn Decimal::max_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::max_finite_contextual(@arithmetic.ArithmeticContext) -> Self
pub fn Decimal::max_mag_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::maximum_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::maximum_mag_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::maximum_magnitude_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::maximum_number_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::maximum_number_mag_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::maximum_number_magnitude_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::min(Self, Self) -> Self
pub fn Decimal::min_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::min_mag_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::min_normal_contextual(@arithmetic.ArithmeticContext) -> Self
pub fn Decimal::minimum_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::minimum_mag_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::minimum_magnitude_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::minimum_number_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::minimum_number_mag_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::minimum_number_magnitude_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::minus_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::mul(Self, Self) -> Self
pub fn Decimal::mul_contextual(Self, Self, @arithmetic.ArithmeticContext) -> Result[@arithmetic.ArithmeticOutcome[Self], @arithmetic.ArithmeticError]
pub fn Decimal::mul_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::nan(precision? : Int) -> Self
pub fn Decimal::nan_payload(Self) -> @bigint.BigInt
pub fn Decimal::neg(Self) -> Self
pub fn Decimal::negative_zero(precision? : Int) -> Self
pub fn Decimal::next_minus(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::next_plus(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::next_toward(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::normalize_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::normalized(Self) -> Self
pub fn Decimal::not_equal(Self, Self) -> Bool
pub fn Decimal::one(precision? : Int) -> Self
pub fn Decimal::one_contextual(@arithmetic.ArithmeticContext) -> Self
pub fn Decimal::op_ge(Self, Self) -> Bool
pub fn Decimal::op_gt(Self, Self) -> Bool
pub fn Decimal::op_le(Self, Self) -> Bool
pub fn Decimal::op_lt(Self, Self) -> Bool
pub fn Decimal::output(Self, &Logger) -> Unit
pub fn Decimal::parse(String, precision? : Int) -> Result[Self, @arithmetic.ArithmeticError]
pub fn Decimal::parse_checked(String, @arithmetic.ArithmeticContext) -> Result[Self, @arithmetic.ArithmeticError]
pub fn Decimal::plus_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::pow_int_checked(Self, Int, @arithmetic.ArithmeticContext) -> Result[Self, @arithmetic.ArithmeticError]
pub fn Decimal::pow_nat_checked(Self, UInt, @arithmetic.ArithmeticContext) -> Result[Self, @arithmetic.ArithmeticError]
pub fn Decimal::power_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::precision(Self) -> Int
pub fn Decimal::quantize(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::quantum(Self) -> Int
pub fn Decimal::quiet_nan(payload? : @bigint.BigInt, negative? : Bool, precision? : Int) -> Self
pub fn Decimal::reduce_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::remainder(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::remainder_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::remainder_near(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::rescale(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::rotate_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::same_quantum(Self, Self) -> Bool
pub fn Decimal::scaleb_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::set_payload(Self, @bigint.BigInt) -> Self
pub fn Decimal::set_payload_signaling(Self, @bigint.BigInt) -> Self
pub fn Decimal::shift_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::sign(Self) -> @def.Sign
pub fn Decimal::signaling_nan(payload? : @bigint.BigInt, negative? : Bool, precision? : Int) -> Self
pub fn Decimal::sqrt(Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn Decimal::sqrt_checked(Self, @arithmetic.ArithmeticContext) -> Result[Self, @arithmetic.ArithmeticError]
pub fn Decimal::sqrt_contextual(Self, @arithmetic.ArithmeticContext) -> Result[@arithmetic.ArithmeticOutcome[Self], @arithmetic.ArithmeticError]
pub fn Decimal::sqrt_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::sub(Self, Self) -> Self
pub fn Decimal::sub_contextual(Self, Self, @arithmetic.ArithmeticContext) -> Result[@arithmetic.ArithmeticOutcome[Self], @arithmetic.ArithmeticError]
pub fn Decimal::sub_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::to_bin_float(Self, precision? : Int, mode? : @arithmetic.RoundingMode) -> @bin_float.BinFloat
pub fn Decimal::to_eng_string(String, DecimalContext) -> (String, DecimalFlags)
pub fn Decimal::to_integral_exact(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::to_integral_value(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::to_interchange_hex(Self, GdaInterchangeFormat) -> (String, DecimalFlags)
pub fn Decimal::to_repr(Self) -> @debug.Repr
pub fn Decimal::to_sci_string(String, DecimalContext) -> (String, DecimalFlags)
pub fn Decimal::to_string(Self) -> String
pub fn Decimal::trim(Self) -> Self
pub fn Decimal::try_exp_ctx(Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::try_ln_ctx(Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::try_log10_ctx(Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::try_power_ctx(Self, Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::with_precision(Self, Int, @arithmetic.RoundingMode) -> Self
pub fn Decimal::zero(precision? : Int) -> Self
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
pub impl @luna-generic.IntegralHomomorphism for Decimal
pub impl @luna-generic.MulMonoid for Decimal
pub impl @luna-generic.NatHomomorphism for Decimal
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

pub struct DecimalContext {
  // private fields
} derive(Eq)
pub fn DecimalContext::clamp(Self) -> Bool
pub fn DecimalContext::decimal128() -> Self
pub fn DecimalContext::decimal32() -> Self
pub fn DecimalContext::decimal64() -> Self
pub fn DecimalContext::decimal_rounding(Self) -> DecimalRoundingMode
pub fn DecimalContext::e_max(Self) -> Int
pub fn DecimalContext::e_min(Self) -> Int
pub fn DecimalContext::equal(Self, Self) -> Bool
pub fn DecimalContext::exact() -> Self
pub fn DecimalContext::extended(Self) -> Bool
pub fn DecimalContext::from_arithmetic_context(@arithmetic.ArithmeticContext) -> Self
pub fn DecimalContext::new(precision? : Int, rounding? : @arithmetic.RoundingMode, decimal_rounding? : DecimalRoundingMode, e_min? : Int, e_max? : Int, clamp? : Bool, extended? : Bool, tininess? : DecimalTininessDetection) -> Self
pub fn DecimalContext::not_equal(Self, Self) -> Bool
pub fn DecimalContext::precision(Self) -> Int
pub fn DecimalContext::rounding(Self) -> @arithmetic.RoundingMode
pub fn DecimalContext::tininess(Self) -> DecimalTininessDetection
pub fn DecimalContext::try_new(precision? : Int, rounding? : @arithmetic.RoundingMode, decimal_rounding? : DecimalRoundingMode, e_min? : Int, e_max? : Int, clamp? : Bool, extended? : Bool, tininess? : DecimalTininessDetection) -> Result[Self, @arithmetic.ArithmeticError]
pub fn DecimalContext::with_rounding(Self, @arithmetic.RoundingMode) -> Self
pub fn DecimalContext::with_tininess(Self, DecimalTininessDetection) -> Self

pub struct DecimalFlags {
  inexact : Bool
  rounded : Bool
  lost_digits : Bool
  invalid_operation : Bool
  division_by_zero : Bool
  overflow : Bool
  underflow : Bool
  subnormal : Bool
  clamped : Bool
  conversion_syntax : Bool
  division_impossible : Bool
  division_undefined : Bool
  invalid_context : Bool
} derive(Eq)
pub fn DecimalFlags::combine(Self, Self) -> Self
pub fn DecimalFlags::contains(Self, DecimalSignal) -> Bool
pub fn DecimalFlags::equal(Self, Self) -> Bool
pub fn DecimalFlags::has_error(Self) -> Bool
pub fn DecimalFlags::new() -> Self
pub fn DecimalFlags::not_equal(Self, Self) -> Bool

pub(all) enum DecimalRoundingMode {
  HalfEven
  HalfUp
  HalfDown
  Down
  Ceiling
  Floor
  Up
  ZeroFiveUp
} derive(Eq)
pub fn DecimalRoundingMode::equal(Self, Self) -> Bool
pub fn DecimalRoundingMode::from_arithmetic(@arithmetic.RoundingMode) -> Self
pub fn DecimalRoundingMode::not_equal(Self, Self) -> Bool
pub fn DecimalRoundingMode::to_arithmetic(Self) -> @arithmetic.RoundingMode?

pub(all) enum DecimalSignal {
  ConversionSyntax
  DivisionByZero
  DivisionImpossible
  DivisionUndefined
  InvalidContext
  InvalidOperation
  Overflow
  Underflow
  Subnormal
  Inexact
  Rounded
  Clamped
  LostDigits
} derive(Eq)
pub fn DecimalSignal::equal(Self, Self) -> Bool
pub fn DecimalSignal::not_equal(Self, Self) -> Bool

pub(all) enum DecimalTininessDetection {
  BeforeRounding
  AfterRounding
} derive(Eq)
pub fn DecimalTininessDetection::equal(Self, Self) -> Bool
pub fn DecimalTininessDetection::not_equal(Self, Self) -> Bool

pub struct GdaContext {
  // private fields
}
pub fn GdaContext::basic() -> Self
pub fn GdaContext::clamp(Self) -> Bool
pub fn GdaContext::clear_status(Self) -> Self
pub fn GdaContext::decimal128() -> Self
pub fn GdaContext::decimal32() -> Self
pub fn GdaContext::decimal64() -> Self
pub fn GdaContext::default() -> Self
pub fn GdaContext::e_max(Self) -> Int
pub fn GdaContext::e_min(Self) -> Int
pub fn GdaContext::extended(Self) -> Bool
pub fn GdaContext::new(precision? : Int, rounding? : GdaRoundingMode, e_min? : Int, e_max? : Int, clamp? : Bool, extended? : Bool, traps? : GdaTrapSet) -> Self
pub fn GdaContext::precision(Self) -> Int
pub fn GdaContext::radix(Self) -> Int
pub fn GdaContext::reset(Self) -> Self
pub fn GdaContext::rounding(Self) -> GdaRoundingMode
pub fn GdaContext::status(Self) -> GdaFlags
pub fn GdaContext::trap(Self, GdaSignal, enabled? : Bool) -> Self
pub fn GdaContext::traps(Self) -> GdaTrapSet
pub fn GdaContext::try_new(precision? : Int, rounding? : GdaRoundingMode, e_min? : Int, e_max? : Int, clamp? : Bool, extended? : Bool, traps? : GdaTrapSet) -> Result[Self, @arithmetic.ArithmeticError]
pub fn GdaContext::with_traps(Self, GdaTrapSet) -> Self

pub struct GdaFlags {
  conversion_syntax : Bool
  division_by_zero : Bool
  division_impossible : Bool
  division_undefined : Bool
  invalid_context : Bool
  invalid_operation : Bool
  overflow : Bool
  underflow : Bool
  subnormal : Bool
  inexact : Bool
  rounded : Bool
  clamped : Bool
  lost_digits : Bool
} derive(Eq)
pub fn GdaFlags::combine(Self, Self) -> Self
pub fn GdaFlags::contains(Self, GdaSignal) -> Bool
pub fn GdaFlags::equal(Self, Self) -> Bool
pub fn GdaFlags::none() -> Self
pub fn GdaFlags::not_equal(Self, Self) -> Bool

pub struct GdaInterchange {
  // private fields
}
pub fn GdaInterchange::canonical(Self) -> Self
pub fn GdaInterchange::copy(Self) -> Self
pub fn GdaInterchange::copy_abs(Self) -> Self
pub fn GdaInterchange::copy_negate(Self) -> Self
pub fn GdaInterchange::copy_sign(Self, Self) -> Self
pub fn GdaInterchange::format(Self) -> GdaInterchangeFormat
pub fn GdaInterchange::from_decimal(Decimal, GdaInterchangeFormat) -> (Self, DecimalFlags)
pub fn GdaInterchange::from_hex(String, GdaInterchangeFormat) -> Self?
pub fn GdaInterchange::is_canonical(Self) -> Bool
pub fn GdaInterchange::to_decimal(Self) -> Decimal
pub fn GdaInterchange::to_decimal_ctx(Self) -> (Decimal, DecimalFlags)
pub fn GdaInterchange::to_hex(Self) -> String

pub(all) enum GdaInterchangeFormat {
  Decimal32
  Decimal64
  Decimal128
} derive(Eq)
pub fn GdaInterchangeFormat::context(Self) -> DecimalContext
pub fn GdaInterchangeFormat::equal(Self, Self) -> Bool
pub fn GdaInterchangeFormat::not_equal(Self, Self) -> Bool

pub(all) enum GdaOutcome[T] {
  Completed(T, GdaContext, GdaFlags)
  Trapped(GdaSignal, T, GdaContext, GdaFlags)
}
pub fn[T] GdaOutcome::next_context(Self[T]) -> GdaContext
pub fn[T] GdaOutcome::raised(Self[T]) -> GdaFlags
pub fn[T] GdaOutcome::value(Self[T]) -> T

pub(all) enum GdaRoundingMode {
  HalfEven
  HalfUp
  HalfDown
  Down
  Ceiling
  Floor
  Up
  ZeroFiveUp
} derive(Eq)
pub fn GdaRoundingMode::equal(Self, Self) -> Bool
pub fn GdaRoundingMode::not_equal(Self, Self) -> Bool

pub(all) enum GdaSignal {
  ConversionSyntax
  DivisionByZero
  DivisionImpossible
  DivisionUndefined
  InvalidContext
  InvalidOperation
  Overflow
  Underflow
  Subnormal
  Inexact
  Rounded
  Clamped
  LostDigits
} derive(Eq)
pub fn GdaSignal::equal(Self, Self) -> Bool
pub fn GdaSignal::not_equal(Self, Self) -> Bool

pub struct GdaTrapSet {
  conversion_syntax : Bool
  division_by_zero : Bool
  division_impossible : Bool
  division_undefined : Bool
  invalid_context : Bool
  invalid_operation : Bool
  overflow : Bool
  underflow : Bool
  subnormal : Bool
  inexact : Bool
  rounded : Bool
  clamped : Bool
  lost_digits : Bool
} derive(Eq)
pub fn GdaTrapSet::contains(Self, GdaSignal) -> Bool
pub fn GdaTrapSet::equal(Self, Self) -> Bool
pub fn GdaTrapSet::none() -> Self
pub fn GdaTrapSet::not_equal(Self, Self) -> Bool
pub fn GdaTrapSet::with_signal(Self, GdaSignal, enabled? : Bool) -> Self

// Type aliases

// Traits
```
<!-- generated-api-end -->
