# Numeric semantics

This guide fixes the numerical vocabulary that every other page of the manual
uses. It separates five things that are easy to blur: the **stored
representation** of a value, the **exact value** an operation defines, the
**rounded result** a context returns, the **status** that rounding raised, and
the **enclosure** an interval guarantees. Each section states the definition,
derives the property the library relies on, and shows it with a runnable
example.

## Values and representations

A finite binary value is a signed integer coefficient times a power of two, and
a finite decimal value is the same with a power of ten:

$$
x = (-1)^s \cdot c \cdot 2^{e}
\qquad\text{or}\qquad
x = (-1)^s \cdot c \cdot 10^{q},
\qquad s \in \{0, 1\},\ c \in \mathbb{N},\ e, q \in \mathbb{Z}.
$$

The triple $(s, c, e)$ is the **representation**; the real number $x$ is the
**value**. Several representations denote one value: $3 \cdot 2^{-1}$ and
$6 \cdot 2^{-2}$ are both $1.5$. The two radices treat this redundancy
differently.

- `BinFloat` removes trailing factors of two from the coefficient whenever it
  builds a finite value, so a finite non-zero `BinFloat` has an odd
  coefficient. Its printed form `c p e` shows that canonical pair.
- `Decimal` (in `decimal` and `decimal_gda`) keeps the exponent it was given.
  The exponent $q$ is the **quantum**, and the set of representations of one
  value is its **cohort**: `12.3400`, `12.340` and `12.34` are one value and
  three cohort members.

Every value also carries a **precision** $p$: the number of radix digits a
rounded result may use. Precision is metadata and a rounding bound; it is not a
claim that every stored digit is significant, and it never changes the radix.

```moonbit
///|
test "representation versus value" {
  // 6 * 2^-2 is stored as the canonical 3 * 2^-1.
  let three_halves = @bin_float.BinFloat::make(
    @bin_float.BinCoeff::from_uint64(6UL),
    -2,
    53,
  )
  inspect(three_halves, content="3p-1")
  inspect(three_halves.to_shortest_string(), content="1.5")
  // A decimal keeps its quantum until it is normalized explicitly.
  let price = @decimal.Decimal::from_string("12.3400").unwrap()
  inspect(price.quantum(), content="-4")
  inspect(price.normalized(), content="12.34")
  inspect(price.normalized().quantum(), content="-2")
  inspect(price.compare(price.normalized()), content="0")
  inspect(price.same_quantum(price.normalized()), content="false")
}
```

Special values sit beside the finite ones: signed infinities $\pm\infty$, and
NaN ("not a number") in a quiet and a signaling flavour, each with a sign and a
payload. `classify` reports `Finite`, `Infinity` or `NaN`; `@def.is_finite`,
`@def.is_nan`, `@def.is_infinite` and `@def.is_zero` work for every type that
implements `@def.Floating`.

## Exact value and rounded result

Every arithmetic operation $\circ$ first defines an **exact value**: the real
number $x \circ y$ (or $\sqrt{x}$, $\exp x$, …) computed with no error. A format
can rarely hold it, so a context maps it to a representable **rounded result**

$$
\operatorname{fl}(x \circ y) = \operatorname{rnd}(x \circ y),
$$

where $\operatorname{rnd}$ is the rounding function of the context. An
operation is **correctly rounded** when its result is exactly this: the exact
value rounded once. Every arithmetic operation, square root, fused
multiply-add, remainder, conversion and parse in `floating` is correctly
rounded; the elementary functions are correctly rounded too, by certified
refinement (see [architecture](./architecture.md)).

Rounding once matters. The fused multiply-add `fma_ctx` rounds $xy + z$ once,
while `mul_ctx` followed by `add_ctx` rounds twice. With $x = \operatorname{fl}(0.1)$
in binary64, $10x$ is not exactly $1$, and only the fused form sees the
difference:

