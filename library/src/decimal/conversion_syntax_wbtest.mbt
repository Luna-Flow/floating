///|
/// `from_string_ctx` reports invalid text with only `invalid_operation` set, so
/// `has_error` has to treat that flag as an error; otherwise a failed parse
/// looks like a successful result.
// oracle: A
// source: written out from the General Decimal Arithmetic specification (to-number: a string that is not a numeric string gives NaN and the Conversion_syntax condition, which is Invalid_operation): the five texts abc, 1.2.3, empty, 1e, +-1 are not numeric strings and 1.25 is
// shares: Decimal::from_string_ctx and DecimalFlags::has_error (the code under test)
test "DecimalFlags::has_error reports a failed parse" {
  let context = DecimalContext::decimal64()
  for text in ["abc", "1.2.3", "", "1e", "+-1"] {
    let (_, flags) = Decimal::from_string_ctx(text, context)
    assert_true(flags.invalid_operation)
    assert_true(flags.has_error())
  }
  let (_, clean) = Decimal::from_string_ctx("1.25", context)
  assert_false(clean.invalid_operation)
  assert_true(clean.has_error() == false)
}
