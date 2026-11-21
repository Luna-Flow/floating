///|
/// Oracle: level A, the outcomes (NaN, which flag, `Ok` or `Err`) are written out
/// from the clauses of IEEE 754-2019 9.2.1; the comparison of the plain form with
/// the `try_` form is level S and is not the only check of a value.
/// S4, power and root family: the three outcomes of `rootn`, `pow`, `powr`, `rsqrt`
/// and `compound`, asserted separately. A domain case is a value in the `try_` form
/// and in the plain form: a NaN with `invalid_operation` and without
/// `not_computed`. The failure to compute is not asserted here: no argument that
/// forces it through the refinement limit is known for these functions (it is for
/// `exp` and the logarithms), so that outcome is covered by the unit test of
/// `binary_defined_or_nan` and of the checked mappings. An ordinary case is
/// unchanged.
fn pow_family_table() -> Array[
  (
    String,
    (BinFloat, BinaryContext) -> Result[
      (BinFloat, BinaryFlags),
      @def.ArithmeticError,
    ],
    (BinFloat, BinaryContext) -> (BinFloat, BinaryFlags),
    BinFloat,
    BinFloat,
  ),
] {
  [
    (
      "rootn",
      fn(x : BinFloat, c : BinaryContext) { x.try_rootn_ctx(2, c) },
      fn(x : BinFloat, c : BinaryContext) { x.rootn_ctx(2, c) },
      // an even degree of a negative value
      BinFloat::from_int(-4),
      BinFloat::from_int(2),
    ),
    (
      "rsqrt",
      fn(x : BinFloat, c : BinaryContext) { x.try_rsqrt_ctx(c) },
      fn(x : BinFloat, c : BinaryContext) { x.rsqrt_ctx(c) },
      BinFloat::from_int(-4),
      BinFloat::from_int(2),
    ),
    (
      "compound",
      fn(x : BinFloat, c : BinaryContext) { x.try_compound_ctx(3, c) },
      fn(x : BinFloat, c : BinaryContext) { x.compound_ctx(3, c) },
      BinFloat::from_int(-2),
      BinFloat::from_int(1).scaleb_ctx(
        BinFloat::from_int(-1),
        BinaryContext::new(precision=53),
      ).0,
    ),
    (
      "pow",
      fn(x : BinFloat, c : BinaryContext) {
        x.try_pow_ctx(
          BinFloat::from_int(1).scaleb_ctx(BinFloat::from_int(-1), c).0,
          c,
        )
      },
      fn(x : BinFloat, c : BinaryContext) {
        x.pow_ctx(
          BinFloat::from_int(1).scaleb_ctx(BinFloat::from_int(-1), c).0,
          c,
        )
      },
      BinFloat::from_int(-4),
      BinFloat::from_int(3),
    ),
    (
      "powr",
      fn(x : BinFloat, c : BinaryContext) {
        x.try_powr_ctx(
          BinFloat::from_int(1).scaleb_ctx(BinFloat::from_int(-1), c).0,
          c,
        )
      },
      fn(x : BinFloat, c : BinaryContext) {
        x.powr_ctx(
          BinFloat::from_int(1).scaleb_ctx(BinFloat::from_int(-1), c).0,
          c,
        )
      },
      BinFloat::from_int(-4),
      BinFloat::from_int(3),
    ),
  ]
}

///|
test "power and root family: domain case and ordinary case" {
  let base = BinaryContext::new(precision=53)
  for row in pow_family_table() {
    let (name, try_form, plain, domain, ordinary) = row
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
