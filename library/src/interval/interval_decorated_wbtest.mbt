///|
// oracle: A
// source: written out from IEEE 1788-2015 11.5 and 10.5.7: the intersection and the convex hull of com inputs are trv; [1, 3] meet [2.1, 4] = [2.1, 3] (lower end the double 2.1, upper end 3) and the hull of [1, 3] and [2.1, 4] is [1, 4]
// shares: Binary::from_int, from_double, Interval::from_bounds, from_int and DecoratedInterval::new build the inputs; Decoration compare and the booleans compare; the decorated operations are the code under test
test "ITF1788 minimal decorated set operations" {
  let one = @binary.Binary::from_int(1, precision=32)
  let three = @binary.Binary::from_int(3, precision=32)
  let left = DecoratedInterval::new(
    Interval::from_bounds(one, three),
    decoration=Com,
  )
  let right = DecoratedInterval::new(
    Interval::from_bounds(
      @binary.Binary::from_double(2.1, precision=64),
      @binary.Binary::from_int(4, precision=32),
    ),
    decoration=Com,
  )
  let intersection = left.intersection(right)
  assert_eq(intersection.decoration(), Trv)
  assert_eq(intersection.interval().upper_bound().compare(three), 0)
  // [1, 3] meet [2.1, 4] is [2.1, 3] (the double 2.1 is the lower end), and the hull is [1, 4]
  assert_eq(
    intersection
    .interval()
    .lower_bound()
    .compare(@binary.Binary::from_double(2.1, precision=64)),
    0,
  )
  let hull = left.convex_hull(right)
  assert_eq(hull.decoration(), Trv)
  assert_eq(hull.interval().lower_bound().compare(one), 0)
  assert_eq(
    hull
    .interval()
    .upper_bound()
    .compare(@binary.Binary::from_int(4, precision=32)),
    0,
  )
}

///|
// oracle: A
// source: written out from IEEE 1788-2015 clause 11: NaI plus a value is NaI, NaI is neither empty nor entire, is not equal to itself and is not a subset; an empty interval given with decoration com is stored with decoration trv
// shares: Binary::from_int, from_double, Interval::from_bounds, from_int and DecoratedInterval::new build the inputs; Decoration compare and the booleans compare; the decorated operations are the code under test
test "decorated NaI propagates and empty canonicalizes" {
  let nai = DecoratedInterval::nai(precision=32)
  let value = DecoratedInterval::new(Interval::from_int(1, precision=32))
  assert_true((nai + value).is_nai())
  let empty = DecoratedInterval::new(
    Interval::empty(precision=32),
    decoration=Com,
  )
  assert_eq(empty.decoration(), Trv)
  assert_false(nai.is_empty())
  assert_false(nai.is_entire())
  assert_false(nai.equal(nai))
  assert_false(nai.subset(value))
  assert_true(nai.overlap(value) is None)
}

///|
// oracle: A
// source: written out from IEEE 1788-2015 clause 11 and Table 9.1: sin on Entire stays def with image [-1, 1], tan of Entire is trv, pow of [-2, -1] to 2 is empty with trv
// shares: Binary::from_int, from_double, Interval::from_bounds, from_int and DecoratedInterval::new build the inputs; Decoration compare and the booleans compare; the decorated operations are the code under test
test "decorated power and trigonometric functions preserve IEEE domain grades" {
  let entire = DecoratedInterval::new(
    Interval::entire(precision=53),
    decoration=Def,
  )
  let sine = entire.sin()
  assert_eq(sine.decoration(), Def)
  assert_true(
    sine
    .interval()
    .equal(
      Interval::from_bounds(
        @binary.Binary::from_int(-1, precision=53),
        @binary.Binary::one(precision=53),
        precision=53,
      ),
    ),
  )
  assert_eq(entire.tan().decoration(), Trv)
  let negative = DecoratedInterval::new(
    Interval::from_bounds(
      @binary.Binary::from_int(-2, precision=53),
      @binary.Binary::from_int(-1, precision=53),
      precision=53,
    ),
  )
  let exponent = DecoratedInterval::new(Interval::from_int(2, precision=53))
  let power = negative.pow(exponent)
  assert_true(power.interval().is_empty())
  assert_eq(power.decoration(), Trv)
}

