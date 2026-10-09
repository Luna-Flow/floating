# decimal API

## Purpose

`Luna-Flow/floating/decimal` is the IEEE 754-2019 decimal floating-point
package of `floating`. A `Decimal` is an arbitrary-precision decimal value
that keeps its quantum (exponent), its sign of zero and its NaN payload; a
`DecimalContext` fixes precision, rounding, exponent range, clamping and
tininess; every context operation returns the rounded value together with the
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
`quantum`, `same_quantum`, `compare_total`, formatting and interchange
encoding.

The derived `Debug` implementation is promoted as `Decimal::to_repr`; see
[Trait implementations](#trait-implementations).

### `Decimal::precision`, `coefficient`, `magnitude`, `exponent10`, `quantum`

These observers return the stored representation of a value.

```mbti
pub fn Decimal::precision(Self) -> Int
pub fn Decimal::coefficient(Self) -> @bigint.BigInt
pub fn Decimal::magnitude(Self) -> @bigint.BigInt
pub fn Decimal::exponent10(Self) -> Int
pub fn Decimal::quantum(Self) -> Int
```

`precision` is the working precision stored in the value (at least 1).
`coefficient` and `magnitude` both return the non-negative coefficient $c$;
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

### `Decimal::sign`, `is_negative`, `is_signed`

These observers report the sign of a value.

```mbti
pub fn Decimal::sign(Self) -> @def.Sign
pub fn Decimal::is_negative(Self) -> Bool
pub fn Decimal::is_signed(Self) -> Bool
```

`sign` returns `@def.Sign::Zero` for both zeros and for every NaN, and
`Negative`/`Positive` otherwise. `is_negative` and `is_signed` are the same
predicate: they return the stored sign bit, so they are `true` for $-0$, for
$-\infty$ and for a negative NaN.

### `Decimal::classify`, `class_name`

`classify` returns the coarse class of a value; `class_name` returns the
General Decimal Arithmetic class string under a context.

```mbti
pub fn Decimal::classify(Self) -> @arithmetic.FpClass
pub fn Decimal::class_name(Self, DecimalContext) -> String
```

`classify` returns `Finite`, `Infinity` or `NaN`. `class_name` returns one of
`"sNaN"`, `"NaN"`, `"-Infinity"`, `"+Infinity"`, `"-Zero"`, `"+Zero"`,
`"-Subnormal"`, `"+Subnormal"`, `"-Normal"` or `"+Normal"`; the
normal/subnormal split uses the context's $e_{\min}$.

### `Decimal::is_finite`, `is_infinite`, `is_nan`, `is_zero`, `is_negative_zero`, `is_quiet_nan`, `is_qnan`, `is_signaling_nan`, `is_snan`, `is_canonical`, `is_normal`, `is_subnormal`

These predicates test the class of a value.

```mbti
pub fn Decimal::is_finite(Self) -> Bool
pub fn Decimal::is_infinite(Self) -> Bool
pub fn Decimal::is_nan(Self) -> Bool
pub fn Decimal::is_zero(Self) -> Bool
pub fn Decimal::is_negative_zero(Self) -> Bool
pub fn Decimal::is_quiet_nan(Self) -> Bool
pub fn Decimal::is_qnan(Self) -> Bool
pub fn Decimal::is_signaling_nan(Self) -> Bool
pub fn Decimal::is_snan(Self) -> Bool
pub fn Decimal::is_canonical(Self) -> Bool
pub fn Decimal::is_normal(Self, DecimalContext) -> Bool
pub fn Decimal::is_subnormal(Self, DecimalContext) -> Bool
```

`is_qnan` and `is_snan` are the General Decimal Arithmetic spellings of
`is_quiet_nan` and `is_signaling_nan`. `is_canonical` always returns `true`:
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

`nan_payload` and `get_payload` return the payload of a NaN and `0` for every
other value. `set_payload` returns a quiet NaN with the given payload (its
absolute value) and the original sign; `set_payload_signaling` returns a
signaling NaN. Both return a non-NaN argument unchanged.

## Construction and conversion

### `Decimal::make`

`make` builds a finite value from a signed integer coefficient and an exponent,
rounding it to a precision.

```mbti
pub fn Decimal::make(@bigint.BigInt, Int, Int, mode? : @arithmetic.RoundingMode) -> Self
```

`Decimal::make(c, q, p, mode~)` represents $c \cdot 10^{q}$; the sign comes
from `c`. Trailing zeros are removed first, the coefficient is then rounded to
`p` digits with `mode` (default `ToNearestEven`) if it is longer, and trailing
zeros are removed again. The result is therefore always in the *reduced*
member of its cohort, and `make(0, q, p)` is $+0$ with exponent `0`. No
exponent range applies.

### `Decimal::zero`, `negative_zero`, `one`, `inf`, `nan`, `quiet_nan`, `signaling_nan`

These constructors build the special and unit values.

```mbti
pub fn Decimal::zero(precision? : Int) -> Self
pub fn Decimal::negative_zero(precision? : Int) -> Self
pub fn Decimal::one(precision? : Int) -> Self
pub fn Decimal::inf(@def.Sign, precision? : Int) -> Self
pub fn Decimal::nan(precision? : Int) -> Self
pub fn Decimal::quiet_nan(payload? : @bigint.BigInt, negative? : Bool, precision? : Int) -> Self
pub fn Decimal::signaling_nan(payload? : @bigint.BigInt, negative? : Bool, precision? : Int) -> Self
```

The default precision is 34. `zero`, `negative_zero` and `one` have exponent
`0`. `inf(sign)` is $-\infty$ for `Negative` and $+\infty$ otherwise. `nan` is
a positive quiet NaN with payload 0; `quiet_nan` and `signaling_nan` default
to payload 0 and a positive sign.

### `Decimal::from_int`, `from_bigint`

These constructors convert an integer.

```mbti
pub fn Decimal::from_int(Int, precision? : Int) -> Self
pub fn Decimal::from_bigint(@bigint.BigInt, precision? : Int) -> Self
```

Both are `make(n, 0, precision)` with the default precision 34: the result is
reduced (`from_int(1000)` is `1E+3`, exponent 3) and an integer with more than
`precision` digits is rounded half-even.

### `Decimal::from_double`, `from_float`

These constructors convert a binary floating-point number.

```mbti
pub fn Decimal::from_double(Double, precision? : Int) -> Self
pub fn Decimal::from_float(Float, precision? : Int) -> Self
```

Every finite `Double` is a dyadic rational $m \cdot 2^{k}$ and therefore has a
finite decimal expansion $m \cdot 5^{-k} \cdot 10^{k}$ for $k<0$; the
conversion forms that exact expansion and rounds it half-even to `precision`
digits (default 34). Signed zeros and infinities are preserved; every NaN
becomes a quiet NaN with payload 0 and the input's sign. `from_float` widens
to `Double` first, which is exact.

### `Decimal::from_bin_float`, `to_bin_float`

These functions convert between `Decimal` and the binary
[`BinFloat`](bin_float.md).

```mbti
pub fn Decimal::from_bin_float(@bin_float.BinFloat, precision? : Int) -> Self
pub fn Decimal::to_bin_float(Self, precision? : Int, mode? : @arithmetic.RoundingMode) -> @bin_float.BinFloat
```

`from_bin_float(x, precision~)` is exact whenever the decimal expansion of
`x` fits in `precision` decimal digits (default: the precision of `x`) and is
otherwise rounded half-even; a binary zero keeps its sign ($-0$ becomes
$-0$, as IEEE 754-2019 §5.4.2 and §6.3 require), and a NaN becomes a quiet
NaN with payload 0. `to_bin_float(precision~, mode~)` rounds the exact decimal value
to a `BinFloat` of `precision` bits (default: the decimal's precision field)
with `mode` (default `ToNearestEven`). Most decimal fractions are not dyadic,
so this direction is usually inexact; converting with `TowardNegative` and
`TowardPositive` gives a binary enclosure of the decimal value. Zeros keep
their sign and NaN payloads are not kept.

### `Decimal::from_natural`, `from_integer`

These functions are the canonical maps out of the naturals and the integers.

```mbti
pub fn Decimal::from_natural(@bigint.BigInt) -> Self
pub fn Decimal::from_integer(@bigint.BigInt) -> Self
```

They return `from_bigint(n).normalized()` with precision 34. They are the
`FromNat` and `FromInteger` implementations. To convert another Luna-Flow
integer type, pick its representative with `Integral::normalize` first, or use
`lift_to`.

## Parsing and formatting

### `Decimal::parse`, `from_string`

`parse` converts decimal text to a `Decimal` while keeping its quantum.

```mbti
pub fn Decimal::parse(String, precision? : Int) -> Result[Self, @arithmetic.ArithmeticError]
pub fn Decimal::from_string(String, precision? : Int) -> Self?
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
`Err(parse_error)` from `parse` and `None` from `from_string`.

No context exponent range is applied; the only limits are those of the
representation: the stored exponent must be at least $-2^{31}$ and the
adjusted exponent at most $2^{31}-1$. As IEEE 754 §5.12 requires, a valid
literal beyond them still converts, with the conversion rounded once: a
literal too large is a signed infinity (`"1e3000000000"` is `inf`), and one
too small is rounded half-even to the exponent $-2^{31}$, possibly to a
signed zero (`"1e-3000000000"` is `0E-2147483648`, `"15e-2147483649"` is
`2E-2147483648`). Use `from_string_ctx` to get the `overflow` and
`underflow` flags.

### `Decimal::from_string_ctx`

`from_string_ctx` converts text under a context and reports conversion flags.

```mbti
pub fn Decimal::from_string_ctx(String, DecimalContext) -> (Self, DecimalFlags)
```

The syntax is the one of `parse`. The value is rounded to the context
precision (raising `rounded`, and `inexact` when non-zero digits are
discarded), checked against the exponent range (overflow, subnormal,
underflow, clamping) and, when `clamp` is set, folded down. A NaN payload with
more digits than the context allows (precision $-1$ digits when `clamp` is
set, otherwise precision) is a syntax error. Invalid text returns a quiet NaN
with only the `conversion_syntax` flag set. In a non-extended context, `Inf`
and `NaN` spellings are conversion-syntax errors.

```moonbit
///|
test "decimal from_string_ctx rounds and flags" {
  let ctx = @decimal.DecimalContext::decimal32()
  let (x, flags) = @decimal.Decimal::from_string_ctx("3.14159265", ctx)
  inspect(x, content="3.141593")
  inspect(flags.rounded && flags.inexact, content="true")
  let (bad, bad_flags) = @decimal.Decimal::from_string_ctx("1..2", ctx)
  inspect(bad.is_nan(), content="true")
  inspect(bad_flags.conversion_syntax, content="true")
}
```

### `Decimal::to_sci_string`, `to_eng_string`

These functions implement the General Decimal Arithmetic `to-scientific-string`
and `to-engineering-string` conversions of a text operand.

```mbti
pub fn Decimal::to_sci_string(String, DecimalContext) -> (String, DecimalFlags)
pub fn Decimal::to_eng_string(String, DecimalContext) -> (String, DecimalFlags)
```

Both take *text*, convert it with `from_string_ctx` and format the result.
Scientific form writes the coefficient with an exponent `E±n` whenever the
exponent is positive or the adjusted exponent is below $-6$, and plain digits
otherwise; engineering form uses an exponent that is a multiple of three.
Special values are written `Infinity`, `-Infinity`, `NaN`, `sNaN`, with a
payload such as `NaN7`. The flags are those of the conversion.

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

A context holds a precision $p$, a shared Luna-Flow `rounding` mode, a
decimal rounding mode (`decimal_rounding`, the one the arithmetic uses), the
adjusted-exponent limits $e_{\min} \le e_{\max}$, the `clamp` switch, the
`extended` switch and a tininess rule. No operation reads ambient state: every
context operation receives its context as an argument.

### `DecimalContext::new`, `try_new`

These constructors build a context from named parameters.

```mbti
pub fn DecimalContext::new(precision? : Int, rounding? : @arithmetic.RoundingMode, decimal_rounding? : DecimalRoundingMode, e_min? : Int, e_max? : Int, clamp? : Bool, extended? : Bool, tininess? : DecimalTininessDetection) -> Self
pub fn DecimalContext::try_new(precision? : Int, rounding? : @arithmetic.RoundingMode, decimal_rounding? : DecimalRoundingMode, e_min? : Int, e_max? : Int, clamp? : Bool, extended? : Bool, tininess? : DecimalTininessDetection) -> Result[Self, @arithmetic.ArithmeticError]
```

| Parameter | Default | Meaning |
| --- | --- | --- |
| `precision` | 34 | coefficient digits $p$ |
| `rounding` | `ToNearestEven` | shared rounding mode |
| `decimal_rounding` | from `rounding` | rounding mode used by the arithmetic |
| `e_min`, `e_max` | $-999\,999\,999$, $999\,999\,999$ | adjusted-exponent range |
| `clamp` | `false` | fold large exponents down to $e_{\max}-p+1$ |
| `extended` | `true` | IEEE/extended arithmetic; `false` selects the GDA subset |
| `tininess` | `AfterRounding` | when a result counts as tiny |

When `decimal_rounding` is omitted it is
`DecimalRoundingMode::from_arithmetic(rounding)`; pass it explicitly to use
`HalfUp`, `HalfDown` or `ZeroFiveUp`. `new` aborts when `precision <= 0` or
`e_min > e_max`; `try_new` returns `Err(domain_error)` instead.

> [!IMPORTANT]
> The default exponent range is wider than the range the elementary
> functions accept ($|e| \le 999\,999$ and $p \le 999\,999$). With
> `DecimalContext::new()` they return NaN with `invalid_context`; use a
> format preset or explicit `e_min`/`e_max`.

The subset mode (`extended=false`) reproduces the classic decNumber subset:
operands longer than $p$ digits are rounded first (raising `lost_digits`),
zero results lose their sign and exponent, and special-value text is
rejected. It exists for General Decimal Arithmetic test compatibility.

### `DecimalContext::decimal32`, `decimal64`, `decimal128`, `exact`

These constructors return the interchange-format contexts and an exact
working context.

```mbti
pub fn DecimalContext::decimal32() -> Self
pub fn DecimalContext::decimal64() -> Self
pub fn DecimalContext::decimal128() -> Self
pub fn DecimalContext::exact() -> Self
```

| Context | $p$ | $e_{\min}$ | $e_{\max}$ | clamp |
| --- | ---: | ---: | ---: | --- |
| `decimal32` | 7 | $-95$ | 96 | yes |
| `decimal64` | 16 | $-383$ | 384 | yes |
| `decimal128` | 34 | $-6143$ | 6144 | yes |

All three use `ToNearestEven` (`HalfEven`), extended arithmetic and
after-rounding tininess. `exact()` has precision 0, which means "unlimited":
results keep every digit and no rounding by precision happens; its exponent
range is the default one. It is the only way to obtain precision 0.

### `DecimalContext::from_arithmetic_context`

`from_arithmetic_context` converts the shared Luna-Flow context.

```mbti
pub fn DecimalContext::from_arithmetic_context(@arithmetic.ArithmeticContext) -> Self
```

Precision, rounding and clamp are copied; a missing `e_min` or `e_max` becomes
$\mp 999\,999\,999$. The result is extended and uses after-rounding tininess.
The contextual and checked trait implementations use this conversion.

### `DecimalContext::precision`, `rounding`, `decimal_rounding`, `e_min`, `e_max`, `clamp`, `extended`, `tininess`

These accessors return the fields of a context.

```mbti
pub fn DecimalContext::precision(Self) -> Int
pub fn DecimalContext::rounding(Self) -> @arithmetic.RoundingMode
pub fn DecimalContext::decimal_rounding(Self) -> DecimalRoundingMode
pub fn DecimalContext::e_min(Self) -> Int
pub fn DecimalContext::e_max(Self) -> Int
pub fn DecimalContext::clamp(Self) -> Bool
pub fn DecimalContext::extended(Self) -> Bool
pub fn DecimalContext::tininess(Self) -> DecimalTininessDetection
```

`precision` is 0 only for `exact()`.

### `DecimalContext::with_rounding`, `with_tininess`, `ieee754`, `is754version2019`

These functions derive a context or describe its standard.

```mbti
pub fn DecimalContext::with_rounding(Self, @arithmetic.RoundingMode) -> Self
pub fn DecimalContext::with_tininess(Self, DecimalTininessDetection) -> Self
pub fn DecimalContext::ieee754(Self) -> Self
pub fn DecimalContext::is754version2019(Self) -> Bool
```

`with_rounding` replaces both rounding fields (the decimal mode becomes
`from_arithmetic(rounding)`). `with_tininess` replaces the tininess rule.
`ieee754` returns the context unchanged: every context already follows the
IEEE 754-2019 semantics of this package. `is754version2019` always returns
`true`.

## Rounding modes and tininess

### `DecimalRoundingMode`

`DecimalRoundingMode` lists the eight decimal rounding directions.

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
}
```

Let $x>0$ lie strictly between two adjacent representable coefficients $c$
and $c+1$ (in units of the last place). `Down` returns $c$, `Up` $c+1$;
`Ceiling` and `Floor` round toward $+\infty$ and $-\infty$ (so they depend on
the sign); `HalfEven`, `HalfUp` and `HalfDown` return the nearer of the two
and break an exact tie toward the even coefficient, away from zero, and
toward zero respectively; `ZeroFiveUp` returns $c+1$ when the last digit of
$c$ is 0 or 5 and $c$ otherwise. IEEE 754 calls `HalfEven`
roundTiesToEven, `HalfUp` roundTiesToAway, `Down` roundTowardZero, `Ceiling`
roundTowardPositive and `Floor` roundTowardNegative.

### `DecimalRoundingMode::from_arithmetic`, `to_arithmetic`

These functions map between decimal modes and the shared
`@arithmetic.RoundingMode`.

```mbti
pub fn DecimalRoundingMode::from_arithmetic(@arithmetic.RoundingMode) -> Self
pub fn DecimalRoundingMode::to_arithmetic(Self) -> @arithmetic.RoundingMode?
```

| `@arithmetic.RoundingMode` | `DecimalRoundingMode` |
| --- | --- |
| `ToNearestEven` | `HalfEven` |
| `TowardZero` | `Down` |
| `TowardPositive` | `Ceiling` |
| `TowardNegative` | `Floor` |
| `AwayFromZero` | `Up` |

`to_arithmetic` returns `None` for `HalfUp`, `HalfDown` and `ZeroFiveUp`,
which the shared enum does not have.

### `DecimalTininessDetection`

`DecimalTininessDetection` chooses when a non-zero result is tiny.

```mbti
pub(all) enum DecimalTininessDetection {
  BeforeRounding
  AfterRounding
}
```

`BeforeRounding` calls a result tiny when the adjusted exponent of the exact
result is below $e_{\min}$; `AfterRounding` uses the result rounded to $p$
digits with unbounded exponent. A tiny result raises `subnormal`, and also
`underflow` when it is inexact.

The two rules differ only for results just below $10^{e_{\min}}$. With
$p = 3$, $e_{\min} = 0$ and `HalfEven`, `plus_ctx` of `0.9951` returns the
subnormal-grid rounding `1.00`, but its rounding to three digits is
$0.995 < 1$, so under `AfterRounding` it is tiny and raises `underflow`,
`subnormal` and `inexact`; `0.99951` rounds to $1.00$ at three digits and
raises only `inexact`.

## Status flags

### `DecimalFlags`

`DecimalFlags` records the conditions raised by one operation.

```mbti
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
```

| Field | Raised when |
| --- | --- |
| `inexact` | the result differs from the exact result |
| `rounded` | digits were discarded, even if they were all zero |
| `lost_digits` | a subset-mode operand longer than $p$ lost non-zero digits |
| `invalid_operation` | the operation is invalid (signaling NaN, $\infty-\infty$, $0\times\infty$, bad quantize, domain error) |
| `division_by_zero` | an exact infinite result from finite operands ($x/0$, $\ln 0$, $\log_2 0$, $\log_{10} 0$, $\operatorname{logb} 0$, $\operatorname{log1p}(-1)$) |
| `overflow` | the rounded result's adjusted exponent exceeds $e_{\max}$ |
| `underflow` | the result is tiny and inexact |
| `subnormal` | the result is tiny |
| `clamped` | the exponent was changed to fit (fold-down or zero exponent clamp) |
| `conversion_syntax` | text could not be parsed |
| `division_impossible` | an integer quotient needs more than $p$ digits |
| `division_undefined` | $0/0$ (raised together with `invalid_operation`) |
| `invalid_context` | the context is outside the range an elementary function supports |

Fields are public and read-only; the flags never accumulate implicitly.

### `DecimalFlags::new`, `combine`, `contains`, `has_error`

These functions create, merge and query flag sets.

```mbti
pub fn DecimalFlags::new() -> Self
pub fn DecimalFlags::combine(Self, Self) -> Self
pub fn DecimalFlags::contains(Self, DecimalSignal) -> Bool
pub fn DecimalFlags::has_error(Self) -> Bool
```

`new` has every flag clear. `combine` is the field-wise OR, so it is
associative, commutative and idempotent with `new()` as identity. `contains`
reads the flag named by a `DecimalSignal`. `has_error` is

$$
\text{invalid\_operation} \lor \text{conversion\_syntax} \lor
\text{division\_by\_zero} \lor \text{division\_undefined} \lor
\text{division\_impossible} \lor \text{invalid\_context},
$$

the conditions for which IEEE 754 or General Decimal Arithmetic delivers no
meaningful number (`conversion_syntax`, `division_impossible` and
`division_undefined` are conditions of the Invalid operation signal). A failed
`from_string_ctx`, which raises only `conversion_syntax`, therefore counts as
an error. `has_error` does not include `overflow`, `underflow`, `inexact`,
`rounded`, `subnormal`, `clamped` or `lost_digits`.

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
  inspect(all.contains(@decimal.DecimalSignal::Inexact), content="true")
  inspect(all.division_by_zero, content="true")
  inspect(all.has_error(), content="true")
}
```

### `DecimalSignal`

`DecimalSignal` names one flag of `DecimalFlags`.

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
}
```

Each constructor corresponds to the field of the same name.

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

The result precision is $\max(p_a, p_b)$ of the operand precision fields.

- `add`/`sub` compute the exact sum, round it half-even to that precision and
  return the reduced cohort member: `1.20 + 3.40` is `4.6`.
- `mul` returns the exact product with exponent $q_a+q_b$ and is **not
  rounded**: `1.25 * 2.50` is `3.1250`, and the coefficient may be longer
  than the precision field.
- `div` rounds the quotient half-even to that precision and reduces it. The
  quotient is computed with a few guard digits and rounded with `ZeroFiveUp`
  first, which makes the second rounding equal to one correct rounding:
  `15 / 83294` at five digits is `0.00018009`.
- `neg` flips the sign bit of every value, including zeros and NaNs.

Special values: a NaN operand gives a quiet NaN with the first NaN's sign and
payload; $\infty-\infty$, $0\times\infty$, $0/0$ and $\infty/\infty$ give a
positive NaN; $x/0$ gives a signed infinity; finite$/\infty$ gives $+0$. No
context exponent range is applied, only the limits of the representation
described under [`parse`](#decimalparse-from_string): a result whose
adjusted exponent would exceed $2^{31}-1$ is a signed infinity, and a result
that needs an exponent below $-2^{31}$ is rounded half-even to that exponent,
possibly to a signed zero, as IEEE 754 §7.4 and §7.5 prescribe for that
range (`1E+1500000000 * 1E+1500000000` is `inf`, `123E-2147483640 * 1E-10`
is `1E-2147483648`). Exact cancellation gives $+0$; the sum of two
negative zeros is $-0$.

```moonbit
///|
test "decimal plain operators" {
  let a = @decimal.Decimal::from_string("1.20").unwrap()
  let b = @decimal.Decimal::from_string("3.40").unwrap()
  inspect(a + b, content="4.6")
  inspect(a * b, content="4.0800")
  inspect(a - b, content="-2.2")
  inspect(-a, content="-1.20")
  inspect(@decimal.Decimal::one() / @decimal.Decimal::from_int(8), content="0.125")
}
```

### `Decimal::abs`, `copy`, `copy_abs`, `copy_negate`, `copy_sign`

These functions change only the sign bit.

```mbti
pub fn Decimal::abs(Self) -> Self
pub fn Decimal::copy(Self) -> Self
pub fn Decimal::copy_abs(Self) -> Self
pub fn Decimal::copy_negate(Self) -> Self
pub fn Decimal::copy_sign(Self, Self) -> Self
```

They never round, never raise flags and keep exponent, payload and NaN kind.
`abs` and `copy_abs` clear the sign, `copy_negate` flips it, `copy_sign`
copies the sign bit of the second operand and `copy` returns its argument.

### `Decimal::normalized`, `trim`, `with_precision`

These functions change the cohort member or the precision field.

```mbti
pub fn Decimal::normalized(Self) -> Self
pub fn Decimal::trim(Self) -> Self
pub fn Decimal::with_precision(Self, Int, @arithmetic.RoundingMode) -> Self
```

`normalized` returns the reduced member of the cohort (all trailing zeros
removed, zero with exponent 0), rounding half-even to the value's own
precision if the coefficient is longer. `trim` removes the trailing zeros of the
fractional part: with a negative exponent it stops at exponent 0 (`12.300`
becomes `12.3`, `1200` stays `1200`), with a positive exponent it removes all
of them (`1.20E+3` becomes `1.2E+3`); a zero gets exponent 0.
`with_precision(p, mode)` rounds a finite value to `p` digits with `mode`,
reduces it and stores `p` as the precision field; special values only get the
new precision field. All three are flag-free.

### `Decimal::div_checked`, `sqrt`

These functions divide and take a square root, reporting domain errors as
`Result`.

```mbti
pub fn Decimal::div_checked(Self, Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn Decimal::sqrt(Self) -> Result[Self, @arithmetic.ArithmeticError]
```

`div_checked(a, b)` is `div_ctx` under `DecimalContext::new(precision=max(p_a,
p_b))`; it returns `Err(division_by_zero)` for $x/0$ and `Err(domain_error)`
for an invalid division. `sqrt` is `sqrt_ctx` under
`DecimalContext::new(precision=p)` and returns `Err(domain_error)` for a
negative non-zero operand. Both are correctly rounded half-even.

## Context arithmetic

Every function in this group takes a `DecimalContext` and returns
`(result, flags)`. The result is the exact result rounded once to the context
precision with the context's decimal rounding mode, then checked against the
exponent range: overflow gives the rounding-mode-dependent result of the
[design page](../design/decimal.md#overflow), a result whose exact magnitude
is below $10^{e_{\min}}$ is rounded directly to the subnormal grid
$10^{E_{\text{tiny}}}$ (a normal result is rounded only to $p$ digits, even
when its exact exponent is below $E_{\text{tiny}}$), and with `clamp` large
exponents are folded down to $e_{\max}-p+1$. When the exact result fits, the exponent is the
*preferred exponent* of the operation, so cohorts carry information. NaN
operands propagate as a quiet NaN with the first NaN's sign and payload (the
payload is cut to its low $p$ digits, even with `clamp`, where
`from_string_ctx` and the interchange encodings allow only $p-1$); any
signaling NaN operand raises `invalid_operation`.

Near the underflow threshold the single rounding matters. In decimal32, the
exact product `3.000001E-45 * 1.500001E-45` is $4.5000045000015\cdot
10^{-90}$, a normal number whose exact exponent is below $E_{\text{tiny}} =
-101$; it is rounded once to seven digits, `4.500005E-90`. The quotient
`1 / 1.9999999999998E+101` is $5.0000000000005\cdot 10^{-102}$, which is
subnormal; its guarded quotient is rounded once to the grid $10^{-101}$,
giving `1E-101` with `inexact`, `underflow` and `subnormal`.

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
with `invalid_operation`; $0/0$ gives NaN with `invalid_operation` and
`division_undefined`; $x/0$ for finite non-zero $x$ gives a signed infinity
with `division_by_zero`; finite$/\infty$ gives a signed zero with exponent
$E_{\text{tiny}}$ and `clamped`.

When one operand of `add_ctx` or `sub_ctx` lies entirely below every
rounding boundary of the sum, an extended context does not align it digit by
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
  inspect(flags.underflow && flags.subnormal, content="true")
  let down = @decimal.DecimalContext::new(precision=7, decimal_rounding=@decimal.DecimalRoundingMode::Down)
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
  inspect(flags.inexact, content="true")
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
$\infty \cdot y + (-\infty)$ with opposite signs is invalid. In a
non-extended context the operation returns NaN with `invalid_operation`.

### `Decimal::sqrt_ctx`

`sqrt_ctx` returns the correctly rounded square root.

```mbti
pub fn Decimal::sqrt_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
```

The preferred exponent is $\lfloor q/2 \rfloor$. An exact root is returned in
the member closest to it (`sqrt(0.0400)` is `0.20`); an inexact root has $p$
digits and raises `inexact` and
`rounded`. $\sqrt{-0} = -0$; a negative non-zero operand or $-\infty$ gives
NaN with `invalid_operation`; $\sqrt{+\infty}=+\infty$.

### `Decimal::plus_ctx`, `minus_ctx`, `abs_ctx`, `apply_ctx`

These functions round one operand to the context.

```mbti
pub fn Decimal::plus_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::minus_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::abs_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::apply_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
```

`apply_ctx` rounds a value to the context (precision, exponent range,
clamping) and quiets a NaN, keeping the sign of zero. `plus_ctx` is $0 + x$
and `minus_ctx` is $0 - x$, the zero taking the operand's exponent, so a zero
result follows the sign rule of addition: it is $-0$ under `Floor`
(`TowardNegative`)
when the zeros have opposite signs (`plus_ctx(-0)`, `minus_ctx(+0)`) and $+0$
otherwise. `abs_ctx` is $|x|$ rounded to the context; signaling NaNs raise
`invalid_operation`.

### `Decimal::divide_integer`, `remainder`, `remainder_near`, `remainder_ctx`

These functions compute integer quotients and remainders.

```mbti
pub fn Decimal::divide_integer(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::remainder(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::remainder_near(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::remainder_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
```

`divide_integer(x, y)` is $\operatorname{trunc}(x/y)$ with preferred exponent 0. When
the integer quotient needs more than $p$ digits, the result is NaN with
`division_impossible` and `invalid_operation`. `remainder(x, y)` is
$x - y\cdot\operatorname{trunc}(x/y)$ with the sign of $x$ (General Decimal
Arithmetic *remainder*). `remainder_near(x, y)` is $x - y\cdot n$ where $n$ is
$x/y$ rounded to the nearest integer, ties to even (IEEE 754 *remainder*);
`remainder_ctx` is the same operation. The remainder is exact when it fits,
with preferred exponent $\min(q_x, q_y)$, and its sign is that of $x$ when it
is zero. $x \operatorname{rem} 0$ and $\infty \operatorname{rem} y$ are invalid
($0 \operatorname{rem} 0$ also raises `division_undefined`);
$x \operatorname{rem} \infty = x$.

In an extended clamped context, a zero `divide_integer` result has its exponent folded
down to $e_{\max}-p+1$ when exponent 0 is larger; the `clamped` flag is
raised. Its sign is still the sign of the exact quotient.

For example, `-8.95E-6` divided by `2.40E-5` with precision 9, $e_{\min}=0$,
$e_{\max}=1$ and clamp enabled gives `-0E-7` with `clamped`. Folding a zero's
exponent preserves its value and does not raise `rounded` or `inexact`.
`remainder` applies exponent bounds to its own result; clamping its internal
integer quotient does not contribute a `clamped` flag to the remainder.

```moonbit
///|
test "decimal remainders" {
  let ctx = @decimal.DecimalContext::decimal64()
  let d = fn(s : String) { @decimal.Decimal::from_string(s).unwrap() }
  inspect(d("10").divide_integer(d("3"), ctx).0, content="3")
  inspect(d("10").remainder(d("3"), ctx).0, content="1")
  inspect(d("10").remainder_near(d("6"), ctx).0, content="-2")
  inspect(d("-7.5").remainder(d("2"), ctx).0, content="-1.5")
}
```

## Quantum and exponent operations

### `Decimal::quantize`

`quantize` rounds a value to the exponent of another value.

```mbti
pub fn Decimal::quantize(Self, Self, DecimalContext) -> (Self, DecimalFlags)
```

`x.quantize(y, ctx)` returns the value of `x` with exponent $q_y$, rounding
with the context's mode when digits are dropped (raising `rounded`, and
`inexact` if they were non-zero). The result is NaN with `invalid_operation`
when the target exponent is outside $[E_{\text{tiny}}, e_{\max}]$, when the
resulting coefficient needs more than $p$ digits, when its adjusted exponent
exceeds $e_{\max}$, or when exactly one operand is infinite. Two infinities
give the infinity of `x`. The quantum never silently changes to another
value of the cohort range: if the result cannot have exponent $q_y$ the
operation fails. The one exception is `clamp`: a target exponent in
$(e_{\max}-p+1,\ e_{\max}]$ is accepted and the result is then folded down
to exponent $e_{\max}-p+1$ with `clamped`, like every other result
(`1E+384` quantized to `1E+384` in decimal64 is `1.000000000000000E+384`).

```moonbit
///|
test "decimal quantize to cents" {
  let ctx = @decimal.DecimalContext::decimal64()
  let d = fn(s : String) { @decimal.Decimal::from_string(s).unwrap() }
  let (cents, flags) = d("12.3456").quantize(d("0.01"), ctx)
  inspect(cents, content="12.35")
  inspect(flags.inexact, content="true")
  let small = @decimal.DecimalContext::new(precision=3, e_min=-99, e_max=99)
  let (bad, bad_flags) = d("999.9").quantize(d("0.1"), small)
  inspect(bad.is_nan(), content="true")
  inspect(bad_flags.invalid_operation, content="true")
}
```

### `Decimal::rescale`

`rescale` sets the exponent to an integer operand.

```mbti
pub fn Decimal::rescale(Self, Self, DecimalContext) -> (Self, DecimalFlags)
```

`x.rescale(n, ctx)` is `quantize` with target exponent $n$, where $n$ must be
a finite integer; any other second operand gives NaN with
`invalid_operation`.

### `Decimal::same_quantum`

`same_quantum` tests whether two values have the same exponent.

```mbti
pub fn Decimal::same_quantum(Self, Self) -> Bool
```

Two finite values have the same quantum when their exponents are equal; two
infinities, and two NaNs, always have the same quantum; any other pair does
not. It never raises flags.

### `Decimal::reduce_ctx`, `normalize_ctx`

These functions round a value to the context and remove trailing zeros.

```mbti
pub fn Decimal::reduce_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::normalize_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
```

`reduce_ctx` applies the context, then removes trailing zeros while the
exponent stays at most $e_{\max}$ (with `clamp`, at most $e_{\max}-p+1$). A
zero becomes a zero with exponent 0 (keeping its sign in an extended
context). `normalize_ctx` is the same operation under its older General
Decimal Arithmetic name.

### `Decimal::to_integral_exact`, `to_integral_value`

These functions round to an integer.

```mbti
pub fn Decimal::to_integral_exact(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::to_integral_value(Self, DecimalContext) -> (Self, DecimalFlags)
```

A finite value with exponent $\ge 0$ is already an integer and is returned
unchanged, even when it is longer than $p$ digits (a `clamp` context still
folds its exponent down). A value with negative exponent is quantized to
exponent 0 with the context's rounding mode, at a working precision of
$\max(p, \text{its digit count})$, so the integral part is never rounded to
$p$ digits: at precision 3, `12345.6` gives `12346`. `to_integral_exact`
reports `rounded`/`inexact` when digits are dropped; `to_integral_value`
returns the same value with those two flags cleared. In a subset context the
operand is first rounded to $p$ digits, with `lost_digits`. Infinities are
returned unchanged; NaNs are quieted.

IEEE 754 §5.9 defines roundToIntegral for an operand in the context's format
(at most $p$ digits), and for such an operand these are its results. An
operand longer than $p$ digits is not a value of the format, so §5.9 does not
cover it and the result is implementation-defined. The behaviour described
above for such operands (a longer integer unchanged, a longer fraction
quantized at $\max(p, \text{its digit count})$ digits) is the package's
chosen, GDA-style behaviour: General Decimal Arithmetic rounds to an integral
value at the operand's own precision.

### `Decimal::scaleb_ctx`, `logb_ctx`

These functions scale by a power of ten and extract the adjusted exponent.

```mbti
pub fn Decimal::scaleb_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::logb_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
```

`x.scaleb_ctx(n, ctx)` returns $x \cdot 10^{n}$ by adding $n$ to the exponent;
$n$ must be a finite integer with exponent 0 and
$|n| \le 2(e_{\max}+p)$, otherwise the result is NaN with
`invalid_operation`. The scaled value is then rounded once like every other
context result: a coefficient longer than $p$ digits is rounded to $p$ digits
(`12345678901234567890` scaled by 0 in decimal64 is
`1.234567890123457E+19` with `inexact`), a subnormal result is rounded to
$E_{\text{tiny}}$, overflow gives the rounding-mode-dependent result with
`overflow`, `inexact` and `rounded` (in decimal64 with `TowardZero`, `9E+384`
scaled by 1 is `9.999999999999999E+384`), and `clamp` folds large exponents
down. A zero keeps its sign and has its exponent clamped into the range with
`clamped`: `0` scaled by 700 in decimal64 is `0E+369`.

```moonbit
///|
test "decimal scaleb rounds like other context results" {
  let c64 = @decimal.DecimalContext::decimal64()
  let d = fn(s : String) { @decimal.Decimal::from_string(s).unwrap() }
  let toward_zero = c64.with_rounding(@def.RoundingMode::TowardZero)
  inspect(d("9E+384").scaleb_ctx(d("1"), toward_zero).0, content="9.999999999999999E+384")
  inspect(d("9E+384").scaleb_ctx(d("1"), c64).0, content="inf")
  let (zero, flags) = d("0").scaleb_ctx(d("700"), c64)
  inspect(zero, content="0E+369")
  inspect(flags.clamped, content="true")
  inspect(d("12345678901234567890").scaleb_ctx(d("0"), c64).0, content="1.234567890123457E+19")
}
```

`logb_ctx(x)` returns the adjusted exponent $\lfloor\log_{10}|x|\rfloor$ as an
integer `Decimal`; $\operatorname{logb}(\pm 0) = -\infty$ with
`division_by_zero` and $\operatorname{logb}(\pm\infty) = +\infty$.

## Adjacent values

### `Decimal::next_plus`, `next_minus`, `next_toward`

These functions return the neighbouring representable values.

```mbti
pub fn Decimal::next_plus(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::next_minus(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::next_toward(Self, Self, DecimalContext) -> (Self, DecimalFlags)
```

`next_plus` is the smallest representable value greater than `x` in the
context and `next_minus` the largest smaller one, including subnormals down to
$10^{E_{\text{tiny}}}$ and the largest finite value
$(10^{p}-1)\,10^{e_{\max}-p+1}$; `next_plus(-∞)` is the most negative finite
value. They raise no flags for finite results. `next_toward(x, y)` moves `x`
one step toward `y`; when $x = y$ it returns `x` with the sign of `y` for
zeros. A step of `next_toward` that ends in an infinity raises `overflow`,
`inexact` and `rounded`; one that ends subnormal or zero raises `underflow`,
`subnormal`, `inexact` and `rounded`.

```moonbit
///|
test "decimal neighbours of one" {
  let ctx = @decimal.DecimalContext::decimal64()
  let one = @decimal.Decimal::one()
  inspect(one.next_plus(ctx).0, content="1.000000000000001")
  inspect(one.next_minus(ctx).0, content="0.9999999999999999")
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
[`compare_checked`](#decimalcompare_checked), `compare_ctx` or the NaN
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

### `Decimal::compare_ctx`, `compare_signal_ctx`

These functions are the General Decimal Arithmetic comparisons with a decimal
result.

```mbti
pub fn Decimal::compare_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::compare_signal_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
```

They return the `Decimal` $-1$, 0 or 1, or a quiet NaN when an operand is a
NaN. `compare_ctx` raises `invalid_operation` only for a signaling NaN;
`compare_signal_ctx` raises it for every NaN (IEEE *signaling* comparison).

### `Decimal::compare_total`, `compare_total_magnitude`, `compare_total_ctx`, `compare_total_magnitude_ctx`

These functions implement the IEEE 754 `totalOrder` predicate as a three-way
comparison.

```mbti
pub fn Decimal::compare_total(Self, Self) -> Int
pub fn Decimal::compare_total_magnitude(Self, Self) -> Int
pub fn Decimal::compare_total_ctx(Self, Self, DecimalContext) -> (Int, DecimalFlags)
pub fn Decimal::compare_total_magnitude_ctx(Self, Self, DecimalContext) -> (Int, DecimalFlags)
```

`compare_total` orders every representation:

$$
-\text{NaN} < -\text{sNaN} < -\infty < \text{negative finite} < -0 < +0 <
\text{positive finite} < +\infty < +\text{sNaN} < +\text{NaN}.
$$

Equal finite values are ordered by exponent: for positive values the smaller
exponent comes first ($1.00 < 1.0$), for negative values the larger. NaNs of
the same sign and kind are ordered by payload (reversed for negative NaNs).
It returns 0 only for identical representations.
`compare_total_magnitude` compares the absolute values. The `_ctx` forms
first prepare the operands for the context (which only matters in subset
mode) and return the flags of that step.

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

### `Decimal::min_ctx`, `max_ctx`, `min_mag_ctx`, `max_mag_ctx`

These functions are the General Decimal Arithmetic `min`, `max`, `min-magnitude`
and `max-magnitude` operations.

```mbti
pub fn Decimal::min_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::max_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::min_mag_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::max_mag_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
```

A quiet NaN loses to a number; two NaNs give the first quieted; a signaling
NaN gives a quiet NaN with `invalid_operation`. Numerically equal operands are
separated by `compare_total` (so `min_ctx(1.0, 1.00)` is `1.00` and
`min_ctx(-0, 0)` is `-0`). The selected value is rounded to the context.

### `Decimal::minimum_ctx`, `maximum_ctx`, `minimum_number_ctx`, `maximum_number_ctx`, `minimum_magnitude_ctx`, `maximum_magnitude_ctx`, `minimum_number_magnitude_ctx`, `maximum_number_magnitude_ctx`, `minimum_mag_ctx`, `maximum_mag_ctx`, `minimum_number_mag_ctx`, `maximum_number_mag_ctx`

These twelve functions are the IEEE 754-2019 §9.6 minimum and maximum
operations.

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

`minimum_ctx` and `maximum_ctx` propagate NaN: any NaN operand gives a quiet
NaN. The `_number_` variants return the number when exactly one operand is a
NaN. In both, a signaling NaN raises `invalid_operation`. The magnitude
variants compare $|x|$ and $|y|$ and fall back to the signed order on equal
magnitudes. Ties are broken by `compare_total`, so $-0 < +0$. The `_mag_`
spellings are aliases of the `_magnitude_` ones. The selected value is rounded
to the context.

## Digit-wise operations

### `Decimal::logical_and`, `logical_or`, `logical_xor`, `logical_invert`

These functions apply Boolean operations digit by digit to *logical
operands*.

```mbti
pub fn Decimal::logical_and(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::logical_or(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::logical_xor(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::logical_invert(Self, DecimalContext) -> (Self, DecimalFlags)
```

A logical operand is a finite, non-negative value with exponent 0 whose
coefficient digits are all 0 or 1, such as `1101`. The operation works on the
low $p$ digits and returns a logical operand; any other operand gives NaN
with `invalid_operation`.

### `Decimal::shift_ctx`, `rotate_ctx`

These functions shift or rotate the coefficient digits.

```mbti
pub fn Decimal::shift_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::rotate_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
```

The coefficient is viewed as $p$ digits. A positive count $n$ moves digits
toward the most significant end, a negative one toward the least significant
end; `shift_ctx` fills with zeros and drops digits that leave the window,
`rotate_ctx` wraps them around. The exponent and sign are kept. The count
must be an integer with exponent 0 and $|n| \le p$; otherwise the result is
NaN with `invalid_operation`. Infinities are returned unchanged.

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
`power_ctx(4, 1.5)` $= 8$ is returned exactly by the enclosure itself. Integer
powers are not certified: [`power_ctx`](#decimalpower_ctx-pown_ctx-rootn_ctx-hypot_ctx-try_power_ctx-try_pown_ctx-try_rootn_ctx-try_hypot_ctx)
rounds them once, in an extended context, from the exact power or from
refined directed bounds.

> [!NOTE]
> **Exact non-integral powers.** A power whose exact value is a representable
> decimal but not a binary fraction is decided in decimal before the loop, so
> in decimal64 `power_ctx(0.0016, 0.25)` is `0.2`, `power_ctx(32, 0.2)` is `2`
> and `power_ctx(0.04, 1.5)` is `0.008`, all without `inexact` and in every
> rounding mode. The exponent is reduced to $p/q$ in lowest terms — a decimal
> exponent is $c \cdot 10^{-k}$, so $q$ keeps only the twos and fives the
> coefficient cannot cancel — and the power is exact exactly when $x$ itself
> is a perfect $q$-th power. The root is taken first and then raised to $p$,
> so the test never handles a number longer than the result. It finds every
> exact result of at most `precision + 1` digits, the only ones that sit on a
> rounding boundary; a longer exact value lies inside its rounding cell and the
> enclosure rounds it like any other.

All of them except `power_ctx`/`pown_ctx` with an integral exponent or the
exponent $0.5$ return NaN with `invalid_context` when $p > 999\,999$,
$e_{\max} > 999\,999$ or $e_{\min} < -999\,999$, or when a finite operand has
more than 999,999 digits or an adjusted exponent beyond about $\pm 10^6$.
Integral powers and $x^{0.5}$ work in any context up to $\pm 999\,999\,999$,
so `power_ctx(2, 3)` is `8` under `DecimalContext::new()` while
`power_ctx(2, 1.5)` and `exp2_ctx(2)` are NaN with `invalid_context`.

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
$\log_{10}$ of $\pm 0$ are $-\infty$ with `division_by_zero` in an extended
context, as IEEE 754-2019 §9.2.1 requires and as `log2_ctx`, `log1p_ctx` and
`logb_ctx` do (General Decimal Arithmetic, which
[`decimal_gda`](decimal_gda.md) follows, raises no condition here; a subset
context makes a zero operand invalid); of
$+\infty$ are $+\infty$, of a negative value or $-\infty$ are NaN with
`invalid_operation`; $\ln 1 = 0$, and $\log_{10}$ of a power of ten is the
exact integer exponent. Arguments so large or small that $e^x$ certainly
overflows or underflows are decided without evaluation.

### `Decimal::power_ctx`, `pown_ctx`, `rootn_ctx`, `hypot_ctx`, `try_power_ctx`, `try_pown_ctx`, `try_rootn_ctx`, `try_hypot_ctx`

These functions compute powers, roots and the Euclidean norm.

```mbti
pub fn Decimal::power_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::pown_ctx(Self, Int, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::rootn_ctx(Self, Int, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::hypot_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::try_power_ctx(Self, Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::try_pown_ctx(Self, Int, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::try_rootn_ctx(Self, Int, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::try_hypot_ctx(Self, Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
```

`power_ctx(x, y)` is $x^y$ with the General Decimal Arithmetic special cases:
an integral exponent gives the exact power when it fits in $p$ digits and
otherwise, in an extended context, the correctly rounded power (in decimal32,
`power_ctx(3.339434, 3)` is `37.24077`; the exact cube is
$37.240765000\ldots$); $x^{0.5}$ is `sqrt_ctx`; a positive base with a
non-integer exponent is certified; a negative base with a non-integer exponent
is invalid; $0^0$ is invalid in an extended context; $0^{-n}$ is $\pm\infty$.
A context that is not extended keeps the General Decimal Arithmetic
square-and-multiply with $p + \operatorname{digits}(n) + 2$ working digits,
whose error is below one unit in the last place. `pown_ctx(x, n)` is
`power_ctx` with the integer `n` converted exactly, so $(-1)^{12345679}$ is
$-1$ at any precision. `rootn_ctx(x, n)` is
$x^{1/n}$ for integer $n \ne 0$; an even root of a negative value and $n=0$
are invalid, and $\operatorname{rootn}(\pm 0, n<0)$ is an infinity with
`division_by_zero`; an exactly representable root is returned exactly
(`rootn_ctx(0.008, 3)` is `0.2` with no flag). `hypot_ctx(x, y)` is
$\sqrt{x^2+y^2}$; it is $+\infty$ if either operand is infinite, even if the
other is a quiet NaN, and an exactly representable norm, or $|x|$ when $y$ is
zero, is returned exactly (`hypot_ctx(0.3, 0.4)` is `0.5`).

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
| `exp2`, `exp10` | none | none | integer argument (via `power_ctx`), $\pm 0 \mapsto 1$, $-\infty \mapsto 0$, $+\infty \mapsto +\infty$ |
| `expm1` | none | none | $\pm0 \mapsto \pm0$, $-\infty\mapsto -1$, $+\infty \mapsto +\infty$ |
| `log2` | $x<0$, $-\infty$ | $\pm 0 \mapsto -\infty$ | $1 \mapsto 0$, exact binary powers ($0.125 \mapsto -3$), $+\infty \mapsto +\infty$ |
| `log1p` | $x<-1$, $-\infty$ | $-1 \mapsto -\infty$ | $\pm0 \mapsto \pm0$, $+\infty \mapsto +\infty$ |
| `sin`, `cos`, `tan` | $\pm\infty$ | none | $\sin(\pm 0)=\pm 0$, $\tan(\pm 0)=\pm 0$, $\cos 0 = 1$ |
| `sinpi`, `cospi`, `tanpi` | $\pm\infty$ | `tanpi` at odd half-integers | integers, half-integers, `tanpi` at odd quarter-integers ($\pm 1$) |
| `asin`, `acos` | $\lvert x\rvert > 1$, $\pm\infty$ | none | $\operatorname{asin}(\pm0)=\pm0$, $\operatorname{acos}(1) = 0$ |
| `atan` | none | none | $\pm 0$; $\pm\infty \mapsto \pm\pi/2$ (certified) |
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
  inspect(flags.inexact, content="false")
  inspect(d("0.008").rootn_ctx(3, c64).0, content="0.2")
  let c32 = @decimal.DecimalContext::decimal32()
  inspect(d("3.339434").power_ctx(d("3"), c32).0, content="37.24077")
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
  let down = ctx.with_rounding(@def.RoundingMode::TowardZero)
  inspect(d("2").ln_ctx(down).0, content="0.6931471805599453")
  match d("2").try_ln_ctx(@decimal.DecimalContext::new()) {
    Ok((value, flags)) => {
      inspect(value.is_nan(), content="true")
      inspect(flags.invalid_context, content="true")
    }
    Err(_) => fail("not a certification failure")
  }
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
pub fn Decimal::from_interchange_hex(String, DecimalInterchangeFormat) -> Self?
pub fn Decimal::from_interchange_hex_with_encoding(String, DecimalInterchangeFormat, DecimalInterchangeEncoding) -> Self?
```

The text may have surrounding ASCII whitespace and a leading `#`; it must have
exactly the format's number of hex digits, in either case, or the result is
`None`. Decoding is exact and keeps the exponent, the sign of zero, the NaN
kind and payload. Non-canonical encodings decode to the value IEEE 754
assigns them: a non-canonical DPD declet to its digits, a BID coefficient
$\ge 10^{p}$ to zero, an out-of-range BID NaN payload to 0; the unused
exponent bits of infinities and NaNs are ignored. The result has the format's
precision.

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
pub fn DecimalInterchange::from_hex(String, DecimalInterchangeFormat) -> Self?
pub fn DecimalInterchange::from_hex_with_encoding(String, DecimalInterchangeFormat, DecimalInterchangeEncoding) -> Self?
pub fn DecimalInterchange::from_decimal(Decimal, DecimalInterchangeFormat) -> (Self, DecimalFlags)
pub fn DecimalInterchange::from_decimal_with_encoding(Decimal, DecimalInterchangeFormat, DecimalInterchangeEncoding) -> (Self, DecimalFlags)
```

`from_hex` stores the bits unchanged (text rules as in
`from_interchange_hex`). `from_decimal` encodes like `to_interchange_hex` and
returns the same flags. The forms without an encoding use `DPD`.

### `DecimalInterchange::to_decimal`, `to_decimal_ctx`

These functions decode the stored bits.

```mbti
pub fn DecimalInterchange::to_decimal(Self) -> Decimal
pub fn DecimalInterchange::to_decimal_ctx(Self) -> (Decimal, DecimalFlags)
```

Decoding is exact. `to_decimal_ctx` additionally raises `subnormal` when the
decoded value is subnormal in the format; no other flag is possible.

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
`from_natural` and `from_integer` are documented under
[construction](#decimalfrom_natural-from_integer).

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
otherwise `Ok` with diagnostics `inexact`, `rounded`, `overflow`,
`underflow`, `subnormal` and `clamped` copied from the flags. Because the
converted context has the default exponent range, `exp_contextual` without
explicit `e_min`/`e_max` fails with `domain_error` (`invalid_context`).

`zero_contextual` and `one_contextual` have the context precision.
`epsilon_contextual` is $10^{1-p}$ (`next_plus(1) - 1`).
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

`parse_checked(s, ctx)` is `Decimal::parse(s, precision=ctx.precision)`.
`DivChecked::div_checked(x, y, ctx)` is `div_ctx` under the converted context
with `Err(division_by_zero)` and `Err(domain_error)` as in
[`div_checked`](#decimaldiv_checked-sqrt). `sqrt_checked` is `sqrt_ctx` under
the converted context and fails for negative operands. `pow_nat_checked` and
`pow_int_checked` are `power_ctx` with the integer exponent converted to a
`Decimal` exactly (with at least ten digits, which hold every accepted
exponent), so at precision 7 `(-1).pow_int_checked(12345679, ctx)` is `-1`;
they return `Err(division_by_zero)` for a
zero base with a negative exponent, `Err(domain_error)` for an invalid power,
and `pow_nat_checked` returns `Err(unsupported)` for exponents above
999,999,999. `CompareChecked` is [`compare_checked`](#decimalcompare_checked).

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
is greater than every number. Use `compare_total` to tell representations
apart.

### Derived equality: `DecimalContext::equal`, `DecimalContext::not_equal`, `DecimalFlags::equal`, `DecimalFlags::not_equal`, `DecimalRoundingMode::equal`, `DecimalRoundingMode::not_equal`, `DecimalTininessDetection::equal`, `DecimalTininessDetection::not_equal`, `DecimalSignal::equal`, `DecimalSignal::not_equal`, `DecimalInterchangeFormat::equal`, `DecimalInterchangeFormat::not_equal`, `DecimalInterchangeEncoding::equal`, `DecimalInterchangeEncoding::not_equal`

These are the derived `Eq` methods of the context, flag and enum types.

```mbti
pub fn DecimalContext::equal(Self, Self) -> Bool
pub fn DecimalContext::not_equal(Self, Self) -> Bool
pub fn DecimalFlags::equal(Self, Self) -> Bool
pub fn DecimalFlags::not_equal(Self, Self) -> Bool
pub fn DecimalRoundingMode::equal(Self, Self) -> Bool
pub fn DecimalRoundingMode::not_equal(Self, Self) -> Bool
pub fn DecimalTininessDetection::equal(Self, Self) -> Bool
pub fn DecimalTininessDetection::not_equal(Self, Self) -> Bool
pub fn DecimalSignal::equal(Self, Self) -> Bool
pub fn DecimalSignal::not_equal(Self, Self) -> Bool
pub fn DecimalInterchangeFormat::equal(Self, Self) -> Bool
pub fn DecimalInterchangeFormat::not_equal(Self, Self) -> Bool
pub fn DecimalInterchangeEncoding::equal(Self, Self) -> Bool
pub fn DecimalInterchangeEncoding::not_equal(Self, Self) -> Bool
```

Contexts compare field by field (precision, both rounding fields, exponent
limits, clamp, extended, tininess); flag sets compare all thirteen fields.
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

// Errors

// Types and methods
pub struct Decimal {
  // private fields
} derive(@debug.Debug)
pub fn Decimal::abs(Self) -> Self
pub fn Decimal::abs_contextual(Self, @arithmetic.ArithmeticContext) -> Result[@arithmetic.ArithmeticOutcome[Self], @arithmetic.ArithmeticError]
pub fn Decimal::abs_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::acos_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::acosh_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::add(Self, Self) -> Self
pub fn Decimal::add_contextual(Self, Self, @arithmetic.ArithmeticContext) -> Result[@arithmetic.ArithmeticOutcome[Self], @arithmetic.ArithmeticError]
pub fn Decimal::add_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::apply_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::asin_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::asinh_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::atan2_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::atan_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::atanh_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
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
pub fn Decimal::cos_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::cosh_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::cospi_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::div(Self, Self) -> Self
pub fn Decimal::div_checked(Self, Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn Decimal::div_contextual(Self, Self, @arithmetic.ArithmeticContext) -> Result[@arithmetic.ArithmeticOutcome[Self], @arithmetic.ArithmeticError]
pub fn Decimal::div_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::divide_integer(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::epsilon_contextual(@arithmetic.ArithmeticContext) -> Self
pub fn Decimal::equal(Self, Self) -> Bool
pub fn Decimal::exp10_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::exp2_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::exp_contextual(Self, @arithmetic.ArithmeticContext) -> Result[@arithmetic.ArithmeticOutcome[Self], @arithmetic.ArithmeticError]
pub fn Decimal::exp_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::expm1_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::exponent10(Self) -> Int
pub fn Decimal::fma_ctx(Self, Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::from_bigint(@bigint.BigInt, precision? : Int) -> Self
pub fn Decimal::from_bin_float(@bin_float.BinFloat, precision? : Int) -> Self
pub fn Decimal::from_double(Double, precision? : Int) -> Self
pub fn Decimal::from_float(Float, precision? : Int) -> Self
pub fn Decimal::from_int(Int, precision? : Int) -> Self
pub fn Decimal::from_integer(@bigint.BigInt) -> Self
pub fn Decimal::from_interchange_hex(String, DecimalInterchangeFormat) -> Self?
pub fn Decimal::from_interchange_hex_with_encoding(String, DecimalInterchangeFormat, DecimalInterchangeEncoding) -> Self?
pub fn Decimal::from_natural(@bigint.BigInt) -> Self
pub fn Decimal::from_string(String, precision? : Int) -> Self?
pub fn Decimal::from_string_ctx(String, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::get_payload(Self) -> @bigint.BigInt
pub fn Decimal::hypot_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
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
pub fn Decimal::log1p_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::log2_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
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
pub fn Decimal::pown_ctx(Self, Int, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::precision(Self) -> Int
pub fn Decimal::quantize(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::quantum(Self) -> Int
pub fn Decimal::quiet_nan(payload? : @bigint.BigInt, negative? : Bool, precision? : Int) -> Self
pub fn Decimal::reduce_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::remainder(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::remainder_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::remainder_near(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::rescale(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::rootn_ctx(Self, Int, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::rotate_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::same_quantum(Self, Self) -> Bool
pub fn Decimal::scaleb_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::set_payload(Self, @bigint.BigInt) -> Self
pub fn Decimal::set_payload_signaling(Self, @bigint.BigInt) -> Self
pub fn Decimal::shift_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::sign(Self) -> @def.Sign
pub fn Decimal::signaling_nan(payload? : @bigint.BigInt, negative? : Bool, precision? : Int) -> Self
pub fn Decimal::sin_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::sinh_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::sinpi_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::sqrt(Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn Decimal::sqrt_checked(Self, @arithmetic.ArithmeticContext) -> Result[Self, @arithmetic.ArithmeticError]
pub fn Decimal::sqrt_contextual(Self, @arithmetic.ArithmeticContext) -> Result[@arithmetic.ArithmeticOutcome[Self], @arithmetic.ArithmeticError]
pub fn Decimal::sqrt_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::sub(Self, Self) -> Self
pub fn Decimal::sub_contextual(Self, Self, @arithmetic.ArithmeticContext) -> Result[@arithmetic.ArithmeticOutcome[Self], @arithmetic.ArithmeticError]
pub fn Decimal::sub_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::tan_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::tanh_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::tanpi_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::to_bin_float(Self, precision? : Int, mode? : @arithmetic.RoundingMode) -> @bin_float.BinFloat
pub fn Decimal::to_eng_string(String, DecimalContext) -> (String, DecimalFlags)
pub fn Decimal::to_integral_exact(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::to_integral_value(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::to_interchange_hex(Self, DecimalInterchangeFormat) -> (String, DecimalFlags)
pub fn Decimal::to_interchange_hex_with_encoding(Self, DecimalInterchangeFormat, DecimalInterchangeEncoding) -> (String, DecimalFlags)
pub fn Decimal::to_repr(Self) -> @debug.Repr
pub fn Decimal::to_sci_string(String, DecimalContext) -> (String, DecimalFlags)
pub fn Decimal::to_string(Self) -> String
pub fn Decimal::trim(Self) -> Self
pub fn Decimal::try_acos_ctx(Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::try_acosh_ctx(Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::try_asin_ctx(Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::try_asinh_ctx(Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::try_atan2_ctx(Self, Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::try_atan_ctx(Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::try_atanh_ctx(Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::try_cos_ctx(Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::try_cosh_ctx(Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::try_cospi_ctx(Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::try_exp10_ctx(Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::try_exp2_ctx(Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::try_exp_ctx(Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::try_expm1_ctx(Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::try_hypot_ctx(Self, Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::try_ln_ctx(Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::try_log10_ctx(Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::try_log1p_ctx(Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::try_log2_ctx(Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::try_power_ctx(Self, Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::try_pown_ctx(Self, Int, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::try_rootn_ctx(Self, Int, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::try_sin_ctx(Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::try_sinh_ctx(Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::try_sinpi_ctx(Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::try_tan_ctx(Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::try_tanh_ctx(Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
pub fn Decimal::try_tanpi_ctx(Self, DecimalContext) -> Result[(Self, DecimalFlags), @arithmetic.ArithmeticError]
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
pub fn DecimalContext::ieee754(Self) -> Self
pub fn DecimalContext::is754version2019(Self) -> Bool
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
pub fn DecimalInterchange::from_hex(String, DecimalInterchangeFormat) -> Self?
pub fn DecimalInterchange::from_hex_with_encoding(String, DecimalInterchangeFormat, DecimalInterchangeEncoding) -> Self?
pub fn DecimalInterchange::is_canonical(Self) -> Bool
pub fn DecimalInterchange::to_decimal(Self) -> Decimal
pub fn DecimalInterchange::to_decimal_ctx(Self) -> (Decimal, DecimalFlags)
pub fn DecimalInterchange::to_hex(Self) -> String

pub(all) enum DecimalInterchangeEncoding {
  DPD
  BID
} derive(Eq)
pub fn DecimalInterchangeEncoding::equal(Self, Self) -> Bool
pub fn DecimalInterchangeEncoding::not_equal(Self, Self) -> Bool

pub(all) enum DecimalInterchangeFormat {
  Decimal32
  Decimal64
  Decimal128
} derive(Eq)
pub fn DecimalInterchangeFormat::context(Self) -> DecimalContext
pub fn DecimalInterchangeFormat::equal(Self, Self) -> Bool
pub fn DecimalInterchangeFormat::not_equal(Self, Self) -> Bool

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

// Type aliases

// Traits
```
<!-- generated-api-end -->
