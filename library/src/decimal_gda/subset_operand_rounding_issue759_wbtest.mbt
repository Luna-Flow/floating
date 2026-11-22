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
