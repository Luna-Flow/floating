///|
/// S4: the three outcomes of every elementary function of `decimal`, asserted
/// separately. A case IEEE 754-2019 defines as invalid is a value, a NaN with
/// `invalid_operation` and without `not_computed`, in the `try_` form and in the
/// plain form (a signaling NaN operand for the functions that have no domain
/// error, a real domain case where there is one). A case the library cannot carry
/// out (a context beyond the kernels: `e_max` above 999,999) is `Err` in the
/// `try_` form and, in the plain form, a NaN with `not_computed` and without
/// `invalid_operation`. An ordinary case is unchanged: `Ok` in the `try_` form,
/// the same value in the plain form, neither flag.
fn elementary_outcome_table() -> Array[
  (
    String,
    (Decimal, Decimal, DecimalContext) -> Result[
      (Decimal, DecimalFlags),
      @def.ArithmeticError,
    ],
    (Decimal, Decimal, DecimalContext) -> (Decimal, DecimalFlags),
    String,
    String,
  ),
] {
  [
    (
      "acos",
      fn(x, _y, ctx) { x.try_acos_ctx(ctx) },
      fn(x, _y, ctx) { x.acos_ctx(ctx) },
      "0.5",
      "2",
    ),
    (
      "acosh",
      fn(x, _y, ctx) { x.try_acosh_ctx(ctx) },
      fn(x, _y, ctx) { x.acosh_ctx(ctx) },
      "2",
      "0.5",
    ),
    (
      "acospi",
      fn(x, _y, ctx) { x.try_acospi_ctx(ctx) },
      fn(x, _y, ctx) { x.acospi_ctx(ctx) },
      "0.5",
      "sNaN",
    ),
    (
      "asin",
      fn(x, _y, ctx) { x.try_asin_ctx(ctx) },
      fn(x, _y, ctx) { x.asin_ctx(ctx) },
      "0.5",
      "2",
    ),
    (
      "asinh",
      fn(x, _y, ctx) { x.try_asinh_ctx(ctx) },
      fn(x, _y, ctx) { x.asinh_ctx(ctx) },
      "0.5",
      "sNaN",
    ),
    (
      "asinpi",
      fn(x, _y, ctx) { x.try_asinpi_ctx(ctx) },
      fn(x, _y, ctx) { x.asinpi_ctx(ctx) },
      "0.5",
      "sNaN",
    ),
    (
      "atan",
      fn(x, _y, ctx) { x.try_atan_ctx(ctx) },
      fn(x, _y, ctx) { x.atan_ctx(ctx) },
      "0.5",
      "sNaN",
    ),
    (
      "atanh",
      fn(x, _y, ctx) { x.try_atanh_ctx(ctx) },
      fn(x, _y, ctx) { x.atanh_ctx(ctx) },
      "0.5",
      "2",
    ),
    (
      "atanpi",
      fn(x, _y, ctx) { x.try_atanpi_ctx(ctx) },
      fn(x, _y, ctx) { x.atanpi_ctx(ctx) },
      "0.5",
      "sNaN",
    ),
    (
      "cos",
      fn(x, _y, ctx) { x.try_cos_ctx(ctx) },
      fn(x, _y, ctx) { x.cos_ctx(ctx) },
      "0.5",
      "sNaN",
    ),
    (
      "cosh",
      fn(x, _y, ctx) { x.try_cosh_ctx(ctx) },
      fn(x, _y, ctx) { x.cosh_ctx(ctx) },
      "0.5",
      "sNaN",
    ),
    (
      "cospi",
      fn(x, _y, ctx) { x.try_cospi_ctx(ctx) },
      fn(x, _y, ctx) { x.cospi_ctx(ctx) },
      "0.3",
      "sNaN",
    ),
    (
      "exp10",
      fn(x, _y, ctx) { x.try_exp10_ctx(ctx) },
      fn(x, _y, ctx) { x.exp10_ctx(ctx) },
      "0.5",
      "sNaN",
    ),
    (
      "exp10m1",
      fn(x, _y, ctx) { x.try_exp10m1_ctx(ctx) },
      fn(x, _y, ctx) { x.exp10m1_ctx(ctx) },
      "0.5",
      "sNaN",
    ),
    (
      "exp2",
      fn(x, _y, ctx) { x.try_exp2_ctx(ctx) },
      fn(x, _y, ctx) { x.exp2_ctx(ctx) },
      "0.5",
      "sNaN",
    ),
    (
      "exp2m1",
      fn(x, _y, ctx) { x.try_exp2m1_ctx(ctx) },
      fn(x, _y, ctx) { x.exp2m1_ctx(ctx) },
      "0.5",
      "sNaN",
    ),
    (
      "exp",
      fn(x, _y, ctx) { x.try_exp_ctx(ctx) },
      fn(x, _y, ctx) { x.exp_ctx(ctx) },
      "0.5",
      "sNaN",
    ),
    (
      "expm1",
      fn(x, _y, ctx) { x.try_expm1_ctx(ctx) },
      fn(x, _y, ctx) { x.expm1_ctx(ctx) },
      "0.5",
      "sNaN",
    ),
    (
      "ln",
      fn(x, _y, ctx) { x.try_ln_ctx(ctx) },
      fn(x, _y, ctx) { x.ln_ctx(ctx) },
      "0.5",
      "-1",
    ),
    (
      "log10",
      fn(x, _y, ctx) { x.try_log10_ctx(ctx) },
      fn(x, _y, ctx) { x.log10_ctx(ctx) },
      "0.5",
      "-1",
    ),
    (
      "log10p1",
      fn(x, _y, ctx) { x.try_log10p1_ctx(ctx) },
      fn(x, _y, ctx) { x.log10p1_ctx(ctx) },
      "0.5",
      "-2",
    ),
    (
      "log1p",
      fn(x, _y, ctx) { x.try_log1p_ctx(ctx) },
      fn(x, _y, ctx) { x.log1p_ctx(ctx) },
      "0.5",
      "-2",
    ),
    (
      "log2",
      fn(x, _y, ctx) { x.try_log2_ctx(ctx) },
      fn(x, _y, ctx) { x.log2_ctx(ctx) },
      "0.5",
      "-1",
    ),
    (
      "log2p1",
      fn(x, _y, ctx) { x.try_log2p1_ctx(ctx) },
      fn(x, _y, ctx) { x.log2p1_ctx(ctx) },
      "0.5",
      "-2",
    ),
    (
      "rsqrt",
      fn(x, _y, ctx) { x.try_rsqrt_ctx(ctx) },
      fn(x, _y, ctx) { x.rsqrt_ctx(ctx) },
      "0.5",
      "-1",
    ),
    (
      "sin",
      fn(x, _y, ctx) { x.try_sin_ctx(ctx) },
      fn(x, _y, ctx) { x.sin_ctx(ctx) },
      "0.5",
      "sNaN",
    ),
    (
      "sinh",
      fn(x, _y, ctx) { x.try_sinh_ctx(ctx) },
      fn(x, _y, ctx) { x.sinh_ctx(ctx) },
      "0.5",
      "sNaN",
    ),
    (
      "sinpi",
      fn(x, _y, ctx) { x.try_sinpi_ctx(ctx) },
      fn(x, _y, ctx) { x.sinpi_ctx(ctx) },
      "0.3",
      "sNaN",
    ),
    (
      "tan",
      fn(x, _y, ctx) { x.try_tan_ctx(ctx) },
      fn(x, _y, ctx) { x.tan_ctx(ctx) },
      "0.5",
      "sNaN",
    ),
    (
      "tanh",
      fn(x, _y, ctx) { x.try_tanh_ctx(ctx) },
      fn(x, _y, ctx) { x.tanh_ctx(ctx) },
      "0.5",
      "sNaN",
    ),
    (
      "tanpi",
      fn(x, _y, ctx) { x.try_tanpi_ctx(ctx) },
      fn(x, _y, ctx) { x.tanpi_ctx(ctx) },
      "0.3",
      "sNaN",
    ),
    (
      "atan2",
      fn(x, y, ctx) { x.try_atan2_ctx(y, ctx) },
      fn(x, y, ctx) { x.atan2_ctx(y, ctx) },
      "2",
      "sNaN",
    ),
    (
      "atan2pi",
      fn(x, y, ctx) { x.try_atan2pi_ctx(y, ctx) },
      fn(x, y, ctx) { x.atan2pi_ctx(y, ctx) },
      "2",
      "sNaN",
    ),
    (
      "hypot",
      fn(x, y, ctx) { x.try_hypot_ctx(y, ctx) },
      fn(x, y, ctx) { x.hypot_ctx(y, ctx) },
      "2",
      "sNaN",
    ),
    (
      "pow",
      // a non-integral power: an integral one is not restricted by the context
      fn(x, _y, ctx) {
        x.try_pow_ctx(Decimal::from_string("2048.5").unwrap(), ctx)
      },
      fn(x, _y, ctx) { x.pow_ctx(Decimal::from_string("2048.5").unwrap(), ctx) },
      "4",
      "-8",
    ),
    (
      "powr",
      fn(x, _y, ctx) {
        x.try_powr_ctx(Decimal::from_string("2048.5").unwrap(), ctx)
      },
      fn(x, _y, ctx) {
        x.powr_ctx(Decimal::from_string("2048.5").unwrap(), ctx)
      },
      "4",
      "-1",
    ),
    (
      "compound",
      fn(x, _y, ctx) { x.try_compound_ctx(3, ctx) },
      fn(x, _y, ctx) { x.compound_ctx(3, ctx) },
      "2",
      "-2",
    ),
    (
      "pown",
      fn(x, _y, ctx) { x.try_pown_ctx(3, ctx) },
      fn(x, _y, ctx) { x.pown_ctx(3, ctx) },
      "2",
      "sNaN",
    ),
    (
      "rootn",
      fn(x, _y, ctx) { x.try_rootn_ctx(3, ctx) },
      fn(x, _y, ctx) { x.rootn_ctx(3, ctx) },
      "2",
      "sNaN",
    ),
  ]
}

