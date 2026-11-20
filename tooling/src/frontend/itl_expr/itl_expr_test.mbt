///|
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
