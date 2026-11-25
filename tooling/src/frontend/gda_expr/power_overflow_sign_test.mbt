// Evidence tools: the `source:` lines of this file that say "per the evidence header" name runs of CPython 3.13.16 decimal (libmpdec 4.0.0), executed on 2026-11-25 by the author of the declarations over the rows quoted in each line; rerun the quoted values with the same tool to check them.

///|
/// GDA 1.70, *power*: the sign of the result is 1 only if the right-hand side is
/// an odd integer and the left-hand side is negative (issue 265). A negative base
/// with an even negative exponent overflows to `Infinity`, not `-Infinity`.
/// Expected values: Python `decimal` (libmpdec 4.0.0) as oracle, checked against
/// the clause by hand.
// oracle: A
// source: GDA 1.70 power (the sign is negative only for an odd integer exponent of a negative base); the rows were run
//   with CPython decimal (libmpdec 4.0.0) per the evidence header and agree in value, cohort and flags, as the doc
//   comment of the block states
// shares: the decimal reader of the operands, the rounding and the scientific-notation printer of the interpreter (the
//   results are compared with the row as text), and the context it builds from the directives; all of them are
//   the code under test
test "gda interpreter signs the overflow of a negative power by the parity of the exponent" {
  let source =
    #|extended: 1
    #|precision: 1
    #|rounding: half_even
    #|maxexponent: 0
    #|minexponent: 0
    #|clamp: 0
    #|po1 power -7E-2 -8 -> Infinity Inexact Rounded Overflow
    #|po2 power -7E-2 -2 -> Infinity Inexact Rounded Overflow
    #|po3 power -7E-2 -7 -> -Infinity Inexact Rounded Overflow
    #|po4 power -7E-2 -9 -> -Infinity Inexact Rounded Overflow
    #|po5 power 7E-2 -8 -> Infinity Inexact Rounded Overflow
    #|po6 power -7E-2 -8.0 -> Infinity Inexact Rounded Overflow
    #|rounding: down
    #|po7 power -7E-2 -8 -> 9 Inexact Rounded Overflow
    #|po8 power -7E-2 -7 -> -9 Inexact Rounded Overflow
    #|
  let document = @gda_expr.parse_dectest("power_sign.decTest", source).unwrap()
  let summary = @gda_expr.execute_documents([document])
  assert_eq(summary.executable_cases(), 8)
  assert_eq(summary.passed_cases(), 8)
  assert_eq(summary.failed_cases(), 0)
}
