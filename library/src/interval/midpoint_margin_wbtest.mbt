// `midpoint_ctx` at a precision larger than the margin of the far-addend stand-in
// (#645): the exact centre `(lo + hi) / 2` of an interval whose bounds are further apart
// than `max(65,536, precision)` places was formed with the stand-in of the smaller
// bound inside the bits that the rounding to the context keeps.
//
// The sweep of the context precision around the margin is a table of
// `tools/interval_bottom_oracle.py` (`bottom_table_check_wbtest.mbt`, rows `ctx`).

///|
fn mm_zeros(n : Int32) -> String {
  let mut text = ""
  for _ in 0..<n {
    text = text + "0"
  }
  text
}

///|
// oracle: A
// source: derived by hand: the centre of [1, 2^100000] is (1 + 2^100000) / 2 = 2^99999 + 1/2 = (2^100000 + 1) * 2^-1, whose coefficient is the hexadecimal 1, 24,999 zeros, 1 (100,001 bits), exact at 200,000 bits; the same case is a row of the table of tools/interval_bottom_oracle.py
// shares: BinCoeff::parse and Binary::make build the expected number, Binary::compare and exponent2 compare it; Interval::from_bounds and Binary::make build the operands
test "midpoint_ctx of [1, 2^100000] at 200,000 bits is 2^99999 + 1/2" {
  let one = @binary.Binary::one(precision=53)
  let big = @binary.Binary::make(@binary.BinCoeff::one(), 100000, 53)
  let interval = Interval::from_bounds(one, big, precision=53)
  let (m, _) = interval.midpoint_ctx(IntervalContext::new(precision=200000))
  // (2^100000 + 1) is "1", 24,999 hex zeros, "1": 100,001 bits
  let expected = match
    @binary.BinCoeff::parse("1" + mm_zeros(24999) + "1", radix=16) {
    Ok(coefficient) => @binary.Binary::make(coefficient, -1, 200000)
    Err(error) => abort(error)
  }
  assert_true(m.compare(expected) == 0)
  assert_true(m.exponent2() == -1)
}
