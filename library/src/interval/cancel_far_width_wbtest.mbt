// `cancelMinus` and `cancelPlus` decide "width(x) < width(y) gives Entire"
// (IEEE 1788-2015 12.12.5) on the exact widths. The end values were rounded (a
// far addend was replaced by a surrogate that only keeps the direction), so a
// width smaller by less than a unit of the end values was taken as equal and
// the result was a point instead of Entire.

///|
fn cfw_value(
  coefficient : UInt64,
  exponent : Int32,
  negative : Bool,
) -> @binary.Binary {
  let bits = Int32::max(64, @binary.binary_implementation_e_min - exponent + 1)
  @binary.Binary::make(
    @binary.BinCoeff::from_uint64(coefficient),
    exponent,
    bits,
    negative~,
  )
}

///|
fn cfw_is_entire(x : Interval) -> Bool {
  x.is_entire()
}

///|
test "a point minus an interval of a tiny positive width is Entire" {
  let x0 = cfw_value(2485731UL, -915372, true)
  let x = Interval::from_bounds(x0, x0, precision=113)
  let y = Interval::from_bounds(
    cfw_value(0UL, 0, false),
    cfw_value(1UL, -1073741874, false),
    precision=53,
  )
  assert_true(cfw_is_entire(x.cancel_minus(y)))
  assert_true(cfw_is_entire(x.cancel_plus(y)))
  // equal widths give a point
  let one = Interval::from_int(1, precision=53)
  let two = Interval::from_int(2, precision=53)
  let eq_x = one.convex_hull(two)
  let eq_y = Interval::from_int(3, precision=53).convex_hull(
    Interval::from_int(4, precision=53),
  )
  assert_true(eq_x.cancel_minus(eq_y).is_singleton())
  assert_true(!cfw_is_entire(eq_x.cancel_plus(eq_y)))
}

///|
test "the far addend does not decide the width of a wide interval" {
  // x = [x0, x0 + 2^-200 x0-units], y = [y0, y0 + 2^-1073741874]: the widths
  // differ at a place far below the end values
  let x0 = cfw_value(8417475269597001UL, 1073741743, true)
  let x = Interval::from_bounds(x0, x0, precision=64)
  let y = Interval::from_bounds(
    cfw_value(1155434267279036823UL, 38, true),
    cfw_value(0UL, 0, false),
    precision=128,
  )
  assert_true(cfw_is_entire(x.cancel_minus(y)))
  assert_true(cfw_is_entire(x.cancel_plus(y)))
}
