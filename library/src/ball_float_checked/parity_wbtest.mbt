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
