///|
// Issue 759: in a subset context (extended=false) every operation of decimal_gda that takes a
// context rounds an operand longer than the precision to precision digits before use and
// raises Lost digits when non-zero digits go (GDA 1.70, page 56, Appendix A, "Operation
// differences", first item). Rows: op, precision, rounding, extended, a, b, result, Lost digits
// (Y or N). "-" in b repeats a.

///|
fn i759_run(rows : String) -> (Int32, Array[String]) {
  let mut calls = 0
  let bad = []
  for line in rows.split("\n") {
    let line = line.to_owned()
    if line == "" {
      continue
    }
    let f = line.split("\t").map(fn(x) { x.to_owned() }).collect()
    let ctx = GdaContext::new(
      precision=i754_int(f[1]),
      rounding=i754_mode(f[2]),
      e_min=-999999,
      e_max=999999,
      extended=f[3] == "1",
    )
    let a = Decimal::from_string(f[4], precision=60).unwrap()
    let b = if f[5] == "-" {
      a
    } else {
      Decimal::from_string(f[5], precision=60).unwrap()
    }
    let out = i754_call(f[0], a, b, ctx)
    calls += 1
    let value = out.value().to_sci_string()
    let lost = if out.raised().lost_digits() { "Y" } else { "N" }
    if value != f[6] || lost != f[7] {
      bad.push(line + " => " + value + "\t" + lost)
    }
  }
  (calls, bad)
}

///|
let i759_rows : String =
  #|reduce	9	half_up	0	1234567891	-	1.23456789E+9	Y
  #|reduce	9	half_up	0	1234567899	-	1.2345679E+9	Y
  #|scaleb	9	half_up	0	1234567891	0	1.23456789E+9	Y
  #|tointegralx	9	half_up	0	1234567891	-	1.23456789E+9	Y
  #|tointegral	9	half_up	0	1234567891	-	1.23456789E+9	Y
  #|apply	9	half_up	0	1234567891	-	1.23456789E+9	Y
  #|shift	9	half_up	0	1234567891	0	1.23456789E+9	Y
  #|rotate	9	half_up	0	1234567891	0	1.23456789E+9	Y
  #|nexttoward	9	half_up	0	1234567891	0	1.23456788E+9	Y
  #|nextminus	9	half_up	0	1234567891	-	1.23456788E+9	Y
  #|nextplus	9	half_up	0	1234567891	-	1.23456790E+9	Y
  #|nexttoward	9	half_up	0	1234567891	1234567892	1.23456789E+9	Y
  #|nexttoward	9	half_up	0	3	1234567891	3.00000001	Y
  #|reduce	5	half_up	0	123456	-	1.2346E+5	Y
  #|reduce	5	floor	0	123456	-	1.2345E+5	Y
  #|reduce	5	ceiling	0	123456	-	1.2346E+5	Y
  #|reduce	5	down	0	123456	-	1.2345E+5	Y
  #|reduce	5	up	0	123456	-	1.2346E+5	Y
  #|nextplus	5	half_up	0	123456	-	1.2347E+5	Y
  #|nextminus	5	half_up	0	123456	-	1.2345E+5	Y
  #|nextminus	5	floor	0	123456	-	1.2344E+5	Y
  #|reduce	5	half_up	0	100001	-	1E+5	Y
  #|reduce	5	half_up	0	-123456	-	-1.2346E+5	Y
  #|nextplus	5	half_up	0	-123456	-	-1.2345E+5	Y
  #|reduce	5	half_up	0	123450	-	1.2345E+5	N
  #|reduce	5	half_up	0	12345	-	12345	N
  #|shift	5	half_up	0	123450	0	1.2345E+5	N
  #|scaleb	5	half_up	0	123456	1	1.2346E+6	Y
  #|reduce	9	half_up	1	1234567891	-	1.23456789E+9	N
  #|reduce	9	half_up	1	1200	-	1.2E+3	N
  #|scaleb	9	half_up	1	12	2	1.2E+3	N
  #|tointegralx	9	half_up	1	1.2E+3	-	1.2E+3	N
  #|nextplus	9	half_up	1	1	-	1.00000001	N
  #|nexttoward	9	half_up	1	1	0	0.999999999	N
  #|shift	9	half_up	1	12	2	1200	N

///|
// oracle: A
// source: expected values written by hand from GDA 1.70, page 56 (Appendix A, "Operation differences", first item: the operand is rounded to precision digits with the rounding of the context, Lost digits when non-zero digits go, trailing zeros not counted) and from the definitions of the operations (reduce strips trailing zeros, next_plus and next_minus step one unit of the last place of the rounded operand); the repro row is the table of issue 759 (decNumber 3.68 with DECSUBSET=1 gives 1.23456788E+9 for next_toward); extended rows follow from the same operations without operand rounding
// shares: Decimal::from_string and Decimal::to_sci_string (the printing of a Decimal, `Show` is to_string), GdaFlags::lost_digits, the table runner i754_call and i754_mode of the issue 754 test file
test "issue 759: operations round a long operand first in a subset context and are unchanged in an extended one" {
  let (calls, bad) = i759_run(i759_rows)
  assert_eq(bad, [])
  assert_eq(calls, 35)
}

