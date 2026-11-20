///|
test "binary conversions keep the sign of zero (IEEE 754 5.4.2, 6.3)" {
  let negative = @bin_float.BinFloat::negative_zero(precision=53)
  let positive = @bin_float.BinFloat::zero(precision=53)
  let from_negative = Decimal::from_bin_float(negative)
  inspect(from_negative, content="-0")
  assert_true(from_negative.is_negative_zero())
  let from_positive = Decimal::from_bin_float(positive)
  inspect(from_positive, content="0")
  assert_false(from_positive.is_negative_zero())
  inspect(
    Decimal::from_bin_float(positive.neg(), precision=16).is_negative_zero(),
    content="true",
  )
  let back = Decimal::negative_zero().to_bin_float(precision=53)
  assert_true(back.is_zero() && back.is_negative())
  let back_positive = Decimal::zero().to_bin_float(precision=53)
  assert_true(back_positive.is_zero() && !back_positive.is_negative())
  let exponent_zero = Decimal::from_string("-0.000").unwrap().to_bin_float()
  assert_true(exponent_zero.is_zero() && exponent_zero.is_negative())
}
