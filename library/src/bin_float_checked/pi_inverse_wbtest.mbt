// `BinFloatResult::asinpi`, `acospi`, `atanpi`, `atan2pi` and their `_ctx`
// forms: the invalid operations of IEEE 754-2019 9.2.1 (|x| > 1 for asinPi and
// acosPi, a signaling NaN) are a `DomainError`; every special value of the
// tables is a value, atan2Pi has no exception on 0 and infinity.

///|
fn pi_render(result : BinFloatResult) -> String {
  match result.result() {
    Err(error) =>
      match error.kind {
        @lf_arith.ArithmeticErrorKind::DivisionByZero => "err:div0"
        @lf_arith.ArithmeticErrorKind::DomainError => "err:invalid"
        _ => "err:other"
      }
    Ok(value) => "ok:\{value}"
  }
}

///|
test "checked asinpi, acospi, atanpi and atan2pi map the exception flags" {
  let context = @bin_float.BinaryContext::binary64()
  let value = fn(x : @bin_float.BinFloat) { BinFloatResult::ok(x) }
  let zero = value(@bin_float.BinFloat::zero())
  let one = value(@bin_float.BinFloat::one())
  let minus_one = value(@bin_float.BinFloat::from_int(-1))
  let two = value(@bin_float.BinFloat::from_int(2))
  let snan = value(@bin_float.BinFloat::signaling_nan())
  let qnan = value(@bin_float.BinFloat::quiet_nan())
  let inf = value(@bin_float.BinFloat::inf(@def.Sign::Positive))
  let minus_inf = value(@bin_float.BinFloat::inf(@def.Sign::Negative))
  // exact values
  assert_eq(pi_render(one.asinpi()), "ok:1p-1")
  assert_eq(pi_render(minus_one.asinpi_ctx(context)), "ok:-1p-1")
  assert_eq(pi_render(one.acospi()), "ok:0")
  assert_eq(pi_render(minus_one.acospi_ctx(context)), "ok:1p0")
  assert_eq(pi_render(zero.acospi()), "ok:1p-1")
  assert_eq(pi_render(one.atanpi()), "ok:1p-2")
  assert_eq(pi_render(inf.atanpi()), "ok:1p-1")
  assert_eq(pi_render(minus_inf.atanpi_ctx(context)), "ok:-1p-1")
  // |x| > 1 and infinities are invalid for asinPi and acosPi
  assert_eq(pi_render(two.asinpi()), "err:invalid")
  assert_eq(pi_render(two.acospi_ctx(context)), "err:invalid")
  assert_eq(pi_render(inf.asinpi()), "err:invalid")
  assert_eq(pi_render(minus_inf.acospi()), "err:invalid")
  // a signaling NaN is invalid, a quiet NaN propagates
  assert_eq(pi_render(snan.asinpi()), "err:invalid")
  assert_eq(pi_render(snan.atanpi_ctx(context)), "err:invalid")
  assert_eq(pi_render(qnan.acospi()), "ok:nan")
  // atan2Pi: exact constants without exception
  assert_eq(pi_render(zero.atan2pi(minus_one)), "ok:1p0")
  assert_eq(pi_render(two.atan2pi(zero)), "ok:1p-1")
  assert_eq(pi_render(inf.atan2pi_ctx(minus_inf, context)), "ok:3p-2")
  assert_eq(pi_render(two.atan2pi(two)), "ok:1p-2")
  assert_eq(pi_render(snan.atan2pi(two)), "err:invalid")
  assert_eq(pi_render(two.atan2pi_ctx(snan, context)), "err:invalid")
  assert_eq(pi_render(qnan.atan2pi(two)), "ok:nan")
}
