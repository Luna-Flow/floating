///|
/// GDA 1.70, *Arithmetic operations*: an inexact result is "rounded (shortened) to
/// exactly precision digits", trailing zeros included (issue 266). A subset context
/// (`extended: 0`) strips them (Appendix A, Operation differences). Expected values:
/// Python `decimal` (libmpdec 4.0.0) as oracle, checked against the clauses by hand.
test "gda interpreter keeps precision digits in an inexact integer power" {
  let source =
    #|extended: 1
    #|precision: 2
    #|rounding: half_even
    #|maxexponent: 0
    #|minexponent: -5
    #|clamp: 0
    #|tz1 power 99999E-1 -1 -> 0.00010 Inexact Rounded
    #|precision: 3
    #|maxexponent: 97
    #|minexponent: -97
    #|clamp: 1
    #|tz2 power 999.99999999 -8 -> 1.00E-24 Inexact Rounded
    #|precision: 4
    #|maxexponent: 999
    #|minexponent: -999
    #|clamp: 0
    #|tz3 power 11952E-2 -2 -> 0.00007000 Inexact Rounded
    #|
  let document = @gda_expr.parse_dectest("power_zeros.decTest", source).unwrap()
  let summary = @gda_expr.execute_documents([document])
  assert_eq(summary.executable_cases(), 3)
  assert_eq(summary.passed_cases(), 3)
  assert_eq(summary.failed_cases(), 0)
}
