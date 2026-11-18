///|
/// GDA 1.70, *Exceptional conditions*, Clamped: an inexact result has `precision`
/// digits at an exponent of at most Etop, so it is not folded down and not flagged
/// (issue 305). Rows .1081 and .1129 of the random differential (seed 20261118).
/// Expected values: Python `decimal` (libmpdec 4.0.0) as oracle, checked against the
/// clause by hand.
test "gda interpreter does not flag Clamped on an inexact power that rounds to a power of ten" {
  let source =
    #|extended: 1
    #|rounding: half_even
    #|clamp: 1
    #|precision: 4
    #|maxexponent: 0
    #|minexponent: -9
    #|ic1 power 0.9999999 -1 -> 1.000 Inexact Rounded
    #|precision: 4
    #|maxexponent: 18
    #|minexponent: -16
    #|ic2 power 000999999900000000000000000E-27 -6 -> 1.000E+18 Inexact Rounded
    #|precision: 6
    #|maxexponent: 0
    #|minexponent: -1
    #|ic3 power 099999999999999999999999999999E-29 -001e+0 -> 1.00000 Inexact Rounded
    #|precision: 2
    #|maxexponent: 3
    #|minexponent: -9
    #|ic4 power 10 3 -> 1.0E+3 Rounded
    #|
  let document = @gda_expr.parse_dectest(
    "power_inexact_clamped.decTest", source,
  ).unwrap()
  let summary = @gda_expr.execute_documents([document])
  assert_eq(summary.executable_cases(), 4)
  assert_eq(summary.passed_cases(), 4)
  assert_eq(summary.failed_cases(), 0)
}
