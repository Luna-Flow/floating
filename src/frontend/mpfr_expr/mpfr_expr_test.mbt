///|
test "MPFR sqrt parser and executor retain hexadecimal precision semantics" {
  let source =
    #|# Pinned MPFR sqrt data rows
    #|53 53 n 0x0p0 0x0p0
    #|53 53 n 0x10000000000000p-1074 0x10000000000000p-563
    #|53 53 n 0x10BC83C8308CB2p-1074 0x105D327678185Dp-563
    #|
  let document = parse_sqrt_data("inline.sqrt", source).unwrap()
  assert_eq(document.source(), "inline.sqrt")
  assert_eq(document.case_count(), 3)
  let summary = execute_sqrt_data(document)
  assert_eq(summary.total_cases(), 3)
  assert_eq(summary.passed_cases(), 3)
  assert_eq(summary.failed_cases(), 0)
}

///|
test "MPFR sqrt parser rejects incomplete data_check rows" {
  match parse_sqrt_data("bad.sqrt", "53 53 n 0x0p0\n") {
    Err([diagnostic]) => {
      assert_eq(diagnostic.source(), "bad.sqrt")
      assert_eq(diagnostic.line(), 1)
      assert_eq(
        diagnostic.message(),
        "MPFR data_check row must contain five fields",
      )
    }
    _ => fail("expected one MPFR parse diagnostic")
  }
}

///|
test "MPFR pow parser executes all supported rounding modes" {
  let source =
    #|# precision rounding input_coefficient_hex input_exponent2 input_negative exponent expected_coefficient_hex expected_exponent2 expected_negative inexact
    #|11 n 3 -1 0 3 6c0 -9 0 0
    #|24 z 7ff -10 0 -3 80300c -26 0 1
    #|53 d 1fffffffffffff -52 1 15 1ffffffffffff2 -38 1 1
    #|113 a 10000000000000000000000000001 -112 0 -7 1fffffffffffffffffffffffffff3 -113 0 1
  let document = parse_pow_data("inline.pow", source).unwrap()
  assert_eq(document.source(), "inline.pow")
  assert_eq(document.case_count(), 4)
  let summary = execute_pow_data(document)
  for result in summary.results() {
    assert_true(result.passed(), msg=result.message())
  }
  assert_eq(summary.total_cases(), 4)
  assert_eq(summary.passed_cases(), 4)
  assert_eq(summary.failed_cases(), 0)
}
