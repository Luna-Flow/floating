///|
/// The remainder of `9E+1000008` by `469135780` has an integer quotient of a
/// million digits; it is computed without forming it. (Moved from the
/// `decimal` package.)
test "remainder avoids materializing a million-digit quotient" {
  let lhs = Decimal::from_string("9E+1000008", precision=34).unwrap()
  let rhs = Decimal::from_string("469135780", precision=34).unwrap()
  let (value, flags) = lhs.remainder(rhs, decimal_exact_work_context())
  assert_eq(value.coefficient().to_string(), "54833220")
  assert_eq(value.exponent10(), 0)
  assert_false(flags.invalid_operation)
  assert_false(flags.division_impossible)
}
