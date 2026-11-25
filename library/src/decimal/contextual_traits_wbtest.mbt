///|
// oracle: A
// source: written out: the machine epsilon of decimal64 (p 16) is 10^(1-16) = 1E-15
// shares: epsilon_contextual and Decimal::to_string (the code under test)
test "Decimal contextual format follows decimal64" {
  let context = @lf_arith.ArithmeticContext::decimal64()
  let epsilon : Decimal = @lf_arith.NumericFormatContextual::epsilon_contextual(
    context,
  )
  inspect(epsilon.to_string(), content="1E-15")
}

///|
// oracle: A
// source: written out: 1/3 in 16 digits is 0.3333333333333333 and inexact
// shares: div_contextual and to_string (the code under test), Decimal::from_int (it builds the operands)
test "Decimal contextual division preserves rounding diagnostics" {
  let context = @lf_arith.ArithmeticContext::decimal64()
  let numerator = Decimal::from_int(1, precision=16)
  let denominator = Decimal::from_int(3, precision=16)
  let outcome = @lf_arith.DivContextual::div_contextual(
    numerator, denominator, context,
  ).unwrap()
  inspect(outcome.value.to_string(), content="0.3333333333333333")
  inspect(outcome.diagnostics.inexact, content="true")
}

///|
// oracle: A
// source: written out by the rounding rules of IEEE 754-2019 4.3 at 3 digits: 1.239 toward zero 1.23, 1.231 toward positive 1.24, -1.231 toward positive -1.23; 1E+200 beyond emax 96 of decimal32 is infinity with overflow; not-a-decimal is an error
// shares: parse_checked, Decimal::from_string_ctx and from_arithmetic_context (the code under test)
test "Decimal checked parsing uses the arithmetic context" {
  let context = @lf_arith.ArithmeticContext::new(
    3,
    rounding=@lf_arith.RoundingMode::TowardZero,
  )
  let rounded : Result[Decimal, @lf_arith.ArithmeticError] = @lf_arith.ParseChecked::parse_checked(
    "1.239", context,
  )
  let rounded = rounded.unwrap()
  inspect(rounded.to_string(), content="1.23")
  let toward_positive = @lf_arith.ArithmeticContext::new(
    3,
    rounding=@lf_arith.RoundingMode::TowardPositive,
  )
  let positive_result : Result[Decimal, @lf_arith.ArithmeticError] = @lf_arith.ParseChecked::parse_checked(
    "1.231", toward_positive,
  )
  inspect(positive_result.unwrap().to_string(), content="1.24")

  let negative_result : Result[Decimal, @lf_arith.ArithmeticError] = @lf_arith.ParseChecked::parse_checked(
    "-1.231", toward_positive,
  )
  inspect(negative_result.unwrap().to_string(), content="-1.23")

  let decimal32 = @lf_arith.ArithmeticContext::new(
    7,
    e_min=-95,
    e_max=96,
    clamp=true,
  )
  let overflow : Result[Decimal, @lf_arith.ArithmeticError] = @lf_arith.ParseChecked::parse_checked(
    "1E+200", decimal32,
  )
  let overflow = overflow.unwrap()
  assert_true(overflow.class == FpClass::Infinity)
  let (overflow_value, overflow_flags) = Decimal::from_string_ctx(
    "1E+200",
    DecimalContext::from_arithmetic_context(decimal32).unwrap(),
  )
  assert_true(overflow_flags.overflow)
  assert_true(overflow_value.class == FpClass::Infinity)

  let invalid : Result[Decimal, @lf_arith.ArithmeticError] = @lf_arith.ParseChecked::parse_checked(
    "not-a-decimal", context,
  )
  assert_true(invalid is Err(_))
}

///|
// oracle: S
// source: a setter and its getter: with_rounding then rounding returns the value set
// shares: DecimalContext::with_rounding and rounding (the code under test)
test "IEEE context has explicit rounding updates" {
  let ctx = DecimalContext::decimal64()
  let directed = ctx.with_rounding(DecimalRoundingMode::RoundTowardPositive)
  assert_true(directed.rounding() == DecimalRoundingMode::RoundTowardPositive)
}

///|
// oracle: A
// source: written out from the decimal32 format (IEEE 754-2019 3.6): precision 7, emin -95, emax 96
// shares: from_arithmetic_context and the accessors (the code under test)
test "Decimal contextual conversion preserves exponent bounds and clamp" {
  let arithmetic = @lf_arith.ArithmeticContext::new(
    7,
    e_min=-95,
    e_max=96,
    clamp=true,
  )
  let context = DecimalContext::from_arithmetic_context(arithmetic).unwrap()
  assert_eq(context.precision(), 7)
  assert_eq(context.e_min(), -95)
  assert_eq(context.e_max(), 96)
}

