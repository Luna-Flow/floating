///|
test "ITF1788 minimal decorated set operations" {
  let one = @bin_float.BinFloat::from_int(1, precision=32)
  let three = @bin_float.BinFloat::from_int(3, precision=32)
  let left = BallFloatDecorated::new(
    BallFloat::from_bounds(one, three),
    decoration=Com,
  )
  let right = BallFloatDecorated::new(
    BallFloat::from_bounds(
      @bin_float.BinFloat::from_double(2.1, precision=64),
      @bin_float.BinFloat::from_int(4, precision=32),
    ),
    decoration=Com,
  )
  let intersection = left.intersection(right)
  assert_eq(intersection.decoration(), Trv)
  assert_eq(intersection.interval().upper_bound().compare(three), 0)
  let hull = left.convex_hull(right)
  assert_eq(hull.decoration(), Trv)
  assert_true(hull.interval().contains(one))
  assert_true(
    hull.interval().contains(@bin_float.BinFloat::from_int(4, precision=32)),
  )
}

///|
test "decorated NaI propagates and empty canonicalizes" {
  let nai = BallFloatDecorated::nai(precision=32)
  let value = BallFloatDecorated::new(BallFloat::from_int(1, precision=32))
  assert_true((nai + value).is_nai())
  let empty = BallFloatDecorated::new(
    BallFloat::empty(precision=32),
    decoration=Com,
  )
  assert_eq(empty.decoration(), Trv)
  assert_false(nai.is_empty())
  assert_false(nai.is_entire())
  assert_false(nai.set_equal(nai))
  assert_false(nai.subset(value))
  assert_true(nai.overlap_state(value) == Undefined)
}

///|
test "decorated power and trigonometric functions preserve IEEE domain grades" {
  let entire = BallFloatDecorated::new(
    BallFloat::whole(precision=53),
    decoration=Def,
  )
  let sine = entire.sin_interval()
  assert_eq(sine.decoration(), Def)
  assert_true(
    sine
    .interval()
    .set_equal(
      BallFloat::from_bounds(
        @bin_float.BinFloat::from_int(-1, precision=53),
        @bin_float.BinFloat::one(precision=53),
        precision=53,
      ),
    ),
  )
  assert_eq(entire.tan_interval().decoration(), Trv)
  let negative = BallFloatDecorated::new(
    BallFloat::from_bounds(
      @bin_float.BinFloat::from_int(-2, precision=53),
      @bin_float.BinFloat::from_int(-1, precision=53),
      precision=53,
    ),
  )
  let exponent = BallFloatDecorated::new(BallFloat::from_int(2, precision=53))
  let power = negative.pow_interval(exponent)
  assert_true(power.interval().is_empty())
  assert_eq(power.decoration(), Trv)
}

///|
test "decorated arithmetic applies operand and operation grades" {
  let left = BallFloatDecorated::new(
    BallFloat::from_bounds(
      @bin_float.BinFloat::from_int(1, precision=53),
      @bin_float.BinFloat::from_int(2, precision=53),
    ),
    decoration=Dac,
  )
  let right = BallFloatDecorated::new(
    BallFloat::from_bounds(
      @bin_float.BinFloat::from_int(3, precision=53),
      @bin_float.BinFloat::from_int(4, precision=53),
    ),
    decoration=Com,
  )
  assert_eq((left + right).decoration(), Dac)
  assert_eq((left - right).decoration(), Dac)
  assert_eq((left * right).decoration(), Dac)
  assert_eq((left / right).decoration(), Dac)
  assert_eq(left.minimum(right).decoration(), Dac)
  assert_eq(left.maximum(right).decoration(), Dac)
  assert_eq(left.fma(right, right).decoration(), Dac)
  assert_eq(left.intersection(right).decoration(), Trv)
  assert_eq(left.convex_hull(right).decoration(), Trv)
  assert_eq(left.cancel_plus(right).decoration(), Trv)
  assert_eq(left.cancel_minus(right).decoration(), Trv)
}

///|
test "decorated unary domains downgrade without losing enclosures" {
  let crossing = BallFloatDecorated::new(
    BallFloat::from_bounds(
      @bin_float.BinFloat::from_int(-1, precision=53),
      @bin_float.BinFloat::from_int(1, precision=53),
    ),
  )
  assert_eq(crossing.reciprocal().decoration(), Trv)
  assert_eq(crossing.sqrt_interval().decoration(), Trv)
  assert_eq(crossing.ln_interval().decoration(), Trv)
  assert_eq(crossing.log2_interval().decoration(), Trv)
  assert_eq(crossing.log10_interval().decoration(), Trv)
  assert_eq(crossing.pown(-2).decoration(), Trv)
  let positive = BallFloatDecorated::new(
    BallFloat::from_bounds(
      @bin_float.BinFloat::from_int(1, precision=53),
      @bin_float.BinFloat::from_int(2, precision=53),
    ),
    decoration=Def,
  )
  assert_eq(positive.pos().decoration(), Def)
  assert_eq(positive.neg().decoration(), Def)
  assert_eq(positive.abs().decoration(), Def)
  assert_eq(positive.square().decoration(), Def)
  assert_eq(positive.exp_interval().decoration(), Def)
  assert_eq(positive.exp2_interval().decoration(), Def)
  assert_eq(positive.exp10_interval().decoration(), Def)
  assert_eq(positive.sin_interval().decoration(), Def)
  assert_eq(positive.cos_interval().decoration(), Def)
}

