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
