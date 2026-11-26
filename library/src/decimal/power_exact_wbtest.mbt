///|
/// `4^1.5 = 8` is exactly representable, so the certified enclosure straddles
/// the result and no refinement can ever make its two endpoints round alike.
/// Reducing the exponent to `3/2` and taking the exact square root of `4^3`
/// decides the power before the refinement loop is reached.
// oracle: A
// source: the twelve exact results are written out and can be checked by hand from the exact arithmetic of the operands (4^1.5 = 8, 9^1.5 = 27, 4^2.5 = 32, 16^0.25 = 2, 16^0.75 = 8, 32^0.2 = 2, 32^0.4 = 4, 1024^0.1 = 2, 0.25^1.5 = 0.125, 1.21^1.5 = 1.331, 4^-1.5 = 0.125, 16^-0.25 = 0.5); no inexact flag
// shares: Decimal::from_string, DecimalContext::decimal64 and to_string (they build the operands and print the result)
test "decimal power decides exact non-integral results" {
  let context = DecimalContext::decimal64()
  let cases = [
    ("4", "1.5", "8"),
    ("9", "1.5", "27"),
    ("4", "2.5", "32"),
    ("16", "0.25", "2"),
    ("16", "0.75", "8"),
    ("32", "0.2", "2"),
    ("32", "0.4", "4"),
    ("1024", "0.1", "2"),
    ("0.25", "1.5", "0.125"),
    ("1.21", "1.5", "1.331"),
    ("4", "-1.5", "0.125"),
    ("16", "-0.25", "0.5"),
  ]
  for entry in cases {
    let (left, right, expected) = entry
    let base = Decimal::from_string(left).unwrap()
    let exponent = Decimal::from_string(right).unwrap()
    let (value, flags) = base.pow_ctx(exponent, context)
    assert_eq(value.to_string(), expected)
    assert_false(flags.inexact)
    assert_false(flags.invalid_operation)
  }
}

///|
// oracle: A
// source: CPython decimal at 120 to 200 digits, rounded once to the context (the digits after the kept ones are not borderline): 2^1.5 = 2.828427124746190, 10^1.5 = 31.62277660168379, 2^0.1 = 1.071773462536293 and 9^-1.5 = 0.03703703703703704 at 16 digits, inexact
// shares: Decimal::from_string (builds the operands), to_string (prints the result), pow_ctx and try_pow_ctx (the code under test)
test "decimal power keeps inexact non-integral results inexact" {
  let context = DecimalContext::decimal64()
  let cases = [
    ("2", "1.5", "2.828427124746190"),
    ("10", "1.5", "31.62277660168379"),
    ("2", "0.1", "1.071773462536293"),
    ("9", "-1.5", "0.03703703703703704"),
  ]
  for entry in cases {
    let (left, right, expected) = entry
    let base = Decimal::from_string(left).unwrap()
    let exponent = Decimal::from_string(right).unwrap()
    let (value, flags) = base.pow_ctx(exponent, context)
    assert_eq(value.to_string(), expected)
    assert_true(flags.inexact)
  }
}

///|
/// An exact power longer than the context precision is not a rounding
/// boundary: it lies strictly inside its rounding cell, so the refinement loop
/// rounds it like any other value.
// oracle: A
// source: arithmetic and IEEE 754-2019 4.3: 4096^1.5 = 262144 rounds half-even to 3E+5 at one digit; 4^106.5 = 2^213 = 1.316403645856965E+64 at 16 digits (CPython decimal); both inexact
// shares: Decimal::from_string (builds the operands), to_string (prints the result), pow_ctx and try_pow_ctx (the code under test)
test "decimal power rounds exact non-integral results beyond the precision" {
  let coarse = DecimalContext::new(
    precision=1,
    e_max=999,
    rounding=DecimalRoundingMode::RoundTiesToEven,
  )
  let (coarse_value, coarse_flags) = Decimal::from_string("4096")
    .unwrap()
    .pow_ctx(Decimal::from_string("1.5").unwrap(), coarse)
  assert_eq(coarse_value.to_string(), "3E+5")
  assert_true(coarse_flags.inexact)
  let context = DecimalContext::decimal64()
  let (wide_value, wide_flags) = Decimal::from_string("4")
    .unwrap()
    .pow_ctx(Decimal::from_string("106.5").unwrap(), context)
  assert_eq(wide_value.to_string(), "1.316403645856965E+64")
  assert_true(wide_flags.inexact)
}

