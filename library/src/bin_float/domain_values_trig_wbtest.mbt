///|
/// S4, trigonometric and inverse family: the three outcomes of `asin`, `acos`,
/// `acosh`, `atanh`, `asinpi`, `acospi` and of `sin`, `cos`, `tan`, `sinpi`, `cospi`,
/// `tanpi`, asserted separately. A domain case (an argument outside the real domain,
/// or an infinity for the trigonometric functions) is a value in the `try_` form and
/// in the plain form: a NaN with `invalid_operation` and without `not_computed`. A
/// result that cannot be certified within the refinement limit is `Err` in the `try_`
/// form and a NaN with `not_computed` and without `invalid_operation` in the plain
/// form: no argument that forces this failure through the refinement limit is known
/// for these functions (it is for `exp` and the logarithms), so that outcome is covered
/// by the unit test of `binary_defined_or_nan` and of the checked mappings only.
/// An ordinary case is unchanged.
fn trig_table() -> Array[
  (
    String,
    (BinFloat, BinaryContext) -> (BinFloat, BinaryFlags),
    (BinFloat, BinaryContext) -> Result[
      (BinFloat, BinaryFlags),
      @def.ArithmeticError,
    ],
    (BinFloat, BinaryContext) -> (BinFloat, BinaryFlags),
    String,
    BinFloat,
  ),
] {
  [
    (
      "asin",
      fn(x, c) { x.sin_ctx(c) },
      fn(x, c) { x.try_asin_ctx(c) },
      fn(x, c) { x.asin_ctx(c) },
      "1",
      BinFloat::from_int(2),
    ),
    (
      "acos",
      fn(x, c) { x.cos_ctx(c) },
      fn(x, c) { x.try_acos_ctx(c) },
      fn(x, c) { x.acos_ctx(c) },
      "1",
      BinFloat::from_int(2),
    ),
    (
      "acosh",
      fn(x, c) { x.cosh_ctx(c) },
      fn(x, c) { x.try_acosh_ctx(c) },
      fn(x, c) { x.acosh_ctx(c) },
      "1",
      BinFloat::from_int(1).scaleb_ctx(
        BinFloat::from_int(-1),
        BinaryContext::new(precision=53),
      ).0,
    ),
    (
      "atanh",
      fn(x, c) { x.tanh_ctx(c) },
      fn(x, c) { x.try_atanh_ctx(c) },
      fn(x, c) { x.atanh_ctx(c) },
      "1",
      BinFloat::from_int(2),
    ),
    (
      "asinpi",
      fn(x, c) { x.sinpi_ctx(c) },
      fn(x, c) { x.try_asinpi_ctx(c) },
      fn(x, c) { x.asinpi_ctx(c) },
      "q",
      BinFloat::from_int(2),
    ),
    (
      "acospi",
      fn(x, c) { x.cospi_ctx(c) },
      fn(x, c) { x.try_acospi_ctx(c) },
      fn(x, c) { x.acospi_ctx(c) },
      "q",
      BinFloat::from_int(2),
    ),
    (
      "sin",
      fn(x, c) { x.asin_ctx(c) },
      fn(x, c) { x.try_sin_ctx(c) },
      fn(x, c) { x.sin_ctx(c) },
      "h",
      BinFloat::inf(Sign::Positive),
    ),
    (
      "cos",
      fn(x, c) { x.acos_ctx(c) },
      fn(x, c) { x.try_cos_ctx(c) },
      fn(x, c) { x.cos_ctx(c) },
      "h",
      BinFloat::inf(Sign::Positive),
    ),
    (
      "tan",
      fn(x, c) { x.atan_ctx(c) },
      fn(x, c) { x.try_tan_ctx(c) },
      fn(x, c) { x.tan_ctx(c) },
      "1",
      BinFloat::inf(Sign::Positive),
    ),
    (
      "sinpi",
      fn(x, c) { x.asinpi_ctx(c) },
      fn(x, c) { x.try_sinpi_ctx(c) },
      fn(x, c) { x.sinpi_ctx(c) },
      "q",
      BinFloat::inf(Sign::Positive),
    ),
    (
      "cospi",
      fn(x, c) { x.acospi_ctx(c) },
      fn(x, c) { x.try_cospi_ctx(c) },
      fn(x, c) { x.cospi_ctx(c) },
      "q",
      BinFloat::inf(Sign::Positive),
    ),
    (
      "tanpi",
      fn(x, c) { x.atanpi_ctx(c) },
      fn(x, c) { x.try_tanpi_ctx(c) },
      fn(x, c) { x.tanpi_ctx(c) },
      "q",
      BinFloat::inf(Sign::Positive),
    ),
  ]
}

///|
test "trigonometric family: domain case, could-not-compute case and ordinary case" {
  let base = BinaryContext::new(precision=53)
  for row in trig_table() {
    let (name, _inverse, try_form, plain, _kind, domain) = row
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
    // an ordinary case: unchanged
    let ordinary = if name == "acosh" {
      BinFloat::from_int(2)
    } else {
      BinFloat::from_int(1).scaleb_ctx(BinFloat::from_int(-1), base).0
    }
    let (ok, ok_flags) = match try_form(ordinary, base) {
      Ok(result) => result
      Err(_) => abort(name + ": an ordinary case must be Ok")
    }
    assert_false(ok.is_nan(), msg=name + " ordinary value")
    assert_false(
      ok_flags.invalid_operation() || ok_flags.not_computed(),
      msg=name + " ordinary flags",
    )
    let (plain_ok, plain_ok_flags) = plain(ordinary, base)
    assert_true(plain_ok.identical(ok), msg=name + " plain = try")
    assert_true(
      plain_ok_flags == ok_flags,
      msg=name + " plain flags = try flags",
    )
  }
}