///|
// oracle: A
// source: written out from IEEE 1788-2015 clause 11: the decoration of a result is the minimum of the operand grades and that of the operation (dac for dac and com inputs on defined operations; trv for intersection, convex hull, cancelPlus and cancelMinus); only decorations are checked
// shares: Binary::from_int, from_double, Interval::from_bounds, from_int and DecoratedInterval::new build the inputs; Decoration compare and the booleans compare; the decorated operations are the code under test
test "decorated arithmetic applies operand and operation grades" {
  let left = DecoratedInterval::new(
    Interval::from_bounds(
      @binary.Binary::from_int(1, precision=53),
      @binary.Binary::from_int(2, precision=53),
    ),
    decoration=Dac,
  )
  let right = DecoratedInterval::new(
    Interval::from_bounds(
      @binary.Binary::from_int(3, precision=53),
      @binary.Binary::from_int(4, precision=53),
    ),
    decoration=Com,
  )
  assert_eq((left + right).decoration(), Dac)
  assert_eq((left - right).decoration(), Dac)
  assert_eq((left * right).decoration(), Dac)
  assert_eq((left / right).decoration(), Dac)
  assert_eq(left.min(right).decoration(), Dac)
  assert_eq(left.max(right).decoration(), Dac)
  assert_eq(left.fma(right, right).decoration(), Dac)
  assert_eq(left.intersection(right).decoration(), Trv)
  assert_eq(left.convex_hull(right).decoration(), Trv)
  assert_eq(left.cancel_plus(right).decoration(), Trv)
  assert_eq(left.cancel_minus(right).decoration(), Trv)
}

///|
// oracle: A
// source: written out from the domains of Table 9.1 and IEEE 1788-2015 clause 11: recip, sqrt, ln, log2, log10 and pown(-2) over [-1, 1] are trv; neg, abs, sqr, exp, exp2, exp10, sin and cos of [1, 2] stay def; only decorations are checked
// shares: Binary::from_int, from_double, Interval::from_bounds, from_int and DecoratedInterval::new build the inputs; Decoration compare and the booleans compare; the decorated operations are the code under test
test "decorated unary domains downgrade without losing enclosures" {
  let crossing = DecoratedInterval::new(
    Interval::from_bounds(
      @binary.Binary::from_int(-1, precision=53),
      @binary.Binary::from_int(1, precision=53),
    ),
  )
  assert_eq(crossing.recip().decoration(), Trv)
  assert_eq(crossing.sqrt().decoration(), Trv)
  assert_eq(crossing.ln().decoration(), Trv)
  assert_eq(crossing.log2().decoration(), Trv)
  assert_eq(crossing.log10().decoration(), Trv)
  assert_eq(crossing.pown(-2).decoration(), Trv)
  let positive = DecoratedInterval::new(
    Interval::from_bounds(
      @binary.Binary::from_int(1, precision=53),
      @binary.Binary::from_int(2, precision=53),
    ),
    decoration=Def,
  )
  assert_eq(positive.pos().decoration(), Def)
  assert_eq(positive.neg().decoration(), Def)
  assert_eq(positive.abs().decoration(), Def)
  assert_eq(positive.sqr().decoration(), Def)
  assert_eq(positive.exp().decoration(), Def)
  assert_eq(positive.exp2().decoration(), Def)
  assert_eq(positive.exp10().decoration(), Def)
  assert_eq(positive.sin().decoration(), Def)
  assert_eq(positive.cos().decoration(), Def)
}

///|
// oracle: A
// source: written out from the NaI rule of IEEE 1788-2015 clause 11: any NaI operand of a unary, binary or ternary operation gives NaI
// shares: Binary::from_int, from_double, Interval::from_bounds, from_int and DecoratedInterval::new build the inputs; Decoration compare and the booleans compare; the decorated operations are the code under test
test "decorated NaI propagates through unary binary and ternary operations" {
  let nai = DecoratedInterval::nai(precision=53)
  let value = DecoratedInterval::new(Interval::from_int(2, precision=53))
  assert_true(nai.recip().is_nai())
  assert_true(nai.sqrt().is_nai())
  assert_true(nai.pow(value).is_nai())
  assert_true(value.pow(nai).is_nai())
  assert_true(nai.fma(value, value).is_nai())
  assert_true(value.fma(nai, value).is_nai())
  assert_true(value.fma(value, nai).is_nai())
}

///|
// oracle: A
// source: written out by hand: 2^2000 in a binary64 context overflows (overflow and inexact flags), 2^-2000 underflows (underflow and inexact), combining the flags is their union, NaI keeps the decoration ill and sets no flag; the rounded values themselves are not asserted
// shares: Binary::from_int, from_double, Interval::from_bounds, from_int and DecoratedInterval::new build the inputs; Decoration compare and the booleans compare; the decorated operations are the code under test
test "decorated context rounding preserves grade and accumulates flags" {
  let context = IntervalContext::binary64()
  let overflow_source = DecoratedInterval::new(
    Interval::exact(@binary.Binary::make(@binary.BinCoeff::one(), 2000, 53)),
    decoration=Def,
  )
  let (overflowed, overflow_flags) = overflow_source.apply_ctx(context)
  assert_eq(overflowed.decoration(), Def)
  assert_true(overflow_flags.overflow())
  assert_true(overflow_flags.inexact())
  let underflow_source = DecoratedInterval::new(
    Interval::exact(@binary.Binary::make(@binary.BinCoeff::one(), -2000, 53)),
    decoration=Dac,
  )
  let (underflowed, underflow_flags) = underflow_source.apply_ctx(context)
  assert_eq(underflowed.decoration(), Dac)
  assert_true(underflow_flags.underflow())
  assert_true(underflow_flags.inexact())
  let combined = overflow_flags.combine(underflow_flags)
  assert_true(combined.overflow())
  assert_true(combined.underflow())
  let (nai, nai_flags) = DecoratedInterval::nai(precision=53).apply_ctx(context)
  assert_true(nai.is_nai())
  assert_eq(nai.decoration(), Ill)
  assert_true(nai_flags == IntervalFlags::new())
}