///|
let all_decimal_roundings : Array[DecimalRound] = [
  HalfEven,
  HalfUp,
  HalfDown,
  Down,
  Ceiling,
  Floor,
  Up,
  ZeroFiveUp,
]

///|
/// Exact powers longer than the precision round correctly in the directed
/// modes too, whether the value is a binary fraction (`4096^1.5 = 2^18`) or
/// not (`0.25^1.5 = 0.125`).
// oracle: A
// source: arithmetic and IEEE 754-2019 4.3: 4096^1.5 = 262144 at one digit and 0.25^1.5 = 0.125 at two digits rounded in the eight directions (CPython decimal plus agrees): 3E+5 or 2E+5 (down, floor and 05up give 2E+5) and 0.12 or 0.13 (half-up, ceiling and up give 0.13), inexact each time
// shares: Decimal::from_string (builds the operands), to_string (prints the result), pow_ctx and try_pow_ctx (the code under test)
test "decimal power rounds long exact non-integral results in every mode" {
  let cases = [
    (
      "4096",
      "1.5",
      1,
      ["3E+5", "3E+5", "3E+5", "2E+5", "3E+5", "2E+5", "3E+5", "2E+5"],
    ),
    (
      "0.25",
      "1.5",
      2,
      ["0.12", "0.13", "0.12", "0.12", "0.13", "0.12", "0.13", "0.12"],
    ),
  ]
  for entry in cases {
    let (left, right, precision, expected) = entry
    for i, mode in all_decimal_roundings {
      let context = DecimalContext::new(precision~, e_max=999).with_round(mode)
      let (value, flags) = Decimal::from_string(left)
        .unwrap()
        .pow_ctx(Decimal::from_string(right).unwrap(), context)
      assert_eq(value.to_string(), expected[i])
      assert_true(flags.inexact)
      assert_false(flags.invalid_operation)
    }
  }
}

///|
/// `(2^1200 * 10^-1200)^1.5 = 2^1800 * 10^-1800` has 542 digits and is exact
/// at precision 1000, but `base^3` needs 1084 digits. Taking the square root
/// first keeps every intermediate at the size of the result, so the power is
/// decided in every mode instead of failing certification after minutes. The
/// negative exponent case raises the reciprocal of the root `5^600`.
// oracle: A
// source: the expected value is the exact power derived by hand: (2^1200 * 10^-1200)^1.5 = 2^1800 * 10^-1800 and (5^1200)^-1.5 = 5^-1800 = 2^1800 * 10^-1800, written as the integer 2^1800 with exponent -1800; no inexact flag in every rounding mode
// shares: BigInt shifts, pow5 and to_string (they build the text of the operands and of the expected value; 2^1800 is a shift of 1), Decimal::from_string, and total_order_compare (it compares the result with the expected value)
test "decimal power decides exact non-integral results past base^p's size (#138)" {
  let two_1200 = (BigInt::from_int(1) << 1200).to_string()
  let two_1800 = (BigInt::from_int(1) << 1800).to_string()
  let expected = "\{two_1800}E-1800"
  let cases = [("\{two_1200}E-1200", "1.5"), (pow5(1200).to_string(), "-1.5")]
  for entry in cases {
    let (left, right) = entry
    let base = Decimal::from_string(left, precision=1000).unwrap()
    let exponent = Decimal::from_string(right).unwrap()
    for mode in all_decimal_roundings {
      let context = DecimalContext::new(precision=1000, e_max=999_999).with_round(
        mode,
      )
      let (value, flags) = base.pow_ctx(exponent, context)
      assert_eq(
        value.total_order_compare(
          Decimal::from_string(expected, precision=1000).unwrap(),
        ),
        0,
      )
      assert_false(flags.inexact)
      assert_false(flags.invalid_operation)
    }
  }
}

