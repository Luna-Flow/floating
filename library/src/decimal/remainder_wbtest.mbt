///|
test "IEEE remainder keeps an infinite quotient intermediate" {
  let ctx = DecimalContext::decimal32().ieee754()
  let lhs = Decimal::from_string("1E+20", precision=34).unwrap()
  let rhs = Decimal::one(precision=34)
  let (value, flags) = lhs.remainder_ctx(rhs, ctx)
  assert_true(value.is_zero())
  assert_false(flags.division_impossible)
  assert_false(flags.invalid_operation)
}

///|
test "remainder avoids materializing a million-digit quotient" {
  let lhs = Decimal::from_string("9E+1000008", precision=34).unwrap()
  let rhs = Decimal::from_string("469135780", precision=34).unwrap()
  let (value, flags) = lhs.remainder(rhs, DecimalContext::exact())
  assert_eq(value.coefficient().to_string(), "54833220")
  assert_eq(value.exponent10(), 0)
  assert_false(flags.invalid_operation)
  assert_false(flags.division_impossible)
}