///|
test "decorated NaI propagates through unary binary and ternary operations" {
  let nai = BallFloatDecorated::nai(precision=53)
  let value = BallFloatDecorated::new(BallFloat::from_int(2, precision=53))
  assert_true(nai.reciprocal().is_nai())
  assert_true(nai.sqrt_interval().is_nai())
  assert_true(nai.pow_interval(value).is_nai())
  assert_true(value.pow_interval(nai).is_nai())
  assert_true(nai.fma(value, value).is_nai())
  assert_true(value.fma(nai, value).is_nai())
  assert_true(value.fma(value, nai).is_nai())
}

///|
test "decorated context rounding preserves grade and accumulates flags" {
  let context = BallContext::binary64()
  let overflow_source = BallFloatDecorated::new(
    BallFloat::exact(
      @bin_float.BinFloat::make(@bin_float.BinCoeff::one(), 2000, 53),
    ),
    decoration=Def,
  )
  let (overflowed, overflow_flags) = overflow_source.apply_ctx(context)
  assert_eq(overflowed.decoration(), Def)
  assert_true(overflow_flags.overflow())
  assert_true(overflow_flags.inexact())
  let underflow_source = BallFloatDecorated::new(
    BallFloat::exact(
      @bin_float.BinFloat::make(@bin_float.BinCoeff::one(), -2000, 53),
    ),
    decoration=Dac,
  )
  let (underflowed, underflow_flags) = underflow_source.apply_ctx(context)
  assert_eq(underflowed.decoration(), Dac)
  assert_true(underflow_flags.underflow())
  assert_true(underflow_flags.inexact())
  let combined = overflow_flags.combine(underflow_flags)
  assert_true(combined.overflow())
  assert_true(combined.underflow())
  let (nai, nai_flags) = BallFloatDecorated::nai(precision=53).apply_ctx(
    context,
  )
  assert_true(nai.is_nai())
  assert_eq(nai.decoration(), Ill)
  assert_true(nai_flags == BallFlags::new())
}

///|
fn decorated_test_interval(
  lower : @bin_float.BinFloat,
  upper : @bin_float.BinFloat,
) -> BallFloatDecorated {
  BallFloatDecorated::new(BallFloat::from_bounds(lower, upper, precision=53))
}

///|
/// rootn(x, n) with n < 0 is x^(-1/n), which is undefined at 0, so an argument
/// containing 0 is not inside the domain and the decoration is trv.
test "decorated rootn with a negative degree over 0 is trv" {
  let zero = @bin_float.BinFloat::zero(precision=53)
  let one = @bin_float.BinFloat::one(precision=53)
  let x = decorated_test_interval(zero, one)
  for degree in [-1, -2, -3] {
    assert_eq(x.rootn(degree).decoration(), Trv)
  }
  assert_eq(decorated_test_interval(one.neg(), one).rootn(-3).decoration(), Trv)
  // Away from 0 the negative degrees stay common.
  let positive = decorated_test_interval(one, @bin_float.BinFloat::from_int(4))
  assert_eq(positive.rootn(-2).decoration(), Com)
  assert_eq(positive.rootn(-1).decoration(), Com)
  assert_eq(
    decorated_test_interval(@bin_float.BinFloat::from_int(-8), one.neg())
    .rootn(-3)
    .decoration(),
    Com,
  )
  // Positive degrees are defined at 0.
  assert_eq(x.rootn(2).decoration(), Com)
  assert_eq(x.rootn(3).decoration(), Com)
}

///|
/// A pole of tanpi at an endpoint gives a half-unbounded image; the argument
/// is not inside the domain, so the decoration is trv, not dac.
test "decorated tanpi with a pole at an endpoint is trv" {
  let zero = @bin_float.BinFloat::zero(precision=53)
  let half = @bin_float.BinFloat::make(@bin_float.BinCoeff::one(), -1, 53)
  let one = @bin_float.BinFloat::one(precision=53)
  let lower_pole = decorated_test_interval(half, one).tanpi_interval()
  assert_true(
    lower_pole.interval().lower_bound().classify() == FpClass::Infinity,
  )
  assert_eq(lower_pole.decoration(), Trv)
  let upper_pole = decorated_test_interval(zero, half).tanpi_interval()
  assert_true(
    upper_pole.interval().upper_bound().classify() == FpClass::Infinity,
  )
  assert_eq(upper_pole.decoration(), Trv)
  let interior_pole = decorated_test_interval(zero, one).tanpi_interval()
  assert_eq(interior_pole.decoration(), Trv)
  // Without a pole the result is bounded and common.
  let quarter = @bin_float.BinFloat::make(@bin_float.BinCoeff::one(), -2, 53)
  assert_eq(
    decorated_test_interval(quarter.neg(), quarter)
    .tanpi_interval()
    .decoration(),
    Com,
  )
}
