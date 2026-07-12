///|
test "ITL parser and executor run minimal set cases" {
  let source =
    #|testcase minimal {
    #|  intersection [1.0,3.0] [2.0,4.0] = [2.0,3.0];
    #|  convexHull [1.0,3.0]_trv [2.0,4.0]_trv = [1.0,4.0]_trv;
    #|}
  let cases = parse_itl(source).unwrap()
  assert_eq(cases.length(), 2)
  let summary = summarize_results(cases.map(fn(case) { execute_case(case) }))
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
  let cases = parse_itl(source).unwrap()
  assert_eq(cases.length(), 1)
  let result = execute_case(cases[0])
  assert_false(result.passed())
  assert_true(result.message().contains("expected"))
}
