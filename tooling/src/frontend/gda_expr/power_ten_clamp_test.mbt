// Evidence tools: the `source:` lines of this file that say "per the evidence header" name runs of CPython 3.13.16 decimal (libmpdec 4.0.0), executed on 2026-11-25 by the author of the declarations over the rows quoted in each line; rerun the quoted values with the same tool to check them.

///|
/// GDA 1.70, *Exceptional conditions*, Clamped: an exponent above Etop under `clamp`
/// is folded down, with `Clamped` (issue 287). A power of ten took a shortcut that
/// skipped it. Expected values: Python `decimal` (libmpdec 4.0.0) as oracle,
/// checked against the clause by hand.
// oracle: A
// source: GDA 1.70 Clamped (an exponent above Etop under clamp is folded down); the rows were run with CPython decimal
//   (libmpdec 4.0.0) per the evidence header and agree in value, cohort and flags, as the doc comment of the block states
// shares: the decimal reader of the operands, the rounding and the scientific-notation printer of the interpreter (the
//   results are compared with the row as text), and the context it builds from the directives; all of them are
//   the code under test
test "gda interpreter folds down a power of ten under clamp" {
  let source =
    #|extended: 1
    #|rounding: half_even
    #|clamp: 1
    #|precision: 7
    #|maxexponent: 999
    #|minexponent: -999
    #|tc1 power -1E+998 1 -> -1.00000E+998 Clamped
    #|precision: 3
    #|maxexponent: 0
    #|minexponent: -1
    #|tc2 power -1E+1 -1 -> -0.10 Clamped
    #|precision: 3
    #|maxexponent: 1
    #|minexponent: -2
    #|tc3 power -1E+1 1 -> -10.0 Clamped
    #|clamp: 0
    #|tc4 power -1E+1 1 -> -1E+1
    #|
  let document = @gda_expr.parse_dectest("power_ten.decTest", source).unwrap()
  let summary = @gda_expr.execute_documents([document])
  assert_eq(summary.executable_cases(), 4)
  assert_eq(summary.passed_cases(), 4)
  assert_eq(summary.failed_cases(), 0)
}
