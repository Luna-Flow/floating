///|
/// plus(x) is 0 + x and minus(x) is 0 - x, the zero taking the operand's
/// exponent. IEEE 754-2019 §6.3 makes an exact zero sum of operands with
/// opposite signs -0 under roundTowardNegative (Floor) and +0 otherwise.
test "plus and minus of a zero follow the addition sign rule" {
  let modes = [
    DecimalRoundingMode::HalfEven,
    DecimalRoundingMode::HalfUp,
    DecimalRoundingMode::HalfDown,
    DecimalRoundingMode::Down,
    DecimalRoundingMode::Up,
    DecimalRoundingMode::Ceiling,
    DecimalRoundingMode::Floor,
    DecimalRoundingMode::ZeroFiveUp,
  ]
  for mode in modes {
    let ctx = DecimalContext::new(precision=16, decimal_rounding=mode).unwrap()
    let floor = mode == DecimalRoundingMode::Floor
    let check = (
      op : (Decimal, DecimalContext) -> (Decimal, DecimalFlags),
      operand : String,
      expected : String,
    ) => {
      let (value, flags) = op(Decimal::from_string(operand).unwrap(), ctx)
      assert_eq(value.to_string(), expected)
      assert_true(flags == DecimalFlags::new())
    }
    check(Decimal::plus_ctx, "0", "0")
    check(Decimal::plus_ctx, "-0", if floor { "-0" } else { "0" })
    check(Decimal::plus_ctx, "-0.00", if floor { "-0.00" } else { "0.00" })
    check(Decimal::plus_ctx, "0E+3", "0E+3")
    check(Decimal::minus_ctx, "0", if floor { "-0" } else { "0" })
    check(Decimal::minus_ctx, "0.00", if floor { "-0.00" } else { "0.00" })
    check(Decimal::minus_ctx, "-0", "0")
    check(Decimal::minus_ctx, "-0E+3", "0E+3")
    check(Decimal::abs_ctx, "-0", "0")
    // add_ctx gives the same signs.
    let zero = Decimal::from_string("0").unwrap()
    let (sum, _) = zero.add_ctx(Decimal::from_string("-0").unwrap(), ctx)
    assert_eq(sum.to_string(), if floor { "-0" } else { "0" })
  }
}
