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
test "issue 446: a gap below 2^31 - 1 costs nothing and rounds like add_ctx" {
  let ctx = DecimalContext::new(precision=34, e_max=999_999)
  // The same shape within the exponent range of a context: compare with add_ctx.
  let cases : Array[(BigInt, Int32, BigInt, Int32)] = [
    (1N, 900_000, 1N, -900_000),
    (1N, 900_000, -1N, -900_000),
    (-1N, 900_000, 1N, -900_000),
    (9999999999999999999999999999999999N, 500_000, 1N, -400_000),
    (9999999999999999999999999999999999N, 500_000, -1N, -400_000),
    (5N, 0, 3N, -700_000),
    (5N, 0, -3N, -700_000),
    (12345N, -10, 6N, 400_000),
  ]
  for c in cases {
    let (ac, ae, bc, be) = c
    let a = gap_value(ac, ae, 34)
    let b = gap_value(bc, be, 34)
    let plain = a + b
    let (expected, _) = a.add_ctx(b, ctx)
    inspect(plain == expected, content="true")
    let plain_diff = a - b
    let (expected_diff, _) = a.sub_ctx(b, ctx)
    inspect(plain_diff == expected_diff, content="true")
  }
}

///|
fn exact_plain_sum(a : Decimal, b : Decimal, precision : Int32) -> Decimal {
  let target = Int32::min(a.exponent10, b.exponent10)
  let (negative, magnitude) = decimal_exact_aligned_sum_result(a, b, target)
  // IEEE 754-2019 5.4.1 and 5.2: the exact sum at the preferred exponent
  // `min(Q(a), Q(b))`, or rounded to `precision` digits (half even, least
  // exponent) when it is longer.
  let signed = if negative {
    -magnitude.to_bigint()
  } else {
    magnitude.to_bigint()
  }
  Decimal::make(signed, target, precision)
}

///|
test "issue 446: the sticky absorption gives the result of the exact aligned sum" {
  // Oracle: the exact aligned sum at the preferred exponent, rounded once
  // half-even to the larger operand precision (the result is compared as a
  // representation, cohort included). The gaps
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
              inspect(
                (high + low).to_string() == expected.to_string(),
                content="true",
              )
              inspect(
                (low + high).to_string() == expected.to_string(),
                content="true",
              )
            }
          }
        }
      }
    }
  }
}

///|
test "issue 446: a gap above 2^31 - 1 between a small and a large exponent" {
  let small = gap_value(5N, -2_000_000_000, 34)
  let big = gap_value(3N, 2_000_000_000, 34)
  // 3E+2000000000 plus 5E-2000000000 rounds to 3E+2000000000 at 34 digits.
  inspect(small + big == big, content="true")
  inspect(big - small == big, content="true")
  inspect(small - big == big.neg(), content="true")
}

///|
test "issue 446: the exact context cannot panic through the exponent gap" {
  let a = gap_value(1N, 1_100_000_000, 34)
  let b = gap_value(1N, -1_100_000_000, 34)
  let (sum, flags) = a.add_ctx(b, decimal_exact_work_context())
  inspect(sum.is_nan(), content="true")
  inspect(flags.invalid_operation, content="true")
  let (difference, _) = a.sub_ctx(b, decimal_exact_work_context())
  inspect(difference.is_nan(), content="true")
}
