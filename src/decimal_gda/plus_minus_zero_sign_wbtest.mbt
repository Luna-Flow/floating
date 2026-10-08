///|
/// GDA defines plus(x) as add('0', x) and minus(x) as subtract('0', x), the
/// zero taking the operand's exponent. A zero sum of operands with opposite
/// signs is -0 only under round-floor, so the sign of a zero result depends on
/// the rounding mode.
test "plus and minus of a zero follow the add and subtract sign rule" {
  let modes = [
    GdaRoundingMode::HalfEven,
    GdaRoundingMode::HalfUp,
    GdaRoundingMode::HalfDown,
    GdaRoundingMode::Down,
    GdaRoundingMode::Up,
    GdaRoundingMode::Ceiling,
    GdaRoundingMode::Floor,
    GdaRoundingMode::ZeroFiveUp,
  ]
  for mode in modes {
    let ctx = GdaContext::new(
      precision=9,
      rounding=mode,
      traps=GdaTrapSet::none(),
    )
    let floor = mode == GdaRoundingMode::Floor
    let check = (
      op : (Decimal, GdaContext) -> GdaOutcome[Decimal],
      operand : String,
      expected : String,
    ) => {
      let outcome = op(Decimal::from_string(operand).unwrap(), ctx)
      assert_eq(outcome.value().to_string(), expected)
      assert_true(outcome.raised() == GdaFlags::none())
    }
    check(plus, "0", "0")
    check(plus, "-0", if floor { "-0" } else { "0" })
    check(plus, "-0.00", if floor { "-0.00" } else { "0.00" })
    check(plus, "0E+3", "0E+3")
    check(minus, "0", if floor { "-0" } else { "0" })
    check(minus, "0.00", if floor { "-0.00" } else { "0.00" })
    check(minus, "-0", "0")
    check(minus, "-0E+3", "0E+3")
    // abs(x) is minus(x) for a negative x and plus(x) otherwise.
    check(abs, "-0", "0")
    check(abs, "0", "0")
  }
}
