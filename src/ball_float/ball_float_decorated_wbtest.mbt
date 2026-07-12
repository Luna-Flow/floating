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
