///|
// Issue 764: in a subset context (extended=false) the quantum of quantize and rescale is the
// second operand after it has been rounded to precision digits (GDA 1.70, page 56, Appendix A,
// "Operation differences", first item), as for every other operand. Rows: op, precision,
// rounding, emax, emin, extended, a, b, result, flags ("*": the flags are not checked).

///|
let i764_carry : String =
  #|quantize	1	half_up	999	-999	0	0	12	0E+1	Inexact,Lost_digits,Rounded
  #|quantize	1	half_up	999	-999	0	0	15	0E+1	Inexact,Lost_digits,Rounded
  #|quantize	1	half_up	999	-999	0	0	96	0E+2	Inexact,Lost_digits,Rounded
  #|quantize	1	half_up	999	-999	0	0	99	0E+2	Inexact,Lost_digits,Rounded
  #|quantize	1	half_up	999	-999	0	0	9.6	0E+1	Inexact,Lost_digits,Rounded
  #|quantize	1	half_up	999	-999	0	5	96	0E+2	Inexact,Lost_digits,Rounded
  #|quantize	1	half_up	999	-999	0	5	12	1E+1	Inexact,Lost_digits,Rounded
  #|quantize	1	half_up	999	-999	0	5	1.2	5	Inexact,Lost_digits,Rounded
  #|quantize	1	half_up	999	-999	0	0	0.99	0	Inexact,Lost_digits,Rounded
  #|quantize	1	half_up	999	-999	0	0.5	0.99	1	Inexact,Lost_digits,Rounded
  #|quantize	1	half_up	999	-999	0	0	100	0E+2	Rounded

///|
// oracle: A
// source: quantize at precision 1, half-up: a second operand longer than the precision, with and without a carry, exact and inexact discards, a zero first operand; expected values written by hand from GDA 1.70, page 56 (Appendix A, "Operation differences", first item: an operand with more digits than the precision is rounded to precision digits with the rounding of the context before use, trailing zeros not counted) and page 36 (quantize: the exponent of the result is that of the second operand; Invalid operation when the coefficient would be longer than the precision or the exponent out of range); every value also agrees with decNumber 3.68 (DECSUBSET=1, pin of testdata/decimal_gda/deviations.tsv) run on the second operand after extended rounding to precision digits (58 rows, 58 equal), and the flags are those of the operation joined with those of the operand rounding (Rounded, Inexact, Lost digits)
// shares: Decimal::from_string and Decimal::to_sci_string (the printing of a Decimal), GdaFlags accessors, the table runner i754_run of the issue 754 test file
test "issue 764: carry" {
  let (calls, bad) = i754_run(i764_carry)
  assert_eq(bad, [])
  assert_eq(calls, 11)
}

///|
let i764_modes : String =
  #|quantize	1	half_up	999	-999	0	0	96	0E+2	Inexact,Lost_digits,Rounded
  #|quantize	1	half_even	999	-999	0	0	96	0E+2	Inexact,Lost_digits,Rounded
  #|quantize	1	half_down	999	-999	0	0	96	0E+2	Inexact,Lost_digits,Rounded
  #|quantize	1	up	999	-999	0	0	96	0E+2	Inexact,Lost_digits,Rounded
  #|quantize	1	ceiling	999	-999	0	0	96	0E+2	Inexact,Lost_digits,Rounded
  #|quantize	1	floor	999	-999	0	0	96	0E+1	Inexact,Lost_digits,Rounded
  #|quantize	1	down	999	-999	0	0	96	0E+1	Inexact,Lost_digits,Rounded
  #|quantize	1	05up	999	-999	0	0	96	0E+1	Inexact,Lost_digits,Rounded
  #|quantize	1	half_up	999	-999	0	0	95	0E+2	Inexact,Lost_digits,Rounded
  #|quantize	1	half_even	999	-999	0	0	95	0E+2	Inexact,Lost_digits,Rounded
  #|quantize	1	half_down	999	-999	0	0	95	0E+1	Inexact,Lost_digits,Rounded
  #|quantize	1	up	999	-999	0	0	95	0E+2	Inexact,Lost_digits,Rounded
  #|quantize	1	ceiling	999	-999	0	0	95	0E+2	Inexact,Lost_digits,Rounded
  #|quantize	1	floor	999	-999	0	0	95	0E+1	Inexact,Lost_digits,Rounded
  #|quantize	1	down	999	-999	0	0	95	0E+1	Inexact,Lost_digits,Rounded
  #|quantize	1	05up	999	-999	0	0	95	0E+1	Inexact,Lost_digits,Rounded
  #|quantize	1	ceiling	999	-999	0	0	-96	0E+1	Inexact,Lost_digits,Rounded
  #|quantize	1	floor	999	-999	0	0	-96	0E+2	Inexact,Lost_digits,Rounded

