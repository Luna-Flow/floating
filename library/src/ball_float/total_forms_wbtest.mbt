///|
fn total_forms_pow2(exponent : Int32, precision : Int32) -> @bin_float.BinFloat {
  @bin_float.BinFloat::make(@bin_float.BinCoeff::one(), exponent, precision)
}

///|
/// Issue 449: the plain `ln_interval` aborted from about 32,000 bits of
/// precision ("certified log series did not converge"). The plain form is the
/// `try_` form with a fallback, so it returns an enclosure at any precision and
/// equals the `try_` form whenever that succeeds.
test "ln_interval at 32,000 bits returns a tight enclosure (issue 449)" {
  let x = BallFloat::from_int(3, precision=32_000)
  let y = x.ln_interval()
  assert_true(y.is_common_interval())
  assert_true(y.width().compare(total_forms_pow2(-31_990, 32_000)) <= 0)
  // exp(ln 3) must contain 3.
  let back = y.exp_interval()
  assert_true(back.contains(@bin_float.BinFloat::from_int(3, precision=32_000)))
  match x.try_ln_interval() {
    Ok(t) => assert_true(y.set_equal(t))
    Err(_) => ()
  }
}

///|
test "exp_interval at 160,000 bits returns an enclosure (issue 449)" {
  let y = BallFloat::from_int(1, precision=160_000).exp_interval()
  assert_true(y.is_common_interval())
  assert_true(y.width().compare(total_forms_pow2(-159_990, 160_000)) <= 0)
}

///|
/// The plain hyperbolic forms lost all relative accuracy for a tiny argument:
/// the lower bound was 0 and the width about 2^-245 at x = 2^-300.
test "hyperbolic forms keep relative accuracy for a tiny argument" {
  let x = BallFloat::exact(total_forms_pow2(-300, 53), precision=53)
  let tiny = total_forms_pow2(-340, 53)
  for
    y in [
      x.sinh_interval(),
      x.tanh_interval(),
      x.asinh_interval(),
      x.atanh_interval(),
    ] {
    assert_true(y.lower_bound().compare(@bin_float.BinFloat::zero()) > 0)
    assert_true(y.width().compare(tiny) <= 0)
  }
}

///|
/// `try_atanh_interval` of an interval whose only point in the domain's closure
/// is 1 or -1 evaluated the pole and aborted ("ball lower bound must not be
/// positive infinity"); the open domain leaves nothing, so the result is Empty.
test "atanh of an interval meeting the closure of the domain at one point" {
  let inf = @bin_float.BinFloat::inf(Sign::Positive, precision=53)
  let one = @bin_float.BinFloat::one(precision=53)
  for
    b in [
      (one, one),
      (one, inf),
      (inf.neg(), one.neg()),
      (one.neg(), one.neg()),
    ] {
    let x = BallFloat::from_bounds(b.0, b.1, precision=53)
    assert_true(x.atanh_interval().is_empty())
    assert_true(x.try_atanh_interval().unwrap().is_empty())
  }
}
