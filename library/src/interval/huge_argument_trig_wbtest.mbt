// floating#377: sin, cos and tan of an argument beyond the old cutoff
// `max(65536, 4 * precision)` bits of exponent were an `Err` (try forms) or the
// whole range [-1, 1] / the whole line (plain forms). They are now tight.
// Expected values: MPFR 4.2.2 at the exact argument
// (tools/generate_decimal_huge_trig_rows.py; the same rows as
// library/src/bin_float/huge_argument_trig_wbtest.mbt).

///|
fn huge_trig_argument(k : Int32) -> Interval {
  Interval::exact(
    @bin_float.BinFloat::make(@bin_float.BinCoeff::one(), k, 2),
    precision=53,
  )
}

///|
fn huge_trig_encloses(value : Interval, expected : @bin_float.BinFloat) -> Bool {
  // The enclosure contains the MPFR value and is narrower than 2^-40.
  let width = value
    .upper_bound()
    .sub_ctx(value.lower_bound(), @bin_float.BinaryContext::new(precision=64)).0
  value.lower_bound().compare(expected) <= 0 &&
  value.upper_bound().compare(expected) >= 0 &&
  width.compare(@bin_float.BinFloat::make(@bin_float.BinCoeff::one(), -40, 2)) <
  0
}

///|
test "sin, cos, tan of 2^70000 are tight beyond the old cutoff" {
  let x = huge_trig_argument(70000)
  // sin, cos, tan of 2^70000 at p = 113 rounded to 53 bits: the values of the
  // binary table, written as BinFloat::make(mantissa, exponent).
  let sin = @bin_float.BinFloat::make(
    @bin_float.BinCoeff::from_uint64(4410396487554295UL),
    -52,
    53,
  )
  let cos = @bin_float.BinFloat::make(
    @bin_float.BinCoeff::from_uint64(3645956502692609UL),
    -54,
    53,
  )
  let tan = @bin_float.BinFloat::make(
    @bin_float.BinCoeff::from_uint64(170245619730007UL),
    -45,
    53,
  )
  assert_true(huge_trig_encloses(x.try_sin().unwrap(), sin))
  assert_true(huge_trig_encloses(x.try_cos().unwrap(), cos))
  assert_true(huge_trig_encloses(x.try_tan().unwrap(), tan))
  assert_true(huge_trig_encloses(x.sin(), sin))
  assert_true(huge_trig_encloses(x.cos(), cos))
  assert_true(huge_trig_encloses(x.tan(), tan))
}
