///|
/// GDA 1.70, *Exceptional conditions*: Subnormal is judged before rounding, on the
/// exact result, and Underflow is Subnormal with Inexact (issue 268). The exact
/// power 1 / 1.00000000000000000001 is below 10^Emin = 1 although it rounds to 1.
/// Expected values: Python `decimal` (libmpdec 4.0.0) as oracle, the side of the
/// exact power decided with exact rational arithmetic.
test "gda interpreter signals Subnormal and Underflow for a power just below Emin" {
  let source =
    #|extended: 1
    #|precision: 1
    #|rounding: half_even
    #|maxexponent: 999
    #|minexponent: 0
    #|clamp: 0
    #|su1 power 100000000000000000001E-20 -1 -> 1 Underflow Subnormal Inexact Rounded
    #|su2 power 100000000000000000001E-20 1 -> 1 Inexact Rounded
    #|su3 power 100000000000000000001E-20 -2 -> 1 Underflow Subnormal Inexact Rounded
    #|su4 power 0.99999999999999999999 1 -> 1 Underflow Subnormal Inexact Rounded
    #|
  let document = @gda_expr.parse_dectest("power_subnormal.decTest", source).unwrap()
  let summary = @gda_expr.execute_documents([document])
  assert_eq(summary.executable_cases(), 4)
  assert_eq(summary.passed_cases(), 4)
  assert_eq(summary.failed_cases(), 0)
}
