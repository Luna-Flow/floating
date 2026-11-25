///|
/// GDA 1.70, *Exceptional conditions*: Subnormal is judged before rounding, on the
/// exact result, and Underflow is Subnormal with Inexact (issue 268). The exact
/// power 1 / 1.00000000000000000001 is below 10^Emin = 1 although it rounds to 1.
/// Expected values: Python `decimal` (libmpdec 4.0.0) as oracle, the side of the
/// exact power decided with exact rational arithmetic.
// oracle: A
// source: GDA 1.70 exceptional conditions (Subnormal is judged on the exact result before rounding; Underflow is
//   Subnormal with Inexact); the rows were run with CPython decimal (libmpdec 4.0.0) in this review and agree in
//   value, cohort and flags, as the doc comment of the block states
// shares: the decimal reader of the operands, the rounding and the scientific-notation printer of the interpreter (the
//   results are compared with the row as text), and the context it builds from the directives; all of them are
//   the code under test
test "gda interpreter signals Subnormal and Underflow for a power just below Emin" {
  let source =
    #|extended: 1
    #|precision: 1
    #|rounding: half_even
    #|maxexponent: 0
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

///|
/// GDA 1.70, *Exceptional conditions*: Underflow is Subnormal with Inexact (issue 342).
/// The 26-digit working value of the exact power is already `1.00000000000000E-9`, so
/// the final rounding to the context is exact, yet the power itself is inexact.
/// Expected values: Python `decimal` (libmpdec 4.0.0) as oracle.
// oracle: A
// source: GDA 1.70 exceptional conditions (Underflow is Subnormal with Inexact; the power itself is inexact); the rows
//   were run with CPython decimal (libmpdec 4.0.0) in this review and agree in value, cohort and flags, as the
//   doc comment of the block states
// shares: the decimal reader of the operands, the rounding and the scientific-notation printer of the interpreter (the
//   results are compared with the row as text), and the context it builds from the directives; all of them are
//   the code under test
test "gda interpreter signals Underflow for an inexact subnormal power with a negative exponent" {
  let source =
    #|extended: 1
    #|precision: 23
    #|rounding: half_even
    #|maxexponent: 1
    #|minexponent: -1
    #|clamp: 0
    #|su5 power 10.000000000000000000000000001 -9 -> 1.00000000000000E-9 Underflow Subnormal Inexact Rounded
    #|su6 power 10.000000000000000000000000001 -9.E+0 -> 1.00000000000000E-9 Underflow Subnormal Inexact Rounded
    #|su7 power 0.10000000000000000000000001 9 -> 1.00000000000000E-9 Underflow Subnormal Inexact Rounded
    #|
  let document = @gda_expr.parse_dectest("power_subnormal_342.decTest", source).unwrap()
  let summary = @gda_expr.execute_documents([document])
  assert_eq(summary.executable_cases(), 3)
  assert_eq(summary.passed_cases(), 3)
  assert_eq(summary.failed_cases(), 0)
}
