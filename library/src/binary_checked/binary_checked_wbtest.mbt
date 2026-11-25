///|
// oracle: S
// source: design contract of the checked package: a pipeline that holds an error stays an error through exp10; no value is computed
// shares: BinaryChecked::err, exp10 and result (all of them the code under test; no expected value)
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
// shares: BinaryChecked::from_int (builds the operand), exp, ln and result (the operations under test), Binary::zero and assert_identical (the expected value and the comparison)
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
// shares: BinaryChecked::from_int (builds the operands), hypot and result (the operation under test), Binary::from_int and assert_identical (the expected value and the comparison)
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
// oracle: A, S
// source: written out: the result of ln_ctx has the precision of the context it is rounded in (24), whatever the precision of the operand (53); that the result precision equals the context precision is a design property of the checked tier (the result is rounded in the context), written out here, not a table from outside
// shares: BinaryChecked::from_int (builds the operand), BinaryChecked::ln_ctx and Binary::precision (the code under test and the accessor that reads the result)
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
// shares: BinaryChecked::err, from_int, add_ctx and is_err (all of them the code under test; no expected value)
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
// shares: binary_precision_max (the limit itself, read from the binary package) and the constructors under test
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
// shares: BinaryChecked::from_int (builds the operands), div and add (the operations that raise the errors), result and error (the accessors compared with each other in the last part)
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

///|
// oracle: A
// source: written out from the contract documented on `bin_result_checked_flags` (S4): a result whose flags say `not_computed` (the library could not compute it) is a certification failure that names the operation, not a domain error and not a division by zero; the flags come from the plain `Binary::exp_ctx` of a case that cannot be certified with a refinement limit of 1 (a quiet NaN with `not_computed`); the other two mappings of the function (division by zero, invalid operation) are written out in the same block for contrast
// shares: Binary::exp_ctx and Binary::try_ln_ctx build the not_computed result (input only); the mapping function bin_result_checked_flags is the code under test
test "bin_result_checked_flags maps not_computed to a certification failure" {
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
  let computed = hard.exp_ctx(limited)
  assert_true(computed.1.not_computed())
  match bin_result_checked_flags("exp", computed) {
    Err(error) => {
      assert_true(error.is_certification_failure())
      assert_false(error.is_domain_error())
      assert_false(error.is_division_by_zero())
      match error.certification_failure_detail() {
        Some(detail) => assert_eq(detail.operation(), "exp")
        None => abort("a certification failure has a detail")
      }
    }
    Ok(_) => abort("a result that was not computed must be an error")
  }
  // the other mappings, for contrast
  match
    bin_result_checked_flags(
      "div",
      @binary.Binary::from_int(1).div_ctx(
        @binary.Binary::zero(),
        @binary.BinaryContext::binary64(),
      ),
    ) {
    Err(error) => assert_true(error.is_division_by_zero())
    Ok(_) => abort("1 / 0 is a division by zero (IEEE 754-2019 7.3)")
  }
  match
    bin_result_checked_flags(
      "sqrt",
      @binary.Binary::from_int(-4).sqrt_ctx(@binary.BinaryContext::binary64()),
    ) {
    Err(error) => assert_true(error.is_domain_error())
    Ok(_) => abort("sqrt(-4) is invalid (IEEE 754-2019 7.2 g)")
  }
}
