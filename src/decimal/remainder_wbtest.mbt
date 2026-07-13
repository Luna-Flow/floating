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
