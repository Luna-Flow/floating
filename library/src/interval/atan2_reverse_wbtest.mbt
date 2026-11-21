///|
/// A float next to a multiple of pi/2: `RD` of `k pi / 2` at `p` bits, `up` for the next float.
fn a2_near(k : Int32, p : Int32, up~ : Bool = false) -> @binary.Binary {
  let pi = ref_pi_interval(p + 64)
  let magnitude = if k == 1 || k == -1 {
    (pi * Interval::exact(@binary.Binary::from_double(0.5))).lo_
  } else {
    pi.lo_
  }
  let down = magnitude.with_precision(
    p,
    @binary.BinaryRoundingMode::RoundTowardNegative,
  )
  let ctx = @binary.BinaryContext::new(precision=p)
  let value = if up { down.next_up_ctx(ctx).0 } else { down }
  if k < 0 {
    value.neg()
  } else {
    value
  }
}

///|
fn a2_iv(lo : Double, hi : Double) -> Interval {
  pw_ival(lo, hi, 53)
}

///|
// oracle: A
// source: zone indices written out by hand from the position of each angle against -pi, -pi/2, 0, pi/2, pi; the floats next to pi and pi/2 come from ref_pi_interval (bounds of pi from tools/interval_pi_oracle.py, Python integers)
// shares: a2_near, with_precision, next_up_ctx of binary (only to step one float; exact operations)
test "atan2 zones: the position of an angle against the multiples of pi/2, exactly" {
  for p in [53, 113] {
    assert_true(atan2_zone(a2_near(2, p)) == 5)
    assert_true(atan2_zone(a2_near(2, p, up=true)) == 6)
    assert_true(atan2_zone(a2_near(1, p)) == 4)
    assert_true(atan2_zone(a2_near(1, p, up=true)) == 5)
    // the negative side: -RD(pi) is above -pi, its next float up is further from -pi
    assert_true(atan2_zone(a2_near(-2, p)) == 1)
    assert_true(atan2_zone(a2_near(-2, p, up=true)) == 0)
    assert_true(atan2_zone(a2_near(-1, p)) == 2)
    assert_true(atan2_zone(a2_near(-1, p, up=true)) == 1)
  }
  assert_true(atan2_zone(pw_num(0.0, 53)) == 3)
  assert_true(atan2_zone(pos_inf(53)) == 6)
  assert_true(atan2_zone(neg_inf(53)) == 0)
  assert_true(atan2_zone(pw_num(1.0, 53)) == 4)
  assert_true(atan2_zone(pw_num(2.0, 53)) == 5)
  assert_true(atan2_zone(pw_num(4.0, 53)) == 6)
  assert_true(atan2_zone(pw_num(-2.0, 53)) == 1)
  assert_true(atan2_zone(pw_num(-1.0, 53)) == 2)
}

///|
/// The inputs that make the set empty, each named: c without a point in (-pi, pi], an empty
/// operand, the abscissa 0 with an angle that misses both axis directions, and the origin.
// oracle: A
// source: each empty or non-empty verdict written out from 1788-2015 atan2_rev1 (set of ordinates whose angle lies in c, open at the origin, c within (-pi, pi]); the floats next to -pi come from ref_pi_interval (Python integers)
// shares: a2_near, with_precision, next_up_ctx of binary
test "atan2_rev1: the empty set" {
  let ctx = @binary.BinaryContext::new(precision=53)
  let entire = Interval::entire(precision=53)
  // c above pi, and c below -pi, up to the float just below -pi
  assert_true(entire.atan2_rev1(a2_iv(4.0, 5.0)).is_empty())
  assert_true(entire.atan2_rev1(a2_iv(-5.0, -4.0)).is_empty())
  let below_minus_pi = a2_near(-2, 53, up=true)
  assert_true(
    entire.atan2_rev1(pw_box(pw_num(-5.0, 53), below_minus_pi, 53)).is_empty(),
  )
  // ... but c ending at -RD(pi), which is above -pi, has points
  assert_true(
    !entire.atan2_rev1(pw_box(pw_num(-5.0, 53), a2_near(-2, 53), 53)).is_empty(),
  )
  // an Empty b, an Empty c and an Empty prior
  let empty = empty_interval(53)
  assert_true(empty.atan2_rev1(a2_iv(0.0, 1.0)).is_empty())
  assert_true(entire.atan2_rev1(empty).is_empty())
  assert_true(entire.atan2_rev1(a2_iv(0.0, 1.0), x=empty).is_empty())
  // the abscissa 0 with c missing both pi/2 and -pi/2
  let zero = a2_iv(0.0, 0.0)
  assert_true(zero.atan2_rev1(a2_iv(1.0, 1.5)).is_empty())
  assert_true(zero.atan2_rev1(a2_iv(2.0, 3.0)).is_empty())
  assert_true(zero.atan2_rev1(a2_iv(-2.0, -1.6)).is_empty())
  // the origin: b = {0} and c = {0} (angle 0 needs a positive abscissa), whatever the prior
  assert_true(zero.atan2_rev1(a2_iv(0.0, 0.0)).is_empty())
  assert_true(zero.atan2_rev1(a2_iv(0.0, 0.0), x=a2_iv(0.0, 0.0)).is_empty())
  // c containing pi/2 with b = {0}: every positive ordinate
  let up = zero.atan2_rev1(a2_iv(1.0, 2.0))
  assert_true(up.lo_.is_zero() && up.hi_.classify() == FpClass::Infinity)
  // the open end 0: the prior [-1, 0] and [0, 0] miss it
  assert_true(zero.atan2_rev1(a2_iv(1.0, 2.0), x=a2_iv(-1.0, 0.0)).is_empty())
  assert_true(zero.atan2_rev1(a2_iv(1.0, 2.0), x=a2_iv(0.0, 0.0)).is_empty())
  ignore(ctx)
}

