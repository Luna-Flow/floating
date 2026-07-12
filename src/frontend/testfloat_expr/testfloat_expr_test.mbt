///|
test "TestFloat parser and executor preserve IEEE values and flags" {
  let spec = TestFloatSpec::parse("f16_mul", "rnear_even").unwrap()
  let source =
    #|# Berkeley TestFloat vector subset
    #|3C00 3C00 3C00 00
    #|0400 3BFF 0400 03
    #|7C00 0000 7E00 10
    #|FC00 BC00 7C00 00
    #|
  let document = parse_testfloat("inline.testfloat", source, spec).unwrap()
  assert_eq(document.case_count(), 4)
  let summary = execute_document(document)
  assert_eq(summary.total_cases(), 4)
  assert_eq(summary.selected_cases(), 4)
  assert_eq(summary.passed_cases(), 4)
  assert_eq(summary.failed_cases(), 0)
}

///|
test "TestFloat parser reports malformed vector rows with source positions" {
  let spec = TestFloatSpec::parse("f16_add", "rnear_even").unwrap()
  match parse_testfloat("bad.testfloat", "3C00 3C00 4000\n", spec) {
    Err([diagnostic]) => {
      assert_eq(diagnostic.source(), "bad.testfloat")
      assert_eq(diagnostic.line(), 1)
      assert_eq(diagnostic.message(), "unexpected TestFloat field count")
    }
    _ => fail("expected one TestFloat parse diagnostic")
  }
}

///|
test "TestFloat execution shards select a deterministic partition" {
  let spec = TestFloatSpec::parse("f16_add", "rnear_even").unwrap()
  let source =
    #|3C00 3C00 4000 00
    #|0001 0001 0002 00
    #|7C00 FC00 7E00 10
    #|8000 0000 0000 00
    #|
  let document = parse_testfloat("shards.testfloat", source, spec).unwrap()
  let summary = execute_document(
    document,
    options=RunOptions::new(shard_count=2, shard_index=1),
  )
  assert_eq(summary.total_cases(), 4)
  assert_eq(summary.selected_cases(), 2)
  assert_eq(summary.passed_cases(), 2)
  assert_eq(summary.failed_cases(), 0)
}
