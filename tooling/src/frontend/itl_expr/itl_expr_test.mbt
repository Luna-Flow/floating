///|
// oracle: A
// source: the intersection row is the line of testdata/interval/smoke.itl; the convexHull row is the hull of [1,3] and
//   [2,4], [1,4], with decoration trv (written out)
// shares: Binary::from_hex_ctx and from_string_ctx (the executor reads the operand and the expected bounds with them)
//   and the interval operation under test
test "ITL parser and executor run minimal set cases" {
  let source =
    #|testcase minimal {
    #|  intersection [1.0,3.0] [2.0,4.0] = [2.0,3.0];
    #|  convexHull [1.0,3.0]_trv [2.0,4.0]_trv = [1.0,4.0]_trv;
    #|}
  let cases = @itl_expr.parse_itl(source).unwrap()
  assert_eq(cases.length(), 2)
  let summary = @itl_expr.summarize_results(
    cases.map(fn(case) { @itl_expr.execute_case(case) }),
  )
  assert_eq(summary.executable_cases(), 2)
  assert_eq(summary.passed_cases(), 2)
  assert_true(summary.success())
}

///|
// oracle: A
// source: IEEE 1788-2015 decorations: the sum of two bounded common intervals is com, so the expected def is wrong and
//   the case must fail (a verdict written out, with the word expected in the message)
// shares: Binary::from_hex_ctx and from_string_ctx (the executor reads the operand and the expected bounds with them)
//   and the interval operation under test
test "ITL decorated expectations reject a wrong decoration" {
  let source =
    #|testcase decorated_mismatch {
    #|  add [1.0,2.0]_com [3.0,4.0]_com = [4.0,6.0]_def;
    #|}
  let cases = @itl_expr.parse_itl(source).unwrap()
  assert_eq(cases.length(), 1)
  let result = @itl_expr.execute_case(cases[0])
  assert_false(result.passed())
  assert_true(result.message().contains("expected"))
}

///|
// oracle: A
// source: verdicts written out: the four operations (nums2interval, rootn, rsqrt and a made-up name) are not in the
//   executor's table of supported operations, so every case is unsupported and none is a diagnostic (a property
//   of the harness, no numeric value is involved)
// shares: nothing (the counts are compared with literals)
test "ITL unknown operations are unsupported whatever their operands" {
  let source =
    #|testcase unknown {
    #|  nums2interval 1.0 2.0 = [1.0,2.0];
    #|  rootn [1.0,8.0] 3 = [1.0,2.0];
    #|  rsqrt [1.0,4.0] = [0.5,1.0];
    #|  frobnicate 1.0 [1.0,2.0] = true;
    #|}
  let cases = @itl_expr.parse_itl(source).unwrap()
  assert_eq(cases.length(), 4)
  let summary = @itl_expr.summarize_results(
    cases.map(fn(case) { @itl_expr.execute_case(case) }),
  )
  assert_eq(summary.unsupported_cases(), 4)
  assert_eq(summary.diagnostic_cases(), 0)
  assert_true(summary.success())
}

///|
// oracle: A
// source: the add row is a line of libieeep1788_tests_elem.itl and the sub row is [5,6] - [1,2] = [5-2,6-1] = [3,5] by
//   hand; the claim is that two statements with comments are two cases
// shares: Binary::from_hex_ctx and from_string_ctx (the executor reads the operand and the expected bounds with them)
//   and the interval operation under test
test "ITL trailing line comments do not merge statements" {
  let source =
    #|testcase comments {
    #|  add [1.0,2.0] [3.0,4.0] = [4.0,6.0]; // first
    #|  sub [5.0,6.0] [1.0,2.0] = [3.0,5.0]; // second
    #|}
  let cases = @itl_expr.parse_itl(source).unwrap()
  assert_eq(cases.length(), 2)
  assert_eq(cases[0].expected(), "[4.0,6.0]")
  assert_eq(cases[1].operation(), "sub")
  let summary = @itl_expr.summarize_results(
    cases.map(fn(case) { @itl_expr.execute_case(case) }),
  )
  assert_eq(summary.passed_cases(), 2)
}

