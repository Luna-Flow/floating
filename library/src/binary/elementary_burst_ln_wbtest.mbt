///|
fn burst_ln_test_corpus() -> Array[Binary] {
  let values : Array[Binary] = []
  let mut seed = 31UL
  for bits in [60, 130, 256, 400, 700, 1100, 2000] {
    // Random values in [1, 2).
    for _ in 0..<12 {
      values.push(burst_test_value(bits, 1, false, seed))
      seed += 1UL
    }
    // Values close to 1 and to 2.
    for k in [17, 18, 24, 40, 100] {
      let offset = Binary::make_coeff(
        burst_test_coefficient(Int32::min(bits, 60), seed),
        -k - Int32::min(bits, 60),
        Int32::min(bits, 60),
      )
      seed += 1UL
      let context = BinaryContext::new(precision=bits + k + 80)
      values.push(Binary::one(precision=2).add_ctx(offset, context).0)
      values.push(Binary::from_int(2, precision=2).sub_ctx(offset, context).0)
    }
  }
  values.push(Binary::from_int(2, precision=2))
  values.push(Binary::make_coeff(Coeff::from_uint64(3UL), -1, 2))
  values.push(Binary::make_coeff(Coeff::from_uint64(5UL), -2, 3))
  values.push(Binary::make_coeff(Coeff::from_uint64(4097UL), -12, 13))
  values
}

///|
// oracle: B, S
// source: B: the Newton enclosure of ln over the corpus must contain the series enclosure at 256 more bits, a different algorithm of the library; S: the series enclosure has no level A block of its own at these precisions (the end results of ln are compared with MPFR in the block `ln keeps its results when the Newton step starts at the entry threshold`, 300 to 1000 bits)
// shares: burst_ln_test_corpus and burst_test_work build the arguments; binary_ln_unit_burst_bounds is the code under test and binary_ln_unit_bounds_series the reference; burst_test_contains compares
// primitives: binary_ln_unit_bounds_series, the series enclosure of ln on the unit interval (no level A block of its own at these precisions: the end results of ln are compared with MPFR in the block `ln keeps its results when the AGM kernel runs`, 1000 to 2000 bits, but not the series bounds), and burst_test_contains
test "ln Newton step contains the series enclosure at higher precision" {
  let mut checked = 0
  for value in burst_ln_test_corpus() {
    let work = burst_test_work(value.precision())
    match binary_ln_unit_burst_bounds(value, work) {
      Some(bounds) => {
        let reference = binary_ln_unit_bounds_series(value, work + 256).unwrap()
        assert_true(burst_test_contains(bounds, reference))
        checked += 1
      }
      None => ()
    }
  }
  assert_true(checked > 60)
}

///|
// oracle: S
// source: the width of the Newton enclosure against the width of the series enclosure of the same argument over the corpus; a width relation between two kernels of the library, no value stated
// shares: burst_ln_test_corpus and burst_test_work build the arguments; binary_ln_unit_burst_bounds is the code under test and binary_ln_unit_bounds_series the reference; sub and compare
test "ln Newton step is no wider than the series enclosure" {
  for value in burst_ln_test_corpus() {
    let work = burst_test_work(value.precision())
    match binary_ln_unit_burst_bounds(value, work) {
      Some((low, high)) => {
        let (series_low, series_high) = binary_ln_unit_bounds_series(
          value, work,
        ).unwrap()
        assert_true(high.sub(low).compare(series_high.sub(series_low)) <= 0)
      }
      None => ()
    }
  }
}

///|
// oracle: S
// source: the written contract of binary_ln_unit_burst_bounds: None for 1, 3, 1/2 at one bit, 1 + 2^-30 (closer to 1 than 2^-16) and +inf; no value is stated
// shares: Binary::one, from_int, make_coeff and inf build the operands; binary_ln_unit_burst_bounds is the code under test
test "ln Newton step declines outside its range" {
  let work = 512
  assert_true(
    binary_ln_unit_burst_bounds(Binary::one(precision=64), work) is None,
  )
  assert_true(
    binary_ln_unit_burst_bounds(Binary::from_int(3, precision=64), work) is None,
  )
  assert_true(
    binary_ln_unit_burst_bounds(
      Binary::make_coeff(Coeff::from_uint64(1UL), -1, 1),
      work,
    )
    is None,
  )
  // Closer to 1 than 2^-16.
  assert_true(
    binary_ln_unit_burst_bounds(
      Binary::make_coeff(Coeff::one().shift_left(30).add(Coeff::one()), -30, 31),
      work,
    )
    is None,
  )
  assert_true(binary_ln_unit_burst_bounds(Binary::inf(), work) is None)
}

