///|
/// Oracle: level A. The expected outcomes are written out: a signaling NaN operand is
/// an invalid operation for every operation below (IEEE 754-2019 7.2 a)), so the
/// checked tier returns a `domain_error`, and its message begins with the name of the
/// operation (`name: invalid operation`). The walk covers every `BinFloatResult`
/// function that can fail, plain and `_ctx` forms, so that a later copy of a wrapper
/// that passes another name, or none, is caught. The plain `add`, `sub` and `mul`
/// are the operators of `bin_float` (rounding without flags) and never fail, so they
/// are not in the table; their `_ctx` forms are.
fn checked_invalid_table() -> Array[
  (String, (BinFloatResult) -> BinFloatResult),
] {
  let two = BinFloatResult::from_int(2)
  let ctx = @bin_float.BinaryContext::new(precision=24)
  [
    ("acos", fn(x : BinFloatResult) { x.acos() }),
    ("acos", fn(x : BinFloatResult) { x.acos_ctx(ctx) }),
    ("acosh", fn(x : BinFloatResult) { x.acosh() }),
    ("acosh", fn(x : BinFloatResult) { x.acosh_ctx(ctx) }),
    ("acospi", fn(x : BinFloatResult) { x.acospi() }),
    ("acospi", fn(x : BinFloatResult) { x.acospi_ctx(ctx) }),
    ("add", fn(x : BinFloatResult) { x.add_ctx(two, ctx) }),
    ("asin", fn(x : BinFloatResult) { x.asin() }),
    ("asin", fn(x : BinFloatResult) { x.asin_ctx(ctx) }),
    ("asinh", fn(x : BinFloatResult) { x.asinh() }),
    ("asinh", fn(x : BinFloatResult) { x.asinh_ctx(ctx) }),
    ("asinpi", fn(x : BinFloatResult) { x.asinpi() }),
    ("asinpi", fn(x : BinFloatResult) { x.asinpi_ctx(ctx) }),
    ("atan", fn(x : BinFloatResult) { x.atan() }),
    ("atan2", fn(x : BinFloatResult) { x.atan2(two) }),
    ("atan2", fn(x : BinFloatResult) { x.atan2_ctx(two, ctx) }),
    ("atan2pi", fn(x : BinFloatResult) { x.atan2pi(two) }),
    ("atan2pi", fn(x : BinFloatResult) { x.atan2pi_ctx(two, ctx) }),
    ("atan", fn(x : BinFloatResult) { x.atan_ctx(ctx) }),
    ("atanh", fn(x : BinFloatResult) { x.atanh() }),
    ("atanh", fn(x : BinFloatResult) { x.atanh_ctx(ctx) }),
    ("atanpi", fn(x : BinFloatResult) { x.atanpi() }),
    ("atanpi", fn(x : BinFloatResult) { x.atanpi_ctx(ctx) }),
    ("compound", fn(x : BinFloatResult) { x.compound(3) }),
    ("compound", fn(x : BinFloatResult) { x.compound_ctx(3, ctx) }),
    ("cos", fn(x : BinFloatResult) { x.cos() }),
    ("cos", fn(x : BinFloatResult) { x.cos_ctx(ctx) }),
    ("cosh", fn(x : BinFloatResult) { x.cosh() }),
    ("cosh", fn(x : BinFloatResult) { x.cosh_ctx(ctx) }),
    ("cospi", fn(x : BinFloatResult) { x.cospi() }),
    ("cospi", fn(x : BinFloatResult) { x.cospi_ctx(ctx) }),
    ("div", fn(x : BinFloatResult) { x.div(two) }),
    ("div", fn(x : BinFloatResult) { x.div_ctx(two, ctx) }),
    ("exp", fn(x : BinFloatResult) { x.exp() }),
    ("exp10", fn(x : BinFloatResult) { x.exp10() }),
    ("exp10", fn(x : BinFloatResult) { x.exp10_ctx(ctx) }),
    ("exp10m1", fn(x : BinFloatResult) { x.exp10m1() }),
    ("exp10m1", fn(x : BinFloatResult) { x.exp10m1_ctx(ctx) }),
    ("exp2", fn(x : BinFloatResult) { x.exp2() }),
    ("exp2", fn(x : BinFloatResult) { x.exp2_ctx(ctx) }),
    ("exp2m1", fn(x : BinFloatResult) { x.exp2m1() }),
    ("exp2m1", fn(x : BinFloatResult) { x.exp2m1_ctx(ctx) }),
    ("exp", fn(x : BinFloatResult) { x.exp_ctx(ctx) }),
    ("expm1", fn(x : BinFloatResult) { x.expm1() }),
    ("expm1", fn(x : BinFloatResult) { x.expm1_ctx(ctx) }),
    ("hypot", fn(x : BinFloatResult) { x.hypot(two) }),
    ("hypot", fn(x : BinFloatResult) { x.hypot_ctx(two, ctx) }),
    ("ln", fn(x : BinFloatResult) { x.ln() }),
    ("ln", fn(x : BinFloatResult) { x.ln_ctx(ctx) }),
    ("log10", fn(x : BinFloatResult) { x.log10() }),
    ("log10", fn(x : BinFloatResult) { x.log10_ctx(ctx) }),
    ("log10p1", fn(x : BinFloatResult) { x.log10p1() }),
    ("log10p1", fn(x : BinFloatResult) { x.log10p1_ctx(ctx) }),
    ("log1p", fn(x : BinFloatResult) { x.log1p() }),
    ("log1p", fn(x : BinFloatResult) { x.log1p_ctx(ctx) }),
    ("log2", fn(x : BinFloatResult) { x.log2() }),
    ("log2", fn(x : BinFloatResult) { x.log2_ctx(ctx) }),
    ("log2p1", fn(x : BinFloatResult) { x.log2p1() }),
    ("log2p1", fn(x : BinFloatResult) { x.log2p1_ctx(ctx) }),
    ("mul", fn(x : BinFloatResult) { x.mul_ctx(two, ctx) }),
    ("pow", fn(x : BinFloatResult) { x.pow(two) }),
    ("pow", fn(x : BinFloatResult) { x.pow_ctx(two, ctx) }),
    ("pown", fn(x : BinFloatResult) { x.pown(3) }),
    ("pown", fn(x : BinFloatResult) { x.pown_ctx(3, ctx) }),
    ("powr", fn(x : BinFloatResult) { x.powr(two) }),
    ("powr", fn(x : BinFloatResult) { x.powr_ctx(two, ctx) }),
    ("rootn", fn(x : BinFloatResult) { x.rootn(3) }),
    ("rootn", fn(x : BinFloatResult) { x.rootn_ctx(3, ctx) }),
    ("rsqrt", fn(x : BinFloatResult) { x.rsqrt() }),
    ("rsqrt", fn(x : BinFloatResult) { x.rsqrt_ctx(ctx) }),
    ("sin", fn(x : BinFloatResult) { x.sin() }),
    ("sin", fn(x : BinFloatResult) { x.sin_ctx(ctx) }),
    ("sinh", fn(x : BinFloatResult) { x.sinh() }),
    ("sinh", fn(x : BinFloatResult) { x.sinh_ctx(ctx) }),
    ("sinpi", fn(x : BinFloatResult) { x.sinpi() }),
    ("sinpi", fn(x : BinFloatResult) { x.sinpi_ctx(ctx) }),
    ("sqrt", fn(x : BinFloatResult) { x.sqrt() }),
    ("sqrt", fn(x : BinFloatResult) { x.sqrt_ctx(ctx) }),
    ("sub", fn(x : BinFloatResult) { x.sub_ctx(two, ctx) }),
    ("tan", fn(x : BinFloatResult) { x.tan() }),
    ("tan", fn(x : BinFloatResult) { x.tan_ctx(ctx) }),
    ("tanh", fn(x : BinFloatResult) { x.tanh() }),
    ("tanh", fn(x : BinFloatResult) { x.tanh_ctx(ctx) }),
    ("tanpi", fn(x : BinFloatResult) { x.tanpi() }),
    ("tanpi", fn(x : BinFloatResult) { x.tanpi_ctx(ctx) }),
  ]
}

///|
test "every failing BinFloatResult operation names itself in its error" {
  let table = checked_invalid_table()
  assert_eq(table.length(), 85)
  for row in table {
    let (name, run) = row
    let operand = BinFloatResult::ok(@bin_float.BinFloat::signaling_nan())
    match run(operand).result() {
      Err(error) => {
        assert_true(error.is_domain_error(), msg=name)
        assert_true(
          error.message.has_prefix(name + ": "),
          msg=name + ": " + error.message,
        )
      }
      Ok(_) => abort(name + ": a signaling NaN operand must be an error")
    }
  }
}