///|
// oracle: A
// source: 0.1 and 0.2 are the binary64 numbers 0x1.999999999999ap-4 and 0x1.999999999999ap-3 (Python float.hex in this
//   review); the singleton [17.1,17.1] is a point by definition; the cancelPlus row is a line of
//   libieeep1788_tests_cancel.itl
// shares: Binary::from_hex_ctx and from_string_ctx (the executor reads the operand and the expected bounds with them)
//   and the interval operation under test
test "ITL bounds are floating constants of the target format" {
  // ITF1788 passes `[l,u]` to the inf-sup constructor of the target type as
  // two floating constants, so a decimal bound is the nearest binary64 number.
  let source =
    #|testcase constants {
    #|  isSingleton [17.1,17.1] = true;
    #|  inf [0.1,0.2] = 0x1.999999999999Ap-4;
    #|  sup [0.1,0.2] = 0x1.999999999999Ap-3;
    #|  cancelPlus [-5.1,-0.0] [0.0,5.0] = [-0X1.999999999998P-4,0.0];
    #|}
  let cases = @itl_expr.parse_itl(source).unwrap()
  assert_eq(cases.length(), 4)
  for case in cases {
    let result = @itl_expr.execute_case(case)
    assert_true(result.passed(), msg=case.id() + ": " + result.message())
  }
}

///|
// oracle: A
// source: exact arithmetic in this review (Python Fractions): the 130 digit constant is 1 + 2^-53 + 1e-130, above the
//   tie 1 + 2^-53 between 1 and 1 + 2^-52, so the nearest 53 bit number is 1 + 2^-52 = 0x1.0000000000001p0
//   (CPython float.hex agrees); the former two step reading gave 1
// shares: Binary::from_string_ctx (the reader whose rounding the block checks)
test "ITL reads a decimal constant once: 1 + 2^-53 + 1e-130 is above the tie (double rounding)" {
  // 1 + 2^-53 is the tie between 1 and 1 + 2^-52 at 53 bits, and the 1e-130
  // puts the constant just above it, so the nearest number is 1 + 2^-52. The
  // former reader rounded the decimal to 2*53+16 digits first, which dropped
  // the 1e-130, and then to 53 bits: the tie went to even, 1. Now the library
  // reads the constant once: 0x1.0000000000001p0 (was 0x1p0).
  let digits = "1.0000000000000001110223024625156540423631668090820312500000000000000000000000000000000000000000000000000000000000000000000000000001"
  let source = "testcase double_rounding {\n  inf [\{digits},2] = 0x1.0000000000001p0;\n}\n"
  let cases = @itl_expr.parse_itl(source).unwrap()
  let result = @itl_expr.execute_case(cases[0])
  assert_true(result.passed(), msg=result.message())
}

///|
// oracle: A
// source: written out: the malformed literal 1.2.3 is not a number, so the case fails and the message names it
// shares: nothing
test "ITL names the literal the library rejects" {
  let source = "testcase bad {\n  inf [1.2.3,4] = 1.0;\n}\n"
  let cases = @itl_expr.parse_itl(source).unwrap()
  let result = @itl_expr.execute_case(cases[0])
  assert_false(result.passed())
  assert_true(result.message().contains("1.2.3"), msg=result.message())
}

