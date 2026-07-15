///|
fn composed_singleton(value : Double) -> BallFloat {
  BallFloat::from_double(value, precision=53)
}

///|
test "rootn and hypot preserve exact identities" {
  let eight = composed_singleton(8.0).rootn(3)
  assert_true(eight.contains(@bin_float.BinFloat::from_double(2.0)))
  let negative_eight = composed_singleton(-8.0).rootn(3)
  assert_true(negative_eight.contains(@bin_float.BinFloat::from_double(-2.0)))
  let hypot = composed_singleton(3.0).hypot(composed_singleton(4.0))
  assert_true(hypot.contains(@bin_float.BinFloat::from_double(5.0)))
  assert_true(
    composed_singleton(3.0).try_hypot(composed_singleton(4.0)) is Ok(_),
  )
  assert_true(composed_singleton(-1.0).rootn(2).is_empty())
}

///|
test "pi-scaled extensions contain exact axis values" {
  assert_true(
    composed_singleton(0.0)
    .sinpi_interval()
    .contains(@bin_float.BinFloat::zero()),
  )
  assert_true(
    composed_singleton(0.0)
    .cospi_interval()
    .contains(@bin_float.BinFloat::one()),
  )
  let huge_integer = BallFloat::exact(
    @bin_float.BinFloat::make(@bin_float.BinCoeff::one(), 40, 53),
  )
  assert_true(huge_integer.sinpi_interval().contains_zero())
  assert_true(
    huge_integer.cospi_interval().contains(@bin_float.BinFloat::one()),
  )
}

///|
test "pi-scaled intervals classify endpoint and interior poles exactly" {
  let upper_pole = BallFloat::from_bounds(
      @bin_float.BinFloat::zero(precision=53),
      @bin_float.BinFloat::make(@bin_float.BinCoeff::one(), -1, 53),
      precision=53,
    )
    .try_tanpi_interval()
    .unwrap()
  assert_true(upper_pole.lower_bound().is_zero())
  assert_true(upper_pole.upper_bound().classify() == @def.FpClass::Infinity)
  let lower_pole = BallFloat::from_bounds(
      @bin_float.BinFloat::make(@bin_float.BinCoeff::one(), -1, 53),
      @bin_float.BinFloat::one(precision=53),
      precision=53,
    )
    .try_tanpi_interval()
    .unwrap()
  assert_true(lower_pole.lower_bound().classify() == @def.FpClass::Infinity)
  assert_true(lower_pole.lower_bound().sign() == @def.Sign::Negative)
  assert_true(lower_pole.upper_bound().is_zero())
  assert_true(
    BallFloat::from_bounds(
      @bin_float.BinFloat::make(@bin_float.BinCoeff::one(), -2, 53),
      @bin_float.BinFloat::make(@bin_float.BinCoeff::from_uint64(3UL), -2, 53),
      precision=53,
    )
    .try_tanpi_interval()
    .unwrap()
    .is_entire(),
  )
  assert_true(composed_singleton(0.5).try_tanpi_interval().unwrap().is_empty())
}

///|
test "stable expm1 and log1p intervals retain tiny singleton inputs" {
  let tiny_value = @bin_float.BinFloat::make(
    @bin_float.BinCoeff::one(),
    -200,
    53,
  )
  let tiny = BallFloat::exact(tiny_value)
  let expm1 = tiny.expm1_interval()
  let log1p = tiny.log1p_interval()
  assert_false(expm1.contains_zero())
  assert_false(log1p.contains_zero())
  assert_true(expm1.lower_bound().sign() == @def.Sign::Positive)
  assert_true(log1p.lower_bound().sign() == @def.Sign::Positive)
}

///|
test "hyperbolic family preserves zero and domain hulls" {
  let zero = composed_singleton(0.0)
  assert_true(zero.sinh_interval().contains(@bin_float.BinFloat::zero()))
  assert_true(zero.tanh_interval().contains(@bin_float.BinFloat::zero()))
  assert_true(zero.cosh_interval().contains(@bin_float.BinFloat::one()))
  assert_true(zero.asinh_interval().contains(@bin_float.BinFloat::zero()))
  assert_true(composed_singleton(0.5).acosh_interval().is_empty())
}

///|
test "decorated composed functions lower partial domains" {
  let negative = BallFloatDecorated::new(composed_singleton(-1.0))
  assert_eq(negative.rootn(2).decoration(), Trv)
  assert_eq(negative.acosh_interval().decoration(), Trv)
  assert_eq(
    BallFloatDecorated::new(composed_singleton(0.0))
    .sinh_interval()
    .decoration(),
    Com,
  )
  let half = BallFloatDecorated::new(composed_singleton(0.5))
  let tangent = half.tanpi_interval()
  assert_true(tangent.is_empty())
  assert_eq(tangent.decoration(), Trv)
  assert_eq(BallFloatDecorated::new(BallFloat::empty()).decoration(), Trv)
  assert_true(BallFloatDecorated::nai().is_nai())
  assert_eq(BallFloatDecorated::nai().decoration(), Ill)
}
