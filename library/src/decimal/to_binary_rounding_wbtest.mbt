///|
/// to_binary rounds the exact value once. 0.0003 and 0.00001 lie just above
/// a binary midpoint at 53 bits; rounding the scaled quotient to an integer in
/// the target mode first landed on that midpoint, and ties-to-even then went
/// the wrong way. The doubles below are the correctly rounded conversions.
test "to_binary rounds the exact value once" {
  for entry in [("0.0003", 0.0003), ("0.00001", 0.00001), ("-0.0003", -0.0003)] {
    let (text, double) = entry
    let value = Decimal::from_string(text).unwrap().to_binary(precision=53)
    assert_eq(value.compare(@binary.Binary::from_double(double)), 0)
  }
  // The directed modes bracket the exact value by one unit in the last place.
  let x = Decimal::from_string("0.0003").unwrap()
  let nearest = @binary.Binary::from_double(0.0003)
  let down = x.to_binary(
    precision=53,
    mode=@binary.BinaryRoundingMode::RoundTowardZero,
  )
  let up = x.to_binary(
    precision=53,
    mode=@binary.BinaryRoundingMode::RoundTowardPositive,
  )
  assert_eq(down.compare(nearest), 0)
  assert_true(up.compare(nearest) > 0)
}
