// floating#377: sin, cos and tan of an argument beyond the old cutoff
// `max(65536, 4 * precision)` bits of exponent were an `Err` (try forms) or the
// whole range [-1, 1] / the whole line (plain forms). They are now tight.
// Expected values: MPFR 4.2.2 at the exact argument
// (tools/generate_decimal_huge_trig_rows.py; the same rows as
// library/src/binary/huge_argument_trig_wbtest.mbt).

///|
fn huge_trig_argument(k : Int32) -> Interval {
  Interval::exact(
    @binary.Binary::make(@binary.BinCoeff::one(), k, 2),
    precision=53,
  )
}

///|
fn huge_trig_encloses(value : Interval, expected : @binary.Binary) -> Bool {
  // The enclosure contains the MPFR value and is narrower than 2^-40.
  let width = value
    .upper_bound()
    .sub_ctx(value.lower_bound(), @binary.BinaryContext::new(precision=64)).0
  value.lower_bound().compare(expected) <= 0 &&
  value.upper_bound().compare(expected) >= 0 &&
  width.compare(@binary.Binary::make(@binary.BinCoeff::one(), -40, 2)) < 0
}

///|
// oracle: A
// source: the values of sin, cos and tan of the exact argument 2^70000 rounded to 53 bits are 8820792975108590 * 2^-53, 7291913005385218 * 2^-55 and 5447859831360224 * 2^-50 (written in the test with one fewer bit), computed with MPFR 4.2.2 (mpfr_sin, mpfr_cos, mpfr_tan, RNDN, 64-bit exact argument) for this audit and as the rows of the binary table; each enclosure must contain its value and be narrower than 2^-40 (a tolerance, the end values are not pinned)
// shares: huge_trig_argument and Binary::make build the operands and the expected values; huge_trig_encloses compares; sin, cos, tan and try_ forms are the code under test
test "sin, cos, tan of 2^70000 are tight beyond the old cutoff" {
  let x = huge_trig_argument(70000)
  // sin, cos, tan of 2^70000 at p = 113 rounded to 53 bits: the values of the
  // binary table, written as Binary::make(mantissa, exponent).
  let sin = @binary.Binary::make(
    @binary.BinCoeff::from_uint64(4410396487554295UL),
    -52,
    53,
  )
  let cos = @binary.Binary::make(
    @binary.BinCoeff::from_uint64(3645956502692609UL),
    -54,
    53,
  )
  let tan = @binary.Binary::make(
    @binary.BinCoeff::from_uint64(170245619730007UL),
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
