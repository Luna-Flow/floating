// `BinFloatResult::rsqrt`, `compound`, `powr` and their `_ctx` forms: the flags
// of IEEE 754-2019 9.2.1 are mapped as for the other elementary functions
// (invalid operation: `DomainError`, divideByZero: `DivisionByZero`).

///|
fn rcp_render(result : BinFloatResult) -> String {
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
test "checked rsqrt, compound and powr map the exception flags" {
  let context = @bin_float.BinaryContext::binary64()
  let value = fn(x : @bin_float.BinFloat) { BinFloatResult::ok(x) }
  let zero = value(@bin_float.BinFloat::zero())
  let minus_zero = value(@bin_float.BinFloat::negative_zero())
  let one = value(@bin_float.BinFloat::one())
  let two = value(@bin_float.BinFloat::from_int(2))
  let four = value(@bin_float.BinFloat::from_int(4))
  let minus_one = value(@bin_float.BinFloat::from_int(-1))
  let minus_two = value(@bin_float.BinFloat::from_int(-2))
  let snan = value(@bin_float.BinFloat::signaling_nan())
  let qnan = value(@bin_float.BinFloat::quiet_nan())
  let inf = value(@bin_float.BinFloat::inf(@def.Sign::Positive))
  let minus_inf = value(@bin_float.BinFloat::inf(@def.Sign::Negative))
  // rSqrt: +0 -> +inf (divideByZero), +inf -> +0, 4 -> 1/2 exactly
  assert_eq(rcp_render(zero.rsqrt()), "err:div0")
  assert_eq(rcp_render(minus_zero.rsqrt_ctx(context)), "err:div0")
  assert_eq(rcp_render(inf.rsqrt()), "ok:0")
  assert_eq(rcp_render(four.rsqrt()), "ok:1p-1")
  assert_eq(rcp_render(minus_two.rsqrt()), "err:invalid")
  assert_eq(rcp_render(minus_inf.rsqrt_ctx(context)), "err:invalid")
  assert_eq(rcp_render(snan.rsqrt()), "err:invalid")
  assert_eq(rcp_render(qnan.rsqrt()), "ok:nan")
  // compound(x, n)
  assert_eq(rcp_render(one.compound(3)), "ok:1p3")
  assert_eq(rcp_render(minus_one.compound(-2)), "err:div0")
  assert_eq(rcp_render(minus_one.compound_ctx(2, context)), "ok:0")
  assert_eq(rcp_render(minus_two.compound(2)), "err:invalid")
  assert_eq(rcp_render(zero.compound(-9)), "ok:1p0")
  assert_eq(rcp_render(inf.compound_ctx(-1, context)), "ok:0")
  assert_eq(rcp_render(qnan.compound(0)), "ok:1p0")
  assert_eq(rcp_render(snan.compound(1)), "err:invalid")
  // powr(x, y)
  assert_eq(rcp_render(two.powr(two)), "ok:1p2")
  assert_eq(rcp_render(zero.powr(minus_one)), "err:div0")
  assert_eq(rcp_render(zero.powr_ctx(minus_inf, context)), "ok:inf")
  assert_eq(rcp_render(zero.powr(zero)), "err:invalid")
  assert_eq(rcp_render(minus_two.powr(two)), "err:invalid")
  assert_eq(rcp_render(one.powr(inf)), "err:invalid")
  assert_eq(rcp_render(inf.powr_ctx(zero, context)), "err:invalid")
  assert_eq(rcp_render(two.powr(qnan)), "ok:nan")
  assert_eq(rcp_render(two.powr(snan)), "err:invalid")
}
