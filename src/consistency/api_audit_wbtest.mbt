test "def predicates classify finite nan and enclosing zero consistently" {
  let finite = @bin_float.BinFloat::from_int(3, precision=8)
  let nan = @bin_float.BinFloat::nan(precision=8)
  let inf = @decimal.Decimal::inf(@def.Sign::Positive, precision=8)
  let straddle = @ball_float.BallFloat::new(
    @bin_float.BinFloat::zero(precision=8),
    @bin_float.BinFloat::make(1N, -2, 8),
    precision=8,
  )
  assert_true(@def.is_finite(finite))
  assert_true(@def.is_nan(nan))
  assert_true(@def.is_infinite(inf))
  assert_true(@def.is_zero(straddle))
  assert_false(@def.is_zero(nan))
}

test "internal rounding helpers honor tie and directed modes" {
  assert_eq(
    @internal.round_positive_div(5N, 2N, false, @def.RoundingMode::ToNearestEven).to_string(),
    "2",
  )
  assert_eq(
    @internal.round_positive_div(7N, 2N, false, @def.RoundingMode::ToNearestEven).to_string(),
    "4",
  )
  assert_eq(
    @internal.round_positive_div(3N, 2N, false, @def.RoundingMode::TowardZero).to_string(),
    "1",
  )
  assert_eq(
    @internal.round_positive_div(3N, 2N, true, @def.RoundingMode::TowardNegative).to_string(),
    "2",
  )
  assert_eq(
    @internal.round_shift(7N, 1, false, @def.RoundingMode::AwayFromZero).to_string(),
    "4",
  )
  assert_eq(@internal.compare_abs(-3N, 2N), 1)
}

test "internal decimal parser accepts scientific notation and rejects malformed strings" {
  match @internal.split_decimal_string("12.340e-1") {
    Some((negative, digits, exponent10)) => {
      assert_false(negative)
      assert_eq(digits, "12340")
      assert_eq(exponent10, -4)
    }
    None => fail("expected scientific decimal parse to succeed")
  }
  match @internal.split_decimal_string("-0.05E+3") {
    Some((negative, digits, exponent10)) => {
      assert_true(negative)
      assert_eq(digits, "005")
      assert_eq(exponent10, 1)
    }
    None => fail("expected signed scientific decimal parse to succeed")
  }
  assert_true(@internal.split_decimal_string("1e") is None)
  assert_true(@internal.split_decimal_string("..1") is None)
}

test "bin_float with_precision rounds and ulp tracks spacing" {
  let x = @bin_float.BinFloat::make(13N, -3, 8)
  let rounded = x.with_precision(2, @def.RoundingMode::ToNearestEven)
  assert_eq(rounded.to_string(), "3p-1")
  assert_eq(rounded.ulp().to_string(), "1p-1")
  assert_eq(@bin_float.BinFloat::zero(precision=4).ulp().to_string(), "1p-3")
}

test "bin_float compare orders finite and infinities" {
  let a = @bin_float.BinFloat::make(3N, -1, 8)
  let b = @bin_float.BinFloat::make(5N, -2, 8)
  assert_eq(a.compare(b), 1)
  assert_eq(@bin_float.BinFloat::inf(@def.Sign::Negative).compare(a), -1)
  assert_eq(@bin_float.BinFloat::inf(@def.Sign::Positive).compare(a), 1)
}

test "decimal make and display normalize trailing zeros" {
  let x = @decimal.Decimal::make(1200N, -2, 12)
  assert_eq(x.coefficient(), 12N)
  assert_eq(x.exponent10(), 0)
  assert_eq(x.to_string(), "12")
}

test "decimal binary conversion preserves dyadics exactly" {
  let d = @decimal.Decimal::from_string("0.375", precision=20).unwrap()
  let x = d.to_bin_float(precision=20)
  assert_eq(x.to_string(), "3p-3")
  assert_eq(@decimal.Decimal::from_bin_float(x, precision=20).to_string(), "0.375")
}

test "ball_float exact widens when lowering precision" {
  let x = @bin_float.BinFloat::make(5N, -3, 8)
  let ball = @ball_float.BallFloat::exact(x, precision=2)
  assert_eq(ball.center().to_string(), "1p-1")
  assert_eq(ball.radius().to_string(), "1p-3")
  assert_true(ball.contains(x))
}

test "ball_float new preserves an input endpoint after center rounding" {
  let center = @bin_float.BinFloat::make(5N, -3, 8)
  let radius = @bin_float.BinFloat::make(1N, -3, 8)
  let ball = @ball_float.BallFloat::new(center, radius, precision=2)
  let hi = @bin_float.BinFloat::make(3N, -2, 8)
  let lo = @bin_float.BinFloat::make(1N, -1, 8)
  assert_true(ball.contains(hi))
  assert_true(ball.contains(lo))
}

test "ball_float multiplication keeps exact scalar result inside zero-radius inputs" {
  let a = @ball_float.BallFloat::exact(@bin_float.BinFloat::make(3N, -1, 8), precision=2)
  let b = @ball_float.BallFloat::exact(@bin_float.BinFloat::make(3N, -1, 8), precision=2)
  let product = a * b
  let exact = @bin_float.BinFloat::make(9N, -2, 16)
  assert_true(product.contains(exact))
}

test "ball_float division keeps exact scalar result inside zero-radius inputs" {
  let a = @ball_float.BallFloat::exact(@bin_float.BinFloat::make(3N, -1, 8), precision=3)
  let b = @ball_float.BallFloat::exact(@bin_float.BinFloat::make(5N, -2, 8), precision=3)
  let q = a / b
  let exact = @decimal.Decimal::from_string("1.2", precision=40).unwrap().to_bin_float(precision=80)
  assert_true(q.contains(exact))
}

test "ball_float sign and overlap relations remain enclosure based" {
  let cross = @ball_float.BallFloat::new(
    @bin_float.BinFloat::make(1N, -2, 8),
    @bin_float.BinFloat::make(1N, -1, 8),
    precision=4,
  )
  let right = @ball_float.BallFloat::new(
    @bin_float.BinFloat::from_int(2, precision=8),
    @bin_float.BinFloat::make(1N, -2, 8),
    precision=4,
  )
  assert_true(cross.sign() == @def.Sign::Zero)
  assert_true(cross.definitely_lt(right))
  assert_true(cross.separated_from(right))
  assert_false(cross.overlaps(right))
}
