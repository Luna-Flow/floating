///|
/// `4^1.5 = 8` is exactly representable, so the certified enclosure straddles
/// the result and no refinement can ever make its two endpoints round alike.
/// Reducing the exponent to `3/2` and taking the exact square root of `4^3`
/// decides the power before the refinement loop is reached.
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
    let (value, flags) = base.power_ctx(exponent, context)
    assert_eq(value.to_string(), expected)
    assert_false(flags.inexact)
    assert_false(flags.rounded)
    assert_false(flags.invalid_operation)
  }
}

///|
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
    let (value, flags) = base.power_ctx(exponent, context)
    assert_eq(value.to_string(), expected)
    assert_true(flags.inexact)
    assert_true(flags.rounded)
  }
}

///|
/// An exact power longer than the context precision is not a rounding
/// boundary: it lies strictly inside its rounding cell, so the refinement loop
/// rounds it like any other value.
test "decimal power rounds exact non-integral results beyond the precision" {
  let coarse = DecimalContext::new(
    precision=1,
    decimal_rounding=DecimalRoundingMode::HalfEven,
    e_min=-999,
    e_max=999,
  ).ieee754()
  let (coarse_value, coarse_flags) = Decimal::from_string("4096")
    .unwrap()
    .power_ctx(Decimal::from_string("1.5").unwrap(), coarse)
  assert_eq(coarse_value.to_string(), "3E+5")
  assert_true(coarse_flags.inexact)
  assert_true(coarse_flags.rounded)
  let context = DecimalContext::decimal64()
  let (wide_value, wide_flags) = Decimal::from_string("4")
    .unwrap()
    .power_ctx(Decimal::from_string("106.5").unwrap(), context)
  assert_eq(wide_value.to_string(), "1.316403645856965E+64")
  assert_true(wide_flags.inexact)
}

///|
let all_decimal_roundings : Array[DecimalRoundingMode] = [
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
      let context = DecimalContext::new(
        precision~,
        decimal_rounding=mode,
        e_min=-999,
        e_max=999,
      )
      let (value, flags) = Decimal::from_string(left)
        .unwrap()
        .power_ctx(Decimal::from_string(right).unwrap(), context)
      assert_eq(value.to_string(), expected[i])
      assert_true(flags.inexact)
      assert_true(flags.rounded)
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
      let context = DecimalContext::new(
        precision=1000,
        decimal_rounding=mode,
        e_min=-999_999,
        e_max=999_999,
      )
      let (value, flags) = base.power_ctx(exponent, context)
      assert_eq(
        value.compare_total(
          Decimal::from_string(expected, precision=1000).unwrap(),
        ),
        0,
      )
      assert_false(flags.inexact)
      assert_false(flags.rounded)
      assert_false(flags.invalid_operation)
    }
  }
}

///|
/// `try_power_ctx` reports the failure instead of returning a quiet NaN, so an
/// uncertifiable power stays distinguishable from an invalid operand.
test "decimal try power reports a certification failure" {
  let context = DecimalContext::decimal64()
  match
    Decimal::from_string("4")
    .unwrap()
    .try_power_ctx(Decimal::from_string("1.5").unwrap(), context) {
    Ok((value, flags)) => {
      assert_eq(value.to_string(), "8")
      assert_false(flags.inexact)
    }
    Err(_) => assert_true(false)
  }
}
