///|
/// `from_string_ctx` reports invalid text with only `conversion_syntax` set, so
/// `has_error` has to treat that flag as an error; otherwise a failed parse
/// looks like a successful result.
test "DecimalFlags::has_error reports a failed parse" {
  let context = DecimalContext::decimal64()
  for text in ["abc", "1.2.3", "", "1e", "+-1"] {
    let (_, flags) = Decimal::from_string_ctx(text, context)
    assert_true(flags.conversion_syntax)
    assert_true(flags.has_error())
  }
  let (_, clean) = Decimal::from_string_ctx("1.25", context)
  assert_true(clean.conversion_syntax == false)
  assert_true(clean.has_error() == false)
}
