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
    #|  sqrRev [1.0,4.0] = [-2.0,2.0];
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
