///|
/// Oracle: level A. The expected outcomes are written out: a signaling NaN operand is
/// an invalid operation for every operation below (IEEE 754-2019 7.2 a)), so the
/// checked tier returns a `domain_error`, and its message begins with the name of the
/// operation (`name: invalid operation`). The walk covers every `BinaryChecked`
/// function that can fail, plain and `_ctx` forms, so that a later copy of a wrapper
/// that passes another name, or none, is caught. The plain `add`, `sub` and `mul`
/// are the operators of `binary` (rounding without flags) and never fail, so they
/// are not in the table; their `_ctx` forms are.
fn checked_invalid_table() -> Array[(String, (BinaryChecked) -> BinaryChecked)] {
  let two = BinaryChecked::from_int(2)
  let ctx = @binary.BinaryContext::new(precision=24)
  [
    ("acos", fn(x : BinaryChecked) { x.acos() }),
    ("acos", fn(x : BinaryChecked) { x.acos_ctx(ctx) }),
    ("acosh", fn(x : BinaryChecked) { x.acosh() }),
    ("acosh", fn(x : BinaryChecked) { x.acosh_ctx(ctx) }),
    ("acospi", fn(x : BinaryChecked) { x.acospi() }),
    ("acospi", fn(x : BinaryChecked) { x.acospi_ctx(ctx) }),
    ("add", fn(x : BinaryChecked) { x.add_ctx(two, ctx) }),
    ("asin", fn(x : BinaryChecked) { x.asin() }),
    ("asin", fn(x : BinaryChecked) { x.asin_ctx(ctx) }),
    ("asinh", fn(x : BinaryChecked) { x.asinh() }),
    ("asinh", fn(x : BinaryChecked) { x.asinh_ctx(ctx) }),
    ("asinpi", fn(x : BinaryChecked) { x.asinpi() }),
    ("asinpi", fn(x : BinaryChecked) { x.asinpi_ctx(ctx) }),
    ("atan", fn(x : BinaryChecked) { x.atan() }),
    ("atan2", fn(x : BinaryChecked) { x.atan2(two) }),
    ("atan2", fn(x : BinaryChecked) { x.atan2_ctx(two, ctx) }),
    ("atan2pi", fn(x : BinaryChecked) { x.atan2pi(two) }),
    ("atan2pi", fn(x : BinaryChecked) { x.atan2pi_ctx(two, ctx) }),
    ("atan", fn(x : BinaryChecked) { x.atan_ctx(ctx) }),
    ("atanh", fn(x : BinaryChecked) { x.atanh() }),
    ("atanh", fn(x : BinaryChecked) { x.atanh_ctx(ctx) }),
    ("atanpi", fn(x : BinaryChecked) { x.atanpi() }),
    ("atanpi", fn(x : BinaryChecked) { x.atanpi_ctx(ctx) }),
    ("compound", fn(x : BinaryChecked) { x.compound(3) }),
    ("compound", fn(x : BinaryChecked) { x.compound_ctx(3, ctx) }),
    ("cos", fn(x : BinaryChecked) { x.cos() }),
    ("cos", fn(x : BinaryChecked) { x.cos_ctx(ctx) }),
    ("cosh", fn(x : BinaryChecked) { x.cosh() }),
    ("cosh", fn(x : BinaryChecked) { x.cosh_ctx(ctx) }),
    ("cospi", fn(x : BinaryChecked) { x.cospi() }),
    ("cospi", fn(x : BinaryChecked) { x.cospi_ctx(ctx) }),
    ("div", fn(x : BinaryChecked) { x.div(two) }),
    ("div", fn(x : BinaryChecked) { x.div_ctx(two, ctx) }),
    ("exp", fn(x : BinaryChecked) { x.exp() }),
    ("exp10", fn(x : BinaryChecked) { x.exp10() }),
    ("exp10", fn(x : BinaryChecked) { x.exp10_ctx(ctx) }),
    ("exp10m1", fn(x : BinaryChecked) { x.exp10m1() }),
    ("exp10m1", fn(x : BinaryChecked) { x.exp10m1_ctx(ctx) }),
    ("exp2", fn(x : BinaryChecked) { x.exp2() }),
    ("exp2", fn(x : BinaryChecked) { x.exp2_ctx(ctx) }),
    ("exp2m1", fn(x : BinaryChecked) { x.exp2m1() }),
    ("exp2m1", fn(x : BinaryChecked) { x.exp2m1_ctx(ctx) }),
    ("exp", fn(x : BinaryChecked) { x.exp_ctx(ctx) }),
    ("expm1", fn(x : BinaryChecked) { x.expm1() }),
    ("expm1", fn(x : BinaryChecked) { x.expm1_ctx(ctx) }),
    ("hypot", fn(x : BinaryChecked) { x.hypot(two) }),
    ("hypot", fn(x : BinaryChecked) { x.hypot_ctx(two, ctx) }),
    ("ln", fn(x : BinaryChecked) { x.ln() }),
    ("ln", fn(x : BinaryChecked) { x.ln_ctx(ctx) }),
    ("log10", fn(x : BinaryChecked) { x.log10() }),
    ("log10", fn(x : BinaryChecked) { x.log10_ctx(ctx) }),
    ("log10p1", fn(x : BinaryChecked) { x.log10p1() }),
    ("log10p1", fn(x : BinaryChecked) { x.log10p1_ctx(ctx) }),
    ("log1p", fn(x : BinaryChecked) { x.log1p() }),
    ("log1p", fn(x : BinaryChecked) { x.log1p_ctx(ctx) }),
    ("log2", fn(x : BinaryChecked) { x.log2() }),
    ("log2", fn(x : BinaryChecked) { x.log2_ctx(ctx) }),
    ("log2p1", fn(x : BinaryChecked) { x.log2p1() }),
    ("log2p1", fn(x : BinaryChecked) { x.log2p1_ctx(ctx) }),
    ("mul", fn(x : BinaryChecked) { x.mul_ctx(two, ctx) }),
    ("pow", fn(x : BinaryChecked) { x.pow(two) }),
    ("pow", fn(x : BinaryChecked) { x.pow_ctx(two, ctx) }),
    ("pown", fn(x : BinaryChecked) { x.pown(3) }),
    ("pown", fn(x : BinaryChecked) { x.pown_ctx(3, ctx) }),
    ("powr", fn(x : BinaryChecked) { x.powr(two) }),
    ("powr", fn(x : BinaryChecked) { x.powr_ctx(two, ctx) }),
    ("rootn", fn(x : BinaryChecked) { x.rootn(3) }),
    ("rootn", fn(x : BinaryChecked) { x.rootn_ctx(3, ctx) }),
    ("rsqrt", fn(x : BinaryChecked) { x.rsqrt() }),
    ("rsqrt", fn(x : BinaryChecked) { x.rsqrt_ctx(ctx) }),
    ("sin", fn(x : BinaryChecked) { x.sin() }),
    ("sin", fn(x : BinaryChecked) { x.sin_ctx(ctx) }),
    ("sinh", fn(x : BinaryChecked) { x.sinh() }),
    ("sinh", fn(x : BinaryChecked) { x.sinh_ctx(ctx) }),
    ("sinpi", fn(x : BinaryChecked) { x.sinpi() }),
    ("sinpi", fn(x : BinaryChecked) { x.sinpi_ctx(ctx) }),
    ("sqrt", fn(x : BinaryChecked) { x.sqrt() }),
    ("sqrt", fn(x : BinaryChecked) { x.sqrt_ctx(ctx) }),
    ("sub", fn(x : BinaryChecked) { x.sub_ctx(two, ctx) }),
    ("tan", fn(x : BinaryChecked) { x.tan() }),
    ("tan", fn(x : BinaryChecked) { x.tan_ctx(ctx) }),
    ("tanh", fn(x : BinaryChecked) { x.tanh() }),
    ("tanh", fn(x : BinaryChecked) { x.tanh_ctx(ctx) }),
    ("tanpi", fn(x : BinaryChecked) { x.tanpi() }),
    ("tanpi", fn(x : BinaryChecked) { x.tanpi_ctx(ctx) }),
  ]
}

///|
test "every failing BinaryChecked operation names itself in its error" {
  let table = checked_invalid_table()
  assert_eq(table.length(), 85)
  for row in table {
    let (name, run) = row
    let operand = BinaryChecked::ok(@binary.Binary::signaling_nan())
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
