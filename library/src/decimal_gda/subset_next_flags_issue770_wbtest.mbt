///|
// Issue 770: `next_plus` and `next_minus` set no flags for a numeric operand (GDA 1.70, page 34),
// also when rule S of page 55 turns a subnormal next number into 0 in a subset context.
// `next_toward` raises the flags of the sum with an infinitesimal (page 35), which for a result
// that is not normal are Inexact, Rounded, Subnormal and Underflow (decNumber 3.68 passes them
// through), and none for a normal result. Rows: op, precision, rounding, emax, emin, extended, a,
// b, result, flags; the runner is i754_run of the issue 754 test file.

///|
let i770_rows : String =
  #|nextplus	3	half_up	99	-99	0	0	-	0	-
  #|nextminus	3	half_up	99	-99	0	0	-	0	-
  #|nextminus	3	half_up	99	-99	0	1E-99	-	0	-
  #|nextplus	3	half_up	99	-99	0	-1E-99	-	0	-
  #|nextplus	3	floor	99	-99	0	0	-	0	-
  #|nextminus	3	ceiling	99	-99	0	0	-	0	-
  #|nextplus	3	half_up	99	-99	0	1	-	1.01	-
  #|nextminus	3	half_up	99	-99	0	1	-	0.999	-
  #|nextminus	3	half_up	99	-99	0	1E-98	-	9.99E-99	-
  #|nexttoward	3	half_up	99	-99	0	0	1	0	Inexact,Rounded,Subnormal,Underflow
  #|nexttoward	3	half_up	99	-99	0	0	-1	0	Inexact,Rounded,Subnormal,Underflow
  #|nexttoward	3	half_up	99	-99	0	1E-99	0	0	Inexact,Rounded,Subnormal,Underflow
  #|nexttoward	3	half_up	99	-99	0	-1E-99	0	0	Inexact,Rounded,Subnormal,Underflow
  #|nexttoward	3	half_up	99	-99	0	1	2	1.01	-
  #|nexttoward	3	half_up	99	-99	0	1	0	0.999	-
  #|nexttoward	3	half_up	99	-99	0	1	1	1	-
  #|nextplus	3	half_up	99	-99	1	0	-	1E-101	-
  #|nextminus	3	half_up	99	-99	1	0	-	-1E-101	-
  #|nextminus	3	half_up	99	-99	1	1E-99	-	9.9E-100	-
  #|nextplus	3	half_up	99	-99	1	-1E-99	-	-9.9E-100	-
  #|nexttoward	3	half_up	99	-99	1	0	1	1E-101	Inexact,Rounded,Subnormal,Underflow
  #|nexttoward	3	half_up	99	-99	1	1E-99	0	9.9E-100	Inexact,Rounded,Subnormal,Underflow

///|
// oracle: A
// source: expected values written by hand from GDA 1.70, page 34 (next-minus and next-plus: the largest or smallest representable number beyond the operand, "No flags will be set when the operand is numeric") and page 35 (next-toward: flags "as though the operation had been computed by adding ... an infinitesimally small positive value" with round-ceiling or round-floor, which for a tiny result are Inexact, Rounded, Subnormal and Underflow) and from page 55 rule S (a subnormal result is refused in a subset context: the result is 0); at precision 3 and Emin -99 the next number above 1 is 1.01, below 1 is 0.999 and below 1E-98 is 9.99E-99; in an extended context Etiny is -101, so the next number above 0 is 1E-101 and below 1E-99 is 9.9E-100; the repro rows are the table of issue 770 (decNumber 3.68 with DECSUBSET=1: no flags for next_plus and next_minus, the four flags for next_toward of a tiny result)
// shares: the table runner i754_run, the dispatcher i754_call and the helpers i754_flags, i754_int and i754_mode of the issue 754 test file, Decimal::from_string and Decimal::to_sci_string
test "issue 770: next_plus and next_minus set no flags in a subset context, next_toward keeps the flags of a tiny result" {
  let (calls, bad) = i754_run(i770_rows)
  assert_eq(bad, [])
  assert_eq(calls, 22)
}