///|
// oracle: A
// source: written out: 2^10 = 1024 has adjusted exponent 3, above emax 2, so the result is infinite
// shares: pow_nat_checked and classify (the code under test), Decimal::from_int (it builds the operand)
test "Decimal checked powers preserve arithmetic exponent bounds" {
  let context = @lf_arith.ArithmeticContext::new(7, e_min=-1, e_max=2)
  let result = @lf_arith.PowNatChecked::pow_nat_checked(
    Decimal::from_int(2, precision=7),
    10U,
    context,
  ).unwrap()
  assert_true(result.classify() == @lf_arith.FpClass::Infinity)
}

///|
// oracle: A
// source: written out: (-1)^n is -1 for odd n and 1 for even n; 12345679 and 2147483647 and 999999999 are odd, 12345678 and 999999998 and -2147483648 are even (the exponent must not be rounded to seven digits, issue 51)
// shares: pow_int_checked, pow_nat_checked and to_string (the code under test), Decimal::from_int (it builds the operand)
test "Decimal checked integer powers use the exact exponent" {
  // An exponent longer than the context precision must not be rounded
  // before use: rounding 12345679 to seven digits makes it even (#51).
  let context = @lf_arith.ArithmeticContext::new(7)
  let minus_one = Decimal::from_int(-1, precision=7)
  let int_power = fn(exponent : Int32) {
    @lf_arith.PowIntChecked::pow_int_checked(minus_one, exponent, context)
    .unwrap()
    .to_string()
  }
  let nat_power = fn(exponent : UInt32) {
    @lf_arith.PowNatChecked::pow_nat_checked(minus_one, exponent, context)
    .unwrap()
    .to_string()
  }
  assert_eq(int_power(12345679), "-1")
  assert_eq(int_power(-12345679), "-1")
  assert_eq(int_power(12345678), "1")
  assert_eq(int_power(2147483647), "-1")
  assert_eq(int_power(-2147483648), "1")
  assert_eq(nat_power(12345679U), "-1")
  assert_eq(nat_power(999999999U), "-1")
  assert_eq(nat_power(999999998U), "1")
}

///|
// oracle: A, S
// source: written out: the limits 1..=999999999 and the message text, emin = 1 - emax (IEEE 754-2019 3.3), emin alone gives emax = 1 - emin (-95 gives 96), a rounding direction without an equivalent in the decimal formats is rejected, and precision 0 is raised to 1 (the limit or message is this library's own, the rule it follows is IEEE 754-2019 3.3)
// shares: from_arithmetic_context, add_contextual and the accessors (the code under test)
test "Decimal context translation rejects out of range bounds" {
  let zero_precision = @lf_arith.ArithmeticContext::new(0)
  let zero_context = DecimalContext::from_arithmetic_context(zero_precision).unwrap()
  assert_eq(zero_context.precision(), 1)
  let excessive_precision = @lf_arith.ArithmeticContext::new(1_000_000_000)
  match DecimalContext::from_arithmetic_context(excessive_precision) {
    Err(error) =>
      assert_eq(error.message, "precision must be within 1..=999999999")
    Ok(_) => fail("excessive precision must be rejected")
  }
  let invalid = @lf_arith.ArithmeticContext::new(7, e_min=-1_000_000_000)
  assert_true(DecimalContext::from_arithmetic_context(invalid) is Err(_))
  let outcome = @lf_arith.AddContextual::add_contextual(
    Decimal::one(),
    Decimal::one(),
    invalid,
  )
  assert_true(outcome is Err(_))
  // IEEE 754-2019 3.3: emin = 1 - emax
  let positive = @lf_arith.ArithmeticContext::new(7, e_min=1, e_max=10)
  match DecimalContext::from_arithmetic_context(positive) {
    Err(error) => assert_true(error.message.contains("e_min must be 1 - e_max"))
    Ok(_) => fail("e_min other than 1 - e_max must be rejected")
  }
  let negative = @lf_arith.ArithmeticContext::new(7, e_min=-10, e_max=-1)
  assert_true(DecimalContext::from_arithmetic_context(negative) is Err(_))
  // e_min alone gives e_max = 1 - e_min; neither gives the default range
  let from_min = @lf_arith.ArithmeticContext::new(7, e_min=-95)
  assert_eq(
    DecimalContext::from_arithmetic_context(from_min).unwrap().e_max(),
    96,
  )
  let away = @lf_arith.ArithmeticContext::new(7, rounding=AwayFromZero)
  assert_true(DecimalContext::from_arithmetic_context(away) is Err(_))
}
