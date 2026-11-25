///|
/// GDA 1.70, *power*: "the result will be inexact unless the right-hand side has an
/// integral value and the result is finite and can be expressed exactly within
/// precision digits" (issue 306). 1^1.03 is `1.0000 Inexact Rounded` at precision 5
/// whatever Emax is; row .3705 of the random differential (seed 20261118,
/// decimal_gda-power). Expected values: Python `decimal` (libmpdec 4.0.0) as oracle,
/// checked against the clause by hand.
// oracle: A
// source: GDA 1.70 power (the result is inexact unless the right-hand side is an integer and the result can be
//   expressed exactly); the rows were run with CPython decimal (libmpdec 4.0.0) in this review and agree in
//   value, cohort and flags, as the doc comment of the block states
// shares: the decimal reader of the operands, the rounding and the scientific-notation printer of the interpreter (the
//   results are compared with the row as text), and the context it builds from the directives; all of them are
//   the code under test
test "gda interpreter signals Inexact for the power of 1 to a non-integer exponent in a small context" {
  let source =
    #|extended: 1
    #|rounding: half_even
    #|precision: 5
    #|maxexponent: 0
    #|minexponent: -1
    #|clamp: 1
    #|po1 power 1 1.03 -> 1.0000 Inexact Rounded
    #|po2 power 1.00000000000000000000000 1.03 -> 1.0000 Inexact Rounded
    #|po3 power 1 -1.03 -> 1.0000 Inexact Rounded
    #|clamp: 0
    #|po4 power 1 1.03 -> 1.0000 Inexact Rounded
    #|po5 power 1 2 -> 1
    #|
  let document = @gda_expr.parse_dectest("power_one.decTest", source).unwrap()
  let summary = @gda_expr.execute_documents([document])
  assert_eq(summary.executable_cases(), 5)
  assert_eq(summary.passed_cases(), 5)
  assert_eq(summary.failed_cases(), 0)
}
