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

test "binary and decimal constructors accept double and float inputs" {
  let bin_d = @bin_float.BinFloat::from_double(0.375)
  let bin_f = @bin_float.BinFloat::from_float(Float::from_double(0.375))
  let dec_d = @decimal.Decimal::from_double(0.375, precision=20)
  let dec_f = @decimal.Decimal::from_float(Float::from_double(0.375), precision=20)
  assert_eq(bin_d.to_string(), "3p-3")
  assert_eq(bin_f.to_string(), "3p-3")
  assert_eq(dec_d.to_string(), "0.375")
  assert_eq(dec_f.to_string(), "0.375")
}

test "double constructors preserve special values" {
  assert_true(@def.is_nan(@bin_float.BinFloat::from_double(0.0 / 0.0)))
  assert_true(@def.is_infinite(@bin_float.BinFloat::from_double(1.0 / 0.0)))
  assert_true(@def.is_nan(@decimal.Decimal::from_double(0.0 / 0.0)))
  assert_true(@def.is_infinite(@decimal.Decimal::from_double(-1.0 / 0.0)))
}

test "floating is_zero rejects nan" {
  assert_false(@def.is_zero(@bin_float.BinFloat::nan()))
  assert_false(@def.is_zero(@decimal.Decimal::nan()))
}

test "bin_float compare helpers align with scalar ordering" {
  let a = @bin_float.BinFloat::from_int(2, precision=16)
  let b = @bin_float.BinFloat::from_int(5, precision=16)
  assert_true(a < b)
  assert_true(b > a)
  assert_eq(a.max(b).to_string(), "5p0")
  assert_eq(b.min(a).to_string(), "1p1")
  assert_eq(@bin_float.BinFloat::from_int(9, precision=16).clamp(min=a, max=b).to_string(), "5p0")
}

test "decimal compare helpers align with scalar ordering" {
  let a = @decimal.Decimal::from_string("1.25", precision=20).unwrap()
  let b = @decimal.Decimal::from_string("2.5", precision=20).unwrap()
  assert_true(a < b)
  assert_true(b > a)
  assert_eq(a.max(b).to_string(), "2.5")
  assert_eq(b.min(a).to_string(), "1.25")
  assert_eq(@decimal.Decimal::from_string("9", precision=20).unwrap().clamp(min=a, max=b).to_string(), "2.5")
}

test "ball_float exact containment works" {
  let x = @bin_float.BinFloat::make(3N, -1, 16)
  let ball = @ball_float.BallFloat::exact(x)
  assert_true(ball.contains(x))
  assert_eq(ball.to_string(), "3p-1 +/- 0")
}

