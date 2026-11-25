///|
/// GDA 1.70, *power*: the exponent of an unrounded result is the one repeated
/// multiplication gives, the reciprocal of a negative power keeping the cohort of
/// the division (issue 284). Expected values: Python `decimal` (libmpdec 4.0.0) as
/// oracle, checked against the clause by hand.
// oracle: A
// source: GDA 1.70 power (the exponent of an exact result is the one repeated multiplication gives); the rows were run
//   with CPython decimal (libmpdec 4.0.0) in this review and agree in value, cohort and flags, as the doc
//   comment of the block states
// shares: the decimal reader of the operands, the rounding and the scientific-notation printer of the interpreter (the
//   results are compared with the row as text), and the context it builds from the directives; all of them are
//   the code under test
test "gda interpreter keeps the cohort of the reciprocal in an exact negative power" {
  let source =
    #|extended: 1
    #|rounding: half_even
    #|maxexponent: 999
    #|minexponent: -999
    #|clamp: 0
    #|precision: 3
    #|rc1 power 0.05 -8 -> 2.56E+10
    #|precision: 5
    #|rc2 power 0.05 -8 -> 2.56E+10
    #|precision: 2
    #|rc3 power 0.05 -3 -> 8E+3
    #|rc4 power -0.05 -5 -> -3.2E+6
    #|
  let document = @gda_expr.parse_dectest("power_cohort.decTest", source).unwrap()
  let summary = @gda_expr.execute_documents([document])
  assert_eq(summary.executable_cases(), 4)
  assert_eq(summary.passed_cases(), 4)
  assert_eq(summary.failed_cases(), 0)
}
