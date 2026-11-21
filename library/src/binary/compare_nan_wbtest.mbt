///|
test "compare orders NaN after every number instead of aborting" {
  let nan = Binary::nan()
  let values = [Binary::inf(), Binary::one(), nan, Binary::zero()]
  inspect(nan.compare(Binary::inf()), content="1")
  inspect(Binary::one().compare(nan), content="-1")
  inspect(nan.compare(Binary::signaling_nan()), content="0")
  inspect(Binary::zero().compare(Binary::negative_zero()), content="0")
  inspect(nan > Binary::one(), content="true")
  values.sort_by(fn(a, b) { a.compare(b) })
  inspect(
    values.map(fn(value) { value.to_string() }).join(" "),
    content="0 1p0 inf nan",
  )
}
