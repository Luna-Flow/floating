///|
// oracle: S
// source: design contract of the checked package: a pipeline that holds an error stays an error through exp10; no value is computed
// shares: BinaryChecked::err, exp10, result
test "checked elementary operations preserve certified failures" {
  let failed = BinaryChecked::err(
      @def.ArithmeticError::unsupported("test failure"),
    )
    .exp10()
    .result()
  match failed {
    Ok(_) => assert_true(false)
    Err(_) => assert_true(true)
  }
}

///|
// oracle: A
// source: written out from IEEE 754-2019 9.2.1: exp(0) = 1 and ln(1) = +0, so exp then ln of 0 is +0, compared by identity (sign, exponent, coefficient, precision)
// shares: assert_identical, Binary::zero
test "checked elementary operations compose successful values" {
  let result = BinaryChecked::from_int(0).exp().ln().result()
  match result {
    Ok(value) => assert_identical(value, @binary.Binary::zero())
    Err(_) => assert_true(false)
  }
}

///|
// oracle: A
// source: written out: hypot(3, 4) = 5 exactly (3^2 + 4^2 = 25), compared by identity
// shares: assert_identical, Binary::from_int
test "checked hypot preserves exact results" {
  let result = BinaryChecked::from_int(3)
    .hypot(BinaryChecked::from_int(4))
    .result()
  match result {
    Ok(value) => assert_identical(value, @binary.Binary::from_int(5))
    Err(_) => assert_true(false)
  }
}

///|
// oracle: A
// source: written out: the result of ln_ctx has the precision of the context it is rounded in (24), whatever the precision of the operand (53)
// shares: nothing
test "checked context methods preserve target precision" {
  let context = @binary.BinaryContext::new(precision=24)
  let result = BinaryChecked::from_int(2, precision=53).ln_ctx(context)
  assert_true(result.is_ok())
  assert_false(result.is_err())
  match result.result() {
    Ok(value) => assert_eq(value.precision(), 24)
    Err(_) => assert_true(false)
  }
}

///|
// oracle: S
// source: design contract of the checked package: an error operand makes add_ctx an error; no value is computed
// shares: BinaryChecked::err, add_ctx
test "checked context arithmetic short-circuits errors" {
  let context = @binary.BinaryContext::binary64()
  let failed = BinaryChecked::err(@def.ArithmeticError::unsupported("sentinel")).add_ctx(
    BinaryChecked::from_int(1),
    context,
  )
  assert_true(failed.is_err())
}

///|
// oracle: A
// source: written out: the precisions 0, -1 and binary_precision_max + 1 are outside the documented range 1..=binary_precision_max and give an error, binary_precision_max itself is accepted
// shares: binary_precision_max (the limit itself, read from the binary package)
test "constructors return Err for a precision outside 1..=binary_precision_max" {
  let max = @binary.binary_precision_max
  assert_true(BinaryChecked::from_int(3, precision=0).is_err())
  assert_true(BinaryChecked::from_int(3, precision=max + 1).is_err())
  assert_true(BinaryChecked::from_int(3, precision=max).is_ok())
  assert_true(BinaryChecked::from_double(1.5, precision=-1).is_err())
  assert_true(BinaryChecked::from_float(1.5, precision=0).is_err())
  assert_true(
    BinaryChecked::from_coefficient(@binary.BinCoeff::one(), precision=max + 1).is_err(),
  )
}

///|
/// Follow-up of S4: the errors of the checked tier name the operation, so that in a
/// chain of `BinaryChecked` operations the message says which step failed. The
/// expected texts and kinds are written out (oracle level A).
test "checked tier errors name the operation" {
  // a domain case: the domain error of `ln`
  match BinaryChecked::from_int(-4).ln().result() {
    Err(error) => {
      assert_true(error.is_domain_error())
      assert_eq(error.message, "ln: invalid operation")
    }
    Ok(_) => abort("ln(-4) must be an error")
  }
  // a pole: the division error of `ln`
  match BinaryChecked::from_int(0).ln().result() {
    Err(error) => {
      assert_true(error.is_division_by_zero())
      assert_eq(error.message, "ln: division by zero")
    }
    Ok(_) => abort("ln(0) must be an error")
  }
  // the step that failed in a chain is the one named
  match BinaryChecked::from_int(3).sqrt().asin().result() {
    Err(error) => {
      assert_true(error.is_domain_error())
      assert_eq(error.message, "asin: invalid operation")
    }
    Ok(_) => abort("asin of a value above 1 must be an error")
  }
  // could not compute: the certification failure carries the operation's name
  let wide = @binary.BinaryContext::new(precision=330)
  let one = @binary.Binary::from_int(1, precision=330)
  let midpoint = one.add_ctx(
      one.scaleb_ctx(@binary.Binary::from_int(-53), wide).0,
      wide,
    ).0
  let hard = midpoint.try_ln_ctx(wide).unwrap().0
  let limited = @binary.BinaryContext::new(precision=53).with_refinement_limit(
    Some(1),
  )
  match BinaryChecked::ok(hard).exp_ctx(limited).result() {
    Err(error) => {
      assert_true(error.is_certification_failure())
      assert_false(error.is_domain_error())
      match error.certification_failure_detail() {
        Some(detail) => assert_eq(detail.operation(), "exp")
        None => abort("a certification failure has a detail")
      }
    }
    Ok(_) => abort("the forced failure must be an error")
  }
}

///|
// oracle: A
// source: expected values written out from IEEE 754-2019 7.3 (a finite non-zero dividend over zero is a division by zero) and 7.2 (0/0 is invalid, here a domain error); the one-set-of-exits contract of the checked tiers (`is_ok`, `is_err`, `error`, `result`)
// shares: nothing
test "error is the failure of a pipeline and None for a success" {
  let good = BinaryChecked::from_int(6).div(BinaryChecked::from_int(3))
  assert_true(good.is_ok() && good.error() is None)
  assert_true(!good.is_err())
  let by_zero = BinaryChecked::from_int(1).div(BinaryChecked::from_int(0))
  assert_true(by_zero.is_err())
  match by_zero.error() {
    Some(error) => assert_true(error.is_division_by_zero())
    None => fail("division by zero must carry its error")
  }
  // The error of the left operand wins, and `error` agrees with `result`.
  let first = BinaryChecked::err(@def.ArithmeticError::unsupported("first"))
  let both = first.add(by_zero)
  match (both.error(), both.result()) {
    (Some(e), Err(r)) => assert_true(e == r)
    _ => fail("error and result must agree")
  }
  assert_true(both.error().unwrap().is_unsupported())
  assert_true(both.error().unwrap() == first.error().unwrap())
}