```moonbit
///|
test "one rounding versus two" {
  let ctx = @bin_float.BinaryContext::binary64()
  let tenth = @bin_float.BinFloat::from_double(0.1)
  let ten = @bin_float.BinFloat::from_int(10)
  let minus_one = @bin_float.BinFloat::from_int(-1)
  let (fused, _) = tenth.fma_ctx(ten, minus_one, ctx)
  inspect(fused, content="1p-54")
  let (product, _) = tenth.mul_ctx(ten, ctx)
  inspect(product, content="1p0")
}
```

The fused result $2^{-54}$ is the exact error of the rounded product: the
product $10 \cdot \operatorname{fl}(0.1)$ exceeds $1$ by $2^{-54}$, and
`mul_ctx` rounds that excess away.

## Rounding functions

Let $\mathbb{F}$ be the set of values a context can represent, extended with
$\pm\infty$. For a real $x$ the **directed** roundings are

$$
\begin{aligned}
\operatorname{RD}(x) &= \max\{\, y \in \mathbb{F} : y \le x \,\}, &
\operatorname{RU}(x) &= \min\{\, y \in \mathbb{F} : y \ge x \,\}, \\
\operatorname{RZ}(x) &= \begin{cases} \operatorname{RD}(x) & x \ge 0 \\ \operatorname{RU}(x) & x < 0 \end{cases}, &
\operatorname{RA}(x) &= \begin{cases} \operatorname{RU}(x) & x \ge 0 \\ \operatorname{RD}(x) & x < 0 \end{cases},
\end{aligned}
$$

and the **nearest** roundings pick whichever of $\operatorname{RD}(x)$ and
$\operatorname{RU}(x)$ is closer to $x$, breaking a tie (an $x$ exactly halfway)
either toward the candidate with an even last digit ($\operatorname{RN}_{\text{even}}$)
or toward the one of larger magnitude ($\operatorname{RN}_{\text{away}}$).[^ieee-rounding]
Every rounding function is monotone ($x \le y \Rightarrow \operatorname{rnd}(x) \le \operatorname{rnd}(y)$)
and fixes $\mathbb{F}$ ($\operatorname{rnd}(y) = y$ for $y \in \mathbb{F}$); these two facts are what
interval arithmetic and the certified elementary functions rely on.

[^ieee-rounding]: IEEE 754-2019, clause 4.3, defines roundTiesToEven,
    roundTiesToAway, roundTowardPositive, roundTowardNegative and
    roundTowardZero. Round-away-from-zero and the decimal "05up" mode come from
    the General Decimal Arithmetic specification (Cowlishaw).

Each domain names these functions in its own enum:

| Function | `BinaryRoundingMode` | `@lf_arith.RoundingMode` | `DecimalRoundingMode` / `GdaRoundingMode` |
| --- | --- | --- | --- |
| $\operatorname{RN}_{\text{even}}$ | `RoundTiesToEven` | `ToNearestEven` | `HalfEven` |
| $\operatorname{RN}_{\text{away}}$ | `RoundTiesToAway` | — | `HalfUp` |
| nearest, ties toward zero | — | — | `HalfDown` |
| $\operatorname{RZ}$ | `RoundTowardZero` | `TowardZero` | `Down` |
| $\operatorname{RU}$ | `RoundTowardPositive` | `TowardPositive` | `Ceiling` |
| $\operatorname{RD}$ | `RoundTowardNegative` | `TowardNegative` | `Floor` |
| $\operatorname{RA}$ | `RoundAwayFromZero` | `AwayFromZero` | `Up` |
| toward zero, then away if the last kept digit is 0 or 5 | — | — | `ZeroFiveUp` |

`with_precision(p, mode)` applies one of these functions to a value at a new
precision. Binary $0.1$ is $0.0001100110011\ldots_2$; at five bits the
truncated form is $11001_2 \cdot 2^{-8}$ and the next bit is a one followed by
non-zero bits, so nearest rounding goes up:

```moonbit
///|
test "rounding 0.1 to five bits" {
  let tenth = @bin_float.BinFloat::from_double(0.1)
  inspect(tenth.with_precision(5, @lf_arith.ToNearestEven), content="13p-7")
  inspect(tenth.with_precision(5, @lf_arith.TowardZero), content="25p-8")
}
```