///|
// oracle: A
// source: quantize at precision 1 with every rounding algorithm on 96 and 95 (and -96 for the two directed ones): the rounded second operand has the exponent 1 or 2; expected values written by hand from GDA 1.70, page 56 (Appendix A, "Operation differences", first item: an operand with more digits than the precision is rounded to precision digits with the rounding of the context before use, trailing zeros not counted) and page 36 (quantize: the exponent of the result is that of the second operand; Invalid operation when the coefficient would be longer than the precision or the exponent out of range); every value also agrees with decNumber 3.68 (DECSUBSET=1, pin of testdata/decimal_gda/deviations.tsv) run on the second operand after extended rounding to precision digits (58 rows, 58 equal), and the flags are those of the operation joined with those of the operand rounding (Rounded, Inexact, Lost digits)
// shares: Decimal::from_string and Decimal::to_sci_string (the printing of a Decimal), GdaFlags accessors, the table runner i754_run of the issue 754 test file
test "issue 764: modes" {
  let (calls, bad) = i754_run(i764_modes)
  assert_eq(bad, [])
  assert_eq(calls, 18)
}

///|
let i764_rescale : String =
  #|rescale	1	half_up	999	-999	0	0	12	0E+10	Inexact,Lost_digits,Rounded
  #|rescale	1	half_up	999	-999	0	0	96	0E+100	Inexact,Lost_digits,Rounded
  #|rescale	1	down	999	-999	0	0	96	0E+90	Inexact,Lost_digits,Rounded
  #|rescale	1	floor	999	-999	0	0	96	0E+90	Inexact,Lost_digits,Rounded
  #|rescale	1	05up	999	-999	0	0	96	0E+90	Inexact,Lost_digits,Rounded
  #|rescale	1	ceiling	999	-999	0	0	96	0E+100	Inexact,Lost_digits,Rounded
  #|rescale	1	half_down	999	-999	0	0	15	0E+10	Inexact,Lost_digits,Rounded
  #|rescale	1	half_even	999	-999	0	0	15	0E+20	Inexact,Lost_digits,Rounded
  #|rescale	1	half_up	999	-999	0	5	12	0E+10	Inexact,Lost_digits,Rounded
  #|rescale	2	half_up	999	-999	0	5	123	0E+120	Inexact,Lost_digits,Rounded
  #|rescale	1	half_up	999	-999	0	0	-96	0E-100	Inexact,Lost_digits,Rounded
  #|rescale	1	half_up	99	-99	0	0	96	NaN	*
  #|rescale	1	half_up	99	-99	0	0	-96	NaN	*

///|
// oracle: A
// source: rescale: the integer given as the second operand is an operand and is rounded to precision digits first, so the power of ten of the quantum is the rounded integer; every rounding algorithm on 96 and 15, positive and negative, and the exponent bounds; expected values written by hand from GDA 1.70, page 56 (Appendix A, "Operation differences", first item: an operand with more digits than the precision is rounded to precision digits with the rounding of the context before use, trailing zeros not counted) and page 36 (quantize: the exponent of the result is that of the second operand; Invalid operation when the coefficient would be longer than the precision or the exponent out of range); every value also agrees with decNumber 3.68 (DECSUBSET=1, pin of testdata/decimal_gda/deviations.tsv) run on the second operand after extended rounding to precision digits (58 rows, 58 equal), and the flags are those of the operation joined with those of the operand rounding (Rounded, Inexact, Lost digits)
// shares: Decimal::from_string and Decimal::to_sci_string (the printing of a Decimal), GdaFlags accessors, the table runner i754_run of the issue 754 test file
test "issue 764: rescale" {
  let (calls, bad) = i754_run(i764_rescale)
  assert_eq(bad, [])
  assert_eq(calls, 13)
}

///|
let i764_precisions : String =
  #|quantize	3	half_up	999	-999	0	7	1234	1E+1	Inexact,Lost_digits,Rounded
  #|quantize	3	half_up	999	-999	0	500	9996	5E+2	Inexact,Lost_digits,Rounded
  #|quantize	9	half_up	999	-999	0	1	1234567891	0E+1	Inexact,Lost_digits,Rounded
  #|quantize	9	up	999	-999	0	1	1234567891	1E+1	Inexact,Lost_digits,Rounded
  #|quantize	1	half_up	9	-9	0	0	12E+8	0E+9	Inexact,Lost_digits,Rounded
  #|quantize	1	half_up	9	-9	0	0	96E+8	NaN	*
  #|quantize	1	half_up	9	-9	0	0	12E-10	0E-9	Inexact,Lost_digits,Rounded
  #|quantize	1	half_up	9	-9	0	0	96E-10	0E-8	Inexact,Lost_digits,Rounded

///|
// oracle: A
// source: three precisions (3, 9) and both ends of the exponent range (emax 9, emin -9); expected values written by hand from GDA 1.70, page 56 (Appendix A, "Operation differences", first item: an operand with more digits than the precision is rounded to precision digits with the rounding of the context before use, trailing zeros not counted) and page 36 (quantize: the exponent of the result is that of the second operand; Invalid operation when the coefficient would be longer than the precision or the exponent out of range); every value also agrees with decNumber 3.68 (DECSUBSET=1, pin of testdata/decimal_gda/deviations.tsv) run on the second operand after extended rounding to precision digits (58 rows, 58 equal), and the flags are those of the operation joined with those of the operand rounding (Rounded, Inexact, Lost digits)
// shares: Decimal::from_string and Decimal::to_sci_string (the printing of a Decimal), GdaFlags accessors, the table runner i754_run of the issue 754 test file
test "issue 764: precisions" {
  let (calls, bad) = i754_run(i764_precisions)
  assert_eq(bad, [])
  assert_eq(calls, 8)
}