///|
// oracle: A
// source: exact arithmetic in this review (Python Fractions, directed rounding to 113 bits): 1 + 2^-100 is exact at
//   113 bits and encloses to [1, 1+2^-52] at 53; the bound 0.1 at 113 bits is
//   0x1.999999999999999999999999999ap-4; (1+2^-52)^2 = 1 + 2^-51 + 2^-104 is exact; adding 2^-200 gives the 113
//   bit enclosure [1 + 2^-51 + 2^-104, 1 + 2^-51 + 2^-104 + 2^-112]; the midpoint of [1, 1 + 2^-100] is 1 +
//   2^-101
// shares: Binary::from_hex_ctx and from_string_ctx (the executor reads the operand and the expected bounds with them)
//   and the interval operation under test
test "ITL results are rounded at the requested precision (issue #62)" {
  let source =
    #|testcase precision {
    #|  add [0x1p0,0x1p0] [0x1p-100,0x1p-100] = [0x1.0000000000000000000000001p0,0x1.0000000000000000000000001p0];
    #|  add [0x1p0,0x1p0] [0x1p-100,0x1p-100] = [0x1p0,0x1.0000000000001p0];
    #|  sup [0.1,0.1] = 0x1.999999999999999999999999999ap-4;
    #|  sqr [0x1.0000000000001p0,0x1.0000000000001p0] = [0x1.00000000000020000000000001p0,0x1.00000000000020000000000001p0];
    #|  pown [0x1.0000000000001p0,0x1.0000000000001p0] 2 = [0x1.00000000000020000000000001p0,0x1.00000000000020000000000001p0];
    #|  fma [0x1.0000000000001p0,0x1.0000000000001p0] [0x1.0000000000001p0,0x1.0000000000001p0] [0x1p-200,0x1p-200] = [0x1.00000000000020000000000001p0,0x1.0000000000002000000000000101p0];
    #|  mid [0x1p0,0x1.0000000000000000000000001p0] = 0x1.00000000000000000000000008p0;
    #|}
  let cases = @itl_expr.parse_itl(source).unwrap()
  let wide = @itl_expr.execute_case(cases[0], precision=113)
  assert_true(wide.passed(), msg=wide.message())
  // At 53 bits the exact sum 1 + 2^-100 is enclosed by [1, 1 + 2^-52].
  let narrow = @itl_expr.execute_case(cases[1])
  assert_true(narrow.passed(), msg=narrow.message())
  assert_false(@itl_expr.execute_case(cases[1], precision=113).passed())
  // Reading at 113 bits is unchanged; the results below were rounded to
  // binary64 before the fix.
  assert_true(@itl_expr.execute_case(cases[2], precision=113).passed())
  for case in cases[3:] {
    let result = @itl_expr.execute_case(case, precision=113)
    assert_true(result.passed(), msg=case.id() + ": " + result.message())
  }
}

///|
// oracle: A
// source: five rows (ceil, floor twice, sign twice) are lines of libieeep1788_tests_elem.itl; the three others (trunc,
//   roundTiesToEven, roundTiesToAway) are written from the same decoration rule and have neighbours in the
//   corpus: trunc [1.1,1.9]_com = [1,1]_com, roundTiesToEven [-1.6,-1.5]_com = [-2,-2]_dac and roundTiesToEven
//   [-1.6,-1.4]_com = [-2,-1]_def
// shares: Binary::from_hex_ctx and from_string_ctx (the executor reads the operand and the expected bounds with them)
//   and the interval operation under test
test "ITL integer functions of IEEE 1788-2015 Table 9.1 with their decorations" {
  let source =
    #|testcase integer_functions {
    #|  ceil [1.1,2.0]_com = [2.0,2.0]_dac;
    #|  floor [1.1,2.0]_com = [1.0,2.0]_def;
    #|  floor [-1.2,-1.1]_com = [-2.0,-2.0]_com;
    #|  sign [0.0,0.0]_dac = [0.0,0.0]_dac;
    #|  sign [-1.0,2.0]_com = [-1.0,1.0]_def;
    #|  trunc [-0.5,0.5]_com = [0.0,0.0]_com;
    #|  roundTiesToEven [0.5,1.0]_com = [0.0,1.0]_def;
    #|  roundTiesToAway [0.5,0.75]_com = [1.0,1.0]_dac;
    #|}
  let cases = @itl_expr.parse_itl(source).unwrap()
  for case in cases {
    let result = @itl_expr.execute_case(case)
    assert_true(result.passed(), msg=case.id() + ": " + result.message())
  }
}

