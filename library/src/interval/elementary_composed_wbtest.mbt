///|
fn composed_singleton(value : Double) -> Interval {
  Interval::from_double(value, precision=53)
}

///|
// oracle: A, S
// source: containment of the exact values rootn(8, 3) = 2, rootn(-8, 3) = -2 and hypot(3, 4) = 5 (S: membership only, no end value); the Empty result of rootn(-1, 2) is by the domain of Table 9.1 (a square root of a negative number), written out (A)
// shares: Interval::from_double, Interval::exact, Binary::from_double, Binary::make and is_member build the inputs and test membership; the composed functions are the code under test
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
// oracle: A
// source: written out by hand: sinpi(0) = 0, cospi(0) = 1, and at the even integer 2^40 sinpi = 0 and cospi = 1 (sin(k pi) = 0, cos(2 m pi) = 1); these are exact, so the tightest enclosure is the point
// shares: Interval::from_double, Interval::exact, Binary::from_double and Binary::make build the inputs; Binary::compare compares the ends; the composed functions are the code under test
test "pi-scaled extensions contain exact axis values" {
  let point = fn(x : Interval, value : @binary.Binary) -> Unit raise {
    assert_eq(x.lower_bound().compare(value), 0)
    assert_eq(x.upper_bound().compare(value), 0)
  }
  point(composed_singleton(0.0).sinpi(), @binary.Binary::zero())
  point(composed_singleton(0.0).cospi(), @binary.Binary::one())
  let huge_integer = Interval::exact(
    @binary.Binary::make(@binary.BinCoeff::one(), 40, 53),
  )
  point(huge_integer.sinpi(), @binary.Binary::zero())
  point(huge_integer.cospi(), @binary.Binary::one())
}

///|
// oracle: A
// source: worked by hand from IEEE 1788-2015 Table 9.1 (tanpi(x) = tan(pi x), poles at x = 1/2 + k): tanpi([0, 1/2]) = [0, +inf), tanpi([1/2, 1]) = (-inf, 0], tanpi([1/4, 3/4]) contains the pole in its interior so it is Entire, tanpi([0.5]) is Empty (the pole is not in the domain)
// shares: Interval::from_double, Interval::exact, Binary::from_double, Binary::make and is_member build the inputs and test membership; the composed functions are the code under test
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
  assert_true(lower_pole.lower_bound().signum() == @def.Sign::Negative)
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
// oracle: A
// source: worked out by hand for x = 2^-200 at 53 bits: expm1(x) = x + x^2 / 2 + ... lies strictly between x and its successor (2^52 + 1) * 2^-252, and log1p(x) = x - x^2 / 2 + ... strictly between the predecessor (2^53 - 1) * 2^-253 and x (x^2 is below 2^-52 x), so every enclosure holds those hulls; the enclosures do not contain 0 and their lower ends are positive
// shares: Interval::exact and Binary::make build the inputs and the expected ends; Binary::compare compares; the composed functions are the code under test
test "stable expm1 and log1p intervals retain tiny singleton inputs" {
  let tiny_value = @binary.Binary::make(@binary.BinCoeff::one(), -200, 53)
  let tiny = Interval::exact(tiny_value)
  let expm1 = tiny.expm1()
  let log1p = tiny.log1p()
  assert_false(expm1.contains_zero())
  assert_false(log1p.contains_zero())
  assert_true(expm1.lower_bound().signum() == @def.Sign::Positive)
  assert_true(log1p.lower_bound().signum() == @def.Sign::Positive)
  let successor = @binary.Binary::make(
    @binary.BinCoeff::from_uint64((1UL << 52) + 1UL),
    -252,
    53,
  )
  let predecessor = @binary.Binary::make(
    @binary.BinCoeff::from_uint64((1UL << 53) - 1UL),
    -253,
    53,
  )
  assert_true(expm1.lower_bound().compare(tiny_value) <= 0)
  assert_true(expm1.upper_bound().compare(successor) >= 0)
  assert_true(log1p.lower_bound().compare(predecessor) <= 0)
  assert_true(log1p.upper_bound().compare(tiny_value) >= 0)
}

///|
// oracle: A
// source: written out by hand: sinh(0) = 0, tanh(0) = 0, cosh(0) = 1, asinh(0) = 0 are exact, so the tightest enclosure is the point; acosh(0.5) is Empty because acosh is defined for x >= 1 (Table 9.1)
// shares: Interval::from_double and composed_singleton build the inputs; Binary::compare compares the ends; the composed functions are the code under test
test "hyperbolic family preserves zero and domain hulls" {
  let zero = composed_singleton(0.0)
  let point = fn(x : Interval, value : @binary.Binary) -> Unit raise {
    assert_eq(x.lower_bound().compare(value), 0)
    assert_eq(x.upper_bound().compare(value), 0)
  }
  point(zero.sinh(), @binary.Binary::zero())
  point(zero.tanh(), @binary.Binary::zero())
  point(zero.cosh(), @binary.Binary::one())
  point(zero.asinh(), @binary.Binary::zero())
  assert_true(composed_singleton(0.5).acosh().is_empty())
}

///|
// oracle: A
// source: IEEE 1788-2015 Table 9.1 and 11.6, 11.7: rootn(-1, 2) and acosh(-1) are outside the domain, so the decoration is trv; sinh(0) is defined and continuous, so com; tanpi(0.5) is Empty with trv; an empty decorated interval is trv; NaI has the decoration ill
// shares: Interval::from_double, Interval::exact, Binary::from_double, Binary::make and is_member build the inputs and test membership; the composed functions are the code under test
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
