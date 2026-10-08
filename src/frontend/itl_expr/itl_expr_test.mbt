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