test "ball_float constructors accept bigint and float family inputs" {
  let from_big = @ball_float.BallFloat::from_bigint(42N, precision=20)
  let from_double = @ball_float.BallFloat::from_double(0.375, precision=20)
  let from_float = @ball_float.BallFloat::from_float(Float::from_double(0.375), precision=20)
  assert_true(from_big.contains(@bin_float.BinFloat::from_int(42, precision=64)))
  assert_true(from_double.contains(@bin_float.BinFloat::from_double(0.375, precision=64)))
  assert_true(from_float.contains(@bin_float.BinFloat::from_double(0.375, precision=64)))
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

test "ball_float compare helpers work on separated intervals" {
  let a = @ball_float.BallFloat::new(
    @bin_float.BinFloat::from_int(1, precision=16),
    @bin_float.BinFloat::make(1N, -2, 16),
    precision=16,
  )
  let b = @ball_float.BallFloat::new(
    @bin_float.BinFloat::from_int(3, precision=16),
    @bin_float.BinFloat::make(1N, -2, 16),
    precision=16,
  )
  assert_true(a < b)
  assert_true(b > a)
  assert_true(a.max(b) == b)
  assert_true(b.min(a) == a)
  assert_true(@ball_float.BallFloat::from_int(10, precision=16).clamp(min=a, max=b) == b)
  assert_eq(a.compare(a), 0)
}

fn[T : @lg.Field + @lg.Num] scalar_identity_roundtrip(x : T) -> T {
  @lg.Num::abs((x * T::one()) + T::zero() - x)
}

test "lg field and num traits compile for floating scalar types" {
  let x = @bin_float.BinFloat::make(3N, -1, 16)
  let d = @decimal.Decimal::from_string("1.25", precision=20).unwrap()
  assert_true(scalar_identity_roundtrip(x).is_zero())
  assert_true(scalar_identity_roundtrip(d).is_zero())
}

test "bin_float arithmetic traits expose representative values" {
  let x = @bin_float.BinFloat::from_int(4, precision=20)
  assert_eq(@arith.Sqrt::sqrt(x).to_string(), "1p1")
  assert_eq(@lg.Num::signum(@bin_float.BinFloat::from_int(-3, precision=20)).to_string(), "-1p0")
  let sin0 = @arith.Trigonometric::sin(@bin_float.BinFloat::zero(precision=20))
  assert_true(sin0.is_zero())
}

test "decimal arithmetic traits expose representative values" {
  let x = @decimal.Decimal::from_string("9", precision=20).unwrap()
  assert_eq(@arith.Sqrt::sqrt(x).to_string(), "3")
  assert_eq(@lg.Num::signum(@decimal.Decimal::from_string("-2", precision=20).unwrap()).to_string(), "-1")
  let e = @arith.Constants::e()
  let one = @arith.Logarithmic::ln((e : @decimal.Decimal))
  let tol = @decimal.Decimal::from_string("0.0000000001", precision=20).unwrap()
  let err = (one - @decimal.Decimal::one(precision=20)).abs().to_bin_float(precision=80)
  assert_true(err.compare(tol.to_bin_float(precision=80)) <= 0)
}

test "ball_float arithmetic traits keep exact scalar results enclosed" {
  let x = @ball_float.BallFloat::exact(@bin_float.BinFloat::from_int(4, precision=32), precision=16)
  let sqrt_x = @arith.Sqrt::sqrt(x)
  assert_true(sqrt_x.contains(@bin_float.BinFloat::from_int(2, precision=64)))
  let exp0 = @arith.Exponential::exp(@ball_float.BallFloat::exact(@bin_float.BinFloat::zero(precision=32), precision=16))
  assert_true(exp0.contains(@bin_float.BinFloat::one(precision=64)))
  let sin_band = @arith.Trigonometric::sin(x)
  let sin_ref = @bin_float.sin_for_precision(@bin_float.BinFloat::from_int(4, precision=128), 128)
  assert_true(sin_band.contains(sin_ref))
}

test "ball_float atan2 keeps quadrant-contained enclosure" {
  let y = @ball_float.BallFloat::new(
    @bin_float.BinFloat::make(3N, -2, 32),
    @bin_float.BinFloat::make(1N, -2, 32),
    precision=24,
  )
  let x = @ball_float.BallFloat::new(
    @bin_float.BinFloat::make(3N, -1, 32),
    @bin_float.BinFloat::make(1N, -2, 32),
    precision=24,
  )
  let theta = @arith.InverseTrigonometric::atan2(y, x)
  let ref_lo = @bin_float.atan2_for_precision(y.lower_bound(), x.upper_bound(), 128)
  let ref_hi = @bin_float.atan2_for_precision(y.upper_bound(), x.lower_bound(), 128)
  assert_true(theta.contains(ref_lo))
  assert_true(theta.contains(ref_hi))
}

test "ball_float atan2 widens across negative-axis branch cut" {
  let y = @ball_float.BallFloat::new(
    @bin_float.BinFloat::zero(precision=32),
    @bin_float.BinFloat::one(precision=32),
    precision=24,
  )
  let x = @ball_float.BallFloat::new(
    @bin_float.BinFloat::from_int(-2, precision=32),
    @bin_float.BinFloat::make(1N, -1, 32),
    precision=24,
  )
  let theta = @arith.InverseTrigonometric::atan2(y, x)
  let pi = @bin_float.pi_for_precision(128)
  assert_true(theta.contains(pi))
  assert_true(theta.contains(pi.neg()))
  assert_true(theta.contains(@bin_float.BinFloat::zero(precision=128)))
}

test "ball_float atan2 returns full angle enclosure when rectangle contains origin" {
  let y = @ball_float.BallFloat::new(
    @bin_float.BinFloat::zero(precision=32),
    @bin_float.BinFloat::one(precision=32),
    precision=24,
  )
  let x = @ball_float.BallFloat::new(
    @bin_float.BinFloat::zero(precision=32),
    @bin_float.BinFloat::one(precision=32),
    precision=24,
  )
  let theta = @arith.InverseTrigonometric::atan2(y, x)
  let pi = @bin_float.pi_for_precision(128)
  let half_pi = @bin_float.half_pi_for_precision(128)
  assert_true(theta.contains(pi))
  assert_true(theta.contains(pi.neg()))
  assert_true(theta.contains(half_pi))
  assert_true(theta.contains(half_pi.neg()))
}

test "bin_float inverse trig and pow cover representative exact cases" {
  let asin_zero = @bin_float.asin_for_precision(@bin_float.BinFloat::zero(precision=64), 96)
  let acos_one = @bin_float.acos_for_precision(@bin_float.BinFloat::one(precision=64), 96)
  let pow_val = @bin_float.pow_for_precision(
    @bin_float.BinFloat::from_int(4, precision=96),
    @bin_float.BinFloat::from_int(2, precision=96),
    96,
  )
  assert_true(asin_zero.is_zero())
  assert_true(acos_one.is_zero())
  assert_eq(pow_val.to_string(), "1p4")
}

test "panic bin_float pow with non-integer exponent on negative base" {
  @bin_float.pow_for_precision(
    @bin_float.BinFloat::from_int(-2, precision=80),
    @bin_float.BinFloat::make(1N, -1, 80),
    80,
  ) |> ignore
}

test "panic bin_float asin outside closed unit interval" {
  @bin_float.asin_for_precision(@bin_float.BinFloat::from_int(2, precision=40), 40) |> ignore
}

test "panic bin_float acosh below one" {
  @bin_float.acosh_for_precision(@bin_float.BinFloat::make(3N, -2, 40), 40) |> ignore
}

test "panic ball_float compare on overlapping intervals" {
  let a = @ball_float.BallFloat::new(
    @bin_float.BinFloat::from_int(0, precision=20),
    @bin_float.BinFloat::one(precision=20),
    precision=20,
  )
  let b = @ball_float.BallFloat::new(
    @bin_float.BinFloat::from_int(1, precision=20),
    @bin_float.BinFloat::one(precision=20),
    precision=20,
  )
  a.compare(b) |> ignore
}

test "panic ball_float pow with non-exact exponent interval" {
  let base = @ball_float.BallFloat::exact(@bin_float.BinFloat::from_int(4, precision=20), precision=20)
  let exponent = @ball_float.BallFloat::new(
    @bin_float.BinFloat::from_int(1, precision=20),
    @bin_float.BinFloat::make(1N, -2, 20),
    precision=20,
  )
  base.pow(exponent) |> ignore
}

test "panic ball_float pow with non-positive base and non-integer exponent" {
  let base = @ball_float.BallFloat::new(
    @bin_float.BinFloat::make(-1N, 0, 20),
    @bin_float.BinFloat::one(precision=20),
    precision=20,
  )
  let exponent = @ball_float.BallFloat::exact(@bin_float.BinFloat::make(3N, -1, 20), precision=20)
  base.pow(exponent) |> ignore
}

test "ball_float constants and signum stay finite enclosures" {
  let pi_ball : @ball_float.BallFloat = @arith.Constants::pi()
  let pi_ref = @decimal.Decimal::from_string(
    "3.141592653589793238462643383279502884197169399375105",
    precision=80,
  ).unwrap().to_bin_float(precision=80)
  let sign_cross = @lg.Num::signum(
    @ball_float.BallFloat::new(
      @bin_float.BinFloat::zero(precision=16),
      @bin_float.BinFloat::make(1N, -2, 16),
      precision=16,
    ),
  )
  assert_true(pi_ball.is_bounded())
  assert_true(pi_ball.contains(pi_ref))
  assert_true(sign_cross.contains(@bin_float.BinFloat::from_int(-1, precision=32)))
  assert_true(sign_cross.contains(@bin_float.BinFloat::zero(precision=32)))
  assert_true(sign_cross.contains(@bin_float.BinFloat::from_int(1, precision=32)))
}
