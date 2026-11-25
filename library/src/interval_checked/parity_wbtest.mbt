///|
fn parity_expect(lo : Double, hi : Double) -> @interval.Interval {
  @interval.Interval::from_bounds(
    @binary.Binary::from_double(lo, precision=53),
    @binary.Binary::from_double(hi, precision=53),
    precision=53,
  )
}

///|
fn parity_up(lo : Double) -> @interval.Interval {
  @interval.Interval::from_bounds(
    @binary.Binary::from_double(lo, precision=53),
    @binary.Binary::inf(precision=53),
    precision=53,
  )
}

///|
fn parity_down(hi : Double) -> @interval.Interval {
  @interval.Interval::from_bounds(
    @binary.Binary::inf(negative=true, precision=53),
    @binary.Binary::from_double(hi, precision=53),
    precision=53,
  )
}

///|
fn parity_interval(lo : Int32, hi : Int32) -> @interval.Interval {
  @interval.Interval::from_bounds(
    @binary.Binary::from_int(lo, precision=53),
    @binary.Binary::from_int(hi, precision=53),
    precision=53,
  )
}

///|
fn parity_result(lo : Int32, hi : Int32) -> IntervalChecked {
  IntervalChecked::ok(parity_interval(lo, hi))
}

///|
fn parity_value(r : IntervalChecked) -> @interval.Interval {
  r.result().unwrap()
}

///|
// oracle: A
// source: expected intervals written out by hand from the definitions of IEEE 1788-2015 Table 9.1 and 10.5.6 to 10.5.7 on small integer inputs (sqrt [1,4] = [1,2], sqr [-3,5] = [0,25], recip [1,4] = [1/4,1], min = [-3,4], max = [1,5], fma [-3,5]*[1,4]+[2,2] = [-10,22], intersection [1,4], hull [-3,5], cancelPlus([-3,5],[1,4]) = [1,6], cancelMinus(x,x) = [0,0]); every result is exactly representable, so the rounding direction does not matter
// shares: Interval ==, from_bounds and Binary::from_double only (building and comparing the expected value)
test "the interval operations of 1788 Table 9.1 and 10.5.6 to 10.5.7 exist on the checked tier and agree with the plain tier" {
  let rx = parity_result(-3, 5)
  let ry = parity_result(1, 4)
  let rz = parity_result(2, 2)
  assert_true(parity_value(ry.sqrt()) == parity_expect(1.0, 2.0))
  assert_true(parity_value(rx.sqr()) == parity_expect(0.0, 25.0))
  assert_true(parity_value(ry.recip()) == parity_expect(0.25, 1.0))
  assert_true(parity_value(rx.min(ry)) == parity_expect(-3.0, 4.0))
  assert_true(parity_value(rx.max(ry)) == parity_expect(1.0, 5.0))
  assert_true(parity_value(rx.fma(ry, rz)) == parity_expect(-10.0, 22.0))
  assert_true(parity_value(rx.intersection(ry)) == parity_expect(1.0, 4.0))
  assert_true(parity_value(rx.convex_hull(ry)) == parity_expect(-3.0, 5.0))
  assert_true(parity_value(rx.cancel_plus(ry)) == parity_expect(1.0, 6.0))
  assert_true(parity_value(rx.cancel_minus(rx)) == parity_expect(0.0, 0.0))
}

///|
// oracle: S
// source: only Err and the message of the first error are checked: an error operand must come back as an error, the contract of the checked tier; no numeric value is involved
// shares: IntervalChecked::err and the checked operations (the contract is that of the code under test)
test "the new checked operations keep the first error" {
  let failed = IntervalChecked::err(
    @lf_arith.ArithmeticError::domain_error("first"),
  )
  let ok = parity_result(1, 2)
  assert_true(failed.sqrt().is_err())
  assert_true(failed.sqr().is_err())
  assert_true(failed.recip().is_err())
  assert_true(failed.min(ok).is_err())
  assert_true(ok.max(failed).is_err())
  assert_true(ok.fma(ok, failed).is_err())
  assert_true(failed.intersection(ok).is_err())
  assert_true(ok.convex_hull(failed).is_err())
  assert_true(failed.cancel_plus(ok).is_err())
  assert_true(ok.cancel_minus(failed).is_err())
  assert_true(failed.min(ok).error().unwrap().message == "first")
}

