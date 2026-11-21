///|
/// S4: the three outcomes of the plain forms of the elementary functions. All 38
/// plain `_ctx` forms go through `binary_defined_or_nan`; the table-free tests
/// below check that helper for each kind of `Err`, and `exp` end to end with a
/// failure forced through the refinement limit (the hook of #15).

///|
test "a certification failure is a NaN with not_computed and without invalid_operation" {
  let context = BinaryContext::binary64()
  let failure = binary_not_computed_error("exp")
  assert_true(failure.is_certification_failure())
  assert_false(failure.is_domain_error())
  let (value, flags) = binary_defined_or_nan(Err(failure), context)
  assert_true(value.is_nan())
  assert_true(flags.not_computed())
  assert_false(flags.invalid_operation())
  // an ordinary result is passed through
  let (one, one_flags) = binary_defined_or_nan(
    Ok((BinFloat::from_int(1), BinaryFlags::new())),
    context,
  )
  assert_false(one.is_nan())
  assert_true(one_flags == BinaryFlags::new())
}

///|
test "exp: a forced failure, a domain-free ordinary case and an invalid operand" {
  let hard = refinement_hard_input()
  let base = BinaryContext::new(precision=53)
  let limited = base.with_refinement_limit(Some(1))
  // could not compute: Err in the try_ form, NaN with not_computed in the plain form
  assert_true(refinement_failed(hard.try_exp_ctx(limited)))
  let (value, flags) = hard.exp_ctx(limited)
  assert_true(value.is_nan())
  assert_true(flags.not_computed())
  assert_false(flags.invalid_operation())
  // ordinary: Ok, the same value in the plain form, neither flag
  let one = BinFloat::from_int(1)
  let (ok, ok_flags) = one.try_exp_ctx(base).unwrap()
  let (plain, plain_flags) = one.exp_ctx(base)
  assert_true(plain == ok)
  assert_true(plain_flags == ok_flags)
  assert_false(ok_flags.not_computed() || ok_flags.invalid_operation())
  // an invalid operand (a signaling NaN): a value with invalid_operation
  let (nan, nan_flags) = BinFloat::signaling_nan().exp_ctx(base)
  assert_true(nan.is_nan())
  assert_true(nan_flags.invalid_operation())
  assert_false(nan_flags.not_computed())
}

///|
/// The domain cases of the plain forms are values with invalid_operation and
/// without not_computed (their try_ forms still return an `Err` for now).
test "plain elementary forms: a domain case is invalid_operation, not not_computed" {
  let base = BinaryContext::new(precision=53)
  let minus_one = BinFloat::from_int(-1)
  let two = BinFloat::from_int(2)
  for
    result in [
      minus_one.ln_ctx(base),
      minus_one.log2_ctx(base),
      minus_one.log10_ctx(base),
      two.asin_ctx(base),
      two.acos_ctx(base),
      minus_one.rsqrt_ctx(base),
    ] {
    let (value, flags) = result
    assert_true(value.is_nan())
    assert_true(flags.invalid_operation())
    assert_false(flags.not_computed())
  }
}

///|
test "checked tier: not_computed is the certification failure, invalid_operation the domain error" {
  let nan = BinFloat::nan()
  match binary_contextual_outcome(nan, binary_not_computed_flags()) {
    Err(error) => {
      assert_true(error.is_certification_failure())
      match error.certification_failure_detail() {
        Some(detail) => assert_eq(detail.operation(), "binary operation")
        None => abort("a certification failure has a detail")
      }
      assert_false(error.is_domain_error())
    }
    Ok(_) => abort("not_computed must be an Err")
  }
  match binary_contextual_outcome(nan, binary_invalid_flags()) {
    Err(error) => {
      assert_true(error.is_domain_error())
      assert_false(error.is_certification_failure())
    }
    Ok(_) => abort("invalid_operation must be an Err")
  }
  assert_true(binary_contextual_outcome(nan, BinaryFlags::new()) is Ok(_))
  match binary_checked_result((nan, binary_not_computed_flags()), "invalid") {
    Err(error) => {
      assert_true(error.is_certification_failure())
      // the detail names an operation, not the sentence of the invalid case
      match error.certification_failure_detail() {
        Some(detail) => assert_eq(detail.operation(), "binary operation")
        None => abort("a certification failure has a detail")
      }
    }
    Ok(_) => abort("not_computed must be an Err")
  }
  match binary_checked_result((nan, binary_invalid_flags()), "invalid") {
    Err(error) => assert_true(error.is_domain_error())
    Ok(_) => abort("invalid_operation must be an Err")
  }
}
