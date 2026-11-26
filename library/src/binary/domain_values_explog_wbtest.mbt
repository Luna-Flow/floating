///|
/// S4, exp/log family: the three outcomes of `ln`, `log2`, `log10`, `log1p`,
/// `log2p1` and `log10p1`, asserted separately. A domain case (`x <= 0`, or
/// `x < -1` for the `p1` forms) is a value in the `try_` form and in the plain form:
/// a NaN with `invalid_operation` and without `not_computed`. A result that cannot
/// be certified within the refinement limit is `Err` in the `try_` form and a NaN
/// with `not_computed` and without `invalid_operation` in the plain form; the
/// argument is the inverse function of the midpoint of two 53-bit values at 330
/// bits, as in `refinement_hard_input`. An ordinary case is unchanged.
fn explog_table() -> Array[
  (
    String,
    (Binary, BinaryContext) -> (Binary, BinaryFlags),
    (Binary, BinaryContext) -> Result[
      (Binary, BinaryFlags),
      @def.ArithmeticError,
    ],
    (Binary, BinaryContext) -> (Binary, BinaryFlags),
    Binary,
  ),
] {
  [
    (
      "ln",
      fn(x, c) { x.exp_ctx(c) },
      fn(x, c) { x.try_ln_ctx(c) },
      fn(x, c) { x.ln_ctx(c) },
      Binary::from_int(-2),
    ),
    (
      "log2",
      fn(x, c) { x.exp2_ctx(c) },
      fn(x, c) { x.try_log2_ctx(c) },
      fn(x, c) { x.log2_ctx(c) },
      Binary::from_int(-2),
    ),
    (
      "log10",
      fn(x, c) { x.exp10_ctx(c) },
      fn(x, c) { x.try_log10_ctx(c) },
      fn(x, c) { x.log10_ctx(c) },
      Binary::from_int(-2),
    ),
    (
      "log1p",
      fn(x, c) { x.expm1_ctx(c) },
      fn(x, c) { x.try_log1p_ctx(c) },
      fn(x, c) { x.log1p_ctx(c) },
      Binary::from_int(-2),
    ),
    (
      "log2p1",
      fn(x, c) { x.exp2m1_ctx(c) },
      fn(x, c) { x.try_log2p1_ctx(c) },
      fn(x, c) { x.log2p1_ctx(c) },
      Binary::from_int(-2),
    ),
    (
      "log10p1",
      fn(x, c) { x.exp10m1_ctx(c) },
      fn(x, c) { x.try_log10p1_ctx(c) },
      fn(x, c) { x.log10p1_ctx(c) },
      Binary::from_int(-2),
    ),
  ]
}

///|
// oracle: S
// source: the written rule S4 of the library for the exp and log families: a domain case is a value with invalid_operation in both forms, a failure forced through the refinement limit is an Err in the try_ form and a NaN with not_computed in the plain form, an ordinary case passes through unchanged; a rule of this library, not of the standard
// shares: explog_table lists the functions with their inverses and domain cases; refinement_failed and the midpoint input of ln at 330 bits build the failing case; the try_ and plain forms are the code under test
test "exp/log family: domain case, could-not-compute case and ordinary case" {
  let base = BinaryContext::new(precision=53)
  let wide = BinaryContext::new(precision=330)
  let one = Binary::from_int(1, precision=330)
  let midpoint = one.add_ctx(
      one.scaleb_ctx(Binary::from_int(-53), wide).0,
      wide,
    ).0
  for row in explog_table() {
    let (name, inverse, try_form, plain, domain) = row
    // a domain case: a value with invalid_operation, in both forms
    match try_form(domain, base) {
      Ok((value, flags)) => {
        assert_true(value.is_nan(), msg=name + " domain value")
        assert_true(flags.invalid_operation(), msg=name + " domain invalid")
        assert_false(flags.not_computed(), msg=name + " domain not_computed")
      }
      Err(_) => abort(name + ": a domain case must not be an Err")
    }
    let (plain_value, plain_flags) = plain(domain, base)
    assert_true(plain_value.is_nan(), msg=name + " plain domain value")
    assert_true(
      plain_flags.invalid_operation(),
      msg=name + " plain domain invalid",
    )
    assert_false(
      plain_flags.not_computed(),
      msg=name + " plain domain not_computed",
    )
    // could not compute: the argument whose result lies next to a midpoint
    let hard = inverse(midpoint, wide).0
    let limited = base.with_refinement_limit(Some(1))
    assert_true(
      refinement_failed(try_form(hard, limited)),
      msg=name + " forced Err",
    )
    let (limit_value, limit_flags) = plain(hard, limited)
    assert_true(limit_value.is_nan(), msg=name + " forced value")
    assert_true(limit_flags.not_computed(), msg=name + " forced not_computed")
    assert_false(limit_flags.invalid_operation(), msg=name + " forced invalid")
    // an ordinary case: unchanged
    let three = Binary::from_int(3)
    let (ok, ok_flags) = match try_form(three, base) {
      Ok(result) => result
      Err(_) => abort(name + ": an ordinary case must be Ok")
    }
    assert_false(ok.is_nan(), msg=name + " ordinary value")
    assert_false(
      ok_flags.invalid_operation() || ok_flags.not_computed(),
      msg=name + " ordinary flags",
    )
    let (plain_ok, plain_ok_flags) = plain(three, base)
    assert_true(plain_ok.identical(ok), msg=name + " plain = try")
    assert_true(
      plain_ok_flags == ok_flags,
      msg=name + " plain flags = try flags",
    )
  }
}
