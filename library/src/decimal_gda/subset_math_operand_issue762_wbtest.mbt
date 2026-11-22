///|
// Issue 762: in a subset context (extended=false) `sqrt`, `ln`, `log10` and `exp` round an operand
// longer than the precision with the rounding algorithm of the context, not with that of the
// mathematical context (round-half-even, which the text keeps for the result), before the operation (GDA 1.70, page 56, Appendix A,
// "Operation differences", first item). Rows: op, precision, rounding, extended, a, b, result,
// Lost digits (Y or N). The runner is the one of the issue 759 test file; b is not used.

///|
let i762_rows : String =
  #|squareroot	1	down	0	0.999	-	0.9	Y
  #|squareroot	1	floor	0	0.999	-	0.9	Y
  #|squareroot	1	up	0	0.999	-	1	Y
  #|squareroot	1	ceiling	0	0.999	-	1	Y
  #|squareroot	1	half_up	0	0.999	-	1	Y
  #|squareroot	3	down	0	99950	-	316	Y
  #|squareroot	3	up	0	99950	-	316	Y
  #|squareroot	1	half_up	0	25	-	5	Y
  #|squareroot	1	half_even	0	25	-	4	Y
  #|squareroot	3	down	0	99900	-	316	N
  #|ln	1	down	0	0.999	-	-0.1	Y
  #|ln	1	floor	0	0.999	-	-0.1	Y
  #|ln	1	ceiling	0	0.999	-	0	Y
  #|ln	1	up	0	0.999	-	0	Y
  #|log10	1	down	0	0.999	-	-0.05	Y
  #|log10	1	floor	0	0.999	-	-0.05	Y
  #|log10	1	ceiling	0	0.999	-	0	Y
  #|log10	1	up	0	0.999	-	0	Y
  #|exp	1	half_up	0	25	-	1E+13	Y
  #|exp	1	half_even	0	25	-	5E+8	Y
  #|squareroot	1	half_up	1	0.999	-	1	N
  #|ln	1	down	1	0.999	-	-0.001	N
  #|log10	1	down	1	0.999	-	-0.0004	N

///|
// oracle: A
// source: expected values written by hand from GDA 1.70, page 56 (Appendix A, "Operation differences", first item: the operand is rounded to precision digits with the rounding algorithm of the context, Lost digits when non-zero digits go) and from the value of the function on the rounded operand, rounded with round-half-even, the rounding the text prescribes for the inexact results of these four operations (pages 30, 31, 31 and 39): sqrt(0.9) = 0.94868, ln(0.9) = -0.105361, log10(0.9) = -0.045757, 99950 rounds to 9.99E+4 (down) or 1.00E+5 (up) and sqrt(99900) = 316.07, sqrt(100000) = 316.23; 25 rounds to 3E+1 (half-up) or 2E+1 (half-even) and sqrt(30) = 5.477, sqrt(20) = 4.472, exp(30) = 1.0687E+13, exp(20) = 4.8517E+8; the repro row is the table of issue 762 (decNumber 3.68 with DECSUBSET=1 gives 0.9 for sqrt(0.999) at precision 1, down); the extended rows follow from the function of the unrounded operand: sqrt(0.999) = 0.99950, ln(0.999) = -0.0010005, log10(0.999) = -0.00043451
// shares: Decimal::from_string and Decimal::to_sci_string (the printing of a Decimal), GdaFlags::lost_digits, the table runner i759_run and the dispatcher i754_call of the issue 759 and 754 test files
test "issue 762: sqrt, ln, log10 and exp round a long operand with the rounding of the context in a subset context" {
  let (calls, bad) = i759_run(i762_rows)
  assert_eq(bad, [])
  assert_eq(calls, 23)
}
