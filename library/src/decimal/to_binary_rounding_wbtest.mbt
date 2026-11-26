///|
/// to_binary rounds the exact value once. 0.0003 and 0.00001 lie just above
/// a binary midpoint at 53 bits; rounding the scaled quotient to an integer in
/// the target mode first landed on that midpoint, and ties-to-even then went
/// the wrong way. The doubles below are the correctly rounded conversions.

///|
// oracle: A
// source: the doubles 0.0003, 0.00001 and -0.0003 as the host compiler's correctly rounded decimal literals (CPython float() gives the same doubles, library-ran: no), which are the correctly rounded conversions of the decimals; the directed modes are asserted only as a bracket of one unit in the last place (toward zero equals the nearest double for 0.0003, toward positive infinity is above it)
// shares: Decimal::from_string reads the operands; to_binary is the code under test; @binary.Binary::from_double builds the expected doubles and compare reads the result
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
