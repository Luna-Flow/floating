test "bin_float normalizes powers of two" {
  let x = @bin_float.BinFloat::make(12N, 0, 16)
  assert_eq(x.significand(), 3N)
  assert_eq(x.exponent2(), 2)
}

test "bin_float arithmetic stays exact on small dyadics" {
  let a = @bin_float.BinFloat::make(3N, -1, 16)
  let b = @bin_float.BinFloat::make(5N, -1, 16)
  assert_eq((a + b).to_string(), "1p2")
  assert_eq((a * b).to_string(), "15p-2")
}

test "decimal parses and normalizes" {
  let x = @decimal.Decimal::from_string("0012.3400", precision=20)
  assert_true(x == Some(@decimal.Decimal::make(1234N, -2, 20)))
}

test "decimal arithmetic and display" {
  let a = @decimal.Decimal::from_string("1.25", precision=20).unwrap()
  let b = @decimal.Decimal::from_string("2.5", precision=20).unwrap()
  assert_eq((a + b).to_string(), "3.75")
  assert_eq((a * b).to_string(), "3.125")
}

test "bin to decimal conversion is exact for finite values" {
  let x = @bin_float.BinFloat::make(3N, -2, 32)
  let d = @decimal.Decimal::from_bin_float(x, precision=20)
  assert_eq(d.to_string(), "0.75")
}

test "decimal to bin conversion handles non-dyadic values" {
  let d = @decimal.Decimal::from_string("0.1", precision=20).unwrap()
  let x = d.to_bin_float(precision=24)
  let back = @decimal.Decimal::from_bin_float(x, precision=10)
  assert_eq(back.to_string(), "0.09999999404")
}

test "floating is_zero rejects nan" {
  assert_false(@def.is_zero(@bin_float.BinFloat::nan()))
  assert_false(@def.is_zero(@decimal.Decimal::nan()))
}

test "ball_float exact containment works" {
  let x = @bin_float.BinFloat::make(3N, -1, 16)
  let ball = @ball_float.BallFloat::exact(x)
  assert_true(ball.contains(x))
  assert_eq(ball.to_string(), "3p-1 +/- 0")
}

test "ball_float radius rounds outward at lower precision" {
  let ball = @ball_float.BallFloat::new(
    @bin_float.BinFloat::zero(precision=8),
    @bin_float.BinFloat::make(9N, -4, 8),
    precision=2,
  )
  assert_eq(ball.radius().to_string(), "3p-2")
}

test "ball_float from_decimal keeps low precision enclosure" {
  let d = @decimal.Decimal::from_string("0.1", precision=20).unwrap()
  let ball = @ball_float.BallFloat::from_decimal(d, precision=4)
  let approx = d.to_bin_float(precision=64)
  assert_true(ball.contains(approx))
}

test "ball_float overlap detects separated balls" {
  let a = @ball_float.BallFloat::new(
    @bin_float.BinFloat::from_int(10, precision=16),
    @bin_float.BinFloat::from_int(1, precision=16),
  )
  let b = @ball_float.BallFloat::new(
    @bin_float.BinFloat::from_int(15, precision=16),
    @bin_float.BinFloat::from_int(1, precision=16),
  )
  assert_true(a.separated_from(b))
  assert_true(a.definitely_lt(b))
}
