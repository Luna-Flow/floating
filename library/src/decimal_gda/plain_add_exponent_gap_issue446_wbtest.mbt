// Issue 446: the plain `+` and `-` of `Decimal` formed the exact aligned sum, so
// an exponent gap above 2^31 - 1 panicked and a smaller one allocated memory
// proportional to the gap. The far smaller operand only contributes a sticky
// digit; the cost is independent of the gap.

///|
fn gap_value(
  coefficient : BigInt,
  exponent : Int32,
  precision : Int32,
) -> Decimal {
  Decimal::make(coefficient, exponent, precision)
}

///|
// oracle: A
// source: expected values derived by hand from the definition of addition at 34 digits (GDA 1.70, Arithmetic
//   operations, add): an operand 2.2E+9 orders of magnitude smaller only decides the sticky digit, so the
//   sum is the larger operand, and the negated cases follow by sign.
// shares: nothing
test "issue 446: plain add and sub with an exponent gap above 2^31 - 1 do not panic" {
  let a = gap_value(1N, 1_100_000_000, 34)
  let b = gap_value(1N, -1_100_000_000, 34)
  let sum = a + b
  let difference = a - b
  let reversed = b + a
  let negated = a + b.neg()
  // The sum is rounded to 34 digits: 1E+1100000000 plus or minus a sticky digit.
  inspect(sum == a, content="true")
  inspect(reversed == a, content="true")
  inspect(difference == a, content="true")
  inspect(negated == a, content="true")
  inspect(sum.coefficient.digits10() <= 34, content="true")
  // The negative operand large: -a + b is -a.
  inspect(a.neg() + b == a.neg(), content="true")
  inspect(b - a == a.neg(), content="true")
}

///|
// oracle: A
// source: expected sums and differences computed with CPython decimal (libmpdec 4.0.0), context prec=34,
//   Emin=-999999, Emax=999999, rounding ROUND_HALF_EVEN, no traps; compared as values (the cohort member
//   the plain operators return is not the subject)
// shares: Decimal::from_string (reads the operands and the expected sums) and Decimal == (compares values, so the cohort is not pinned)
test "issue 446: a gap below 2^31 - 1 costs nothing and rounds like add_ctx" {
  // (a, b, a + b, a - b), each operand with its own 34-digit working precision
  let rows : Array[(String, String, String, String)] = [
    (
      "1E900000", "1E-900000", "1.000000000000000000000000000000000E+900000", "1.000000000000000000000000000000000E+900000",
    ),
    (
      "1E900000", "-1E-900000", "1.000000000000000000000000000000000E+900000", "1.000000000000000000000000000000000E+900000",
    ),
    (
      "-1E900000", "1E-900000", "-1.000000000000000000000000000000000E+900000", "-1.000000000000000000000000000000000E+900000",
    ),
    (
      "9999999999999999999999999999999999E500000", "1E-400000", "9.999999999999999999999999999999999E+500033",
      "9.999999999999999999999999999999999E+500033",
    ),
    (
      "9999999999999999999999999999999999E500000", "-1E-400000", "9.999999999999999999999999999999999E+500033",
      "9.999999999999999999999999999999999E+500033",
    ),
    (
      "5E0", "3E-700000", "5.000000000000000000000000000000000", "5.000000000000000000000000000000000",
    ),
    (
      "5E0", "-3E-700000", "5.000000000000000000000000000000000", "5.000000000000000000000000000000000",
    ),
    (
      "12345E-10", "6E400000", "6.000000000000000000000000000000000E+400000", "-6.000000000000000000000000000000000E+400000",
    ),
  ]
  for row in rows {
    let (a_text, b_text, sum_text, difference_text) = row
    let a = Decimal::from_string(a_text, precision=34).unwrap()
    let b = Decimal::from_string(b_text, precision=34).unwrap()
    let sum = Decimal::from_string(sum_text, precision=34).unwrap()
    let difference = Decimal::from_string(difference_text, precision=34).unwrap()
    inspect(a + b == sum, content="true")
    inspect(a - b == difference, content="true")
  }
}

