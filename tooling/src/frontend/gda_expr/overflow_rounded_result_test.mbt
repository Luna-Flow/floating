///|
/// GDA 1.70, *Exceptional conditions*, Overflow: the condition is judged on the
/// adjusted exponent of the result after rounding, not on an operand that would
/// round past Emax on its own (issue 264). Expected values: Python `decimal`
/// (libmpdec 4.0.0) as oracle, checked against the clause by hand.
test "gda interpreter judges overflow on the rounded result of add, subtract and fma" {
  let source =
    #|extended: 1
    #|precision: 1
    #|rounding: half_even
    #|maxexponent: 0
    #|minexponent: -1
    #|clamp: 0
    #|ov1 add 9.5 -0.5 -> 9 Rounded
    #|ov2 subtract -9.5 -0.5 -> -9 Rounded
    #|ov3 add 9.5 0.5 -> Infinity Inexact Rounded Overflow
    #|precision: 2
    #|ov4 add 9.99 -0.07 -> 9.9 Inexact Rounded
    #|precision: 1
    #|rounding: up
    #|minexponent: 0
    #|ov5 add 0.1 -9.1 -> -9 Rounded
    #|precision: 5
    #|maxexponent: 18
    #|minexponent: -17
    #|ov6 fma 100000.00000000000000000000000000000000000001 -9999.9E+10 1E+0 -> -9.9999E+18 Inexact Rounded
    #|precision: 1
    #|rounding: half_even
    #|maxexponent: 5
    #|minexponent: -4
    #|ov7 add 999E4 -1E7 -> -1E+4
    #|
  let document = @gda_expr.parse_dectest("overflow.decTest", source).unwrap()
  let summary = @gda_expr.execute_documents([document])
  assert_eq(summary.executable_cases(), 7)
  assert_eq(summary.passed_cases(), 7)
  assert_eq(summary.failed_cases(), 0)
}