///|
// oracle: A
// source: expected intervals written out by hand from IEEE 1788-2015 Table 9.1 for x = [-1.5, 2.5]: sign [-1,1], ceil [-1,3], floor [-2,2], trunc [-1,2], roundTiesToEven [-2,2] (-1.5 to -2, 2.5 to 2), roundTiesToAway [-2,3]; the failed operand gives Err
// shares: Interval ==, from_bounds and Binary::from_double only
test "the integer functions of Table 9.1 exist on the checked tier and agree with the plain tier" {
  let x = parity_expect(-1.5, 2.5)
  let r = IntervalChecked::ok(x)
  assert_true(parity_value(r.sign()) == parity_expect(-1.0, 1.0))
  assert_true(parity_value(r.ceil()) == parity_expect(-1.0, 3.0))
  assert_true(parity_value(r.floor()) == parity_expect(-2.0, 2.0))
  assert_true(parity_value(r.trunc()) == parity_expect(-1.0, 2.0))
  assert_true(parity_value(r.round_ties_to_even()) == parity_expect(-2.0, 2.0))
  assert_true(parity_value(r.round_ties_to_away()) == parity_expect(-2.0, 3.0))
  let failed = IntervalChecked::from_result(
    Err(@def.ArithmeticError::domain_error("earlier failure")),
  )
  assert_true(failed.ceil().result() is Err(_))
}

///|
// oracle: A
// source: expected values written out by hand from IEEE 1788-2015 10.5.4 mulRev and 10.5.5 mulRevToPair for b = [-2,4], c = [3,5]: 0 is in b and not in c, so c/b = (-inf,-3/2] and [3/4,inf), the hull is Entire, with the prior [0,9] it is [3/4,9], the pair is ((-inf,-3/2], [3/4,inf)); all ends are exact
// shares: Interval ==, from_bounds, Binary::inf and Binary::from_double only
test "mul_rev and mul_rev_to_pair exist on the checked tier and agree with the plain tier" {
  let rb = parity_result(-2, 4)
  let rc = parity_result(3, 5)
  let rx = parity_result(0, 9)
  assert_true(
    parity_value(rb.mul_rev(rc)) == @interval.Interval::entire(precision=53),
  )
  assert_true(parity_value(rb.mul_rev(rc, x=rx)) == parity_expect(0.75, 9.0))
  let (u, v) = rb.mul_rev_to_pair(rc)
  assert_true(parity_value(u) == parity_down(-1.5))
  assert_true(parity_value(v) == parity_up(0.75))
  let failed = IntervalChecked::from_result(
    Err(@def.ArithmeticError::domain_error("earlier failure")),
  )
  assert_true(failed.mul_rev(rc).result() is Err(_))
  assert_true(rb.mul_rev(failed).result() is Err(_))
  let (fu, fv) = failed.mul_rev_to_pair(rc)
  assert_true(fu.result() is Err(_) && fv.result() is Err(_))
}

///|
// oracle: A
// source: expected values written out by hand from IEEE 1788-2015 10.5.4 for c = [1,4], prior x = [0,9]: sqrRev [-2,2], with the prior [0,9] it is [1,2]; absRev [-4,4], with the prior it is [1,4]; coshRev([1,1]) = [0,0]; pownRev(c=[1,8], 3) = [1,2]; pownRev(c=[1,4], -2) = [-1,1], with the prior [1/2,1]; all ends are exact
// shares: Interval ==, from_bounds and Binary::from_double only
test "sqr_rev, abs_rev, cosh_rev and pown_rev exist on the checked tier and agree with the plain tier" {
  let rc = parity_result(1, 4)
  let rx = parity_result(0, 9)
  let one = parity_result(1, 1)
  let cube = parity_result(1, 8)
  assert_true(parity_value(rc.sqr_rev()) == parity_expect(-2.0, 2.0))
  assert_true(parity_value(rc.sqr_rev(x=rx)) == parity_expect(1.0, 2.0))
  assert_true(parity_value(rc.abs_rev()) == parity_expect(-4.0, 4.0))
  assert_true(parity_value(rc.abs_rev(x=rx)) == parity_expect(1.0, 4.0))
  assert_true(parity_value(one.cosh_rev()) == parity_expect(0.0, 0.0))
  assert_true(parity_value(one.cosh_rev(x=rx)) == parity_expect(0.0, 0.0))
  assert_true(parity_value(cube.pown_rev(3)) == parity_expect(1.0, 2.0))
  assert_true(parity_value(rc.pown_rev(-2)) == parity_expect(-1.0, 1.0))
  assert_true(parity_value(rc.pown_rev(-2, x=rx)) == parity_expect(0.5, 1.0))
  let failed = IntervalChecked::from_result(
    Err(@def.ArithmeticError::domain_error("earlier failure")),
  )
  assert_true(failed.sqr_rev().result() is Err(_))
  assert_true(rc.sqr_rev(x=failed).result() is Err(_))
  assert_true(failed.abs_rev().result() is Err(_))
  assert_true(failed.cosh_rev().result() is Err(_))
  assert_true(failed.pown_rev(2).result() is Err(_))
  assert_true(rc.pown_rev(2, x=failed).result() is Err(_))
}

