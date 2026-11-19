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

///|
test "gda parser reads a doubled quote inside a quoted token (issue #63)" {
  let source =
    #|precision: 9
    #|rounding: half_up
    #|maxExponent: 999
    #|minExponent: -999
    #|basx558 toSci '1E''1' -> NaN Conversion_syntax
    #|basx560 toSci "1E""""" -> NaN Conversion_syntax
    #|qq001 toSci '1''2' -> NaN Conversion_syntax
    #|qq002 toSci "'1'" -> NaN Conversion_syntax
    #|qq003 toSci '''' -> NaN Conversion_syntax
    #|qq004 toSci '' -> NaN Conversion_syntax
    #|qq005 toSci '1''' -> NaN Conversion_syntax
    #|qq006 add '1' "2" -> '3'
    #|
  let document = @gda_expr.parse_dectest("inline.decTest", source).unwrap()
  let cases = document.cases()
  assert_eq(cases.length(), 8)
  assert_true(cases[0].operands() == ["1E'1"])
  assert_true(cases[1].operands() == ["1E\"\""])
  assert_true(cases[2].operands() == ["1'2"])
  assert_true(cases[3].operands() == ["'1'"])
  assert_true(cases[4].operands() == ["'"])
  assert_true(cases[5].operands() == [""])
  assert_true(cases[6].operands() == ["1'"])
  assert_true(cases[7].operands() == ["1", "2"])
  assert_eq(cases[7].expected(), "3")
  let summary = @gda_expr.execute_documents([document])
  assert_eq(summary.passed_cases(), 8)
}

///|
test "gda parser rejects a quoted token ended by a doubled quote" {
  let result = @gda_expr.parse_dectest("bad.decTest", "x toSci '1'' -> NaN\n")
  assert_true(result is Err(_))
}