///|
fn decorated_test_interval(
  lower : @binary.Binary,
  upper : @binary.Binary,
) -> DecoratedInterval {
  DecoratedInterval::new(Interval::from_bounds(lower, upper, precision=53))
}

///|
// rootn(x, n) with n < 0 is x^(-1/n), which is undefined at 0, so an argument
// containing 0 is not inside the domain and the decoration is trv.
// oracle: A
// source: written out from the domain of rootn (IEEE 1788-2015 Table 9.1): for a negative degree rootn is undefined at 0, so an interval containing 0 is trv, an interval away from 0 and a positive degree give com
// shares: Binary::from_int, from_double, Interval::from_bounds, from_int and DecoratedInterval::new build the inputs; Decoration compare and the booleans compare; the decorated operations are the code under test
test "decorated rootn with a negative degree over 0 is trv" {
  let zero = @binary.Binary::zero(precision=53)
  let one = @binary.Binary::one(precision=53)
  let x = decorated_test_interval(zero, one)
  for degree in [-1, -2, -3] {
    assert_eq(x.rootn(degree).decoration(), Trv)
  }
  assert_eq(decorated_test_interval(one.neg(), one).rootn(-3).decoration(), Trv)
  // Away from 0 the negative degrees stay common.
  let positive = decorated_test_interval(one, @binary.Binary::from_int(4))
  assert_eq(positive.rootn(-2).decoration(), Com)
  assert_eq(positive.rootn(-1).decoration(), Com)
  assert_eq(
    decorated_test_interval(@binary.Binary::from_int(-8), one.neg())
    .rootn(-3)
    .decoration(),
    Com,
  )
  // Positive degrees are defined at 0.
  assert_eq(x.rootn(2).decoration(), Com)
  assert_eq(x.rootn(3).decoration(), Com)
}

///|
// A pole of tanpi at an endpoint gives a half-unbounded image; the argument
// is not inside the domain, so the decoration is trv, not dac.
// oracle: A
// source: written out from the pole of tanpi at 1/2 (Table 9.1): an interval with the pole as an endpoint has an infinite end and is trv, one with the pole inside is trv, [-1/4, 1/4] is com
// shares: Binary::from_int, from_double, Interval::from_bounds, from_int and DecoratedInterval::new build the inputs; Decoration compare and the booleans compare; the decorated operations are the code under test
test "decorated tanpi with a pole at an endpoint is trv" {
  let zero = @binary.Binary::zero(precision=53)
  let half = @binary.Binary::make(@binary.BinCoeff::one(), -1, 53)
  let one = @binary.Binary::one(precision=53)
  let lower_pole = decorated_test_interval(half, one).tanpi()
  assert_true(
    lower_pole.interval().lower_bound().classify() == FpClass::Infinity,
  )
  assert_eq(lower_pole.decoration(), Trv)
  let upper_pole = decorated_test_interval(zero, half).tanpi()
  assert_true(
    upper_pole.interval().upper_bound().classify() == FpClass::Infinity,
  )
  assert_eq(upper_pole.decoration(), Trv)
  let interior_pole = decorated_test_interval(zero, one).tanpi()
  assert_eq(interior_pole.decoration(), Trv)
  // Without a pole the result is bounded and common.
  let quarter = @binary.Binary::make(@binary.BinCoeff::one(), -2, 53)
  assert_eq(
    decorated_test_interval(quarter.neg(), quarter).tanpi().decoration(),
    Com,
  )
}

///|
// IEEE 1788-2015 11.5.3: the comparisons of decorations follow the
// propagation order com > dac > def > trv > ill.
// oracle: A
// source: written out from IEEE 1788-2015 11.5.3: the order is ill < trv < def < dac < com; the test compares the operators with the indices of that literal list
// shares: Binary::from_int, from_double, Interval::from_bounds, from_int and DecoratedInterval::new build the inputs; Decoration compare and the booleans compare; the decorated operations are the code under test
test "decorations compare in the propagation order" {
  let ascending = [Ill, Trv, Def, Dac, Com]
  for i in 0..<ascending.length() {
    for j in 0..<ascending.length() {
      assert_eq(ascending[i] < ascending[j], i < j)
      assert_eq(ascending[i] <= ascending[j], i <= j)
      assert_eq(ascending[i] > ascending[j], i > j)
      assert_eq(ascending[i] >= ascending[j], i >= j)
    }
  }
}
