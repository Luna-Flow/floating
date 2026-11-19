///|
/// GDA 1.70, *Exceptional conditions*, Clamped: the condition is signaled only if
/// the exponent of a result has been altered to fit (issue 267). Expected values:
/// Python `decimal` (libmpdec 4.0.0) as oracle, checked against the clause by hand.
test "gda interpreter signals Clamped for power only when the result exponent was altered" {
  let source =
    #|extended: 1
    #|precision: 1
    #|rounding: half_even
    #|maxexponent: 0
    #|minexponent: -1
    #|clamp: 1
    #|cl1 power 6E-1 2 -> 0.4 Inexact Rounded
    #|cl2 power -0.5 -2 -> 4
    #|cl3 power -9.99 1 -> -Infinity Inexact Rounded Overflow
    #|precision: 3
    #|maxexponent: 2
    #|minexponent: -2
    #|cl4 power 2E+1 2 -> 400 Clamped
    #|
  let document = @gda_expr.parse_dectest("power_clamped.decTest", source).unwrap()
  let summary = @gda_expr.execute_documents([document])
  assert_eq(summary.executable_cases(), 4)
  assert_eq(summary.passed_cases(), 4)
  assert_eq(summary.failed_cases(), 0)
}
