///|
/// The previous construction of `pi` (finding 4 of #374): `4 atan(1)` through
/// the ball interval `atan`. Kept here only to prove the cached source gives
/// the same interval bit for bit.
fn old_decimal_pi_ball(precision : Int32) -> @ball_float.BallFloat {
  @ball_float.BallFloat::from_int(1, precision~)
  .try_atan()
  .unwrap()
  .mul(@ball_float.BallFloat::from_int(4, precision~))
}

///|
fn old_decimal_quarter_pi_ball(precision : Int32) -> @ball_float.BallFloat {
  @ball_float.BallFloat::from_int(1, precision~).atan()
}

///|
test "decimal pi enclosure equals 4 atan(1) bit for bit" {
  let mut precision = 1
  while precision <= 300 {
    let fresh = decimal_pi_ball(precision)
    let old = old_decimal_pi_ball(precision)
    assert_true(
      fresh.lower_bound().compare(old.lower_bound()) == 0,
      msg="lower bound differs at precision \{precision}",
    )
    assert_true(
      fresh.upper_bound().compare(old.upper_bound()) == 0,
      msg="upper bound differs at precision \{precision}",
    )
    assert_eq(fresh.precision(), old.precision())
    precision += if precision < 80 { 1 } else { 17 }
  }
  for precision in [512, 1000, 2048] {
    let fresh = decimal_pi_ball(precision)
    let old = old_decimal_pi_ball(precision)
    assert_true(fresh.lower_bound().compare(old.lower_bound()) == 0)
    assert_true(fresh.upper_bound().compare(old.upper_bound()) == 0)
  }
}

///|
test "decimal quarter pi multiples equal quarters of the atan(1) interval" {
  for precision in [1, 2, 7, 24, 53, 64, 113, 200, 333] {
    let pi = decimal_pi_enclosure(precision)
    let scale = @bin_float.BinFloat::make(@bin_float.BinCoeff::one(), -2, 2)
    let exact = @bin_float.BinaryContext::new(precision~)
    let quarter = @ball_float.BallFloat::from_bounds(
      pi.0.mul_ctx(scale, exact).0,
      pi.1.mul_ctx(scale, exact).0,
      precision~,
    )
    let old = old_decimal_quarter_pi_ball(precision)
    assert_true(quarter.lower_bound().compare(old.lower_bound()) == 0)
    assert_true(quarter.upper_bound().compare(old.upper_bound()) == 0)
  }
}
