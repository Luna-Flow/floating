// `Interval::fma` at the bottom of the exponent range (issue #607): the products
// and the sums are exact and the result is rounded once, outward, at the end
// (IEEE 1788-2015 12.10.2: the accuracy of the basic operations shall be
// tightest). The product was made at its own bit length, which rounds it outward
// to the quantum of a few bits before the sum.

///|
fn fm_value(c : UInt64, exponent : Int32, negative : Bool) -> @binary.Binary {
  @binary.Binary::make(
    @binary.BinCoeff::from_uint64(c),
    exponent,
    200,
    negative~,
  )
}

///|
fn fm_point(v : @binary.Binary, precision : Int32) -> Interval {
  Interval::from_bounds(v, v, precision~)
}

///|
// oracle: A
// source: worked out by hand: with t = 2^(e_min - 3), t * 1 + t = 2t = 2^(e_min - 2) = 1p-1073741824 (e_min = 2 - 2^30), an exact point; the same case is a row of the table of tools/interval_bottom_oracle.py
// shares: fm_value and fm_point (Binary::make and Interval::from_bounds) build the operands; Binary::to_string prints the ends
test "the fma of the issue is the exact point" {
  let e_min = @binary.binary_value_e_min
  let t = fm_value(1UL, e_min - 3, false)
  let one = fm_value(1UL, 0, false)
  let z = fm_point(t, 53).fma(fm_point(one, 53), fm_point(t, 53))
  // t * 1 + t = 2t = 2^(e_min - 2)
  inspect(z.lower_bound().to_string(), content="1p-1073741824")
  inspect(z.upper_bound().to_string(), content="1p-1073741824")
}
