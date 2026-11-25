// Evidence tools: the `source:` lines of this file that say "per the evidence header" name runs of CPython 3.13.16 decimal (libmpdec 4.0.0), executed on 2026-11-25 by the author of the declarations over the rows quoted in each line; rerun the quoted values with the same tool to check them.

///|
// oracle: A
// source: counts and fields written out from the source: two rows, the first with the directives precision 9 and
//   rounding half_up, the second with precision 16, and the operands 1.20 and 2 with quotes removed
// shares: nothing (the parser under test reads the text)
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
// oracle: A
// source: written out: the text x add '1 2 -> 3 has an unterminated quote on line 1 of bad.decTest, one diagnostic
// shares: nothing
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
// oracle: A
// source: a doubled quote inside a quoted token stands for one quote; basx558 and basx560 are rows of
//   testdata/decimal_gda/official/base.decTest, the others are written out; the eight rows were run with CPython
//   decimal (libmpdec 4.0.0) per the evidence header (the seven toSci rows give NaN Conversion_syntax, '1' + '2' is 3)
//   and agree
// shares: the interpreter's decimal reader for the executed rows (the code under test)
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
// oracle: A
// source: written out: '1'' leaves the quote open (the doubled quote is an escape), so the row is a parse error
// shares: nothing
test "gda parser rejects a quoted token ended by a doubled quote" {
  let result = @gda_expr.parse_dectest("bad.decTest", "x toSci '1'' -> NaN\n")
  assert_true(result is Err(_))
}
