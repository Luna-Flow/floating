///|
/// An operand is read by the library as written: its exponent field is not
/// rewritten (the saturation at +-2,000,000,000 that this frontend used to apply is
/// gone), and the conversion overflows or underflows by the widest range of a GDA
/// context (dtfile.html: an operand is converted with the to-number conversion,
/// with sufficient precision). Oracle (level A): decNumber 3.68 (DECSUBSET=1, built
/// outside the repository, run on the same rows: `0.9e9999999999 + 1` is
/// `Infinity`, `99e-9999999999 + 1` is `1.0000000` with Rounded, and
/// `99e-9999999999 * 1` is `0E-1000000006` with Clamped), and the verdict of each
/// passing row is judged as text.
// oracle: A
// source: decNumber 3.68 (DECSUBSET=1, built outside the repository) on the same rows, as stated in the doc comment of
//   the block: 0.9e9999999999 + 1 is Infinity, 99e-9999999999 + 1 is 1.0000000 Rounded, 99e-9999999999 * 1 is
//   0E-1000000006 Clamped; CPython decimal (libmpdec 4.0.0) gives the same three result texts in this review (it
//   reports more flags, since it raises them for the conversion of the operand, which the rows do not carry)
// shares: the decimal reader of the operands, the rounding and the scientific-notation printer of the interpreter (the
//   results are compared with the row as text), and the context it builds from the directives; all of them are
//   the code under test
test "gda interpreter reads an exponent field beyond 2e9 as written" {
  let source =
    #|precision: 8
    #|rounding: half_even
    #|maxexponent: 999999999
    #|minexponent: -999999999
    #|extended: 1
    #|op1 add 0.9e9999999999 1 -> Infinity
    #|op2 add 99e-9999999999 1 -> 1.0000000 Rounded
    #|op3 multiply 99e-9999999999 1 -> 0E-1000000006 Clamped
    #|
  let document = @gda_expr.parse_dectest("operands.decTest", source).unwrap()
  let summary = @gda_expr.execute_documents([document])
  assert_eq(summary.executable_cases(), 3)
  assert_eq(summary.passed_cases(), 3)
  for result in summary.results() {
    // the verdict kind of a decimal result is text: the to-scientific-string of
    // the result against the result token, no number read from the token
    assert_eq(result.message(), "text")
  }
}

///|
// oracle: A
// source: classification written out from the row syntax: a result token '?' means the value is not compared (kind
//   value-not-checked) and a row with a result token is compared as text; q1 raises Invalid_operation in both
//   libmpdec and the interpreter (123.456 at exponent -999999999 needs more than 9 digits), q2 is 1 + 1 = 2
// shares: the decimal reader of the operands, the rounding and the scientific-notation printer of the interpreter (the
//   results are compared with the row as text), and the context it builds from the directives; all of them are
//   the code under test
test "gda interpreter reports the rows whose value is not checked" {
  let source =
    #|extended: 0
    #|precision: 9
    #|rounding: half_up
    #|q1 quantize 123.456 1e-999999999 -> ? Invalid_operation
    #|q2 add 1 1 -> 2
    #|
  let document = @gda_expr.parse_dectest("unchecked.decTest", source).unwrap()
  let summary = @gda_expr.execute_documents([document])
  assert_eq(summary.passed_cases(), 2)
  let kinds = summary.results().map(fn(result) { result.message() })
  assert_eq(kinds, ["value-not-checked", "text"])
}

///|
test "gda interpreter judges a recorded deviation against the held value" {
  let source =
    #|precision: 9
    #|rounding: half_up
    #|d1 add 1 1 -> 3
    #|d2 add 2 2 -> 5
    #|d3 add 3 3 -> 6
    #|
  let document = @gda_expr.parse_dectest("deviation.decTest", source).unwrap()
  let summary = @gda_expr.execute_documents(
    [document],
    options=@gda_expr.RunOptions::new(deviations=[
      // the corpus value 3 is recorded and the held value is the correct 2
      ("deviation.decTest:d1", "3", "2", None),
      // the record does not match the row: the row fails and says why
      ("deviation.decTest:d2", "4", "4", None),
    ]),
  )
  let kinds = summary.results().map(fn(result) { result.message() })
  assert_eq(summary.passed_cases(), 2)
  assert_eq(summary.failed_cases(), 1)
  assert_eq(kinds[0], "deviation")
  assert_true(kinds[1].contains("records the corpus value 4"))
  assert_eq(kinds[2], "text")
}

///|
// oracle: A
// source: expected verdicts written by hand from the definition of the column: a row recorded with held flags is judged by them and not by the conditions of the row (the corpus gives `d1 add 1 1 -> 2 Rounded`; 1 + 1 at precision 9 raises no flag, so the row fails without a record, passes with the held flags "" (none) and fails with the held flags "Rounded")
// shares: nothing
test "gda interpreter judges a recorded deviation against the held flags" {
  let source =
    #|precision: 9
    #|rounding: half_up
    #|d1 add 1 1 -> 2 Rounded
    #|d2 add 1 1 -> 2 Rounded
    #|d3 add 1 1 -> 2 Rounded
    #|
  let document = @gda_expr.parse_dectest("flags.decTest", source).unwrap()
  let summary = @gda_expr.execute_documents(
    [document],
    options=@gda_expr.RunOptions::new(deviations=[
      ("flags.decTest:d1", "2", "2", Some("")),
      ("flags.decTest:d2", "2", "2", Some("Rounded")),
    ]),
  )
  let kinds = summary.results().map(fn(result) { result.message() })
  assert_eq(summary.passed_cases(), 1)
  assert_eq(summary.failed_cases(), 2)
  assert_eq(kinds[0], "deviation")
  assert_true(kinds[1].contains("status flags mismatch: expected Rounded"))
  assert_true(kinds[2].contains("status flags mismatch: expected Rounded"))
}