///|
/// `try_pow_ctx` reports the failure instead of returning a quiet NaN, so an
/// uncertifiable power stays distinguishable from an invalid operand.
// oracle: A
// source: arithmetic: 4^1.5 = 8 exactly, no inexact flag; the block checks the Ok form of try_pow_ctx (the Err form is the library's API and is not reached by this input)
// shares: Decimal::from_string (builds the operands), to_string (prints the result), pow_ctx and try_pow_ctx (the code under test)
test "decimal try power reports a certification failure" {
  let context = DecimalContext::decimal64()
  match
    Decimal::from_string("4")
    .unwrap()
    .try_pow_ctx(Decimal::from_string("1.5").unwrap(), context) {
    Ok((value, flags)) => {
      assert_eq(value.to_string(), "8")
      assert_false(flags.inexact)
    }
    Err(_) => assert_true(false)
  }
}

///|
/// The reduced exponent is bounded by the operands, not by fixed constants:
/// `(5^1024)^(2^-10) = 5` has a denominator of 1024, and
/// `0.25^4096.5 = 5^8193 * 10^-8193` a numerator of 8193.
// oracle: A
// source: arithmetic: (5^1024)^(2^-10) = 5, (5^1024)^(-2^-10) = 0.2 and 0.25^4096.5 = 2^-8193 = 5^8193 * 10^-8193, exact in each of the eight directions (the operands and expected values are built with pow5 and BigInt::to_string, the coefficients 5^k themselves are the arithmetic definition); no inexact flag
// shares: pow5 and to_string (build the operands and expected texts), Decimal::from_string and total_order_compare (read them), pow_ctx (the code under test)
test "decimal power decides exact powers with large reduced exponents" {
  let cases = [
    (pow5(1024).to_string(), "0.0009765625", 720, "5"),
    (pow5(1024).to_string(), "-0.0009765625", 720, "0.2"),
    ("0.25", "4096.5", 5800, "\{pow5(8193)}E-8193"),
  ]
  for entry in cases {
    let (left, right, precision, expected) = entry
    let base = Decimal::from_string(left, precision~).unwrap()
    let exponent = Decimal::from_string(right).unwrap()
    let want = Decimal::from_string(expected, precision~).unwrap()
    for mode in all_decimal_roundings {
      let context = DecimalContext::new(precision~, e_max=999_999).with_round(
        mode,
      )
      let (value, flags) = base.pow_ctx(exponent, context)
      assert_eq(value.total_order_compare(want), 0)
      assert_false(flags.inexact)
      assert_false(flags.invalid_operation)
    }
  }
}

///|
// oracle: S
// source: a round trip: the exact power of the constructed root 10^40 + 7 for each degree must have that exact root, a number one above it must have none and its floor root is the root; the root is constructed in the test and no power is written out
// shares: dec_coeff_exact_power_repr, dec_coeff_exact_nth_root_repr and dec_coeff_floor_nth_root_repr (the code under test, the power and both roots)
test "decimal exact integer roots take Newton steps for long roots" {
  let root = dec_coeff_magnitude_add_repr(
    dec_coeff_power10_repr(40),
    dec_coeff_from_int(7),
  )
  for degree in [2, 3, 5, 8, 25] {
    let power = dec_coeff_exact_power_repr(root, degree)
    match dec_coeff_exact_nth_root_repr(power, degree) {
      Some(value) => assert_eq(dec_coeff_compare_repr(value, root), 0)
      None => fail("missed an exact root of degree \{degree}")
    }
    let above = dec_coeff_magnitude_add_repr(power, dec_coeff_from_int(1))
    assert_true(dec_coeff_exact_nth_root_repr(above, degree) is None)
    assert_eq(
      dec_coeff_compare_repr(dec_coeff_floor_nth_root_repr(above, degree), root),
      0,
    )
  }
}
