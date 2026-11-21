///|
// oracle: S
// source: design rule of the library's Comparable (NaN orders after every number and equals NaN), not an operation
//   of GDA 1.70 (its compare returns NaN); the expected 1, -1 and 0 are written out
// shares: nothing
test "GDA decimal compare orders NaN after every number instead of aborting" {
  let nan = Decimal::nan()
  inspect(nan.compare(Decimal::from_int(1)), content="1")
  inspect(Decimal::from_int(1).compare(nan), content="-1")
  inspect(nan.compare(nan), content="0")
}