///|
fn exact_plain_sum(a : Decimal, b : Decimal, precision : Int32) -> Decimal {
  let target = Int32::min(a.exponent10, b.exponent10)
  let (negative, magnitude) = decimal_exact_aligned_sum_result(a, b, target)
  normalize_decimal_parts_gda_repr(
    negative,
    magnitude,
    target,
    precision,
    DecimalRoundingMode::HalfEven,
  )
}

///|
// oracle: B
// source: the exact aligned sum (decimal_exact_aligned_sum_result), rounded once half-even by
//   normalize_decimal_parts_gda_repr, the computation the plain operators made before the absorption
// shares: normalize_decimal_parts_gda_repr, decimal_exact_aligned_sum_result
// primitives: normalize_decimal_parts_gda_repr (level A: the decTest add rows and libmpdec random rows of the
//   gate; direct tests in coeff_kernel_wbtest) and the exact aligned sum, both outside the absorption
//   path under test
test "issue 446: the sticky absorption gives the result of the exact aligned sum" {
  // Oracle: the exact aligned sum rounded once half-even to the larger operand
  // precision, the computation the plain operators made before the absorption
  // (the result is compared as a value: the plain operators now return the least exponent, not the reduced cohort member). The gaps
  // straddle the point where the absorption starts.
  let coefficients : Array[BigInt] = [
    1N, 5N, 9N, 10N, 12345N, 99999N, 100000N, 5000000000000N, 9999999999999999999999999999999999N,
    1000000000000000000000000000000000N,
  ]
  for precision in [1, 2, 5, 34] {
    for hc in coefficients {
      for lc in [1N, 5N, 7N, 99N, 500000N] {
        for
          gap in [
            precision - 1,
            precision,
            precision + 1,
            precision + 2,
            precision + 3,
            precision + 7,
            precision + 40,
            5000,
          ] {
          for high_negative in [false, true] {
            for low_negative in [false, true] {
              let high = gap_value(
                if high_negative {
                  -hc
                } else {
                  hc
                },
                0,
                precision,
              )
              let low = gap_value(
                if low_negative {
                  -lc
                } else {
                  lc
                },
                -gap - lc.to_string().length() - hc.to_string().length(),
                precision,
              )
              let expected = exact_plain_sum(high, low, precision)
              inspect(high + low == expected, content="true")
              inspect(low + high == expected, content="true")
            }
          }
        }
      }
    }
  }
}

///|
// oracle: A
// source: hand: at 34 digits the operand 5E-2000000000 only sets a sticky digit, so 3E+2000000000 plus or minus it
//   is 3E+2000000000 (CPython 3.13 agrees on the three comparisons)
// shares: Decimal::make (builds the inputs and the expected value) and the library Eq for Decimal
test "issue 446: a gap above 2^31 - 1 between a small and a large exponent" {
  let small = gap_value(5N, -2_000_000_000, 34)
  let big = gap_value(3N, 2_000_000_000, 34)
  // 3E+2000000000 plus 5E-2000000000 rounds to 3E+2000000000 at 34 digits.
  inspect(small + big == big, content="true")
  inspect(big - small == big, content="true")
  inspect(small - big == big.neg(), content="true")
}

///|
// oracle: S
// source: design rule of the library, not a clause of GDA 1.70: the exact context refuses a sum whose alignment
//   exceeds the stored exponent range with a NaN and invalid_context (written out, no computed value)
// shares: nothing
test "issue 446: the exact context cannot panic through the exponent gap" {
  let a = gap_value(1N, 1_100_000_000, 34)
  let b = gap_value(1N, -1_100_000_000, 34)
  let (sum, flags) = a.add_ctx(b, DecimalContext::exact())
  inspect(sum.is_nan(), content="true")
  inspect(flags.invalid_context, content="true")
  let (difference, _) = a.sub_ctx(b, DecimalContext::exact())
  inspect(difference.is_nan(), content="true")
}