///|
// Rows of the issue 754 decNumber matrix where the library, which follows GDA 1.70, page 56
// (operands longer than the precision are rounded before use), and decNumber 3.68 (DECSUBSET=1)
// give different results: moved here from the matrix of issue 754 instead of being dropped.
// Columns: op, precision, rounding, emax, emin, extended, a, b, decNumber value, decNumber flags,
// held value, held flags. decNumber's values are the recorded ones of the matrix.
let i759_deviations : String =
  #|nexttoward	9	half_up	999	-999	0	0	1.23456789123E+11	0	Inexact,Rounded,Subnormal,Underflow	0	Inexact,Lost_digits,Rounded,Subnormal,Underflow
  #|nexttoward	9	half_up	999	-999	0	-0	123456789123	0	Inexact,Rounded,Subnormal,Underflow	0	Inexact,Lost_digits,Rounded,Subnormal,Underflow
  #|nexttoward	9	half_up	999	-999	0	1.23456789123E+11	123456789123	123456789123	-	1.23456789E+11	Inexact,Lost_digits,Rounded
  #|nexttoward	9	half_up	999	-999	0	-1E-999	1.23456789123E+11	0	Inexact,Rounded,Subnormal,Underflow	0	Inexact,Lost_digits,Rounded,Subnormal,Underflow
  #|nexttoward	9	half_even	999	-999	0	0	123456789123	0	Inexact,Rounded,Subnormal,Underflow	0	Inexact,Lost_digits,Rounded,Subnormal,Underflow
  #|nexttoward	9	half_even	999	-999	0	1.2E+3	123456789123	1200.00001	-	1200.00001	Inexact,Lost_digits,Rounded
  #|nexttoward	9	half_even	999	-999	0	-1E-999	123456789123	0	Inexact,Rounded,Subnormal,Underflow	0	Inexact,Lost_digits,Rounded,Subnormal,Underflow
  #|rotate	9	half_even	999	-999	0	1.23456789123E+11	2	678912345	-	3.45678912E+11	Inexact,Lost_digits,Rounded
  #|nexttoward	9	half_down	999	-999	0	0	123456789123	0	Inexact,Rounded,Subnormal,Underflow	0	Inexact,Lost_digits,Rounded,Subnormal,Underflow
  #|rotate	9	down	999	-999	0	123456789123	12	NaN	Invalid_operation	NaN	Inexact,Invalid_operation,Lost_digits,Rounded
  #|nexttoward	9	ceiling	999	-999	0	0	123456789123	0	Inexact,Rounded,Subnormal,Underflow	0	Inexact,Lost_digits,Rounded,Subnormal,Underflow
  #|rotate	9	ceiling	999	-999	0	123456789123	0	123456789123	-	1.23456790E+11	Inexact,Lost_digits,Rounded
  #|nexttoward	9	05up	999	-999	0	1E-5	123456789123	0.0000100000001	-	0.0000100000001	Inexact,Lost_digits,Rounded
  #|nexttoward	3	half_up	99	-99	0	0	9.99999999E+99	0	Inexact,Rounded,Subnormal,Underflow	0	Inexact,Lost_digits,Overflow,Rounded,Subnormal,Underflow
  #|nexttoward	3	half_up	99	-99	0	-0	1.23456789123E+11	0	Inexact,Rounded,Subnormal,Underflow	0	Inexact,Lost_digits,Rounded,Subnormal,Underflow
  #|nexttoward	3	half_up	99	-99	0	1200	12E+2	1200	-	1.20E+3	Rounded
  #|nexttoward	3	half_up	99	-99	0	12E+2	123456789123	1.21E+3	-	1.21E+3	Inexact,Lost_digits,Rounded
  #|nexttoward	3	half_up	99	-99	0	25E+1	1.23456789123E+11	251	-	251	Inexact,Lost_digits,Rounded
  #|nexttoward	3	half_up	99	-99	0	-1E-99	9.99999999E+99	0	Inexact,Rounded,Subnormal,Underflow	0	Inexact,Lost_digits,Overflow,Rounded,Subnormal,Underflow
  #|rotate	3	half_up	99	-99	0	1.23456789123E+11	-1	312	-	3.12E+11	Inexact,Lost_digits,Rounded
  #|rotate	3	half_even	99	-99	0	123456789123	2	312	-	3.12E+11	Inexact,Lost_digits,Rounded
  #|nexttoward	3	half_down	99	-99	0	0	123456789123	0	Inexact,Rounded,Subnormal,Underflow	0	Inexact,Lost_digits,Rounded,Subnormal,Underflow
  #|nexttoward	3	ceiling	99	-99	0	0	123456789123	0	Inexact,Rounded,Subnormal,Underflow	0	Inexact,Lost_digits,Rounded,Subnormal,Underflow
  #|nexttoward	1	half_up	9	-9	0	-1	12	-0.9	-	-0.9	Inexact,Lost_digits,Rounded
  #|nexttoward	1	half_up	9	-9	0	5E+2	1200	6E+2	-	6E+2	Inexact,Lost_digits,Rounded
  #|nexttoward	1	half_up	9	-9	0	0.5	12E-3	0.4	-	0.4	Inexact,Lost_digits,Rounded
  #|nexttoward	1	half_up	9	-9	0	1E-9	1200	2E-9	-	2E-9	Inexact,Lost_digits,Rounded
  #|shift	1	half_up	9	-9	0	-1.4E+3	-2	NaN	Invalid_operation	NaN	Inexact,Invalid_operation,Lost_digits,Rounded
  #|shift	1	half_up	9	-9	0	1.01E-8	12	NaN	Invalid_operation	NaN	Inexact,Invalid_operation,Lost_digits,Rounded
  #|rotate	1	half_up	9	-9	0	1.2E+3	-1	1.2E+3	-	1E+3	Inexact,Lost_digits,Rounded
  #|rotate	1	half_up	9	-9	0	-1E-9	12	NaN	Invalid_operation	NaN	Inexact,Invalid_operation,Lost_digits,Rounded
  #|nexttoward	1	half_even	9	-9	0	-1	1.1E-9	-0.9	-	-0.9	Inexact,Lost_digits,Rounded
  #|rotate	1	half_even	9	-9	0	1.2E+3	3	NaN	Invalid_operation	NaN	Inexact,Invalid_operation,Lost_digits,Rounded
  #|nexttoward	1	half_down	9	-9	0	1E+9	1.2E+3	9E+8	-	9E+8	Inexact,Lost_digits,Rounded
  #|rotate	1	half_down	9	-9	0	1E-5	12	NaN	Invalid_operation	NaN	Inexact,Invalid_operation,Lost_digits,Rounded
  #|nexttoward	1	up	9	-9	0	1E-5	-1.4E+3	0.000009	-	0.000009	Inexact,Lost_digits,Rounded
  #|shift	1	up	9	-9	0	1.2E+3	3	NaN	Invalid_operation	NaN	Inexact,Invalid_operation,Lost_digits,Rounded
  #|nexttoward	1	ceiling	9	-9	0	-1	1.1E-9	-0.9	-	-0.9	Inexact,Lost_digits,Rounded
  #|rotate	1	ceiling	9	-9	0	1.2E+3	3	NaN	Invalid_operation	NaN	Inexact,Invalid_operation,Lost_digits,Rounded
  #|rotate	1	05up	9	-9	0	-1.4E+3	-1	-1.4E+3	-	-1E+3	Inexact,Lost_digits,Rounded

