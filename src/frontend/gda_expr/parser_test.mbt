///|
test "gda parser snapshots directives and lowers calls" {
  let source =
    #|precision: 9
    #|rounding: half_up
    #|t1 add '1.20' 2 -> '3.20' Inexact -- comment
    #|precision: 16
    #|t2 multiply 3 4 -> 12
    #|
  let document = @gda_expr.parse_dectest("sample.decTest", source).unwrap()
  assert_eq(document.case_count(), 2)
  let cases = document.cases()
  assert_eq(cases[0].context().precision(), 9)
  assert_eq(cases[0].context().rounding(), "half_up")
  assert_true(cases[0].operands() == ["1.20", "2"])
  assert_eq(cases[1].context().precision(), 16)
}

///|
test "gda parser reports malformed quotes with source" {
  let result = @gda_expr.parse_dectest("bad.decTest", "x add '1 2 -> 3\n")
  match result {
    Err([diagnostic]) => {
      assert_eq(diagnostic.span().source(), "bad.decTest")
      assert_eq(diagnostic.span().line(), 1)
    }
    _ => fail("expected one parse diagnostic")
  }
}
