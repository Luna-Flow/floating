///|
// oracle: A, S
// source: A: the order of the numbers (0 below 1 below +inf, +0 equal to -0); S: that every NaN compares equal to every NaN and greater than every number is the library's own convention for compare as a total order, not an IEEE 754-2019 predicate (the standard's predicates, tested in order_predicates_wbtest.mbt, make the comparison with a NaN unordered)
// shares: Binary::inf, one, nan, signaling_nan, zero and negative_zero build the operands; compare, the greater-than operator and the sort are the code under test
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