///|
// oracle: A
// source: each empty or non-empty verdict written out from 1788-2015 atan2_rev2; the float next to -pi comes from ref_pi_interval (Python integers)
// shares: a2_near, with_precision, next_up_ctx of binary
test "atan2_rev2: the empty set" {
  let entire = Interval::entire(precision=53)
  assert_true(entire.atan2_rev2(a2_iv(4.0, 5.0)).is_empty())
  assert_true(entire.atan2_rev2(a2_iv(-5.0, -4.0)).is_empty())
  assert_true(
    entire
    .atan2_rev2(pw_box(pw_num(-5.0, 53), a2_near(-2, 53, up=true), 53))
    .is_empty(),
  )
  let empty = empty_interval(53)
  assert_true(empty.atan2_rev2(a2_iv(0.0, 1.0)).is_empty())
  assert_true(entire.atan2_rev2(empty).is_empty())
  assert_true(entire.atan2_rev2(a2_iv(0.0, 1.0), x=empty).is_empty())
  // the ordinate 0: only the angles 0 and pi; c missing both is empty
  let zero = a2_iv(0.0, 0.0)
  assert_true(zero.atan2_rev2(a2_iv(1.0, 1.5)).is_empty())
  assert_true(zero.atan2_rev2(a2_iv(-2.0, -1.0)).is_empty())
  assert_true(zero.atan2_rev2(a2_iv(-4.0, -3.1)).is_empty())
  // the origin: a = {0}, c = {0}: the abscissas x0 > 0, and the prior [-1, 0] misses them
  let right = zero.atan2_rev2(a2_iv(0.0, 0.0))
  assert_true(right.lo_.is_zero() && right.hi_.classify() == FpClass::Infinity)
  assert_true(zero.atan2_rev2(a2_iv(0.0, 0.0), x=a2_iv(-1.0, 0.0)).is_empty())
  assert_true(zero.atan2_rev2(a2_iv(0.0, 0.0), x=a2_iv(0.0, 0.0)).is_empty())
}