### Rounding to an integer

Rounding to an integral value is the same construction with
$\mathbb{F} = \mathbb{Z}$. `BinFloat` offers the fixed-direction forms `floor`
($\operatorname{RD}$), `ceil` ($\operatorname{RU}$), `trunc`
($\operatorname{RZ}$), `round` (nearest, ties away) and `round_ties_even`
(nearest, ties to even); `to_integral_value_ctx` uses the context's direction
and is quiet, and `to_integral_exact_ctx` additionally raises *inexact* when the
value changes. The integer conversions `to_int_ctx`, `to_int64_ctx`,
`to_uint_ctx` and `to_uint64_ctx` round the same way and return `None` with
*invalid* for NaN, infinities and out-of-range results. The result keeps the
sign of zero: $\lceil -0.3 \rceil = -0$.

```moonbit
///|
test "rounding to integers" {
  let x = @bin_float.BinFloat::from_double(2.5)
  inspect(x.round(), content="3p0")
  inspect(x.round_ties_even(), content="1p1")
  inspect(x.floor(), content="1p1")
  inspect(@bin_float.BinFloat::from_double(-0.3).ceil(), content="-0")
  let (n, flags) = x.to_int_ctx(
    @bin_float.BinaryContext::binary64(),
    exact=true,
  )
  inspect(n == Some(2), content="true")
  inspect(flags.inexact(), content="true")
}
```

## Ulp and unit roundoff

For a radix $\beta$, a precision $p$ and a non-zero $x$ with
$\beta^{e} \le |x| < \beta^{e+1}$, the **unit in the last place** is the spacing
of the $p$-digit values around $x$:

$$
\operatorname{ulp}(x) = \beta^{\,e - p + 1}.
$$

`BinFloat::ulp` computes it for $\beta = 2$ at the value's own precision with an
unbounded exponent range; for zero it returns $2^{1-p}$, the ulp of $1$. In a
bounded context the spacing stops shrinking at the subnormal threshold
(next section), so there the ulp of a tiny value is $\beta^{\,e_{\min} - p + 1}$.

The **unit roundoff** $u$ bounds the relative error of one rounding. Take
$x$ in range with $\beta^{e} \le |x| < \beta^{e+1}$. Both neighbours
$\operatorname{RD}(x)$ and $\operatorname{RU}(x)$ lie in the same binade (or
one of them is $\pm\beta^{e+1}$), one ulp apart, so

$$
\begin{aligned}
|\operatorname{RN}(x) - x| &\le \tfrac{1}{2}\operatorname{ulp}(x)
  = \tfrac{1}{2}\beta^{\,e-p+1}
  = \tfrac{1}{2}\beta^{1-p} \cdot \beta^{e}
  \le \tfrac{1}{2}\beta^{1-p}\,|x|, \\
|\operatorname{RD}(x) - x|,\ |\operatorname{RU}(x) - x| &< \operatorname{ulp}(x) \le \beta^{1-p}\,|x|.
\end{aligned}
$$

Hence the **standard model** of floating-point arithmetic:[^higham]

$$
\operatorname{fl}(x \circ y) = (x \circ y)(1 + \delta), \qquad
|\delta| \le u =
\begin{cases}
\tfrac{1}{2}\beta^{1-p} & \text{nearest rounding}, \\
\beta^{1-p} & \text{directed rounding},
\end{cases}
$$

valid whenever the exact value is neither in the overflow range nor below the
normal range. Below the normal range the error is absolute instead: with
subnormals, $\operatorname{fl}(x \circ y) = (x \circ y)(1+\delta) + \eta$ with
$\delta\eta = 0$, $|\eta| \le \tfrac{1}{2}\beta^{\,e_{\min}-p+1}$ for nearest
rounding. For binary64 ($p = 53$) $u = 2^{-53}$; for decimal64 ($p = 16$)
$u = \tfrac{1}{2}\cdot 10^{-15}$.

