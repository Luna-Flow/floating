///|
// oracle: A
// source: written out from IEEE 754-2019 5.4.2 and 6.3 (a conversion of a zero keeps its sign): -0 gives -0, +0 gives 0, in both directions and for a zero with exponent -3
// shares: Binary::negative_zero, zero and neg (they build the operands), Decimal::from_binary, to_binary, from_string and is_negative_zero (the code under test)
test "binary conversions keep the sign of zero (IEEE 754 5.4.2, 6.3)" {
  let negative = @binary.Binary::negative_zero(precision=53)
  let positive = @binary.Binary::zero(precision=53)
  let from_negative = Decimal::from_binary(negative, precision=34)
  inspect(from_negative, content="-0")
  assert_true(from_negative.is_negative_zero())
  let from_positive = Decimal::from_binary(positive, precision=34)
  inspect(from_positive, content="0")
  assert_false(from_positive.is_negative_zero())
  inspect(
    Decimal::from_binary(positive.neg(), precision=16).is_negative_zero(),
    content="true",
  )
  let back = Decimal::negative_zero().to_binary(precision=53)
  assert_true(back.is_zero() && back.is_sign_minus())
  let back_positive = Decimal::zero().to_binary(precision=53)
  assert_true(back_positive.is_zero() && !back_positive.is_sign_minus())
  let exponent_zero = Decimal::from_string("-0.000")
    .unwrap()
    .to_binary(precision=53)
  assert_true(exponent_zero.is_zero() && exponent_zero.is_sign_minus())
}
