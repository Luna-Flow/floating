///|
fn composed_singleton(value : Double) -> Interval {
  Interval::from_double(value, precision=53)
}

///|
test "rootn and hypot preserve exact identities" {
  let eight = composed_singleton(8.0).rootn(3)
  assert_true(eight.is_member(@binary.Binary::from_double(2.0)))
  let negative_eight = composed_singleton(-8.0).rootn(3)
  assert_true(negative_eight.is_member(@binary.Binary::from_double(-2.0)))
  let hypot = composed_singleton(3.0).hypot(composed_singleton(4.0))
  assert_true(hypot.is_member(@binary.Binary::from_double(5.0)))
  assert_true(
    composed_singleton(3.0).try_hypot(composed_singleton(4.0)) is Ok(_),
  )
  assert_true(composed_singleton(-1.0).rootn(2).is_empty())
}

///|
test "pi-scaled extensions contain exact axis values" {
  assert_true(composed_singleton(0.0).sinpi().is_member(@binary.Binary::zero()))
  assert_true(composed_singleton(0.0).cospi().is_member(@binary.Binary::one()))
  let huge_integer = Interval::exact(
    @binary.Binary::make(@binary.BinCoeff::one(), 40, 53),
  )
  assert_true(huge_integer.sinpi().contains_zero())
  assert_true(huge_integer.cospi().is_member(@binary.Binary::one()))
}

///|
test "pi-scaled intervals classify endpoint and interior poles exactly" {
  let upper_pole = Interval::from_bounds(
      @binary.Binary::zero(precision=53),
      @binary.Binary::make(@binary.BinCoeff::one(), -1, 53),
      precision=53,
    )
    .try_tanpi()
    .unwrap()
  assert_true(upper_pole.lower_bound().is_zero())
  assert_true(upper_pole.upper_bound().classify() == @def.FpClass::Infinity)
  let lower_pole = Interval::from_bounds(
      @binary.Binary::make(@binary.BinCoeff::one(), -1, 53),
      @binary.Binary::one(precision=53),
      precision=53,
    )
    .try_tanpi()
    .unwrap()
  assert_true(lower_pole.lower_bound().classify() == @def.FpClass::Infinity)
  assert_true(lower_pole.lower_bound().sign() == @def.Sign::Negative)
  assert_true(lower_pole.upper_bound().is_zero())
  assert_true(
    Interval::from_bounds(
      @binary.Binary::make(@binary.BinCoeff::one(), -2, 53),
      @binary.Binary::make(@binary.BinCoeff::from_uint64(3UL), -2, 53),
      precision=53,
    )
    .try_tanpi()
    .unwrap()
    .is_entire(),
  )
  assert_true(composed_singleton(0.5).try_tanpi().unwrap().is_empty())
}

///|
test "stable expm1 and log1p intervals retain tiny singleton inputs" {
  let tiny_value = @binary.Binary::make(@binary.BinCoeff::one(), -200, 53)
  let tiny = Interval::exact(tiny_value)
  let expm1 = tiny.expm1()
  let log1p = tiny.log1p()
  assert_false(expm1.contains_zero())
  assert_false(log1p.contains_zero())
  assert_true(expm1.lower_bound().sign() == @def.Sign::Positive)
  assert_true(log1p.lower_bound().sign() == @def.Sign::Positive)
}

///|
test "hyperbolic family preserves zero and domain hulls" {
  let zero = composed_singleton(0.0)
  assert_true(zero.sinh().is_member(@binary.Binary::zero()))
  assert_true(zero.tanh().is_member(@binary.Binary::zero()))
  assert_true(zero.cosh().is_member(@binary.Binary::one()))
  assert_true(zero.asinh().is_member(@binary.Binary::zero()))
  assert_true(composed_singleton(0.5).acosh().is_empty())
}

///|
test "decorated composed functions lower partial domains" {
  let negative = DecoratedInterval::new(composed_singleton(-1.0))
  assert_eq(negative.rootn(2).decoration(), Trv)
  assert_eq(negative.acosh().decoration(), Trv)
  assert_eq(
    DecoratedInterval::new(composed_singleton(0.0)).sinh().decoration(),
    Com,
  )
  let half = DecoratedInterval::new(composed_singleton(0.5))
  let tangent = half.tanpi()
  assert_true(tangent.is_empty())
  assert_eq(tangent.decoration(), Trv)
  assert_eq(DecoratedInterval::new(Interval::empty()).decoration(), Trv)
  assert_true(DecoratedInterval::nai().is_nai())
  assert_eq(DecoratedInterval::nai().decoration(), Ill)
}

///|
// oracle: A
// source: written out from Table 10.5 of IEEE 1788-2015 (rootn(x, q) is defined for a nonzero integer q only, so degree 0 has no point of the domain and the interval extension is empty)
// shares: nothing
test "rootn of degree 0 and of an empty interval is empty, with the precision of the operand" {
  for p in [24, 53, 113] {
    let x = Interval::from_double(2.0, precision=p)
    let zero_degree = x.rootn(0)
    assert_true(zero_degree.is_empty())
    assert_eq(zero_degree.precision(), p)
    let empty = Interval::empty(precision=p)
    for degree in [-3, -2, 0, 2, 3] {
      assert_true(empty.rootn(degree).is_empty())
      assert_eq(empty.rootn(degree).precision(), p)
    }
    assert_true(empty.try_rootn(0) is Err(_))
    assert_true(x.try_rootn(0) is Err(_))
  }
}
