///|
test "decimal compare orders NaN after every number instead of aborting" {
  let nan = Decimal::nan()
  inspect(nan.compare(Decimal::from_int(1)), content="1")
  inspect(Decimal::from_int(1).compare(nan), content="-1")
  inspect(nan.compare(nan), content="0")
}