///|
// oracle: A, S
// source: A for the kinds of outcome: a domain operand gives a NaN with invalid_operation and without not_computed (IEEE 754-2019 7.2, written as the table of operands), a restricted context gives an Err or a NaN with not_computed and without invalid_operation (the documented limit of DecimalContext, not a standard clause); S for the ordinary case, which only asserts no NaN, no flag, and that the plain and the try form agree
// shares: the 39 elementary functions of the table themselves (both forms), Decimal::from_string, Decimal::signaling_nan and DecimalContext::new
test "decimal elementary functions: domain, could-not-compute and ordinary outcomes" {
  let d = fn(s : String) { Decimal::from_string(s).unwrap() }
  let ctx = DecimalContext::decimal64()
  let restricted = DecimalContext::new(precision=34, e_max=1_000_000)
  let table = elementary_outcome_table()
  assert_eq(table.length(), 39)
  for row in table {
    let (name, try_form, plain, ordinary, domain) = row
    let operand = fn(text : String) {
      if text == "sNaN" {
        Decimal::signaling_nan()
      } else {
        d(text)
      }
    }
    // a domain case: a value with invalid_operation, never not_computed
    let (value, flags) = match try_form(operand(domain), d("0.5"), ctx) {
      Ok(result) => result
      Err(_) => abort(name + ": a domain case must not be an Err")
    }
    assert_true(value.is_nan(), msg=name + " domain value")
    assert_true(flags.invalid_operation(), msg=name + " domain invalid")
    assert_false(flags.not_computed(), msg=name + " domain not_computed")
    let (plain_value, plain_flags) = plain(operand(domain), d("0.5"), ctx)
    assert_true(plain_value.is_nan(), msg=name + " plain domain value")
    assert_true(
      plain_flags.invalid_operation(),
      msg=name + " plain domain invalid",
    )
    assert_false(
      plain_flags.not_computed(),
      msg=name + " plain domain not_computed",
    )
    // could not compute: Err in the try_ form, NaN with not_computed in the plain form.
    // `pown` has no such case: an integral power is exact whatever the context.
    if name != "pown" {
      match try_form(d(ordinary), d("0.5"), restricted) {
        Err(error) => {
          assert_true(error.is_certification_failure(), msg=name + " kind")
          // the error names the public operation the caller called
          match error.certification_failure_detail() {
            Some(detail) => assert_eq(detail.operation(), name)
            None => abort(name + ": a certification failure has a detail")
          }
        }
        Ok(_) => abort(name + ": a restricted context must be an Err")
      }
      let (limit_value, limit_flags) = plain(d(ordinary), d("0.5"), restricted)
      assert_true(limit_value.is_nan(), msg=name + " restricted value")
      assert_true(
        limit_flags.not_computed(),
        msg=name + " restricted not_computed",
      )
      assert_false(
        limit_flags.invalid_operation(),
        msg=name + " restricted invalid",
      )
    }
    // an ordinary case: unchanged, neither flag
    let (ok_value, ok_flags) = match try_form(d(ordinary), d("0.5"), ctx) {
      Ok(result) => result
      Err(_) => abort(name + ": an ordinary case must be Ok")
    }
    assert_false(ok_value.is_nan(), msg=name + " ordinary value")
    assert_false(
      ok_flags.invalid_operation() || ok_flags.not_computed(),
      msg=name + " ordinary flags",
    )
    let (plain_ok, plain_ok_flags) = plain(d(ordinary), d("0.5"), ctx)
    assert_true(plain_ok.identical(ok_value), msg=name + " plain = try")
    assert_true(
      plain_ok_flags == ok_flags,
      msg=name + " plain flags = try flags",
    )
  }
}