///|
/// c wider than the range, and unbounded operands.
// oracle: A
// source: the hull and the sign of each result written out by hand from the sign of sin(c) and cos(c) in each quadrant (validity of the hull: the hull is the exact set here, since each set is a half-line or a point); the floats next to pi/2 and pi come from ref_pi_interval (Python integers)
// shares: a2_near, with_precision, next_up_ctx of binary
test "atan2_rev1 and atan2_rev2: c = Entire, and Entire operands with a thin c" {
  let entire = Interval::entire(precision=53)
  let is_entire = fn(r : Interval) {
    r.lo_.classify() == FpClass::Infinity &&
    r.hi_.classify() == FpClass::Infinity &&
    r.lo_.signum() == Sign::Negative
  }
  // c = Entire: every operand sign gives the whole line (b = {0}: every y != 0, hull Entire)
  for
    operand in [
      a2_iv(1.0, 2.0),
      a2_iv(-2.0, -1.0),
      a2_iv(-1.0, 1.0),
      a2_iv(0.0, 0.0),
      entire,
    ] {
    assert_true(is_entire(operand.atan2_rev1(entire)))
    assert_true(is_entire(operand.atan2_rev2(entire)))
  }
  // Entire operand and a thin c: the quadrant fixes the sign of the unknown. Rev1: the
  // ordinate has the sign of sin(c); Rev2: the abscissa has the sign of cos(c)
  let positive = fn(r : Interval) {
    r.lo_.is_zero() && r.hi_.classify() == FpClass::Infinity
  }
  let negative = fn(r : Interval) {
    r.hi_.is_zero() && r.lo_.classify() == FpClass::Infinity
  }
  // open quadrants (angles 0.5, 2, -2, -0.5)
  assert_true(positive(entire.atan2_rev1(a2_iv(0.5, 0.5))))
  assert_true(positive(entire.atan2_rev1(a2_iv(2.0, 2.0))))
  assert_true(negative(entire.atan2_rev1(a2_iv(-2.0, -2.0))))
  assert_true(negative(entire.atan2_rev1(a2_iv(-0.5, -0.5))))
  assert_true(positive(entire.atan2_rev2(a2_iv(0.5, 0.5))))
  assert_true(negative(entire.atan2_rev2(a2_iv(2.0, 2.0))))
  assert_true(negative(entire.atan2_rev2(a2_iv(-2.0, -2.0))))
  assert_true(positive(entire.atan2_rev2(a2_iv(-0.5, -0.5))))
  // the axis angle 0: y = 0 (Rev1) and x0 > 0 (Rev2)
  assert_true(pw_same(entire.atan2_rev1(a2_iv(0.0, 0.0)), 0.0, 0.0))
  assert_true(positive(entire.atan2_rev2(a2_iv(0.0, 0.0))))
  // the axis angles next to pi/2 (below) and pi (below): y > 0 and x0 < 0 / x0 > 0
  assert_true(
    positive(entire.atan2_rev1(pw_box(a2_near(1, 53), a2_near(1, 53), 53))),
  )
  assert_true(
    positive(entire.atan2_rev1(pw_box(a2_near(2, 53), a2_near(2, 53), 53))),
  )
  assert_true(
    positive(entire.atan2_rev2(pw_box(a2_near(1, 53), a2_near(1, 53), 53))),
  )
  assert_true(
    negative(entire.atan2_rev2(pw_box(a2_near(2, 53), a2_near(2, 53), 53))),
  )
}

///|
/// The branch cut: the angle pi is attained on y = 0, x < 0, and -pi never.
// oracle: A
// source: empty or non-empty verdicts and the bounds 0 written out by hand from the range (-pi, pi] of atan2 (1788-2015) and y = -tan(theta) at the cut
// shares: nothing
test "atan2: the branch cut and the half-open range" {
  // Rev1, b = {-1}: c = [3.1, 4] has Theta = [3.1, pi], and y = -tan(theta) runs from
  // about 0.0416 down to 0, attained at pi
  let b = a2_iv(-1.0, -1.0)
  let c = a2_iv(3.1, 4.0)
  let r = b.atan2_rev1(c, x=a2_iv(-1.0, 0.0))
  assert_true(pw_same(r, 0.0, 0.0))
  // c = [-4, -3.1] has Theta = (-pi, -3.1]: y = -tan(theta) runs from -0.0416 up to 0, not
  // attained at -pi
  let r2 = b.atan2_rev1(a2_iv(-4.0, -3.1), x=a2_iv(-1.0, 0.0))
  assert_true(!r2.is_empty())
  assert_true(r2.hi_.is_zero())
  assert_true(b.atan2_rev1(a2_iv(-4.0, -3.1), x=a2_iv(0.0, 0.0)).is_empty())
  // Rev2, a = {0}: c = [3.1, 4] contains pi, the set is x0 < 0; c = [-4, -3.1] is empty
  let r3 = a2_iv(0.0, 0.0).atan2_rev2(a2_iv(3.1, 4.0))
  assert_true(r3.hi_.is_zero() && r3.lo_.classify() == FpClass::Infinity)
  assert_true(a2_iv(0.0, 0.0).atan2_rev2(a2_iv(-4.0, -3.1)).is_empty())
}

