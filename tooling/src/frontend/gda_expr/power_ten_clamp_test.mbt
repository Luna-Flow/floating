///|
/// GDA 1.70, *Exceptional conditions*, Clamped: an exponent above Etop under `clamp`
/// is folded down, with `Clamped` (issue 287). A power of ten took a shortcut that
/// skipped it. Expected values: Python `decimal` (libmpdec 4.0.0) as oracle,
/// checked against the clause by hand.
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
