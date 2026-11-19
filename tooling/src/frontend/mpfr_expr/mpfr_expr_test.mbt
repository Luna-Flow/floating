///|
test "MPFR sqrt parser and executor retain hexadecimal precision semantics" {
  let source =
    #|# Pinned MPFR sqrt data rows
    #|53 53 n 0x0p0 0x0p0
    #|53 53 n 0x10000000000000p-1074 0x10000000000000p-563
    #|53 53 n 0x10BC83C8308CB2p-1074 0x105D327678185Dp-563
    #|
  let document = @mpfr_expr.parse_sqrt_data("inline.sqrt", source).unwrap()
  assert_eq(document.source(), "inline.sqrt")
  assert_eq(document.case_count(), 3)
  let summary = @mpfr_expr.execute_sqrt_data(document)
  assert_eq(summary.total_cases(), 3)
  assert_eq(summary.passed_cases(), 3)
  assert_eq(summary.failed_cases(), 0)
}

///|
test "MPFR sqrt parser rejects incomplete data_check rows" {
  match @mpfr_expr.parse_sqrt_data("bad.sqrt", "53 53 n 0x0p0\n") {
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
  let document = @mpfr_expr.parse_pow_data("inline.pow", source).unwrap()
  assert_eq(document.source(), "inline.pow")
  assert_eq(document.case_count(), 4)
  let summary = @mpfr_expr.execute_pow_data(document)
  for result in summary.results() {
    assert_true(result.passed(), msg=result.message())
  }
  assert_eq(summary.total_cases(), 4)
  assert_eq(summary.passed_cases(), 4)
  assert_eq(summary.failed_cases(), 0)
}

///|
test "MPFR elementary parser executes certified exact identities" {
  let source =
    #|# mpfr-elementary-v1
    #|exp 24 n 0x0p0 - 0 0x1p0 0 0 0
    #|tanpi 24 na 0x1p-2 - 0 0x1p0 0 0 0
    #|hypot 53 d 0x3p0 0x4p0 0 0x5p0 0 0 0
  let document = @mpfr_expr.parse_elementary_data("inline.elementary", source).unwrap()
  assert_eq(document.source(), "inline.elementary")
  assert_eq(document.case_count(), 3)
  let summary = @mpfr_expr.execute_elementary_data(document)
  for result in summary.results() {
    assert_true(result.passed(), msg=result.message())
  }
  assert_eq(summary.passed_cases(), 3)
}

///|
test "MPFR elementary parser rejects a missing second operand" {
  for
    row in [
      "pow 53 n 0x2p0 - 0 0x1p0 0 0 0", "hypot 53 n 0x3p0 - 0 0x5p0 0 0 0", "atan2 53 n 0x1p0 - 0 0x0p0 0 0 0",
    ] {
    match @mpfr_expr.parse_elementary_data("missing", row) {
      Err([diagnostic]) =>
        assert_eq(diagnostic.message(), "invalid MPFR elementary field")
      _ => fail("expected one diagnostic for " + row)
    }
  }
}

///|
test "MPFR elementary executor compares the sign of zero results" {
  let source =
    #|sin 53 n -0x0p0 - 0 0x0p0 0 0 0
    #|sin 53 n -0x0p0 - 0 -0x0p0 0 0 0
    #|atan2 53 n -0x0p0 0x1p0 0 0x0p0 0 0 0
    #|atan2 53 n -0x0p0 0x1p0 0 -0x0p0 0 0 0
  let summary = @mpfr_expr.execute_elementary_data(
    @mpfr_expr.parse_elementary_data("zeros", source).unwrap(),
  )
  let passed = summary.results().map(result => result.passed())
  assert_eq(passed, [false, true, false, true])
}

///|
test "MPFR strtofr parser executes literals, halfway points and the range limits" {
  let source =
    #|# mpfr-strtofr-v1
    #|# precision rounding input expected inexact overflow underflow
    #|24 n 0.1 0xcccccdp-27 1 0 0
    #|24 z 0.1 0xccccccp-27 1 0 0
    #|11 n 2049 0x1p11 1 0 0
    #|11 na 2049 0x401p1 1 0 0
    #|53 u -0.0 -0x0p0 0 0 0
    #|24 n 1e323228497 inf 1 1 0
  let document = @mpfr_expr.parse_strtofr_data("inline.strtofr", source).unwrap()
  assert_eq(document.source(), "inline.strtofr")
  assert_eq(document.case_count(), 6)
  let summary = @mpfr_expr.execute_strtofr_data(document)
  for result in summary.results() {
    assert_true(result.passed(), msg=result.message())
  }
  assert_eq(summary.passed_cases(), 6)
}

///|
test "MPFR strtofr parser rejects malformed rows" {
  for
    row in [
      "24 n 0.1 0x1p0 1 0", "24 q 0.1 0x1p0 1 0 0", "24 n 0.1 0xzp0 1 0 0", "24 n 0.1 0x1p0 2 0 0",
    ] {
    match @mpfr_expr.parse_strtofr_data("bad", row) {
      Err([_]) => ()
      _ => fail("expected one diagnostic for " + row)
    }
  }
}

///|
test "MPFR decimal output parser executes fixed digits, ties and shortest forms" {
  let source =
    #|# mpfr-decimal-output-v1
    #|fixed 1 53 n 0x5p-1 2 0 1
    #|fixed 1 53 na 0x5p-1 3 0 1
    #|fixed 1 53 z 0x5p-1 2 0 1
    #|fixed 2 53 n 0x1p-3 12 -1 1
    #|fixed 2 53 u 0x1p-3 13 -1 1
    #|fixed 3 53 n 0x7dp0 125 2 0
    #|shortest 53 0x1999999999999ap-56 1
    #|shortest 24 0x1p-1 1
  let document = @mpfr_expr.parse_decimal_output_data("inline.output", source).unwrap()
  assert_eq(document.source(), "inline.output")
  assert_eq(document.case_count(), 8)
  let summary = @mpfr_expr.execute_decimal_output_data(document)
  for result in summary.results() {
    assert_true(result.passed(), msg=result.message())
  }
}

///|
test "MPFR decimal output parser rejects malformed rows" {
  for
    row in [
      "fixed 1 53 n 0x5p-1 2 0", "shortest 53 0x1p0", "other 1 2 3 4", "fixed x 53 n 0x5p-1 2 0 0",
    ] {
    match @mpfr_expr.parse_decimal_output_data("bad", row) {
      Err([_]) => ()
      _ => fail("expected one diagnostic for " + row)
    }
  }
}