///|
// oracle: A
// source: expected values written out by hand from IEEE 1788-2015 10.5.4: sinRev([0,0]) over the default prior is Entire (every multiple of pi), over the prior [-1,1] only 0 lies in it, so [0,0]; cosRev([1,1]) on [-1,1] is [0,0]; tanRev([0,0]) is Entire, on [-1,1] it is [0,0]
// shares: Interval ==, from_bounds, Interval::entire and Binary::from_double only
test "sin_rev, cos_rev and tan_rev exist on the checked tier and agree with the plain tier" {
  let rc = parity_result(0, 0)
  let one = parity_result(1, 1)
  let rx = parity_result(-1, 1)
  let entire = @interval.Interval::entire(precision=53)
  assert_true(parity_value(rc.sin_rev()) == entire)
  assert_true(parity_value(rc.sin_rev(x=rx)) == parity_expect(0.0, 0.0))
  assert_true(parity_value(one.cos_rev(x=rx)) == parity_expect(0.0, 0.0))
  assert_true(parity_value(rc.tan_rev(x=rx)) == parity_expect(0.0, 0.0))
  assert_true(parity_value(rc.tan_rev()) == entire)
  let failed = IntervalChecked::from_result(
    Err(@def.ArithmeticError::domain_error("earlier failure")),
  )
  assert_true(failed.sin_rev().result() is Err(_))
  assert_true(failed.cos_rev().result() is Err(_))
  assert_true(failed.tan_rev().result() is Err(_))
  assert_true(rc.sin_rev(x=failed).result() is Err(_))
  assert_true(rc.cos_rev(x=failed).result() is Err(_))
  assert_true(rc.tan_rev(x=failed).result() is Err(_))
}

///|
// oracle: A
// source: expected values written out by hand from IEEE 1788-2015 10.5.4: x^2 in [1,4] with x >= 0 (the domain of pow) gives x in [1,2]; with the prior [0,3/2] it is [1,3/2]
// shares: Interval ==, from_bounds and Binary::from_double only
test "pow_rev1 exists on the checked tier and agrees with the plain tier" {
  let rb = parity_result(2, 2)
  let rc = parity_result(1, 4)
  let rx = IntervalChecked::ok(parity_expect(0.0, 1.5))
  assert_true(parity_value(rb.pow_rev1(rc)) == parity_expect(1.0, 2.0))
  assert_true(parity_value(rb.pow_rev1(rc, x=rx)) == parity_expect(1.0, 1.5))
  let failed = IntervalChecked::from_result(
    Err(@def.ArithmeticError::domain_error("earlier failure")),
  )
  assert_true(failed.pow_rev1(rc).result() is Err(_))
  assert_true(rb.pow_rev1(failed).result() is Err(_))
  assert_true(rb.pow_rev1(rc, x=failed).result() is Err(_))
}

