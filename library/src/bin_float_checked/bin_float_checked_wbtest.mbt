///|
test "checked elementary operations preserve certified failures" {
  let failed = BinFloatResult::err(
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
test "checked elementary operations compose successful values" {
  let result = BinFloatResult::from_int(0).exp().ln().result()
  match result {
    Ok(value) => assert_eq(value, @bin_float.BinFloat::zero())
    Err(_) => assert_true(false)
  }
}

///|
test "checked hypot preserves exact results" {
  let result = BinFloatResult::from_int(3)
    .hypot(BinFloatResult::from_int(4))
    .result()
  match result {
    Ok(value) => assert_eq(value, @bin_float.BinFloat::from_int(5))
    Err(_) => assert_true(false)
  }
}

///|
test "checked context methods preserve target precision" {
  let context = @bin_float.BinaryContext::unbounded(24)
  let result = BinFloatResult::from_int(2, precision=53).ln_ctx(context)
  assert_true(result.is_ok())
  assert_false(result.is_err())
  match result.result() {
    Ok(value) => assert_eq(value.precision(), 24)
    Err(_) => assert_true(false)
  }
}

///|
test "checked context arithmetic short-circuits errors" {
  let context = @bin_float.BinaryContext::binary64()
  let failed = BinFloatResult::err(
    @def.ArithmeticError::unsupported("sentinel"),
  ).add_ctx(BinFloatResult::from_int(1), context)
  assert_true(failed.is_err())
}
