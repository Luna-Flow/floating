///|
test "IEEE 1788 rejects infinity singleton bounds" {
  let precision = 32
  let positive_infinity = @bin_float.BinFloat::inf(
    @def.Sign::Positive,
    precision~,
  )
  let negative_infinity = @bin_float.BinFloat::inf(
    @def.Sign::Negative,
    precision~,
  )
  let positive_result = BallFloatResult::from_bounds(
    positive_infinity,
    positive_infinity,
    precision~,
  )
  assert_true(positive_result.result() is Err(_))
  assert_true(
    positive_result.result() ==
    @ball_float.BallFloat::try_from_bounds(
      positive_infinity,
      positive_infinity,
      precision~,
    ),
  )
  let negative_result = BallFloatResult::from_bounds(
    negative_infinity,
    negative_infinity,
    precision~,
  )
  assert_true(negative_result.result() is Err(_))
  assert_true(
    negative_result.result() ==
    @ball_float.BallFloat::try_from_bounds(
      negative_infinity,
      negative_infinity,
      precision~,
    ),
  )
}

///|
test "checked exact construction shares BallFloat validation" {
  let value = @bin_float.BinFloat::nan(precision=32)
  let result = BallFloatResult::exact(value, precision=32)
  assert_true(result.result() is Err(_))
  assert_true(
    result.result() == @ball_float.BallFloat::try_exact(value, precision=32),
  )
}