///|
// oracle: A
// source: expected values written out by hand from IEEE 1788-2015 10.5.4: 2^x in [2,8] gives x in [1,3]; with the prior [0,2] it is [1,2]
// shares: Interval ==, from_bounds and Binary::from_double only
test "pow_rev2 exists on the checked tier and agrees with the plain tier" {
  let rb = parity_result(2, 2)
  let rc = parity_result(2, 8)
  let rx = parity_result(0, 2)
  assert_true(parity_value(rb.pow_rev2(rc)) == parity_expect(1.0, 3.0))
  assert_true(parity_value(rb.pow_rev2(rc, x=rx)) == parity_expect(1.0, 2.0))
  let failed = IntervalChecked::from_result(
    Err(@def.ArithmeticError::domain_error("earlier failure")),
  )
  assert_true(failed.pow_rev2(rc).result() is Err(_))
  assert_true(rb.pow_rev2(failed).result() is Err(_))
  assert_true(rb.pow_rev2(rc, x=failed).result() is Err(_))
}

///|
// oracle: A
// source: expected values written out by hand from IEEE 1788-2015 10.5.4: atan2(y, 1) = 0 only for y = 0, so atan2Rev1(b=[1,1], c=[0,0]) is [0,0]; c = [-4,4] contains every angle, so the result is the prior (Entire, or [0,9])
// shares: Interval ==, from_bounds, Interval::entire and Binary::from_double only
test "atan2_rev1 exists on the checked tier and agrees with the plain tier" {
  let rb = parity_result(1, 1)
  let zero = parity_result(0, 0)
  let wide = parity_result(-4, 4)
  let rx = parity_result(0, 9)
  assert_true(parity_value(rb.atan2_rev1(zero)) == parity_expect(0.0, 0.0))
  assert_true(
    parity_value(rb.atan2_rev1(wide)) == @interval.Interval::entire(precision=53),
  )
  assert_true(parity_value(rb.atan2_rev1(wide, x=rx)) == parity_expect(0.0, 9.0))
  let failed = IntervalChecked::from_result(
    Err(@def.ArithmeticError::domain_error("earlier failure")),
  )
  assert_true(failed.atan2_rev1(wide).result() is Err(_))
  assert_true(rb.atan2_rev1(failed).result() is Err(_))
  assert_true(rb.atan2_rev1(wide, x=failed).result() is Err(_))
}

///|
// oracle: A
// source: expected values written out by hand from IEEE 1788-2015 10.5.4: atan2(1, x) is never 0, so atan2Rev2(b=[1,1], c=[0,0]) is Empty; c = [-4,4] contains every angle, so the result is the prior (Entire, or [0,9])
// shares: Interval ==, from_bounds, Interval::entire, Interval::empty and Binary::from_double only
test "atan2_rev2 exists on the checked tier and agrees with the plain tier" {
  let rb = parity_result(1, 1)
  let zero = parity_result(0, 0)
  let wide = parity_result(-4, 4)
  let rx = parity_result(0, 9)
  assert_true(
    parity_value(rb.atan2_rev2(zero)) == @interval.Interval::empty(precision=53),
  )
  assert_true(
    parity_value(rb.atan2_rev2(wide)) == @interval.Interval::entire(precision=53),
  )
  assert_true(parity_value(rb.atan2_rev2(wide, x=rx)) == parity_expect(0.0, 9.0))
  let failed = IntervalChecked::from_result(
    Err(@def.ArithmeticError::domain_error("earlier failure")),
  )
  assert_true(failed.atan2_rev2(wide).result() is Err(_))
  assert_true(rb.atan2_rev2(failed).result() is Err(_))
  assert_true(rb.atan2_rev2(wide, x=failed).result() is Err(_))
}

///|
// oracle: A
// source: expected value written out: the literal [1.5, 2.5] is the interval with the exact bounds 1.5 and 2.5; the text [2,1] (lower above upper) and precision 0 are errors: by IEEE 1788-2015 10.2 (4) a lower bound above the upper bound is not an interval; precision 0 is outside the library limits
// shares: Interval ==, from_bounds and Binary::from_double only
test "from_string exists on the checked tier and agrees with the plain tier" {
  let ok = IntervalChecked::from_string("[1.5, 2.5]")
  assert_true(ok.result() is Ok(_))
  assert_true(parity_value(ok) == parity_expect(1.5, 2.5))
  assert_true(IntervalChecked::from_string("[2,1]").result() is Err(_))
  assert_true(
    IntervalChecked::from_string("[1]", precision=0).result() is Err(_),
  )
}