///|
// oracle: A
// source: the first six rows are lines of libieeep1788_tests_rev.itl and libieeep1788_tests_mul_rev.itl; the last case
//   changes the second output of the first mulRevToPair row to [empty], which is wrong because the true second
//   part is [0x1.999999999999Ap-3, infinity]; verdict written out
// shares: Binary::from_hex_ctx and from_string_ctx (the executor reads the operand and the expected bounds with them)
//   and the interval operation under test
test "ITL reverse multiplication: one-output, ternary and two-output forms" {
  let source =
    #|testcase reverse_multiplication {
    #|  mulRev [-2.0, 1.1] [-2.1, -0.4] = [entire];
    #|  mulRevTen [-2.0, 1.1] [-2.1, -0.4] [-2.1, -0.4] = [-2.1, -0.4];
    #|  mulRev [-2.0, -0.1]_dac [-2.1, -0.4]_dac = [0X1.999999999999AP-3, 0X1.5P+4]_trv;
    #|  mulRevToPair [-2.0, 1.1] [-2.1, -0.4] = [-infinity, -0X1.745D1745D1745P-2] [0X1.999999999999AP-3, infinity];
    #|  mulRevToPair [-2.0, -0.1]_com [-2.1, -0.4]_com = [0X1.999999999999AP-3, 0X1.5P+4]_com [empty];
    #|  mulRevToPair [-2.0, 1.1]_com [-2.1, -0.4]_dac = [-infinity, -0X1.745D1745D1745P-2]_trv [0X1.999999999999AP-3, infinity]_trv;
    #|}
  let cases = @itl_expr.parse_itl(source).unwrap()
  for case in cases {
    let result = @itl_expr.execute_case(case)
    assert_true(result.passed(), msg=case.id() + ": " + result.message())
  }

  // a wrong second output is reported
  let wrong = @itl_expr.parse_itl(
    (
      #|testcase wrong {
      #|  mulRevToPair [-2.0, 1.1] [-2.1, -0.4] = [-infinity, -0X1.745D1745D1745P-2] [empty];
      #|}
    ),
  ).unwrap()
  assert_false(@itl_expr.execute_case(wrong[0]).passed())
}

///|
// oracle: A
// source: written from the definitions of IEEE 1788-2015 10.5.4 by hand: sqrRev [1,4] = [-2,2]; with prior [0,1.2]
//   gives [1,1.2]; absRev [1,3] = [-3,3] decorated trv; absRev with prior [-2,0.5] gives [-2,-1]; pownRev
//   [16,81] 4 = [-3,3] and with prior [-1,2.5] gives [2,2.5]; x^-2 in [1,inf) means |x| <= 1, x /= 0; with prior
//   [0,0] it is empty; the coshRev row is a line of libieeep1788_tests_rev.itl
// shares: Binary::from_hex_ctx and from_string_ctx (the executor reads the operand and the expected bounds with them)
//   and the interval operation under test
test "ITL algebraic reverse functions: bare, with a prior, and decorated" {
  let source =
    #|testcase algebraic_reverse {
    #|  sqrRev [1.0,4.0] = [-2.0,2.0];
    #|  sqrRevBin [1.0,4.0] [0.0,1.2] = [1.0,1.2];
    #|  absRev [1.0,3.0]_com = [-3.0,3.0]_trv;
    #|  absRevBin [1.0,3.0] [-2.0,0.5] = [-2.0,-1.0];
    #|  coshRev [1.0,1.0] = [0.0,0.0];
    #|  pownRev [16.0,81.0] 4 = [-3.0,3.0];
    #|  pownRevBin [16.0,81.0] [-1.0,2.5] 4 = [2.0,2.5];
    #|  pownRev [1.0,infinity] -2 = [-1.0,1.0];
    #|  pownRevBin [1.0,infinity] [0.0,0.0] -2 = [empty];
    #|}
  let cases = @itl_expr.parse_itl(source).unwrap()
  for case in cases {
    let result = @itl_expr.execute_case(case)
    assert_true(result.passed(), msg=case.id() + ": " + result.message())
  }
}