///|
let i764_extended : String =
  #|quantize	1	half_up	999	-999	1	0	12	0	-
  #|quantize	1	half_up	999	-999	1	0	96	0	-
  #|quantize	1	half_up	999	-999	1	5	1.2	NaN	Invalid_operation
  #|quantize	1	half_up	999	-999	1	0	0.99	0.00	-
  #|quantize	1	half_up	999	-999	1	5	12	5	-
  #|rescale	1	half_up	999	-999	1	0	12	0E+12	-
  #|rescale	1	half_up	999	-999	1	0	96	0E+96	-
  #|rescale	2	half_up	999	-999	1	5	123	0E+123	Inexact,Rounded

///|
// oracle: A
// source: an extended context: the second operand is used as it stands, nothing changes; expected values from the unchanged behaviour of an extended context (page 36 for quantize, page 37 note 2 for rescale), written by hand; the same rows give the same value and flags on origin/main and on this head, and decNumber 3.68 (extended flag set) agrees
// shares: Decimal::from_string and Decimal::to_sci_string (the printing of a Decimal), GdaFlags accessors, the table runner i754_run of the issue 754 test file
test "issue 764: extended" {
  let (calls, bad) = i754_run(i764_extended)
  assert_eq(bad, [])
  assert_eq(calls, 8)
}

///|
// Rows of the issue 754 decNumber matrix where decNumber 3.68 (DECSUBSET=1) takes the quantum of
// quantize from the unrounded second operand and the library takes it from the rounded one, as
// page 56 says. Columns: op, precision, rounding, emax, emin, extended, a, b, held value, held
// flags, decNumber value, decNumber flags. Moved here from the matrix of issue 754.
let i764_deviations : String =
  #|quantize	9	half_up	999	-999	0	1E-5	123456789123	0E+3	Inexact,Lost_digits,Rounded	0	Inexact,Lost_digits,Rounded
  #|quantize	9	half_even	999	-999	0	12E-3	123456789123	0E+3	Inexact,Lost_digits,Rounded	0	Inexact,Lost_digits,Rounded
  #|quantize	9	half_down	999	-999	0	1.1E-999	123456789123	0E+3	Inexact,Lost_digits,Rounded	0	Inexact,Lost_digits,Rounded
  #|quantize	9	05up	999	-999	0	1.2E+3	123456789123	1E+3	Inexact,Lost_digits,Rounded	1200	Inexact,Lost_digits,Rounded
  #|quantize	3	half_up	99	-99	0	12	123456789123	0E+9	Inexact,Lost_digits,Rounded	12	Inexact,Lost_digits,Rounded
  #|quantize	3	half_up	99	-99	0	-1.4E+3	1200	-1.40E+3	Rounded	NaN	Invalid_operation,Rounded
  #|quantize	3	half_down	99	-99	0	1.2E+3	123456789123	0E+9	Inexact,Lost_digits,Rounded	NaN	Inexact,Invalid_operation,Lost_digits,Rounded
  #|quantize	1	half_up	9	-9	0	12	1.2E+3	0E+3	Inexact,Lost_digits,Rounded	0E+2	Inexact,Lost_digits,Rounded
  #|quantize	1	half_up	9	-9	0	-1.4E+3	1.2E+3	-1E+3	Inexact,Lost_digits,Rounded	NaN	Inexact,Invalid_operation,Lost_digits,Rounded
  #|quantize	1	half_up	9	-9	0	25E+1	1.2E+3	0E+3	Inexact,Lost_digits,Rounded	3E+2	Inexact,Lost_digits,Rounded
  #|quantize	1	half_up	9	-9	0	1.1E-9	1.2E+3	0E+3	Inexact,Lost_digits,Rounded	0E+2	Inexact,Lost_digits,Rounded
  #|quantize	1	floor	9	-9	0	1.1E-9	1.1E-9	1E-9	Inexact,Lost_digits,Rounded	NaN	Inexact,Invalid_operation,Lost_digits,Rounded

///|
// oracle: A
// source: the held values (columns 9 and 10) written by hand from GDA 1.70, page 56 (the second operand is rounded to precision digits first) and page 36 (the exponent of the result is that of the second operand), each checked by hand on the rounded operand, for example 123456789123 at precision 9 is 1.23456789E+11 and so the quantum exponent is 3, and 1.2E+3 at precision 1 is 1E+3; the decNumber values (columns 11 and 12) are the recorded ones of the issue 754 matrix
// shares: Decimal::from_string and Decimal::to_sci_string (the printing of a Decimal), GdaFlags accessors, the table runner i754_run of the issue 754 test file
test "issue 764: rows where the library follows page 56 and decNumber 3.68 differs" {
  let (calls, bad) = i754_run(i764_deviations)
  assert_eq(bad, [])
  assert_eq(calls, 12)
}
