///|
// Issue 761: in a subset context (extended=false) `subtract` rounds the second operand, when it
// is longer than the precision, with the algorithm of the context and its own sign, and only
// then adjusts the sign for the subtraction (GDA 1.70, page 56, Appendix A, "Operation
// differences", first item). Rows: op, precision, rounding, extended, a, b, result, Lost digits
// (Y or N). The runner is the one of the issue 759 test file.

///|
let i761_rows : String =
  #|subtract	1	floor	0	0	12	-1E+1	Y
  #|subtract	1	ceiling	0	0	12	-2E+1	Y
  #|subtract	1	floor	0	0	-12	2E+1	Y
  #|subtract	1	ceiling	0	0	-12	1E+1	Y
  #|subtract	1	down	0	0	12	-1E+1	Y
  #|subtract	1	up	0	0	12	-2E+1	Y
  #|subtract	1	half_up	0	0	12	-1E+1	Y
  #|subtract	3	floor	0	0	123456	-1.23E+5	Y
  #|subtract	3	ceiling	0	0	123456	-1.24E+5	Y
  #|subtract	3	floor	0	-0	123456	-1.23E+5	Y
  #|subtract	3	floor	0	0	123000	-1.23E+5	N
  #|subtract	3	floor	0	0	12	-12	N
  #|subtract	1	floor	0	0	-0.999	1	Y
  #|subtract	1	ceiling	0	0	-0.999	0.9	Y
  #|subtract	3	floor	0	5	123456	-1.23E+5	Y
  #|subtract	3	ceiling	0	5	123456	-1.23E+5	Y
  #|subtract	1	ceiling	0	5	12	-1E+1	Y
  #|subtract	1	floor	1	0	12	-2E+1	N
  #|subtract	1	ceiling	1	0	12	-1E+1	N
  #|subtract	1	floor	1	0	-12	1E+1	N

///|
// oracle: A
// source: expected values written by hand from GDA 1.70, page 56 (Appendix A, "Operation differences", first item: the operand is rounded to precision digits with the rounding of the context, Lost digits when non-zero digits go) and the subtraction rule (the other number, rounded to precision if necessary, is used with its sign adjusted); the repro row is the table of issue 761 (decNumber 3.68 with DECSUBSET=1 gives -1E+1 for subtract(0, 12) at precision 1, floor); rows with a first operand other than zero: 12 rounds to 2E+1 (ceiling) and 5 - 2E+1 = -15 which ceiling rounds to -1E+1; 123456 rounds to 1.23E+5 (floor) and 5 - 123000 = -122995 which floor rounds to -1.23E+5, to 1.24E+5 (ceiling) and 5 - 124000 = -123995 which ceiling rounds to -1.23E+5; extended rows follow from the exact difference rounded once (-12 at precision 1: -2E+1 floor, -1E+1 ceiling)
// shares: Decimal::from_string and Decimal::to_sci_string (the printing of a Decimal), GdaFlags::lost_digits, the table runner i759_run and the dispatcher i754_call of the issue 759 and 754 test files
test "issue 761: subtract rounds the second operand with its own sign before the sign adjustment in a subset context" {
  let (calls, bad) = i759_run(i761_rows)
  assert_eq(bad, [])
  assert_eq(calls, 20)
}