///|
// oracle: A
// source: six rows are lines of libieeep1788_tests_rev.itl; the cosRevBin row is written by hand (cos x = 1 with x in
//   [-1,1] means x = 0, decorated trv)
// shares: Binary::from_hex_ctx and from_string_ctx (the executor reads the operand and the expected bounds with them)
//   and the interval operation under test
test "ITL trigonometric reverse functions: bare, with a prior, and decorated" {
  let source =
    #|testcase trigonometric_reverse {
    #|  sinRev [0.0,0.0] = [entire];
    #|  sinRevBin [0.0,0.0] [-1.0,1.0] = [0.0,0.0];
    #|  sinRevBin [-0.0,-0.0] [3.0,3.5] = [0x1.921fb54442d18p+1,0x1.921fb54442d19p+1];
    #|  cosRevBin [1.0,1.0]_com [-1.0,1.0]_com = [0.0,0.0]_trv;
    #|  cosRev [-2.0,-1.1] = [empty];
    #|  tanRev [0.0,0.0] = [entire];
    #|  tanRevBin [0.0,0.0] [-1.5708,1.5708] = [0.0,0.0];
    #|}
  let cases = @itl_expr.parse_itl(source).unwrap()
  for case in cases {
    let result = @itl_expr.execute_case(case)
    assert_true(result.passed(), msg=case.id() + ": " + result.message())
  }
}

///|
// oracle: A
// source: tools/itl_pow_reverse_oracle.py hull(), an oracle that shares no code with interval (260 digit enclosures,
//   exact classification of the ends), was run on the five rows in this review and returns exactly the written
//   results; three rows are also lines of the pinned pow_rev.itl
// shares: Binary::from_hex_ctx and from_string_ctx (the executor reads the operand and the expected bounds with them)
//   and the interval operation under test
test "ITL powRev1: exact ends, a rounded end and the zero part" {
  let source =
    #|testcase pow_reverse_1 {
    #|  powRev1 [2.0,2.0] [4.0,4.0] [entire] = [2.0,2.0];
    #|  powRev1 [-4.0,-2.0] [0.25,0.5] [entire] = [0x1.306FE0A31B715p0, 2.0];
    #|  powRev1 [1.0,2.0] [0.0,0.0] [entire] = [0.0,0.0];
    #|  powRev1 [0.0,0.0] [1.0,1.0] [entire] = [0.0,infinity];
    #|  powRev1 [entire] [-infinity,-1.0] [entire] = [empty];
    #|}
  let cases = @itl_expr.parse_itl(source).unwrap()
  for case in cases {
    let result = @itl_expr.execute_case(case)
    assert_true(result.passed(), msg=case.id() + ": " + result.message())
  }
}

///|
// oracle: A
// source: tools/itl_pow2_reverse_oracle.py hull(), an oracle that shares no code with interval, was run on the five
//   rows in this review and returns exactly the written results
// shares: Binary::from_hex_ctx and from_string_ctx (the executor reads the operand and the expected bounds with them)
//   and the interval operation under test
test "ITL powRev2: exact ends, an open end and the base 0" {
  let source =
    #|testcase pow_reverse_2 {
    #|  powRev2 [2.0,2.0] [8.0,8.0] [entire] = [3.0,3.0];
    #|  powRev2 [0.25,0.5] [2.0,4.0] [entire] = [-2.0,-0.5];
    #|  powRev2 [2.0,infinity] [2.0,4.0] [-3.0,0.0] = [empty];
    #|  powRev2 [0.0,0.0] [0.0,0.0] [entire] = [0.0,infinity];
    #|  powRev2 [1.0,1.0] [2.0,4.0] [entire] = [empty];
    #|}
  let cases = @itl_expr.parse_itl(source).unwrap()
  for case in cases {
    let result = @itl_expr.execute_case(case)
    assert_true(result.passed(), msg=case.id() + ": " + result.message())
  }
}

///|
// oracle: A
// source: tools/itl_atan2_reverse_oracle.py hull() (IEEE 1788-2015 10.5.4, exact hulls, the forward definition checked
//   in the tool), an oracle that shares no code with interval, was run on the seven undecorated rows in this
//   review and returns exactly the written results; the decorated row follows from the trv decoration of reverse
//   operations
// shares: Binary::from_hex_ctx and from_string_ctx (the executor reads the operand and the expected bounds with them)
//   and the interval operation under test
test "ITL atan2Rev1 and atan2Rev2: axis angles, the branch cut and the empty set" {
  let source =
    #|testcase atan2_reverse {
    #|  atan2Rev1 [0.0,0.0] [1.0,2.0] [entire] = [0.0,infinity];
    #|  atan2Rev1 [entire] [0.0,0.0] [entire] = [0.0,0.0];
    #|  atan2Rev1 [0.0,0.0] [4.0,5.0] [entire] = [empty];
    #|  atan2Rev1 [-1.0,-1.0] [3.1,4.0] [-1.0,0.0] = [0.0,0.0];
    #|  atan2Rev2 [0.0,0.0] [3.1,4.0] [entire] = [-infinity,0.0];
    #|  atan2Rev2 [0.0,0.0] [-4.0,-3.1] [entire] = [empty];
    #|  atan2Rev2 [0.0,0.0] [0.0,0.0] [-1.0,0.0] = [empty];
    #|  atan2Rev1 [0.0,0.0]_def [1.0,2.0]_def [entire]_def = [0.0,infinity]_trv;
    #|}
  let cases = @itl_expr.parse_itl(source).unwrap()
  for case in cases {
    let result = @itl_expr.execute_case(case)
    assert_true(result.passed(), msg=case.id() + ": " + result.message())
  }
}

