# internal tutorial

The goal of this page is to show maintainers of the numeric cores how the
helpers of `internal` combine: rounding a decimal coefficient to a precision,
parsing a decimal literal into exact parts, and writing a refinement loop that
certifies a rounded result. The package is internal to `Luna-Flow/floating`,
so only code inside the module can use it; the examples on this page compile
inside the module.

| I want to | Use |
| --- | --- |
| round a quotient of integers with a rounding mode | [`round_positive_div`](#quick-start) |
| round a decimal coefficient to `p` digits | [`digits10`, `pow10`, `round_positive_div`](#round-a-decimal-coefficient-to-p-digits) |
| split a decimal literal into sign, digits and exponent | [`split_decimal_string`](#parse-a-literal-into-exact-parts) |
| drop trailing zeros while keeping the value | [`trim_trailing_decimal_zeros`](#parse-a-literal-into-exact-parts) |
| enclose a ratio between two dyadics | [`certified_dyadic_fraction`](#certify-a-rounding-with-a-refinement-loop) |
| bound a Ziv refinement loop | [`CertifiedRefinementBudget`](#certify-a-rounding-with-a-refinement-loop) |
| report that certification gave up | [`certified_failure`](#certify-a-rounding-with-a-refinement-loop) |

## Quick start

There is nothing to install: the package ships inside `Luna-Flow/floating`
and is visible only to its packages. Run its tests from the repository:

```bash
sh tools/run_moon_clean_exec.sh test src/internal --target native
```

In a package of the module, import it in `moon.pkg`:

```moonbit nocheck
import {
  "Luna-Flow/floating/internal",
}
```

Round $2/3$ to an integer in two modes:

```moonbit
///|
test "rounded quotient" {
  let mode_even = @lf_arith.RoundingMode::ToNearestEven
  let mode_down = @lf_arith.RoundingMode::TowardZero
  inspect(@internal.round_positive_div(2N, 3N, false, mode_even), content="1")
  inspect(@internal.round_positive_div(2N, 3N, false, mode_down), content="0")
}
```

`round_positive_div` takes the magnitude $n/d$ and the sign of the true
quotient separately, because directed modes round magnitudes differently for
negative numbers.

## Everyday tasks

### Round a decimal coefficient to `p` digits

A decimal $c \cdot 10^{q}$ with more than $p$ digits is rounded by dividing
the coefficient by $10^{k}$, $k = \text{digits}(c) - p$, and adding $k$ to the
exponent:

```moonbit
///|
fn round_coefficient(
  coefficient : BigInt,
  exponent : Int,
  precision : Int,
  mode : @lf_arith.RoundingMode,
) -> (BigInt, Int) {
  let negative = coefficient < 0N
  let magnitude = @internal.abs_bigint(coefficient)
  let excess = @internal.digits10(magnitude) - precision
  if excess <= 0 {
    return (coefficient, exponent)
  }
  let rounded = @internal.round_positive_div(
    magnitude,
    @internal.pow10(excess),
    negative,
    mode,
  )
  (if negative { -rounded } else { rounded }, exponent + excess)
}

///|
test "round to three digits" {
  let (c, q) = round_coefficient(-123456N, -3, 3, @lf_arith.RoundingMode::TowardNegative)
  inspect(c, content="-124")
  inspect(q, content="0")
}
```

A carry can produce $10^{p}$ (for example $999.6 \to 1000$); real cores
renormalize that case, which this sketch omits.

### Parse a literal into exact parts

`split_decimal_string` does the lexical work for decimal parsers; trimming
the result gives a canonical coefficient:

```moonbit
///|
test "parse then trim" {
  guard @internal.split_decimal_string("-0.012500e2") is Some((negative, digits, exponent)) else {
    fail("expected a literal")
  }
  let coefficient = BigInt::from_string(digits)
  let (c, q, dropped) = @internal.trim_trailing_decimal_zeros(coefficient, exponent)
  inspect(negative, content="true")
  inspect(c, content="125")
  inspect(q, content="-2")
  inspect(dropped, content="2")
}
```

So $-0.012500 \times 10^{2} = -125 \times 10^{-2}$.

### Certify a rounding with a refinement loop

The certified elementary functions follow Ziv's strategy: compute an
enclosure at some working precision, and accept the rounded result only when
both ends of the enclosure round to the same number; otherwise raise the
precision. The budget bounds the loop. Here the "function" is the exact ratio
$n/d$, rounded down to `target` fractional bits:

```moonbit
///|
fn floor_ratio_certified(
  n : BigInt,
  d : BigInt,
  target : Int,
) -> Result[@internal.CertifiedDyadic, @lf_arith.ArithmeticError] {
  let mut budget = @internal.CertifiedRefinementBudget::new(target + 2)
  while budget.available() {
    let enclosure = match
      @internal.certified_dyadic_fraction(n, d, budget.precision()) {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    let low = enclosure.lower().round_down(target)
    let high = enclosure.upper().round_down(target)
    if low.compare(high) == 0 {
      return Ok(low)
    }
    budget = budget.next()
  }
  Err(
    @internal.certified_failure(
      "floor_ratio",
      @lf_arith.CertificationStage::TargetRounding,
      @lf_arith.CertificationFailureReason::RefinementBudgetExhausted,
      target,
      budget,
    ),
  )
}

///|
test "certified floor of 1/3" {
  let third = floor_ratio_certified(1N, 3N, 8).unwrap()
  inspect(third.numerator(), content="85")
  inspect(third.scale(), content="8")
}
```

## Going further

- `bin_float`, `decimal`, `decimal_gda` and `ball_float` create their
  refinement budgets at the target precision plus a guard margin and report
  `certified_failure` when the budget runs out; see the
  [bin_float design](../design/bin_float.md) for the certified elementary
  functions.
- `semantic` uses `ExactRat` as the canonical exact value of finite binary
  and decimal numbers.
- The `consistency` package tests these helpers against `BigInt` oracles.
- Run the package tests from a workspace containing the module:
  `moon test -p Luna-Flow/floating/internal`.
- The decimal cores parse literals with `split_decimal_string`; its exponent
  saturation is a known defect described on the
  [API page](../api/internal.md#split_decimal_string).

## Common pitfalls

- **Signed inputs.** `round_positive_div` aborts on a negative numerator;
  pass the magnitude and the sign separately.
- **`round_shift` with $s \le 0$** returns the input unchanged; it never
  shifts left. With a negative magnitude it floors instead of rounding the
  magnitude, so pass $|m|$ and the sign separately, as for
  `round_positive_div`.
- **Zero loses its exponent.** `remove_factor2`, `remove_factor10` and
  `trim_trailing_decimal_zeros` return exponent 0 for a zero coefficient.
  Keep the original exponent yourself if the cohort of zero matters.
- **Unnormalized dyadics.** `CertifiedDyadic` values with different scales may
  be numerically equal; compare with `compare`, not by fields.

## Next steps

- [internal API](../api/internal.md)
- [internal design](../design/internal.md)
- [consistency tutorial](consistency.md) for the tests that cross-check these
  helpers.
