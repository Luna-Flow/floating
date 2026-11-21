// `BinFloatResult::exp2m1`, `exp10m1`, `log2p1`, `log10p1` and their `_ctx`
// forms: the flags of IEEE 754-2019 9.2.1 are mapped as for the family since
// #292 (invalid operation: `DomainError`, divideByZero: `DivisionByZero`).

///|
fn pm1_render(result : BinFloatResult) -> String {
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
test "checked exp2m1, exp10m1, log2p1 and log10p1 map the exception flags" {
  let context = @bin_float.BinaryContext::binary64()
  let value = fn(x : @bin_float.BinFloat) { BinFloatResult::ok(x) }
  let zero = value(@bin_float.BinFloat::zero())
  let one = value(@bin_float.BinFloat::one())
  let minus_one = value(@bin_float.BinFloat::from_int(-1))
  let minus_two = value(@bin_float.BinFloat::from_int(-2))
  let snan = value(@bin_float.BinFloat::signaling_nan())
  let qnan = value(@bin_float.BinFloat::quiet_nan())
  let inf = value(@bin_float.BinFloat::inf())
  let minus_inf = value(@bin_float.BinFloat::inf(negative=true))
  // f(+0) = +0, f(+inf) = +inf, f(-inf) = -1: values, no error
  assert_eq(pm1_render(zero.exp2m1()), "ok:0")
  assert_eq(pm1_render(inf.exp2m1()), "ok:inf")
  assert_eq(pm1_render(minus_inf.exp2m1()), "ok:-1p0")
  assert_eq(pm1_render(minus_inf.exp10m1_ctx(context)), "ok:-1p0")
  assert_eq(pm1_render(inf.log2p1()), "ok:inf")
  assert_eq(pm1_render(inf.log10p1_ctx(context)), "ok:inf")
  // exact cases
  assert_eq(pm1_render(one.exp2m1()), "ok:1p0")
  assert_eq(pm1_render(one.log2p1()), "ok:1p0")
  // log2p1(-1) = -inf with divideByZero; below -1 and -inf are invalid
  assert_eq(pm1_render(minus_one.log2p1()), "err:div0")
  assert_eq(pm1_render(minus_one.log10p1_ctx(context)), "err:div0")
  assert_eq(pm1_render(minus_two.log2p1()), "err:invalid")
  assert_eq(pm1_render(minus_two.log10p1_ctx(context)), "err:invalid")
  assert_eq(pm1_render(minus_inf.log2p1()), "err:invalid")
  // a signaling NaN is invalid, a quiet NaN propagates
  assert_eq(pm1_render(snan.exp2m1()), "err:invalid")
  assert_eq(pm1_render(snan.exp10m1_ctx(context)), "err:invalid")
  assert_eq(pm1_render(snan.log2p1()), "err:invalid")
  assert_eq(pm1_render(snan.log10p1_ctx(context)), "err:invalid")
  assert_eq(pm1_render(qnan.exp10m1()), "ok:nan")
  assert_eq(pm1_render(qnan.log2p1_ctx(context)), "ok:nan")
}
