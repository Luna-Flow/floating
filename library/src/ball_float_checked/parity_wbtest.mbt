///|
fn parity_interval(lo : Int32, hi : Int32) -> @ball_float.BallFloat {
  @ball_float.BallFloat::from_bounds(
    @bin_float.BinFloat::from_int(lo, precision=53),
    @bin_float.BinFloat::from_int(hi, precision=53),
    precision=53,
  )
}

///|
fn parity_result(lo : Int32, hi : Int32) -> BallFloatResult {
  BallFloatResult::ok(parity_interval(lo, hi))
}

///|
fn parity_value(r : BallFloatResult) -> @ball_float.BallFloat {
  r.result().unwrap()
}

///|
test "the interval operations of 1788 Table 9.1 and 10.5.6 to 10.5.7 exist on the checked tier and agree with the plain tier" {
  let x = parity_interval(-3, 5)
  let y = parity_interval(1, 4)
  let z = parity_interval(2, 2)
  let rx = parity_result(-3, 5)
  let ry = parity_result(1, 4)
  let rz = parity_result(2, 2)
  assert_true(parity_value(ry.sqrt()).equal(y.sqrt()))
  assert_true(parity_value(rx.sqr()).equal(x.sqr()))
  assert_true(parity_value(ry.recip()).equal(y.recip()))
  assert_true(parity_value(rx.min(ry)).equal(x.min(y)))
  assert_true(parity_value(rx.max(ry)).equal(x.max(y)))
  assert_true(parity_value(rx.fma(ry, rz)).equal(x.fma(y, z)))
  assert_true(parity_value(rx.intersection(ry)).equal(x.intersection(y)))
  assert_true(parity_value(rx.convex_hull(ry)).equal(x.convex_hull(y)))
  assert_true(parity_value(rx.cancel_plus(ry)).equal(x.cancel_plus(y)))
  assert_true(parity_value(rx.cancel_minus(rx)).equal(x.cancel_minus(x)))
}

///|
test "the new checked operations keep the first error" {
  let failed = BallFloatResult::err(
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
test "the integer functions of Table 9.1 exist on the checked tier and agree with the plain tier" {
  let x = @ball_float.BallFloat::from_bounds(
    @bin_float.BinFloat::from_double(-1.5),
    @bin_float.BinFloat::from_double(2.5),
  )
  let r = BallFloatResult::ok(x)
  assert_true(parity_value(r.sign()) == x.sign())
  assert_true(parity_value(r.ceil()) == x.ceil())
  assert_true(parity_value(r.floor()) == x.floor())
  assert_true(parity_value(r.trunc()) == x.trunc())
  assert_true(parity_value(r.round_ties_to_even()) == x.round_ties_to_even())
  assert_true(parity_value(r.round_ties_to_away()) == x.round_ties_to_away())
  let failed = BallFloatResult::from_result(
    Err(@def.ArithmeticError::domain_error("earlier failure")),
  )
  assert_true(failed.ceil().result() is Err(_))
}

///|
test "mul_rev and mul_rev_to_pair exist on the checked tier and agree with the plain tier" {
  let b = parity_interval(-2, 4)
  let c = parity_interval(3, 5)
  let x = parity_interval(0, 9)
  let rb = parity_result(-2, 4)
  let rc = parity_result(3, 5)
  let rx = parity_result(0, 9)
  assert_true(parity_value(rb.mul_rev(rc)) == b.mul_rev(c))
  assert_true(parity_value(rb.mul_rev(rc, x=rx)) == b.mul_rev(c, x~))
  let (u, v) = rb.mul_rev_to_pair(rc)
  let (pu, pv) = b.mul_rev_to_pair(c)
  assert_true(parity_value(u) == pu)
  assert_true(parity_value(v) == pv)
  let failed = BallFloatResult::from_result(
    Err(@def.ArithmeticError::domain_error("earlier failure")),
  )
  assert_true(failed.mul_rev(rc).result() is Err(_))
  assert_true(rb.mul_rev(failed).result() is Err(_))
  let (fu, fv) = failed.mul_rev_to_pair(rc)
  assert_true(fu.result() is Err(_) && fv.result() is Err(_))
}

///|
test "sqr_rev, abs_rev, cosh_rev and pown_rev exist on the checked tier and agree with the plain tier" {
  let c = parity_interval(1, 4)
  let x = parity_interval(0, 9)
  let rc = parity_result(1, 4)
  let rx = parity_result(0, 9)
  assert_true(parity_value(rc.sqr_rev()) == c.sqr_rev())
  assert_true(parity_value(rc.sqr_rev(x=rx)) == c.sqr_rev(x~))
  assert_true(parity_value(rc.abs_rev()) == c.abs_rev())
  assert_true(parity_value(rc.abs_rev(x=rx)) == c.abs_rev(x~))
  assert_true(parity_value(rc.cosh_rev()) == c.cosh_rev())
  assert_true(parity_value(rc.cosh_rev(x=rx)) == c.cosh_rev(x~))
  assert_true(parity_value(rc.pown_rev(3)) == c.pown_rev(3))
  assert_true(parity_value(rc.pown_rev(-2, x=rx)) == c.pown_rev(-2, x~))
  let failed = BallFloatResult::from_result(
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
test "sin_rev, cos_rev and tan_rev exist on the checked tier and agree with the plain tier" {
  let c = parity_interval(0, 0)
  let x = parity_interval(1, 20)
  let rc = parity_result(0, 0)
  let rx = parity_result(1, 20)
  assert_true(parity_value(rc.sin_rev()) == c.sin_rev())
  assert_true(parity_value(rc.sin_rev(x=rx)) == c.sin_rev(x~))
  assert_true(parity_value(rc.cos_rev(x=rx)) == c.cos_rev(x~))
  assert_true(parity_value(rc.tan_rev(x=rx)) == c.tan_rev(x~))
  assert_true(parity_value(rc.tan_rev()) == c.tan_rev())
  let failed = BallFloatResult::from_result(
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
test "pow_rev1 exists on the checked tier and agrees with the plain tier" {
  let b = parity_interval(-2, 3)
  let c = parity_interval(1, 4)
  let x = parity_interval(0, 9)
  let rb = parity_result(-2, 3)
  let rc = parity_result(1, 4)
  let rx = parity_result(0, 9)
  assert_true(parity_value(rb.pow_rev1(rc)) == b.pow_rev1(c))
  assert_true(parity_value(rb.pow_rev1(rc, x=rx)) == b.pow_rev1(c, x~))
  let failed = BallFloatResult::from_result(
    Err(@def.ArithmeticError::domain_error("earlier failure")),
  )
  assert_true(failed.pow_rev1(rc).result() is Err(_))
  assert_true(rb.pow_rev1(failed).result() is Err(_))
  assert_true(rb.pow_rev1(rc, x=failed).result() is Err(_))
}
