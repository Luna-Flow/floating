///|
// oracle: A
// source: written out from the totalOrder of IEEE 754-2019 5.10 (a positive quiet NaN is greater than every number, two equal NaNs compare equal): compare(NaN, 1) = 1, compare(1, NaN) = -1, compare(NaN, NaN) = 0
// shares: Decimal::nan and compare (the code under test), Decimal::from_int (it builds the operand)
test "decimal compare orders NaN after every number instead of aborting" {
  let nan = Decimal::nan()
  inspect(nan.compare(Decimal::from_int(1)), content="1")
  inspect(Decimal::from_int(1).compare(nan), content="-1")
  inspect(nan.compare(nan), content="0")
}
