///|
// oracle: A
// source: written out: 1E+20 rem 1 is 0 (the quotient is an integer; IEEE Std 754-2019 5.3.1), no invalid operation
// shares: Decimal::from_string and one build the operands; remainder_ctx is the code under test; DecimalContext::decimal32 builds the context; is_zero and the flag read the result
test "IEEE remainder keeps an infinite quotient intermediate" {
  let ctx = DecimalContext::decimal32()
  let lhs = Decimal::from_string("1E+20", precision=34).unwrap()
  let rhs = Decimal::one(precision=34)
  let (value, flags) = lhs.remainder_ctx(rhs, ctx)
  assert_true(value.is_zero())
  assert_false(flags.invalid_operation)
}

///|
// oracle: A
// source: 9 * 10^1000008 mod 469135780 computed with Python integers (pow(10, 1000008, 469135780) * 9 reduced to the nearest residue, library-ran: no) is 54833220, at exponent 0, no invalid operation (IEEE Std 754-2019 5.3.1)
// shares: Decimal::from_string reads the operands; remainder_ctx is the code under test; DecimalContext::new builds the context; coefficient, exponent10 and the flag read the result
test "remainder avoids materializing a million-digit quotient" {
  let ctx = DecimalContext::new(precision=34, e_max=2_000_000)
  let lhs = Decimal::from_string("9E+1000008", precision=34).unwrap()
  let rhs = Decimal::from_string("469135780", precision=34).unwrap()
  let (value, flags) = lhs.remainder_ctx(rhs, ctx)
  assert_eq(value.coefficient().to_string(), "54833220")
  assert_eq(value.exponent10(), 0)
  assert_false(flags.invalid_operation)
}
