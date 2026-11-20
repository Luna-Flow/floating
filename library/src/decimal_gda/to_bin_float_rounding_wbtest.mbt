///|
/// to_bin_float rounds the exact value once. 0.0003 and 0.00001 lie just above
/// a binary midpoint at 53 bits; rounding the scaled quotient to an integer in
/// the target mode first landed on that midpoint, and ties-to-even then went
/// the wrong way. The doubles below are the correctly rounded conversions.
test "to_bin_float rounds the exact value once" {
  for entry in [("0.0003", 0.0003), ("0.00001", 0.00001), ("-0.0003", -0.0003)] {
    let (text, double) = entry
    let value = Decimal::parse(text).unwrap().to_bin_float(precision=53)
    assert_eq(value.compare(@bin_float.BinFloat::from_double(double)), 0)
  }
  // The directed modes bracket the exact value by one unit in the last place.
  let x = Decimal::parse("0.0003").unwrap()
  let nearest = @bin_float.BinFloat::from_double(0.0003)
  let down = x.to_bin_float(precision=53, mode=TowardZero)
  let up = x.to_bin_float(precision=53, mode=AwayFromZero)
  assert_eq(down.compare(nearest), 0)
  assert_true(up.compare(nearest) > 0)
}
