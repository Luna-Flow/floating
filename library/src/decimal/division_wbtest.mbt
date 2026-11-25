///|
// oracle: A
// source: written out and checked with Python decimal (CPython, libmpdec): 123456789012345678901234567890 / 7 at 6 digits is 1.76367E+28, inexact
// shares: Decimal::from_string, div_ctx and compare (the code under test)
test "bounded division rounds a long coefficient at context precision" {
  let dividend = Decimal::from_string(
    "123456789012345678901234567890",
    precision=64,
  ).unwrap()
  let divisor = Decimal::from_string("7", precision=64).unwrap()
  let ctx = DecimalContext::new(precision=6)
  let (value, flags) = dividend.div_ctx(divisor, ctx)
  assert_eq(value.compare(Decimal::from_string("1.76367E+28").unwrap()), 0)
  assert_true(flags.inexact)
}

///|
// oracle: A
// source: written out from the preferred exponent rule of IEEE 754-2019 5.4.1 and GDA (the exact quotient of 1.20 and 1 is 1.20: coefficient 120, exponent -2), not inexact
// shares: Decimal::from_string, one, div_ctx and the accessors (the code under test)
test "exact division preserves the preferred cohort" {
  let dividend = Decimal::from_string("1.20", precision=16).unwrap()
  let divisor = Decimal::one(precision=16)
  let (value, flags) = dividend.div_ctx(
    divisor,
    DecimalContext::new(precision=16),
  )
  assert_eq(value.coefficient().to_string(), "120")
  assert_eq(value.exponent10(), -2)
  assert_false(flags.inexact)
}

///|
// oracle: A
// source: written out: 1/8 = 0.125 exactly, a tie at two digits: half-even gives 0.12, half-up (ties to away) gives 0.13, both inexact (Python decimal agrees)
// shares: Decimal::from_string, div_ctx and compare (the code under test)
test "exact division honors decimal tie rounding" {
  let dividend = Decimal::from_string("1", precision=8).unwrap()
  let divisor = Decimal::from_string("8", precision=8).unwrap()
  let half_even = DecimalContext::new(precision=2)
  let half_up = DecimalContext::new(
    precision=2,
    rounding=DecimalRoundingMode::RoundTiesToAway,
  )
  let (even_value, even_flags) = dividend.div_ctx(divisor, half_even)
  let (up_value, up_flags) = dividend.div_ctx(divisor, half_up)
  assert_eq(even_value.compare(Decimal::from_string("0.12").unwrap()), 0)
  assert_eq(up_value.compare(Decimal::from_string("0.13").unwrap()), 0)
  assert_true(even_flags.inexact)
  assert_true(up_flags.inexact)
}
