///|
/// Every `ball_float` constructor must return an interval that contains its
/// input. `from_int` and `from_coefficient` used to round the value to the
/// requested precision first and wrap the rounded result as a singleton, which
/// excluded the input whenever it needed more bits than the precision.
test "BallFloat::from_int contains integers wider than the precision" {
  for n in [100001, 65537, 123456789, 2147483647, -100001, -2147483647] {
    let exact = @bin_float.BinFloat::from_int(n, precision=32)
    for precision in [16, 8, 24, 53] {
      let ball = BallFloat::from_int(n, precision~)
      assert_true(ball.contains(exact))
    }
  }
}

///|
test "BallFloat::from_coefficient contains coefficients wider than the precision" {
  let coefficient = @bin_float.BinCoeff::from_uint64(100001UL)
  for negative in [false, true] {
    let exact = @bin_float.BinFloat::from_coefficient(
      coefficient,
      precision=Int::max(1, coefficient.bit_length()),
      negative~,
    )
    for precision in [16, 8, 24] {
      let ball = BallFloat::from_coefficient(coefficient, precision~, negative~)
      assert_true(ball.contains(exact))
    }
  }
}

///|
test "BallFloat::from_int stays exact when the precision is wide enough" {
  let ball = BallFloat::from_int(100001, precision=53)
  assert_eq(ball.radius().classify(), FpClass::Finite)
  assert_true(ball.radius().is_zero())
}
