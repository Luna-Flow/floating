///|
// Issue 763: in a subset context (extended=false) `compare_total` and `compare_total_magnitude`
// round an operand longer than the precision with the algorithm of the context before the total
// order is taken; `compare_total_magnitude` drops the sign first (page 43), which matters in Floor
// and Ceiling (GDA 1.70, page 56, Appendix A, "Operation differences", first item). Rows: op
// (ctotal, ctotalmag), precision, rounding, extended, a, b, result, Lost digits (Y or N).

///|
fn i763_run(rows : String) -> (Int32, Array[String]) {
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
    let b = Decimal::from_string(f[5], precision=60).unwrap()
    let out = if f[0] == "ctotal" {
      compare_total(a, b, ctx)
    } else {
      compare_total_magnitude(a, b, ctx)
    }
    calls += 1
    let value = out.value().to_string()
    let lost = if out.raised().lost_digits() { "Y" } else { "N" }
    if value != f[6] || lost != f[7] {
      bad.push(line + " => " + value + "\t" + lost)
    }
  }
  (calls, bad)
}

///|
let i763_rows : String =
  #|ctotal	1	half_up	0	12	1E+1	0	Y
  #|ctotal	1	half_up	0	1E+1	12	0	Y
  #|ctotal	1	half_up	0	15	1E+1	1	Y
  #|ctotal	1	down	0	15	1E+1	0	Y
  #|ctotal	1	ceiling	0	12	1E+1	1	Y
  #|ctotal	1	floor	0	12	1E+1	0	Y
  #|ctotal	1	half_up	0	-12	-1E+1	0	Y
  #|ctotal	1	floor	0	-12	-1E+1	-1	Y
  #|ctotal	2	half_up	0	120	12E+1	0	N
  #|ctotal	2	half_up	0	12E+1	120	0	N
  #|ctotal	3	half_up	0	123456	1.23E+5	0	Y
  #|ctotal	3	half_up	0	1.23E+5	123456	0	Y
  #|ctotal	3	up	0	123456	1.23E+5	1	Y
  #|ctotalmag	1	half_up	0	-12	1E+1	0	Y
  #|ctotalmag	1	ceiling	0	-12	1E+1	1	Y
  #|ctotalmag	1	floor	0	-12	1E+1	0	Y
  #|ctotalmag	1	floor	0	12	-12	0	Y
  #|ctotalmag	1	ceiling	0	-12	12	0	Y
  #|ctotalmag	3	floor	0	123456	-99950	1	Y
  #|ctotalmag	3	ceiling	0	-99950	123456	-1	Y
  #|ctotalmag	1	down	0	-12	12	0	Y
  #|ctotalmag	2	half_up	0	-120	12E+1	0	N
  #|ctotalmag	3	half_up	0	123456	-1.23E+5	0	Y
  #|ctotal	1	half_up	1	12	1E+1	1	N
  #|ctotal	2	half_up	1	120	12E+1	-1	N
  #|ctotalmag	1	half_up	1	-12	1E+1	1	N

///|
// oracle: A
// source: expected values written by hand from GDA 1.70, page 56 (Appendix A, "Operation differences", first item: the operand is rounded to precision digits with the rounding of the context, Lost digits when non-zero digits go, trailing zeros not counted) and from the total order of page 42 (numbers of equal value are ordered by exponent, the larger exponent is the greater for positive numbers) and from page 43 (compare-total-magnitude(x, y) is compare-total(copy-abs(x), copy-abs(y)), so the sign is dropped before the operand is rounded: -12 at precision 1 is rounded as 12, to 1E+1 in Floor and 2E+1 in Ceiling); 12 rounds to 1E+1 (half-up, down, floor) or 2E+1 (up, ceiling), 15 to 2E+1 (half-up) or 1E+1 (down), -12 to -1E+1 or -2E+1 (floor), 120 at precision 2 loses only a zero and is 1.2E+2 (12E+1), 123456 at precision 3 is 1.23E+5 (half-up) or 1.24E+5 (up); the repro row is the table of issue 763 (decNumber 3.68 with DECSUBSET=1 gives 0 for compare_total(12, 1E+1) at precision 1); extended rows follow from the total order of the unrounded operands
// shares: Decimal::from_string, GdaFlags::lost_digits, Int32 printing, and the i754_int and i754_mode helpers of the issue 754 test file
test "issue 763: compare_total and compare_total_magnitude round a long operand first in a subset context" {
  let (calls, bad) = i763_run(i763_rows)
  assert_eq(bad, [])
  assert_eq(calls, 26)
}
