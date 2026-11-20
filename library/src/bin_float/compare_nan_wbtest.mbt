///|
test "compare orders NaN after every number instead of aborting" {
  let nan = BinFloat::nan()
  let values = [
    BinFloat::inf(Sign::Positive),
    BinFloat::one(),
    nan,
    BinFloat::zero(),
  ]
  inspect(nan.compare(BinFloat::inf(Sign::Positive)), content="1")
  inspect(BinFloat::one().compare(nan), content="-1")
  inspect(nan.compare(BinFloat::signaling_nan()), content="0")
  inspect(BinFloat::zero().compare(BinFloat::negative_zero()), content="0")
  inspect(nan > BinFloat::one(), content="true")
  values.sort_by(fn(a, b) { a.compare(b) })
  inspect(
    values.map(fn(value) { value.to_string() }).join(" "),
    content="0 1p0 inf nan",
  )
}