///|
/// Runs the deviation rows: the library gives the held value and flags, which differ from
/// decNumber's, and the result equals the result of the same operation on operands that the
/// library's `plus` (rounding of page 56 before it) has already rounded.
fn i759_run_deviations(rows : String) -> (Int32, Array[String]) {
  let mut calls = 0
  let bad = []
  for line in rows.split("\n") {
    let line = line.to_owned()
    if line == "" {
      continue
    }
    let f = line.split("\t").map(fn(x) { x.to_owned() }).collect()
    let ctx = GdaContext::new(
      precision=i754_int(f[1]),
      rounding=i754_mode(f[2]),
      e_min=i754_int(f[4]),
      e_max=i754_int(f[3]),
      extended=f[5] == "1",
    )
    let a = Decimal::from_string(f[6], precision=60).unwrap()
    let b = Decimal::from_string(f[7], precision=60).unwrap()
    let out = i754_call(f[0], a, b, ctx)
    calls += 1
    let value = out.value().to_sci_string()
    let flags = i754_flags(out.raised())
    let pa = plus(a, ctx).value()
    let pb = plus(b, ctx).value()
    let pre = i754_call(f[0], pa, pb, ctx).value().to_sci_string()
    if value != f[10] ||
      flags != f[11] ||
      (value == f[8] && flags == f[9]) ||
      pre != value {
      bad.push(line + " => " + value + "\t" + flags + "\t" + pre)
    }
  }
  (calls, bad)
}

///|
// oracle: S
// source: rows recorded from the issue 754 matrix of decNumber 3.68 (values in columns 9 and 10) and the held values of the library (columns 11 and 12), each differing from decNumber's; the held value rests on GDA 1.70, page 56 (Appendix A, "Operation differences", first item: an operand longer than the precision is rounded before use), checked here only as equal to the result of the same operation on operands that `plus` has rounded
// shares: the operand rounding of the library (`plus` and the new subset step both call prepare_operand_for_context), Decimal::from_string and Decimal::to_sci_string, the runner i754_call
test "issue 759: rows where the library follows page 56 and decNumber 3.68 differs" {
  let (calls, bad) = i759_run_deviations(i759_deviations)
  assert_eq(bad, [])
  assert_eq(calls, 40)
}
