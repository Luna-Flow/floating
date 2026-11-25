// Evidence tools: the `source:` lines of this file that say "per the evidence header" name runs of CPython 3.13.16 decimal (libmpdec 4.0.0), executed on 2026-11-25 by the author of the declarations over the rows quoted in each line; rerun the quoted values with the same tool to check them.

///|
/// GDA 1.70, *Exceptional conditions*, Clamped: an inexact result has `precision`
/// digits at an exponent of at most Etop, so it is not folded down and not flagged
/// (issue 305). Rows .1081 and .1129 of the random differential (seed 20261118).
/// Expected values: Python `decimal` (libmpdec 4.0.0) as oracle, checked against the
/// clause by hand.
// oracle: A
// source: GDA 1.70 Clamped (an inexact result of precision digits at an exponent of at most Etop is not folded down);
//   the rows were run with CPython decimal (libmpdec 4.0.0) per the evidence header and agree in value, cohort and flags,
//   as the doc comment of the block states
// shares: the decimal reader of the operands, the rounding and the scientific-notation printer of the interpreter (the
//   results are compared with the row as text), and the context it builds from the directives; all of them are
//   the code under test
test "gda interpreter does not flag Clamped on an inexact power that rounds to a power of ten" {
  let source =
    #|extended: 1
    #|rounding: half_even
    #|clamp: 1
    #|precision: 4
    #|maxexponent: 0
    #|minexponent: -1
    #|ic1 power 0.9999999 -1 -> 1.000 Inexact Rounded
    #|precision: 4
    #|maxexponent: 18
    #|minexponent: -17
    #|ic2 power 000999999900000000000000000E-27 -6 -> 1.000E+18 Inexact Rounded
    #|precision: 6
    #|maxexponent: 0
    #|minexponent: -1
    #|ic3 power 099999999999999999999999999999E-29 -001e+0 -> 1.00000 Inexact Rounded
    #|precision: 2
    #|maxexponent: 3
    #|minexponent: -4
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