[^higham]: N. J. Higham, *Accuracy and Stability of Numerical Algorithms*,
    2nd ed., SIAM 2002, §2.2. The underflow form with $\eta$ is Theorem 2.3
    there; Goldberg, "What every computer scientist should know about
    floating-point arithmetic", ACM Computing Surveys 23(1), 1991, gives the
    same derivation for the binary case.

```moonbit
///|
test "ulp of one tenth" {
  let ctx = @bin_float.BinaryContext::binary64()
  let (tenth, _) = @bin_float.BinFloat::from_string_ctx("0.1", ctx).unwrap()
  inspect(tenth, content="3602879701896397p-55")
  // 0.1 lies in [2^-4, 2^-3), so ulp = 2^(-4 - 53 + 1).
  inspect(tenth.ulp(), content="1p-56")
  let (third, flags) = @bin_float.BinFloat::from_int(1).div_ctx(
    @bin_float.BinFloat::from_int(3),
    ctx,
  )
  inspect(third.to_shortest_string(), content="0.3333333333333333")
  inspect(flags.inexact(), content="true")
  let (digits, _) = third.to_decimal_string_ctx(20, ctx)
  inspect(digits, content="3.3333333333333331483e-1")
}
```

## Contexts: precision, exponent range and tininess

A context fixes $\mathbb{F}$ and the rounding function. No package reads an
ambient rounding mode; the context is an ordinary immutable argument.

- `BinaryContext` holds the precision $p$ (bits), a `BinaryRoundingMode`,
  optional exponent bounds $e_{\min}, e_{\max}$ for the **leading bit**, and a
  `TininessDetection`. Normal values satisfy $2^{e_{\min}} \le |x| \le (2 - 2^{1-p})\,2^{e_{\max}}$;
  below $2^{e_{\min}}$ the **subnormal** values keep the fixed spacing
  $2^{\,e_{\min}-p+1}$ (gradual underflow). `binary16`, `binary32`, `binary64`
  and `binary128` are the IEEE interchange presets. `unbounded(p)` and a
  missing bound use the implementation range
  $[\texttt{binary\_implementation\_e\_min}, \texttt{binary\_implementation\_e\_max}] = [1 - 2^{30},\ 2^{30} - 1]$,
  and every precision is capped at $\texttt{binary\_precision\_max} = 2^{28}$
  bits. A result beyond the implementation range is classified (overflow to
  infinity or the largest finite value, underflow to zero or the smallest
  subnormal, by rounding direction), never stored with a saturated exponent.
- The plain binary operators (`add`, `sub`, `mul`, `div`, `+`, `-`, `*`, `/`)
  round to nearest-even at the larger operand precision in that unbounded
  context and discard the flags.
- `DecimalContext` (IEEE) and `GdaContext` (GDA) hold the precision in digits,
  the rounding mode, $e_{\min}$ and $e_{\max}$ for the **adjusted exponent**
  $q + (\text{digits of } c) - 1$, and a `clamp` switch. The smallest exponent
  a subnormal may use is $E_{\text{tiny}} = e_{\min} - p + 1$. With `clamp`
  set, a result whose exponent exceeds $e_{\max} - p + 1$ is padded with zeros
  and raises *clamped*, as the interchange formats require. `decimal64`, for
  example, has $p = 16$, $e_{\max} = 384$, $e_{\min} = -383$.
- **Tininess** decides when a tiny result counts as an underflow: *before
  rounding* compares the exact value with $\beta^{e_{\min}}$, *after rounding*
  compares the value rounded as if the exponent range were unbounded. IEEE 754
  allows either for binary formats; GDA always detects before rounding.

## Flags, errors and enclosures

`floating` reports trouble through four channels that are not
interchangeable:

| Channel | Carried by | A value is returned? | Meaning |
| --- | --- | --- | --- |
| status flag | `BinaryFlags`, `DecimalFlags`, `BallFlags` beside the result | yes, the IEEE-defined one | a condition occurred while producing a defined result |
| GDA status and trap | `GdaOutcome`, `GdaContext::status` | yes, also when trapped | sticky conditions; an enabled trap marks the outcome `Trapped` |
| checked error | `Result[_, ArithmeticError]`, `*Result` wrappers | no | the requested scalar cannot be produced under the checked contract |
| enclosure | `BallFloat`, `BallFloatDecorated` | yes, a set | every possible exact result lies in the returned interval |

