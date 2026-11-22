///|
// Issue 765: in a subset context (extended=false) `power` treats an operand written with a
// positive exponent like the same value written plainly: the exponent is reduced to zero before
// the operation (GDA 1.70, page 55, footnote 45: "positive exponents in the operands are reduced
// to zero before the operation, so that all operations take place on numbers that could be
// expressed as plain decimal numbers"), so the rounding of the result raises Rounded for both
// writings. Rows: op, precision, rounding, emax, emin, extended, a, b, result, flags; the runner
// is i754_run of the issue 754 test file.

///|
let i765_rows : String =
  #|power	9	half_up	999999	-999999	0	1200	3	1.728E+9	Rounded
  #|power	9	half_up	999999	-999999	0	1.2E+3	3	1.728E+9	Rounded
  #|power	9	half_up	999999	-999999	0	12E+2	3	1.728E+9	Rounded
  #|power	9	half_up	999999	-999999	0	100	5	1E+10	Rounded
  #|power	9	half_up	999999	-999999	0	1E+2	5	1E+10	Rounded
  #|power	9	half_up	999999	-999999	0	123400000	2	1.522756E+16	Rounded
  #|power	9	half_up	999999	-999999	0	1.234E+8	2	1.522756E+16	Rounded
  #|power	9	half_up	999999	-999999	0	120	3	1728000	-
  #|power	9	half_up	999999	-999999	0	12E+1	3	1728000	-
  #|power	9	half_up	999999	-999999	0	50	4	6250000	-
  #|power	9	half_up	999999	-999999	0	5E+1	4	6250000	-
  #|power	9	half_up	999999	-999999	0	3	12	531441	-
  #|power	9	half_up	999999	-999999	0	3	1.2E+1	531441	-
  #|power	9	down	999999	-999999	0	1.2E+3	3	1.728E+9	Rounded
  #|power	9	half_up	999999	-999999	1	1.2E+3	3	1.728E+9	-

///|
// oracle: A
// source: expected values written by hand from the powers (1200^3 = 1,728,000,000 has ten digits, so it is rounded to nine digits, 172800000E+1, and the trailing zero that the rounding leaves is removed after a power operation, GDA 1.70, page 56: the result is 1.728E+9 and only Rounded is raised because the digit lost is a zero; 100^5 = 10^10 has eleven digits; 123400000^2 = 15,227,560,000,000,000 has seventeen digits, 1.522756E+16; 120^3 = 1,728,000, 50^4 = 6,250,000 and 3^12 = 531,441 have at most nine digits and need no rounding) and from page 55, footnote 45, which makes the two writings of an operand the same; the repro row is the table of issue 765 (decNumber 3.68 with DECSUBSET=1 gives 1.728E+9 with Rounded for both writings); the extended row follows from the exact power of 12E+2, 1728E+6
// shares: the table runner i754_run, the dispatcher i754_call and the helpers i754_flags, i754_int and i754_mode of the issue 754 test file, Decimal::from_string and Decimal::to_sci_string
test "issue 765: power in a subset context treats a positive exponent of an operand like the plain writing" {
  let (calls, bad) = i754_run(i765_rows)
  assert_eq(bad, [])
  assert_eq(calls, 15)
}
