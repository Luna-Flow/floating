// Evidence tools: the `source:` lines of this file that say "per the evidence header" name runs of CPython 3.13.16 fractions, struct and integers, executed on 2026-11-25 by the author of the declarations over the rows quoted in each line; rerun the quoted values with the same tool to check them.

///|
// oracle: A
// source: four binary16 multiplications written out as bit patterns: 1 * 1 = 1; min normal * 0x3BFF = 2^-14 (1 -
//   2^-11) is the tie between two subnormals and rounds to even, 0x0400, flags underflow and inexact (03; exact
//   product shown with Python Fractions); inf * 0 = quiet NaN with invalid (10); -inf * -1 = +inf
// shares: the hexadecimal reader and the rounding of the library behind the executor (the code under test); the vector
//   columns are read as bit patterns
test "TestFloat parser and executor preserve IEEE values and flags" {
  let spec = @testfloat_expr.TestFloatSpec::parse("f16_mul", "rnear_even").unwrap()
  let source =
    #|# Berkeley TestFloat vector subset
    #|3C00 3C00 3C00 00
    #|0400 3BFF 0400 03
    #|7C00 0000 7E00 10
    #|FC00 BC00 7C00 00
    #|
  let document = @testfloat_expr.parse_testfloat(
    "inline.testfloat", source, spec,
  ).unwrap()
  assert_eq(document.case_count(), 4)
  let summary = @testfloat_expr.execute_document(document)
  assert_eq(summary.total_cases(), 4)
  assert_eq(summary.selected_cases(), 4)
  assert_eq(summary.passed_cases(), 4)
  assert_eq(summary.failed_cases(), 0)
}

///|
// oracle: A
// source: bit patterns checked with Python struct per the evidence header: 1 + 2^-52 narrows to 1 with inexact (01), 2^1000
//   overflows to +inf with overflow and inexact (05), a signaling NaN is quieted with invalid (10), and binary16
//   0x3E00 is 1.5 = 0x3FF8000000000000 exactly
// shares: the hexadecimal reader and the rounding of the library behind the executor (the code under test); the vector
//   columns are read as bit patterns
test "TestFloat format conversions read the operand in the source format and the result in the destination" {
  // f64_to_f32: 1.0 is exact; 1 + 2^-52 rounds to 1 (inexact); 2^1000 overflows;
  // a signaling NaN is quieted (invalid). The result column is binary32.
  let spec = @testfloat_expr.TestFloatSpec::parse("f64_to_f32", "rnear_even").unwrap()
  assert_eq(
    spec.operation(),
    @testfloat_expr.TestFloatOperation::ConvertFormat(
      @binary.BinaryInterchangeFormat::Binary32,
    ),
  )
  let source =
    #|3FF0000000000000 3F800000 00
    #|3FF0000000000001 3F800000 01
    #|7E70000000000000 7F800000 05
    #|7FF0000000000001 7FC00000 10
    #|
  let document = @testfloat_expr.parse_testfloat(
    "inline.testfloat", source, spec,
  ).unwrap()
  assert_eq(document.case_count(), 4)
  let summary = @testfloat_expr.execute_document(document)
  assert_eq(summary.passed_cases(), 4)
  assert_eq(summary.failed_cases(), 0)
  // a wrong destination value is reported
  let wrong = @testfloat_expr.parse_testfloat(
    "wrong.testfloat", "3FF0000000000000 3F800001 00\n", spec,
  ).unwrap()
  assert_eq(@testfloat_expr.execute_document(wrong).failed_cases(), 1)
  // widening: f16 to f64, exact
  let widening = @testfloat_expr.TestFloatSpec::parse(
    "f16_to_f64", "rnear_even",
  ).unwrap()
  let wide = @testfloat_expr.parse_testfloat(
    "wide.testfloat", "3E00 3FF8000000000000 00\n", widening,
  ).unwrap()
  assert_eq(@testfloat_expr.execute_document(wide).passed_cases(), 1)
}

///|
// oracle: A
// source: written out: a row with three fields where binary16 addition needs four (two operands, result, flags) is one
//   diagnostic with the message and line 1
// shares: nothing
test "TestFloat parser reports malformed vector rows with source positions" {
  let spec = @testfloat_expr.TestFloatSpec::parse("f16_add", "rnear_even").unwrap()
  match
    @testfloat_expr.parse_testfloat("bad.testfloat", "3C00 3C00 4000\n", spec) {
    Err([diagnostic]) => {
      assert_eq(diagnostic.source(), "bad.testfloat")
      assert_eq(diagnostic.line(), 1)
      assert_eq(diagnostic.message(), "unexpected TestFloat field count")
    }
    _ => fail("expected one TestFloat parse diagnostic")
  }
}

///|
// oracle: A
// source: written out: shard 1 of 2 selects 2 of the 4 rows; the rows are correct sums written as bit patterns (1+1 =
//   2, 2^-24 + 2^-24 = 2^-23, inf + -inf = NaN with invalid, -0 + +0 = +0)
// shares: the hexadecimal reader and the rounding of the library behind the executor (the code under test); the vector
//   columns are read as bit patterns
test "TestFloat execution shards select a deterministic partition" {
  let spec = @testfloat_expr.TestFloatSpec::parse("f16_add", "rnear_even").unwrap()
  let source =
    #|3C00 3C00 4000 00
    #|0001 0001 0002 00
    #|7C00 FC00 7E00 10
    #|8000 0000 0000 00
    #|
  let document = @testfloat_expr.parse_testfloat(
    "shards.testfloat", source, spec,
  ).unwrap()
  let summary = @testfloat_expr.execute_document(
    document,
    options=@testfloat_expr.RunOptions::new(shard_count=2, shard_index=1),
  )
  assert_eq(summary.total_cases(), 4)
  assert_eq(summary.selected_cases(), 2)
  assert_eq(summary.passed_cases(), 2)
  assert_eq(summary.failed_cases(), 0)
}

///|
// oracle: S
// source: the arm names `mul`, `add` and `eq` are written out in the test from the operation named in the TestFloat function (`f16_mul`, `f16_add`, `f16_eq`); the check is that the summary agrees with that name, a consistency check of the recorded set against the specification, not an independent value
// shares: TestFloatSpec::parse and execute_document (the code under test)
test "the summary names the operation arms that ran" {
  // The set is per process (tests share it), so only membership is asserted here; the
  // command-line summary of a fresh process holds exactly the arm of its function.
  let run = fn(name : String, row : String) {
    let spec = @testfloat_expr.TestFloatSpec::parse(name, "rnear_even").unwrap()
    let document = @testfloat_expr.parse_testfloat(
      "inline.testfloat", row, spec,
    ).unwrap()
    @testfloat_expr.execute_document(document).arms()
  }
  assert_true(run("f16_mul", "3C00 3C00 3C00 00\n").contains("mul"))
  assert_true(run("f16_add", "3C00 3C00 4000 00\n").contains("add"))
  assert_true(run("f16_eq", "3C00 3C00 1 00\n").contains("eq"))
}
