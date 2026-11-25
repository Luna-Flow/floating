///|
fn observer_exact_diff(
  a : @binary.Binary,
  b : @binary.Binary,
) -> @binary.Binary {
  // a - b exactly: both operands have a few hundred bits at most in these tests
  a.sub_ctx(b, @binary.BinaryContext::new(precision=2000)).0
}

///|
fn observer_pow2(e : Int32, p : Int32) -> @binary.Binary {
  @binary.Binary::make(@binary.BinCoeff::one(), e, p)
}

///|
/// Issue 477: `radius` was the half-width around the exact center, not the
/// `rad` of IEEE 1788-2015 12.12.8, which is measured from the value `midpoint`
/// returns. For x = [1, 1 + 3 * 2^-52] at 53 bits the center needs 54 bits,
/// `midpoint` rounds it to 1 + 2^-51 and the radius 3 * 2^-53 left the lower
/// bound outside [mid - rad, mid + rad].
test "radius covers the interval around the midpoint (issue 477)" {
  let one = @binary.Binary::one(precision=53)
  let hi = @binary.Binary::make(@binary.BinCoeff::from_uint64(3UL), -52, 53).add(
    one,
  )
  let x = Interval::from_bounds(one, hi, precision=53)
  let m = x.midpoint()
  let r = x.radius()
  // exact distances: compare these, not `m - r`, which rounds back to the bound
  assert_true(r.compare(observer_exact_diff(m, x.lower_bound())) >= 0)
  assert_true(r.compare(observer_exact_diff(x.upper_bound(), m)) >= 0)
  assert_eq(r.compare(observer_pow2(-51, 53)), 0)
}

///|
test "observers are total and follow 12.12.8 on Empty, Entire and half-bounded intervals" {
  let one = @binary.Binary::one(precision=53)
  let inf = @binary.Binary::inf(precision=53)
  let empty = Interval::empty(precision=53)
  for
    v in [
      empty.midpoint(),
      empty.radius(),
      empty.width(),
      empty.magnitude(),
      empty.mignitude(),
    ] {
    assert_eq(v.classify(), FpClass::NaN)
  }
  let entire = Interval::entire(precision=53)
  assert_true(entire.midpoint().is_zero())
  assert_eq(entire.radius().classify(), FpClass::Infinity)
  assert_eq(entire.width().classify(), FpClass::Infinity)
  let upper = Interval::from_bounds(one, inf, precision=53)
  let lower = Interval::from_bounds(inf.neg(), one, precision=53)
  assert_eq(upper.midpoint().classify(), FpClass::Finite)
  assert_true(upper.midpoint().signum() == Sign::Positive)
  assert_eq(lower.midpoint().classify(), FpClass::Finite)
  assert_true(lower.midpoint().signum() == Sign::Negative)
  assert_eq(upper.midpoint().compare(lower.midpoint().neg()), 0)
  assert_eq(upper.radius().classify(), FpClass::Infinity)
  assert_eq(lower.radius().classify(), FpClass::Infinity)
  assert_eq(upper.mignitude().compare(one), 0)
  assert_eq(upper.magnitude().classify(), FpClass::Infinity)
}

///|
test "try_new reports an invalid center or radius" {
  let one = @binary.Binary::one(precision=53)
  let inf = @binary.Binary::inf(precision=53)
  let nan = @binary.Binary::nan(precision=53)
  assert_true(
    Interval::try_from_midpoint_radius(one, one, precision=53)
    .unwrap()
    .is_member(one),
  )
  assert_true(
    Interval::try_from_midpoint_radius(inf, one, precision=53) is Err(_),
  )
  assert_true(
    Interval::try_from_midpoint_radius(nan, one, precision=53) is Err(_),
  )
  assert_true(
    Interval::try_from_midpoint_radius(one, inf, precision=53) is Err(_),
  )
  assert_true(
    Interval::try_from_midpoint_radius(one, one.neg(), precision=53) is Err(_),
  )
}