///|
// oracle: A
// source: the expected dispositions are written out by hand: each literal below is not an interval by the definition of a nonempty interval in IEEE 1788-2015 (a lower bound above the upper one, a NaN bound, [+inf,+inf], [-inf,-inf]), and `[1e400,1e400]` reads as [+inf,+inf] in binary64
// shares: nothing (only the public parse_itl, execute_case and ItlResult accessors; the verdict is a variant tag compared with a literal)
test "ITL an interval literal that is not an interval is a diagnostic" {
  let bad = ["[2,1]", "[nan,1]", "[inf,inf]", "[1e400,1e400]", "[-inf,-inf]"]
  for literal in bad {
    let source = "testcase bad {\n  add \{literal} [1.0,2.0] = [1.0,2.0];\n}"
    let cases = @itl_expr.parse_itl(source).unwrap()
    let result = @itl_expr.execute_case(cases[0])
    guard result.disposition() is Diagnostic("invalid interval operand") else {
      fail("expected the diagnostic for " + literal)
    }
    assert_false(result.passed())
    assert_eq(result.message(), literal)
  }
}

///|
// oracle: A
// source: expected dispositions written out by hand (same definition as above), one operation per executor path of execute_case that reads an interval literal
// shares: nothing (public accessors only)
test "ITL a bad interval is a diagnostic on every executor path" {
  let source =
    #|testcase paths {
    #|  pown [2,1] 2 = [1.0,4.0];
    #|  fma [2,1] [1.0,2.0] [1.0,2.0] = [1.0,2.0];
    #|  sqr [nan,1] = [1.0,2.0];
    #|  mulRev [inf,inf] [1.0,2.0] [1.0,2.0] = [1.0,2.0];
    #|  isMember 1.0 [2,1] = true;
    #|}
  let cases = @itl_expr.parse_itl(source).unwrap()
  assert_eq(cases.length(), 5)
  for case in cases {
    let result = @itl_expr.execute_case(case)
    match result.disposition() {
      Diagnostic(_) => ()
      _ => fail("expected a diagnostic for " + case.operation())
    }
    assert_false(result.passed())
  }
}

///|
// oracle: A
// source: counts written out by hand: three good cases pass, the one bad case between them is a diagnostic; the sums are 1+2, 3+4 as binary64 numbers that are exact
// shares: nothing (public summary accessors)
test "ITL a bad case does not stop the cases after it" {
  let source =
    #|testcase run {
    #|  add [1.0,1.0] [2.0,2.0] = [3.0,3.0];
    #|  add [2,1] [2.0,2.0] = [3.0,3.0];
    #|  add [3.0,3.0] [4.0,4.0] = [7.0,7.0];
    #|  add [-inf,-inf] [4.0,4.0] = [7.0,7.0];
    #|  add [5.0,5.0] [4.0,4.0] = [9.0,9.0];
    #|}
  let cases = @itl_expr.parse_itl(source).unwrap()
  let summary = @itl_expr.summarize_results(
    cases.map(fn(case) { @itl_expr.execute_case(case) }),
  )
  assert_eq(summary.total_cases(), 5)
  assert_eq(summary.passed_cases(), 3)
  assert_eq(summary.diagnostic_cases(), 2)
  assert_eq(summary.failed_cases(), 0)
}