### IEEE flags

The five IEEE exceptions[^ieee-exceptions] are reported as booleans on
`BinaryFlags` and as `DecimalSignal` members of `DecimalFlags`:

- *invalid operation*: no useful real result exists ($\infty - \infty$,
  $0 \cdot \infty$, $\sqrt{-1}$, any operation on a signaling NaN); the result is
  a quiet NaN.
- *division by zero*: an exact infinite result from finite operands
  ($1/{-0} = -\infty$, $\log 0 = -\infty$).
- *overflow*: the rounded result with an unbounded exponent would exceed the
  largest finite value; the result is $\pm\infty$ or the largest finite value
  by direction, and *inexact* is raised too.
- *underflow*: the result is tiny (by the context's tininess rule) and inexact.
- *inexact*: the rounded result differs from the exact value.

Decimal adds the GDA conditions *rounded* (digits were discarded, even zeros),
*clamped*, *subnormal*, *conversion syntax*, *division impossible*, *division
undefined*, *invalid context* and *lost digits*. Flags never replace the value.
To accumulate them over several steps, `combine` them yourself or use
`decimal_checked`, which keeps the latest (`raised`) and the accumulated
(`flags`) sets.

[^ieee-exceptions]: IEEE 754-2019, clause 7. The default exception handling
    returns the values listed here and raises the status flag; `floating`
    implements exactly this default and never alters control flow.

```moonbit
///|
test "flags report conditions beside a defined value" {
  let ctx = @bin_float.BinaryContext::binary64()
  let one = @bin_float.BinFloat::from_int(1)
  let (pole, pole_flags) = one.div_ctx(
    @bin_float.BinFloat::negative_zero(),
    ctx,
  )
  inspect(pole, content="-inf")
  inspect(pole_flags.division_by_zero(), content="true")
  let (huge, huge_flags) = @bin_float.BinFloat::from_double(1.0e308).mul_ctx(
    @bin_float.BinFloat::from_int(10),
    ctx,
  )
  inspect(huge, content="inf")
  inspect(huge_flags.overflow() && huge_flags.inexact(), content="true")
  let inf = @bin_float.BinFloat::inf(@def.Positive)
  let (undefined, invalid) = inf.sub_ctx(inf, ctx)
  inspect(@def.is_nan(undefined), content="true")
  inspect(invalid.invalid_operation(), content="true")
}
```

### GDA status and traps

`decimal_gda` follows the General Decimal Arithmetic model. Each operation
returns a `GdaOutcome` that holds the defined result, the **next context** and
the **raised** flags of this operation. The next context's `status()` is the
sticky union of everything raised so far. When a raised condition is enabled in
the context's trap set the outcome is `Trapped(signal, value, context, raised)`
instead of `Completed(value, context, raised)`; the defined result is still
there. If several enabled conditions are raised at once the trapped signal is
the first in this precedence: invalid operation, division by zero, division
undefined, division impossible, invalid context, conversion syntax, overflow,
underflow, subnormal, inexact, rounded, clamped, lost digits.

```moonbit
///|
test "a GDA trap keeps the defined result" {
  let ctx = @decimal_gda.GdaContext::decimal64().trap(
    @decimal_gda.DivisionByZero,
  )
  let one = @decimal_gda.Decimal::from_string("1").unwrap()
  let zero = @decimal_gda.Decimal::from_string("0").unwrap()
  match @decimal_gda.divide(one, zero, ctx) {
    Trapped(signal, value, next, _) => {
      inspect(signal == @decimal_gda.DivisionByZero, content="true")
      inspect(value, content="inf")
      inspect(next.status().division_by_zero, content="true")
    }
    Completed(_, _, _) => fail("an enabled trap must fire")
  }
}
```

### Checked errors

An `ArithmeticError` (re-exported by `def`) has a kind: `DivisionByZero`,
`ParseError`, `DomainError`, `FormatError`, `UnsupportedOperation`,
`UnorderedComparison` or `CertificationFailure`. It is used where the checked
contract has no value to return: `div_checked` by zero, `sqrt` of a negative
number, `compare_checked` with a NaN, a malformed literal. `BinFloatResult` and
`BallFloatResult` keep the first error and skip the remaining steps.

The elementary functions have both forms. A `try_*_ctx` function returns
`Err` with a `CertificationFailure` detail if the certified refinement cannot
decide the rounding within its budget. The non-`try` forms never abort: the
binary ones return a quiet NaN with *invalid operation*, and the decimal and
GDA ones return their invalid result so that flags and traps apply as usual.

### Enclosures

A `BallFloat` denotes a closed set of reals $X = [\underline{x}, \overline{x}]$
with binary endpoints, or one of the special sets **Empty** ($\varnothing$) and
**Entire** ($\mathbb{R}$). An interval extension $F$ of a function $f$ must
satisfy the **inclusion property**

$$
\{\, f(x) : x \in X \,\} \subseteq F(X),
$$

which outward rounding guarantees: the exact lower endpoint is rounded with
$\operatorname{RD}$ and the exact upper endpoint with $\operatorname{RU}$, so by
$\operatorname{RD}(a) \le a$ and $b \le \operatorname{RU}(b)$ the stored
interval contains the exact one.[^interval] A wide enclosure is a correct
result; tightness is a quality, not a contract. Division by an interval that
contains zero can return Entire.

`BallFloatDecorated` adds an IEEE 1788 **decoration** describing what is known
about $f$ on $X$: `Com` (defined, continuous and bounded on a bounded $X$),
`Dac` (defined and continuous), `Def` (defined), `Trv` (nothing known) and
`Ill` (the interval is NaI, "not an interval"). NaI is distinct from Empty.
Decorations are not scalar flags; `BallFlags` reports precision and range
events of a `BallContext`.

[^interval]: R. E. Moore, R. B. Kearfott and M. J. Cloud, *Introduction to
    Interval Analysis*, SIAM 2009, ch. 3; IEEE 1788-2015, clauses 10–11 for
    the set and decoration model.

```moonbit
///|
test "an enclosure contains every exact result" {
  let one = @ball_float.BallFloat::from_int(1, precision=53)
  let three = @ball_float.BallFloat::from_int(3, precision=53)
  let third = one.div(three)
  inspect(third.contains(@bin_float.BinFloat::from_double(1.0 / 3.0)), content="true")
  let around_zero = @ball_float.BallFloat::from_bounds(
    @bin_float.BinFloat::from_int(-1),
    @bin_float.BinFloat::from_int(1),
  )
  inspect(one.div(around_zero).is_entire(), content="true")
  let partly_defined = @ball_float.BallFloatDecorated::new(
    @ball_float.BallFloat::from_bounds(
      @bin_float.BinFloat::from_int(-1),
      @bin_float.BinFloat::from_int(4),
    ),
  )
  inspect(partly_defined.decoration(), content="com")
  inspect(partly_defined.sqrt_interval().decoration(), content="trv")
}
```

## Quantum and cohorts

For decimal values the cohort member an operation returns is part of its
contract. When the exact result fits in the precision, IEEE 754 and GDA choose
the member with the **ideal exponent**:[^ideal]

$$
\begin{aligned}
q(x + y) = q(x - y) &= \min(q_x, q_y), \\
q(x \cdot y) &= q_x + q_y, \\
q(x / y) &= q_x - q_y \quad (\text{when the quotient is exact}),
\end{aligned}
$$

and when the result must be rounded, the member with the largest coefficient
that fits. Parsing preserves the quantum of the literal. `quantize(x, y)`
rounds $x$ to the quantum of $y$; `reduce_ctx` (GDA `reduce`) and
`normalized()` strip trailing zeros. Numeric comparison sees only the value;
`same_quantum` and the total orders `compare_total` (IEEE) and
`compare_total` (GDA) also see the cohort.

[^ideal]: IEEE 754-2019, clause 5.2 and table 5.1; Cowlishaw, *General Decimal
    Arithmetic Specification* 1.70, "Arithmetic operations".

```moonbit
///|
test "decimal results keep the ideal exponent" {
  let ctx = @decimal.DecimalContext::decimal64()
  let a = @decimal.Decimal::from_string("1.20").unwrap()
  let b = @decimal.Decimal::from_string("1.3").unwrap()
  inspect(a.add_ctx(b, ctx).0, content="2.50")
  inspect(a.mul_ctx(b, ctx).0, content="1.560")
  let c = @decimal.Decimal::from_string("2.400").unwrap()
  let d = @decimal.Decimal::from_string("1.2").unwrap()
  inspect(c.div_ctx(d, ctx).0, content="2.00")
  let (cents, flags) = @decimal.Decimal::from_string("2.345")
    .unwrap()
    .quantize(@decimal.Decimal::from_string("0.01").unwrap(), ctx)
  inspect(cents, content="2.34")
  inspect(flags.contains(@decimal.Inexact), content="true")
  let x = @decimal.Decimal::from_string("12.30").unwrap()
  let y = @decimal.Decimal::from_string("12.3").unwrap()
  inspect(x.compare(y), content="0")
  inspect(x.compare_total(y), content="-1")
}
```

## Signed zero and NaN

### Zero

Zero carries a sign so that $1/{+0} = +\infty$ and $1/{-0} = -\infty$ keep the
direction of an underflow. The rules follow IEEE 754-2019 clause 6.3:

- a product or quotient has the exclusive-or of the operand signs;
- an exact zero sum of operands with opposite signs, or $x - x$, is $+0$ under
  every rounding direction except $\operatorname{RD}$, where it is $-0$;
- $\sqrt{-0} = -0$, and rounding to an integer keeps the sign
  ($\lceil -0.3 \rceil = -0$);
- numeric comparison treats $-0$ and $+0$ as equal.

### NaN

A **quiet NaN** propagates through arithmetic silently; a **signaling NaN**
raises *invalid operation* when an operation consumes it and is quieted in
the result. A NaN carries a sign and an integer payload (`nan_payload`); an
operation with NaN operands returns a quiet NaN derived from the first of
them.

```moonbit
///|
test "zero and NaN rules" {
  let ctx = @bin_float.BinaryContext::binary64()
  let down = @bin_float.BinaryContext::binary64(rounding=RoundTowardNegative)
  let one = @bin_float.BinFloat::from_int(1)
  inspect(one.sub_ctx(one, ctx).0.is_negative_zero(), content="false")
  inspect(one.sub_ctx(one, down).0.is_negative_zero(), content="true")
  inspect(@bin_float.BinFloat::negative_zero().sqrt_ctx(ctx).0, content="-0")
  let (quieted, flags) = @bin_float.BinFloat::signaling_nan().add_ctx(one, ctx)
  inspect(quieted.is_quiet_nan(), content="true")
  inspect(flags.invalid_operation(), content="true")
}
```

### Comparison

IEEE comparison has four outcomes: less, equal, greater and **unordered**,
the last whenever an operand is NaN. Several APIs expose different orders, and
choosing the right one matters:

| API | Order | NaN | $-0$ vs $+0$ |
| --- | --- | --- | --- |
| `compare_quiet`, `less_quiet`, `equal_quiet`, … (`bin_float`) | IEEE partial order, `@def.PartialOrder` | `Unordered`; *invalid* only for a signaling NaN | equal |
| `compare_signaling`, `less_signaling`, … (`bin_float`) | IEEE partial order | `Unordered`; *invalid* for any NaN | equal |
| `compare_checked` | numeric order | `Err` with `UnorderedComparison` | equal |
| `compare`, `<`, `<=`, sorting (`Compare`) | total preorder | every NaN equals every NaN and is above every number | equal |
| `total_order`, `total_order_compare`, `total_order_mag` (`bin_float`), `compare_total` (decimal) | IEEE `totalOrder` on representations | ordered by sign, kind and payload | $-0 < +0$ |

`compare` orders NaN above every number so that `Compare` is a total preorder
and sorting never fails; it never aborts. Use the quiet predicates or
`compare_checked` when NaN must be treated as unordered.

Equality follows the type. `Decimal`'s `==` is numeric for finite values
(`-0 == 0.00`) and treats two NaNs as equal. `BinFloat` and `BallFloat` derive
`Eq`, so their `==` compares representations, including the sign of zero and
the precision: `-0 == +0` is false there, while `compare` returns `0`. Use
`compare(...) == 0` or `equal_quiet` for numeric equality of binary values.

```moonbit
///|
test "choosing a comparison" {
  let nan = @bin_float.BinFloat::nan()
  let one = @bin_float.BinFloat::from_int(1)
  inspect(nan.compare(one), content="1")
  inspect(nan > @bin_float.BinFloat::inf(@def.Positive), content="true")
  inspect(nan.compare_checked(one) is Err(_), content="true")
  let (order, flags) = nan.compare_quiet(one)
  inspect(order == @def.Unordered, content="true")
  inspect(flags.invalid_operation(), content="false")
  let neg_zero = @bin_float.BinFloat::negative_zero()
  let pos_zero = @bin_float.BinFloat::zero()
  inspect(neg_zero.compare(pos_zero), content="0")
  inspect(neg_zero.total_order_compare(pos_zero), content="-1")
  inspect(neg_zero == pos_zero, content="false")
}
```

## Conversion between radices

Every binary fraction has a finite decimal expansion, because
$2^{-k} = 5^{k} \cdot 10^{-k}$; most decimal fractions have no finite binary
expansion, because $10^{-k} = 2^{-k}5^{-k}$ and $5^{-k}$ is not dyadic. So
decimal-to-binary conversion is usually inexact and binary-to-decimal
conversion is exact but may need many digits. `BinFloat::from_string_ctx`
(IEEE convertFromDecimalCharacter) and `to_decimal_string_ctx`
(convertToDecimalCharacter) are both correctly rounded for every precision and
exponent; `to_shortest_string` prints the fewest digits that read back to the
same value, which is how `0.1 + 0.2` shows its rounding error.

Interchange conversion is narrower: `BinaryInterchange` (binary16/32/64/128)
and the decimal32/64/128 DPD and BID encodings fix field widths, exponent
bounds and special encodings. `semantic` projects values of every package to
exact rationals, so it can tell that decimal $0.1$ and binary $\operatorname{fl}(0.1)$
are different numbers; the projection deliberately drops precision, quantum,
signed zero, payloads, decorations and flags.

```moonbit
///|
test "decimal 0.1 is not binary 0.1" {
  let sum = @bin_float.BinFloat::from_double(0.1).add(
    @bin_float.BinFloat::from_double(0.2),
  )
  inspect(sum.to_shortest_string(), content="0.30000000000000004")
  let decimal_tenth = @semantic.SemanticScalar::from_decimal(
    @decimal.Decimal::from_string("0.1").unwrap(),
  )
  let binary_tenth = @semantic.SemanticScalar::from_bin_float(
    @bin_float.BinFloat::from_double(0.1),
  )
  inspect(decimal_tenth == binary_tenth, content="false")
  let decimal_half = @semantic.SemanticScalar::from_decimal(
    @decimal.Decimal::from_string("0.500").unwrap(),
  )
  let binary_half = @semantic.SemanticScalar::from_bin_float(
    @bin_float.BinFloat::from_double(0.5),
  )
  inspect(decimal_half == binary_half, content="true")
}
```

## Decision checklist

Before choosing an API, answer:

1. Is the result a scalar value, a representation, or a set of reals?
2. Must the radix, precision, exponent range or quantum stay observable?
3. Does the caller need per-operation flags, sticky GDA status and traps, or a
   short-circuiting checked error?
4. Can NaN, an infinity, a signed zero, Empty, Entire or NaI occur?
5. Is the numeric order enough, or is the IEEE partial order, a total order or
   a set relation required?
6. Is the conversion arbitrary-precision or a fixed interchange format?
7. Which pinned conformance evidence supports the claim? See
   [verification](./verification.md).
