///|
// oracle: A
// source: three data_check rows: 0 is a line of the pinned MPFR corpus; sqrt(2^-1022) = 2^-511 exactly; the third
//   result 0x105D327678185Dp-563 is the 53 bit nearest to sqrt(0x10BC83C8308CB2p-1074), shown by exact squares
//   of the neighbours at half a unit (Python Fractions, in this review)
// shares: the hexadecimal and decimal readers and the operations of the library that the executor runs on each row
//   (the code under test); the expected value is read from the row
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
// oracle: A
// source: written out: a row with four fields instead of five is one diagnostic with the message and the line number 1
// shares: nothing
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
// oracle: A
// source: the three rows are lines of the pinned MPFR corpus and were recomputed with Python Fractions in this review:
//   (3/2)^3 = 27/8 at 11 bits to nearest, (2047/1024)^-3 at 24 bits toward zero, and -(0x1fffffffffffff p-52)^15
//   at 53 bits toward negative infinity
// shares: the hexadecimal and decimal readers and the operations of the library that the executor runs on each row
//   (the code under test); the expected value is read from the row
test "MPFR pow parser executes the IEEE 754-2019 rounding modes" {
  let source =
    #|# precision rounding input_coefficient_hex input_exponent2 input_negative exponent expected_coefficient_hex expected_exponent2 expected_negative inexact
    #|11 n 3 -1 0 3 6c0 -9 0 0
    #|24 z 7ff -10 0 -3 80300c -26 0 1
    #|53 d 1fffffffffffff -52 1 15 1ffffffffffff2 -38 1 1
  let document = @mpfr_expr.parse_pow_data("inline.pow", source).unwrap()
  assert_eq(document.source(), "inline.pow")
  assert_eq(document.case_count(), 3)
  let summary = @mpfr_expr.execute_pow_data(document)
  for result in summary.results() {
    assert_true(result.passed(), msg=result.message())
  }
  assert_eq(summary.total_cases(), 3)
  assert_eq(summary.passed_cases(), 3)
  assert_eq(summary.failed_cases(), 0)
}

///|
// oracle: A
// source: exp(0) = 1, tanpi(1/4) = 1 and hypot(3,4) = 5 are exact identities; MPFR 4.2.2 (installed here) returns the
//   same three values in this review
// shares: the hexadecimal and decimal readers and the operations of the library that the executor runs on each row
//   (the code under test); the expected value is read from the row
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
// oracle: A
// source: written out: pow, hypot and atan2 take two operands, so a row with '-' for the second operand is one
//   diagnostic with this message
// shares: nothing
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
// oracle: A
// source: sin(-0) and atan2(-0, 1) are -0 (MPFR 4.2.2, run in this review); a row that expects +0 must fail and one
//   that expects -0 must pass, so the verdicts are false, true, false, true
// shares: the hexadecimal and decimal readers and the operations of the library that the executor runs on each row
//   (the code under test); the expected value is read from the row
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
// oracle: A
// source: three rows are lines of the pinned MPFR corpus (0.1 to nearest and toward zero at 24 bits, and the overflow
//   of 1e323228497); 2049 at 11 bits is the tie between 2048 and 2050 (to nearest even 2048 = 0x1p11, ties away
//   2050 = 0x401p1) and -0.0 reads as -0, recomputed with Python Fractions
// shares: the hexadecimal and decimal readers and the operations of the library that the executor runs on each row
//   (the code under test); the expected value is read from the row
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
// oracle: A
// source: written out: a row with six fields, an unknown rounding letter q, a non hexadecimal digit and a flag 2 each
//   give one diagnostic
// shares: nothing
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
// oracle: A
// source: 2.5 at one digit is 2 to nearest even, 3 ties away, 2 toward zero; 0.125 at two digits is 12 to nearest even
//   and 13 upward (CPython decimal quantize, in this review); 125 at three digits is exact; the exponent column
//   is the scientific exponent, as in the rows of the pinned mpfr-4.2.2-decimal-output.txt; 0x1999999999999a
//   p-56 is the double 0.1 and its shortest form has one digit, 0.5 has one digit
// shares: the hexadecimal and decimal readers and the operations of the library that the executor runs on each row
//   (the code under test); the expected value is read from the row
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
// oracle: A
// source: written out: a row with a missing field, a shortest row without a count, an unknown kind and a non numeric
//   digit count each give one diagnostic
// shares: nothing
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

///|
// oracle: A
// source: ln(1 + 2^-1199) at 24 bits to nearest is 2^-1199 to within the precision, inexact (the sum 1 + 2^-1199 read
//   at 512 bits would be 1 and ln 1 = 0); the operand has 1200 bits
// shares: the hexadecimal and decimal readers and the operations of the library that the executor runs on each row
//   (the code under test); the expected value is read from the row
test "MPFR elementary rows read an operand longer than the result precision exactly" {
  // ln(1 + 2^-1199) at 24 bits, to nearest: 2^-1199 (inexact). The operand has
  // 1200 bits; read at 512 bits it would be 1 and ln 1 = 0.
  let operand = StringBuilder()
  operand.write_string("0x8")
  for _ in 0..<298 {
    operand.write_char('0')
  }
  operand.write_string("1p-1199")
  let source = "# mpfr-elementary-v1\nln 24 n " +
    operand.to_string() +
    " - 0 0x1p-1199 1 0 0\n"
  let document = @mpfr_expr.parse_elementary_data("long-operand", source).unwrap()
  let summary = @mpfr_expr.execute_elementary_data(document)
  for result in summary.results() {
    assert_true(result.passed(), msg=result.message())
  }
  assert_eq(summary.passed_cases(), 1)
}