///|
// oracle: B, S
// source: B: the unmutated Newton enclosure at 2064 bits contains the series enclosure at 2320 bits, and the mutants (a lower bias of 8 units, a poor start value with the quadratic term dropped) are caught as not containing it, the poor start alone stays valid or is declined; S: the series enclosure has no level A block of its own at this precision, and burst_test_caught is the verdict of the test
// shares: burst_test_value builds the argument; binary_ln_unit_burst_bounds with the mutation record is the code under test and binary_ln_unit_bounds_series the reference; burst_test_contains and burst_test_caught compare
// primitives: binary_ln_unit_bounds_series, the series enclosure of ln on the unit interval (no level A block of its own at these precisions: the end results of ln are compared with MPFR in the block `ln keeps its results when the AGM kernel runs`, 1000 to 2000 bits, but not the series bounds), and burst_test_contains
test "mutated ln Newton steps are caught by the containment test" {
  let value = burst_test_value(2000, 1, false, 4242UL)
  let work = 2064
  let reference = binary_ln_unit_bounds_series(value, work + 256).unwrap()
  assert_true(
    burst_test_contains(
      binary_ln_unit_burst_bounds(value, work).unwrap(),
      reference,
    ),
  )
  // A bias of 8 units of the last place in the lower end.
  let biased = { start_bits_drop: 0, drop_quadratic: false, lower_bias: 8, }
  assert_true(
    burst_test_caught(
      binary_ln_unit_burst_bounds(value, work, mutation=biased),
      reference,
    ),
  )
  // A poor start value (about work / 8 bits) with the quadratic term dropped.
  let poor = {
    start_bits_drop: work / 2 + 16 - work / 8,
    drop_quadratic: true,
    lower_bias: 0,
  }
  assert_true(
    burst_test_caught(
      binary_ln_unit_burst_bounds(value, work, mutation=poor),
      reference,
    ),
  )
  // The poor start value alone only widens the enclosure; the quadratic term
  // keeps it valid (or the width check declines it).
  let wide = {
    start_bits_drop: work / 2 + 16 - work / 8,
    drop_quadratic: false,
    lower_bias: 0,
  }
  match binary_ln_unit_burst_bounds(value, work, mutation=wide) {
    Some(bounds) => assert_true(burst_test_contains(bounds, reference))
    None => ()
  }
}

///|
// oracle: A
// source: enclosure_rows_wbtest.mbt, generated by tools/generate_enclosure_rows.py; ln at 2 * bits + 200 bits, rounded in each context by binary_certified_inexact_target_rounding when both ends round alike; the rows are (GNU MPFR 4.2.2 rounded toward negative and toward positive infinity at the stated precision), library-ran: no; the arguments are inputs of the test and the reference is the pair of MPFR results
// shares: Binary::to_hex writes the key of the request, Binary::from_hex_ctx and Binary::add_ctx read the pair exactly (level A through hex_ctx_rows and arith_rows), Binary::compare in the containment check; burst_test_value builds the arguments; binary_certified_inexact_target_rounding rounds the pair (level A through round_rows_wbtest.mbt); the name keeps the old wording, the reference is now MPFR
test "ln results are identical with and without the Newton step" {
  let modes = [
    RoundTiesToEven,
    RoundTowardZero,
    RoundTowardPositive,
    RoundTowardNegative,
  ]
  let mut seed = 700UL
  let mut compared = 0
  for bits in [200, 300, 513, 640, 1000, 1024, 2048] {
    for top in [-20, -3, -1, 0, 1, 2, 5, 12, 40] {
      seed += 1UL
      let value = burst_test_value(bits, top, false, seed)
      for mode in modes {
        let context = BinaryContext::new(precision=bits, rounding=mode)
        match
          (
            mpfr_rounded("ln", value, context, 2 * bits + 200),
            value.try_ln_ctx(context),
          ) {
          (Some((expected, expected_flags)), Ok((result, flags))) => {
            assert_true(result.identical(expected))
            assert_true(flags == expected_flags)
            compared += 1
          }
          _ => ()
        }
      }
    }
  }
  assert_true(compared > 150)
}

///|
// oracle: B, S
// source: B: the entry-step enclosure of ln at 384 to 2112 bits must contain the series enclosure at 256 more bits (up to 66 arguments); S: the series enclosure has no level A block of its own at these precisions
// shares: burst_test_value builds the arguments; binary_ln_unit_bounds with entry=true is the code under test and binary_ln_unit_bounds_series the reference; burst_test_contains compares
// primitives: binary_ln_unit_bounds_series, the series enclosure of ln on the unit interval (no level A block of its own at these precisions: the end results of ln are compared with MPFR in the block `ln keeps its results when the AGM kernel runs`, 1000 to 2000 bits, but not the series bounds), and burst_test_contains
test "ln entry step on the table kernel contains the series enclosure" {
  let mut checked = 0
  let mut seed = 977UL
  for work in [384, 448, 576, 704, 832, 1000, 1100, 1151, 1152, 1400, 2112] {
    for _ in 0..<6 {
      let value = burst_test_value(Int32::min(work, 1100), 1, false, seed)
      seed += 1UL
      match binary_ln_unit_bounds(value, work, entry=true) {
        Some(bounds) => {
          let reference = binary_ln_unit_bounds_series(value, work + 256).unwrap()
          assert_true(burst_test_contains(bounds, reference))
          checked += 1
        }
        None => ()
      }
    }
  }
  assert_true(checked > 60)
}

///|
// oracle: A
// source: enclosure_rows_wbtest.mbt, generated by tools/generate_enclosure_rows.py; ln at precision + 320 bits, both ends rounded to nearest to the precision and compared with Binary::ln; the rows are (GNU MPFR 4.2.2 rounded toward negative and toward positive infinity at the stated precision), library-ran: no; the arguments are inputs of the test and the reference is the pair of MPFR results
// shares: Binary::to_hex writes the key of the request, Binary::from_hex_ctx and Binary::add_ctx read the pair exactly (level A through hex_ctx_rows and arith_rows), Binary::compare in the containment check; burst_test_value builds the arguments; Binary::with_precision rounds the ends and assert_identical compares
test "ln keeps its results when the Newton step starts at the entry threshold" {
  let mut seed = 131UL
  for precision in [300, 330, 450, 600, 900, 1000] {
    for _ in 0..<4 {
      let value = burst_test_value(precision, 1, false, seed)
      seed += 1UL
      let result = value.ln()
      let work = precision + 320
      let (low, high) = mpfr_enclosure("ln", value, work)
      assert_identical(
        result,
        low.with_precision(precision, BinaryRoundingMode::RoundTiesToEven),
      )
      assert_identical(
        result,
        high.with_precision(precision, BinaryRoundingMode::RoundTiesToEven),
      )
    }
  }
}