///|
/// The checked tier (`*_contextual`, `*_checked`) turns each kind of failure into
/// its own `Err`: `invalid_operation` is the domain error, `not_computed` the
/// certification failure, `division_by_zero` the division error; a clean result
/// is `Ok`.
test "decimal checked tier: the two kinds of Err stay apart" {
  let nan = Decimal::nan()
  match
    contextual_outcome("exp", nan, {
      ..DecimalFlags::new(),
      invalid_operation: true,
    }) {
    Err(error) => {
      assert_true(error.is_domain_error())
      assert_false(error.is_certification_failure())
    }
    Ok(_) => abort("invalid_operation must be an Err")
  }
  match contextual_outcome("exp", nan, not_computed_flags()) {
    Err(error) => {
      assert_true(error.is_certification_failure())
      assert_false(error.is_domain_error())
    }
    Ok(_) => abort("not_computed must be an Err")
  }
  match
    contextual_outcome("exp", nan, {
      ..DecimalFlags::new(),
      division_by_zero: true,
    }) {
    Err(error) => assert_true(error.is_division_by_zero())
    Ok(_) => abort("division_by_zero must be an Err")
  }
  assert_true(
    contextual_outcome("exp", Decimal::one(), DecimalFlags::new()) is Ok(_),
  )
  // through the public forms: a domain case and a plain addition that cannot be done
  let context = @lf_arith.ArithmeticContext::new(16)
  match Decimal::from_string("-1").unwrap().sqrt_contextual(context) {
    Err(error) => assert_true(error.is_domain_error())
    Ok(_) => abort("sqrt of a negative must be a domain error")
  }
  match Decimal::from_string("-1").unwrap().exp_contextual(context) {
    Ok(_) => ()
    Err(_) => abort("exp(-1) is an ordinary case")
  }
}