///|
/// A float next to pi (or pi/2): the tangent (cotangent) is huge and the working precision
/// follows it. The result is the tightest one, the two adjacent floats around the exact value
/// `tan(c)` (Rev1, b = 1) or `cot(c)` (Rev2, b = 1), whose enclosure at 200 bits comes from MPFR.
// oracle: A
// source: tan and cot of the float next to pi/2 and pi, rounded down and up to 200 bits by MPFR (tools/interval_forward_oracle.py), then rounded again down and up to p bits here: the tightest result; the floats next to pi/2 and pi come from ref_pi_interval (Python integers)
// shares: a2_near (with_precision of binary); forward_reference_table
test "atan2_rev1 and atan2_rev2: an angle one float from pi/2 or pi gives a huge result" {
  let down = @binary.BinaryRoundingMode::RoundTowardNegative
  let up = @binary.BinaryRoundingMode::RoundTowardPositive
  for p in [53, 113] {
    let ctx = @binary.BinaryContext::new(precision=p)
    let one = pw_box(pw_num(1.0, p), pw_num(1.0, p), p)
    // Rev1 next to pi/2: y = 1 * tan(c) is positive and about 2^p
    let c1 = a2_near(1, p)
    let r1 = one.atan2_rev1(pw_box(c1, c1, p))
    let e1 = fwd_find("tan", c1)
    assert_true(r1.lo_.compare(e1.lo.with_precision(p, down)) == 0)
    assert_true(r1.hi_.compare(e1.hi.with_precision(p, up)) == 0)
    assert_true(r1.lo_.next_up_ctx(ctx).0.compare(r1.hi_) == 0)
    assert_true(pow_adjusted_exponent(r1.lo_) >= (p - 4).to_int64())
    // Rev2 next to pi: x0 = 1 * cot(c) is negative and about -2^p
    let c2 = a2_near(2, p)
    let r2 = one.atan2_rev2(pw_box(c2, c2, p))
    let e2 = fwd_find("cot", c2)
    assert_true(r2.lo_.compare(e2.lo.with_precision(p, down)) == 0)
    assert_true(r2.hi_.compare(e2.hi.with_precision(p, up)) == 0)
    assert_true(r2.lo_.next_up_ctx(ctx).0.compare(r2.hi_) == 0)
    assert_true(pow_adjusted_exponent(r2.lo_.neg()) >= (p - 4).to_int64())
  }
}

///|
// oracle: A
// source: tan(0.5) and cot(0.5) rounded down and up to 200 bits by MPFR (tools/interval_forward_oracle.py), scaled by the exact power of two 2^(+-1e9) (a shift of the exponent), then rounded to 53 bits: the tightest result
// shares: Interval::mul only to scale by a power of two (exact)
test "atan2_rev1 and atan2_rev2: extreme operands return at once" {
  let p = 53
  let down = @binary.BinaryRoundingMode::RoundTowardNegative
  let up = @binary.BinaryRoundingMode::RoundTowardPositive
  let huge = pw_pow2(1000000000, p)
  let tiny = pw_pow2(-1000000000, p)
  let half = pw_num(0.5, p)
  let t = fwd_find("tan", half)
  let k = fwd_find("cot", half)
  for factor in [huge, tiny] {
    let b = pw_box(factor, factor, p)
    let c = pw_box(half, half, p)
    let scale = Interval::exact(factor, precision=200)
    // Rev1: y = b tan(c)
    let reference = scale * Interval::from_bounds(t.lo, t.hi, precision=200)
    let r1 = b.atan2_rev1(c)
    assert_true(r1.lo_.compare(reference.lo_.with_precision(p, down)) == 0)
    assert_true(r1.hi_.compare(reference.hi_.with_precision(p, up)) == 0)
    // Rev2: x0 = b cot(c)
    let reference2 = scale * Interval::from_bounds(k.lo, k.hi, precision=200)
    let r2 = b.atan2_rev2(c)
    assert_true(r2.lo_.compare(reference2.lo_.with_precision(p, down)) == 0)
    assert_true(r2.hi_.compare(reference2.hi_.with_precision(p, up)) == 0)
  }
  // prior ends of magnitude 2^+-1e9
  let one = pw_box(pw_num(1.0, p), pw_num(1.0, p), p)
  let c = pw_box(pw_num(1.0, p), pw_num(1.0, p), p)
  assert_true(one.atan2_rev1(c, x=pw_box(huge, huge, p)).is_empty())
  assert_true(!one.atan2_rev1(c, x=pw_box(tiny, huge, p)).is_empty())
}

///|
// oracle: A
// source: decorations written out from 1788-2015 11.7.1 (reverse functions give trv) and NaI propagation
// shares: nothing
test "atan2_rev1 and atan2_rev2: decorated forms are trv and NaI propagates" {
  let p = 53
  let b = DecoratedInterval::new(pw_ival(1.0, 2.0, p), decoration=Com)
  let c = DecoratedInterval::new(pw_ival(0.5, 1.0, p), decoration=Com)
  assert_true(b.atan2_rev1(c).decoration() == Trv)
  assert_true(b.atan2_rev2(c).decoration() == Trv)
  let nai = DecoratedInterval::nai(precision=p)
  assert_true(b.atan2_rev1(nai).is_nai())
  assert_true(nai.atan2_rev2(c).is_nai())
  assert_true(b.atan2_rev1(c, x=nai).is_nai())
}
